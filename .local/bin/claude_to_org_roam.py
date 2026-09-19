#!/usr/bin/env python3
"""
Claude Chat History JSON → org-roam ノード変換バッチ

1会話 = 1 org-roam ノードファイルとして出力し、Emacs側の capture template
で生成される :PROPERTIES: 形式に合わせる。

  :PROPERTIES:
  :ID:       <org-id UUID>
  :ROAM_REFS: https://claude.ai/chat/<会話UUID>
  :STATUS:   <--status で指定 (デフォルト: captured)>
  :END:
  #+TITLE: <会話タイトル>
  #+FILETAGS: :tag1:tag2:
  #+CATEGORY: <--category で指定>
  #+DATE: [YYYY-MM-DD Day]

既に同じ :ROAM_REFS: (チャットURL) を持つファイルが --output-dir 配下に
存在する場合はスキップする（org-roamはROAM_REFSの重複を許容しないため）。

Usage:
  python claude_to_org_roam.py <input.json> [--output-dir DIR]
  python claude_to_org_roam.py *.json --output-dir ~/org/roam --tags tools,claude

--flat を付けると、org-roamノード分割ではなく、入力JSON 1件につき1つの
単純な .org ファイル(会話ごとに `* タイトル` の見出しを並べただけ、
ROAM_REFS/タグ自動判定なし)を出力する(旧 claude_to_org.py 相当)。
  python claude_to_org_roam.py chat.json --flat
"""

import argparse
import json
import re
import sys
import unicodedata
import uuid
from datetime import datetime
from pathlib import Path

# --- STATUS のデフォルト値についての注記 -----------------------------------
# アップロード頂いた例では :STATUS: resolved でしたが、これは手動トリアージ
# 後の状態と思われるため、自動一括インポートでは既定値を "captured" として
# います。実際の運用に合わせて --status で上書きしてください。
DEFAULT_STATUS = "captured"
DEFAULT_TAGS = "tools,claude"
DEFAULT_CATEGORY = "tools"

# --- タグ/カテゴリ自動判定ルール ---------------------------------------------
# 会話タイトル＋全メッセージ本文に対して単純な部分一致で判定する。
# categories は上から順に評価し、最初にキーワードが一致したものを採用。
# keywords が空のエントリは常にマッチする「フォールバック」として末尾に置く。
# tags は該当した名前をすべて付与する（複数付与可）。
# --taxonomy でこの辞書と同じ形のJSONファイルを渡せば丸ごと差し替えられる。
DEFAULT_TAXONOMY = {
    "categories": [
        {"name": "defense", "keywords": ["防衛省", "防衛装備庁", "自衛隊", "DII"]},
        {"name": "infosec", "keywords": ["情報セキュリティ", "セキュリティ基準", "セキュリティ実施手順",
                                          "infosec", "セキュリティ", "security"]},
        {"name": "procurement", "keywords": ["概算要求", "PJMO", "調達仕様", "DS-110", "DS-910",
                                              "デジタル庁", "procurement"]},
        {"name": "emacs", "keywords": ["emacs", "org-mode", "org-roam", "elisp",
                                        "straight.el", ".emacs.d"]},
        {"name": "programming", "keywords": ["python", "javascript", "typescript", "react",
                                              "リファクタリング", "デバッグ", "バグ", "エラー",
                                              "スクリプト", "コード"]},
        {"name": "tools", "keywords": []},
    ],
    "tags": [
        {"name": "defense", "keywords": ["防衛省", "防衛装備庁", "自衛隊"]},
        {"name": "infosec", "keywords": ["情報セキュリティ", "セキュリティ", "security"]},
        {"name": "budget-review", "keywords": ["概算要求", "予算", "budget"]},
        {"name": "procurement", "keywords": ["PJMO", "調達", "DS-110", "DS-910"]},
        {"name": "emacs", "keywords": ["emacs", "org-mode", "elisp", ".emacs.d", "straight.el"]},
        {"name": "org-roam", "keywords": ["org-roam", "roam"]},
        {"name": "python", "keywords": ["python", ".py"]},
        {"name": "trouble", "keywords": ["エラー", "バグ", "失敗", "デバッグ", "error", "bug",
                                          "トラブル"]},
        {"name": "claude", "keywords": []},
    ],
}


def load_taxonomy(path):
    """--taxonomy で指定されたJSONを読み込む。未指定ならデフォルトを使う。"""
    if not path:
        return DEFAULT_TAXONOMY
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    if 'categories' not in data or 'tags' not in data:
        raise ValueError('taxonomyファイルには "categories" と "tags" の両方が必要です')
    return data


def _text_matches(text: str, keywords: list) -> bool:
    if not keywords:
        return True  # キーワード無しは常にマッチ(フォールバック用)
    return any(kw.lower() in text for kw in (k.lower() for k in keywords)) or \
        any(kw in text for kw in keywords)


def detect_category(text: str, taxonomy: dict) -> str:
    for rule in taxonomy.get('categories', []):
        if _text_matches(text, rule.get('keywords', [])):
            return rule['name']
    return DEFAULT_CATEGORY


def detect_tags(text: str, taxonomy: dict) -> list:
    matched = []
    for rule in taxonomy.get('tags', []):
        if _text_matches(text, rule.get('keywords', [])):
            matched.append(rule['name'])
    return matched


def build_conversation_text(conv: dict, messages: list) -> str:
    """カテゴリ/タグ判定用に、タイトル＋全メッセージのプレーンテキストを結合する。"""
    title = conv.get('name') or conv.get('title') or ''
    bodies = [title]
    for msg in messages:
        bodies.append(extract_text(msg.get('content') or msg.get('text') or ''))
    return '\n'.join(bodies)


# --- タイムスタンプ ---------------------------------------------------------

def parse_ts(ts):
    """unix秒/ミリ秒 または ISO8601文字列 を datetime に変換する（失敗時 None）。"""
    if not ts:
        return None
    try:
        if isinstance(ts, (int, float)):
            return datetime.fromtimestamp(ts / 1000 if ts > 1e10 else ts)
        if isinstance(ts, str):
            return datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except Exception:
        return None
    return None


def format_timestamp(ts) -> str:
    """メッセージ見出し用: [YYYY-MM-DD Day HH:MM]"""
    dt = parse_ts(ts)
    return dt.strftime('[%Y-%m-%d %a %H:%M]') if dt else ''


def format_date(ts) -> str:
    """#+DATE: 用: [YYYY-MM-DD Day]"""
    dt = parse_ts(ts)
    return dt.strftime('[%Y-%m-%d %a]') if dt else ''


def date_prefix(ts) -> str:
    """ファイル名用: YYYYMMDD（タイムスタンプが取れない場合は本日日付）"""
    dt = parse_ts(ts) or datetime.now()
    return dt.strftime('%Y%m%d')


# --- org変換 -----------------------------------------------------------------

def escape_org(text: str) -> str:
    """行頭の * を org見出しと誤認しないようエスケープ"""
    lines = text.split('\n')
    return '\n'.join((',' + line if line.startswith('*') else line) for line in lines)


def markdown_to_org(text: str) -> str:
    """Markdown 記法を org-mode 記法に変換する。
    コードブロックはプレースホルダに退避してから他の変換をかけ、最後に復元
    することで、コード内部が太字/斜体変換等に巻き込まれるのを防ぐ。
    """
    code_blocks = []

    def stash_code_block(m):
        lang = m.group(1).strip() or 'text'
        code = m.group(2)
        placeholder = f'\x00CODEBLOCK{len(code_blocks)}\x00'
        code_blocks.append(f'#+begin_src {lang}\n{code}#+end_src')
        return placeholder

    text = re.sub(r'```(\w*)\n(.*?)```', stash_code_block, text, flags=re.DOTALL)

    # インラインコード `code` → =code=
    text = re.sub(r'`([^`\n]+)`', r'=\1=', text)
    # 太字 **text** → *text*
    text = re.sub(r'\*\*(.+?)\*\*', r'*\1*', text)
    # 斜体 *text* → /text/ (太字変換後に処理)
    text = re.sub(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)', r'/\1/', text)

    def replace_heading(m):
        # メッセージ見出し自体が level 1 (*) を使うため、本文中の見出しは
        # level+1 から始める (H1 → **, H2 → ***, ...)
        level = len(m.group(1))
        title = m.group(2).strip()
        return '*' * (level + 1) + ' ' + title

    text = re.sub(r'^(#{1,6})\s+(.+)$', replace_heading, text, flags=re.MULTILINE)
    # リンク [text](url) → [[url][text]]
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'[[\2][\1]]', text)
    # 箇条書きの統一
    text = re.sub(r'^[ \t]*[-*]\s+', '- ', text, flags=re.MULTILINE)
    # 水平線
    text = re.sub(r'^---+$', '-----', text, flags=re.MULTILINE)

    for i, block in enumerate(code_blocks):
        text = text.replace(f'\x00CODEBLOCK{i}\x00', block)

    return escape_org(text)


def extract_text(content) -> str:
    """メッセージの content フィールドからテキストを抽出"""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                if item.get('type') == 'text':
                    parts.append(item.get('text', ''))
                elif item.get('type') == 'tool_use':
                    tool_name = item.get('name', 'tool')
                    tool_input = json.dumps(item.get('input', {}), ensure_ascii=False, indent=2)
                    parts.append(f'[Tool: {tool_name}]\n#+begin_src json\n{tool_input}\n#+end_src')
                elif item.get('type') == 'tool_result':
                    result_content = item.get('content', '')
                    if isinstance(result_content, list):
                        result_content = '\n'.join(
                            r.get('text', '') for r in result_content if isinstance(r, dict)
                        )
                    parts.append(f'[Tool Result]\n#+begin_example\n{result_content}\n#+end_example')
                elif item.get('type') == 'image':
                    parts.append('[Image attachment]')
                elif item.get('type') == 'document':
                    parts.append('[Document attachment]')
            elif isinstance(item, str):
                parts.append(item)
        return '\n\n'.join(p for p in parts if p)
    return str(content) if content else ''


def render_messages(messages) -> str:
    if not messages:
        return '/(No messages)/\n'

    lines = []
    for msg in messages:
        role = msg.get('role') or msg.get('sender') or 'unknown'
        text = extract_text(msg.get('content') or msg.get('text') or '')
        ts = format_timestamp(
            msg.get('created_at') or msg.get('timestamp') or msg.get('updated_at')
        )

        if role in ('human', 'user'):
            role_label, tag = '👤 Human', ':human:'
        elif role in ('assistant', 'claude'):
            role_label, tag = '🤖 Claude', ':claude:'
        else:
            role_label, tag = f'🔧 {role.capitalize()}', f':{role}:'

        heading = f'* {role_label}'
        if ts:
            heading += f'  {ts}'
        heading += f'  {tag}'
        lines.append(heading)
        lines.append('')
        lines.append(markdown_to_org(text) if text else '/(empty message)/')
        lines.append('')

    return '\n'.join(lines)


# --- 単純出力モード(--flat, 旧 claude_to_org.py 相当) -----------------------

def convert_conversation_flat(conv: dict) -> str:
    """1つの会話を、org-roam分割ではなく単純な `* タイトル` 見出しに変換する。"""
    lines = []

    title = conv.get('name') or conv.get('title') or conv.get('id') or 'Untitled Conversation'
    lines.append(f'* {title}')

    created = format_timestamp(conv.get('created_at') or conv.get('created'))
    updated = format_timestamp(conv.get('updated_at') or conv.get('updated'))
    if created:
        lines.append(':PROPERTIES:')
        lines.append(f':CREATED: {created}')
        if updated:
            lines.append(f':UPDATED: {updated}')
        conv_id = conv.get('uuid') or conv.get('id') or ''
        if conv_id:
            lines.append(f':ID: {conv_id}')
        lines.append(':END:')
    lines.append('')

    messages = (
        conv.get('chat_messages') or
        conv.get('messages') or
        conv.get('turns') or
        []
    )
    if not messages:
        lines.append('/(No messages)/\n')
        return '\n'.join(lines)

    for msg in messages:
        role = msg.get('role') or msg.get('sender') or 'unknown'
        text = extract_text(msg.get('content') or msg.get('text') or '')
        ts = format_timestamp(
            msg.get('created_at') or msg.get('timestamp') or msg.get('updated_at')
        )

        if role in ('human', 'user'):
            role_label, tag = '👤 Human', ':human:'
        elif role in ('assistant', 'claude'):
            role_label, tag = '🤖 Claude', ':claude:'
        else:
            role_label, tag = f'🔧 {role.capitalize()}', f':{role}:'

        heading = f'** {role_label}'
        if ts:
            heading += f'  {ts}'
        heading += f'  {tag}'
        lines.append(heading)
        lines.append('')
        lines.append(markdown_to_org(text) if text else '/(empty message)/')
        lines.append('')

    return '\n'.join(lines)


def json_to_org_flat(input_path: Path, output_path: Path) -> None:
    """入力JSON 1件を、単純な単一 .org ファイルに変換する(--flat)。"""
    with open(input_path, encoding='utf-8') as f:
        data = json.load(f)

    conversations = normalize_conversations(data)
    print(f'  → {len(conversations)} 件の会話を変換中...')

    org_lines = [
        f'#+TITLE: Claude Chat History - {input_path.stem}',
        f'#+DATE: {datetime.now().strftime("[%Y-%m-%d %a]")}',
        '#+AUTHOR: Claude Chat Exporter',
        '#+STARTUP: overview',
        '#+OPTIONS: toc:2 num:nil',
        '',
    ]
    for i, conv in enumerate(conversations, 1):
        try:
            org_lines.append(convert_conversation_flat(conv))
            org_lines.append('')
        except Exception as e:
            org_lines.append(f'* [Error in conversation {i}: {e}]')
            org_lines.append('')

    output_path.write_text('\n'.join(org_lines), encoding='utf-8')
    print(f'  ✓ 保存: {output_path}')


# --- プロパティドロワー -------------------------------------------------------

def property_line(key: str, value: str, align_to: int = 11) -> str:
    """:KEY: value を、org標準の見た目に近い形で桁を揃えて出力する。
    (Emacs側でも org-mode が編集/保存時に自動で再整列するため、
    ここでの桁揃えは見た目のみの目的。)
    """
    key_str = f':{key}:'
    pad = max(1, align_to - len(key_str) + 1)
    return f'{key_str}{" " * pad}{value}'


def resolve_tags(conv_text: str, taxonomy: dict, args) -> list:
    """自動判定タグ + --tags で指定された固定タグをマージする(重複除去・順序維持)。"""
    tags = []
    if not args.no_auto_tags:
        tags.extend(detect_tags(conv_text, taxonomy))
    if args.tags:
        tags.extend(t.strip() for t in args.tags.split(',') if t.strip())
    if not tags:
        tags = [t.strip() for t in DEFAULT_TAGS.split(',') if t.strip()]
    # 重複除去（最初の出現順を維持）
    seen = set()
    result = []
    for t in tags:
        if t not in seen:
            seen.add(t)
            result.append(t)
    return result


def resolve_category(conv_text: str, taxonomy: dict, args) -> str:
    """--category が明示指定されていればそれを優先、なければ自動判定。"""
    if args.category:
        return args.category
    if not args.no_auto_category:
        return detect_category(conv_text, taxonomy)
    return DEFAULT_CATEGORY


def build_org_roam_file(conv: dict, conv_id: str, node_id: str, taxonomy: dict, args) -> str:
    title = conv.get('name') or conv.get('title') or 'Untitled Conversation'
    roam_ref = f'https://claude.ai/chat/{conv_id}'
    created = conv.get('created_at') or conv.get('created')
    date_str = format_date(created)

    messages = (
        conv.get('chat_messages') or
        conv.get('messages') or
        conv.get('turns') or
        []
    )

    conv_text = build_conversation_text(conv, messages)
    tags = resolve_tags(conv_text, taxonomy, args)
    category = resolve_category(conv_text, taxonomy, args)
    filetags = ':' + ':'.join(tags) + ':' if tags else ''

    lines = [
        ':PROPERTIES:',
        property_line('ID', node_id),
        property_line('ROAM_REFS', roam_ref),
        property_line('STATUS', args.status),
        ':END:',
        f'#+TITLE: {title}',
    ]
    if filetags:
        lines.append(f'#+FILETAGS: {filetags}')
    lines.append(f'#+CATEGORY: {category}')
    if date_str:
        lines.append(f'#+DATE: {date_str}')
    lines.append('')
    lines.append(render_messages(messages))

    return '\n'.join(lines)


# --- ファイル名 / 重複判定 ----------------------------------------------------

def slugify(text: str) -> str:
    # NFKDでラテン文字のアクセント記号を分離してから除去するが、そのままだと
    # 日本語の濁点/半濁点も分離されて \w にマッチせず消えてしまう(表示崩れの原因)。
    # NFCで再合成してから除去することでカナの濁点/半濁点を保持する。
    text = unicodedata.normalize('NFKD', text)
    text = re.sub(r'[̀-ͯ]', '', text)
    text = unicodedata.normalize('NFC', text)
    text = re.sub(r'[^\w\s-]', '', text, flags=re.UNICODE).strip().lower()
    text = re.sub(r'[-\s]+', '-', text)
    return text[:60].strip('-') or 'untitled'


def make_filename(conv: dict, conv_id: str) -> str:
    title = conv.get('name') or conv.get('title') or 'untitled'
    created = conv.get('created_at') or conv.get('created')
    prefix = date_prefix(created)
    slug = slugify(title)
    short_id = (conv_id or uuid.uuid4().hex)[:8]
    return f'{prefix}-{slug}-{short_id}.org'


ROAM_REFS_RE = re.compile(r':ROAM_REFS:\s*(\S+)')


def scan_existing_refs(output_dir: Path) -> set:
    """output_dir配下の既存 .org ファイルから :ROAM_REFS: の値を収集する。"""
    refs = set()
    if not output_dir.exists():
        return refs
    for org_file in output_dir.rglob('*.org'):
        try:
            content = org_file.read_text(encoding='utf-8', errors='ignore')
        except Exception:
            continue
        for m in ROAM_REFS_RE.finditer(content):
            refs.add(m.group(1).strip())
    return refs


def normalize_conversations(data) -> list:
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        if 'conversations' in data:
            return data['conversations']
        if any(k in data for k in ('chat_messages', 'messages', 'turns')):
            return [data]
    return []


# --- メイン処理 ---------------------------------------------------------------

def process_file(input_path: Path, output_dir: Path, existing_refs: set, taxonomy: dict, args) -> tuple:
    """(created数, skipped数) を返す"""
    with open(input_path, encoding='utf-8') as f:
        data = json.load(f)

    conversations = normalize_conversations(data)
    print(f'  → {len(conversations)} 件の会話を確認中...')

    created = 0
    skipped = 0

    for conv in conversations:
        conv_id = conv.get('uuid') or conv.get('id')
        if not conv_id:
            print('  [WARN] uuid/id が無い会話をスキップします')
            continue

        roam_ref = f'https://claude.ai/chat/{conv_id}'

        if roam_ref in existing_refs and not args.force:
            title = conv.get('name') or conv.get('title') or conv_id
            print(f'  ⏭  スキップ (既存ノードあり): {title}')
            skipped += 1
            continue

        node_id = str(uuid.uuid4())
        try:
            org_text = build_org_roam_file(conv, conv_id, node_id, taxonomy, args)
        except Exception as e:
            print(f'  [ERROR] 会話 {conv_id} の変換に失敗: {e}')
            continue

        filename = make_filename(conv, conv_id)
        out_path = output_dir / filename

        # ファイル名が衝突した場合(同一バッチ内の重複タイトル等)は連番を付与
        n = 1
        while out_path.exists():
            out_path = output_dir / f'{filename[:-4]}-{n}.org'
            n += 1

        out_path.write_text(org_text, encoding='utf-8')
        existing_refs.add(roam_ref)  # 同一バッチ内の重複投入も防ぐ
        created += 1
        print(f'  ✓ 作成: {out_path.name}')

    return created, skipped


def main():
    parser = argparse.ArgumentParser(
        prog='claude_to_org_roam.py',
        description='Claude Chat History JSON → org-roam ノード変換バッチ',
        epilog='例: python claude_to_org_roam.py chat.json --output-dir ~/org/roam\n'
               '    python claude_to_org_roam.py *.json --tags tools,claude --status captured',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('input_files', nargs='*', metavar='input.json',
                         help='変換対象のJSONファイル（複数指定・ワイルドカード可）')
    parser.add_argument('--output-dir', type=Path, default=Path('org-roam'),
                         help='org-roamノードの出力先ディレクトリ (デフォルト: ./org-roam)')
    parser.add_argument('--tags', default=None,
                         help='#+FILETAGS: に必ず含める固定タグ(カンマ区切り)。'
                              '自動判定タグに追加される。指定が無く自動判定も無効な場合は '
                              f'{DEFAULT_TAGS} を使用')
    parser.add_argument('--category', default=None,
                         help='#+CATEGORY: を固定値で強制する(指定時は自動判定より優先)')
    parser.add_argument('--status', default=DEFAULT_STATUS,
                         help=f':STATUS: の値 (デフォルト: {DEFAULT_STATUS})')
    parser.add_argument('--taxonomy', type=Path, default=None,
                         help='タグ/カテゴリ自動判定ルールを定義したJSONファイル '
                              '(categories/tags キーを持つ。省略時は組み込みルールを使用)')
    parser.add_argument('--no-auto-tags', action='store_true',
                         help='タグの自動判定を無効化する（--tags のみを使う）')
    parser.add_argument('--no-auto-category', action='store_true',
                         help='カテゴリの自動判定を無効化する（--category のみを使う）')
    parser.add_argument('--force', action='store_true',
                         help='既存のROAM_REFSと重複していても新規ファイルを作成する')
    parser.add_argument('--flat', action='store_true',
                         help='org-roamノード分割ではなく、入力JSON 1件につき1つの単純な'
                              '.org ファイルを出力する(ROAM_REFS/タグ自動判定なし、旧 '
                              'claude_to_org.py 相当)。--output-dir はこのモードでは無視され、'
                              '入力ファイルと同じディレクトリに <入力名>.org として保存する。')

    if len(sys.argv) < 2:
        parser.print_help()
        sys.exit(1)

    args = parser.parse_args()
    if not args.input_files:
        parser.print_help()
        sys.exit(1)

    if args.flat:
        for input_file in args.input_files:
            input_path = Path(input_file)
            if not input_path.exists():
                print(f'[ERROR] ファイルが見つかりません: {input_path}')
                continue
            output_path = input_path.with_suffix('.org')
            print(f'\n変換中: {input_path.name}')
            try:
                json_to_org_flat(input_path, output_path)
            except json.JSONDecodeError as e:
                print(f'  [ERROR] JSON パースエラー: {e}')
            except Exception as e:
                print(f'  [ERROR] 変換エラー: {e}')
                raise
        print('\n完了!')
        return

    output_dir = args.output_dir.expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        taxonomy = load_taxonomy(args.taxonomy)
    except (json.JSONDecodeError, ValueError, OSError) as e:
        print(f'[ERROR] taxonomyファイルの読み込みに失敗: {e}')
        sys.exit(1)

    existing_refs = scan_existing_refs(output_dir)
    print(f'既存ノード数 (ROAM_REFS基準): {len(existing_refs)}')

    total_created = 0
    total_skipped = 0

    for input_file in args.input_files:
        input_path = Path(input_file)
        if not input_path.exists():
            print(f'[ERROR] ファイルが見つかりません: {input_path}')
            continue

        print(f'\n変換中: {input_path.name}')
        try:
            created, skipped = process_file(input_path, output_dir, existing_refs, taxonomy, args)
            total_created += created
            total_skipped += skipped
        except json.JSONDecodeError as e:
            print(f'  [ERROR] JSON パースエラー: {e}')
        except Exception as e:
            print(f'  [ERROR] 変換エラー: {e}')
            raise

    print(f'\n完了! 作成: {total_created}件 / スキップ: {total_skipped}件')


if __name__ == '__main__':
    main()
