#!/usr/bin/env python3
"""
Claude Chat History JSON → Org-mode Converter
Usage: python claude_to_org.py <input.json> [output.org]
       python claude_to_org.py *.json  (複数ファイル一括変換)
"""

import json
import sys
import re
from pathlib import Path
from datetime import datetime


def escape_org(text: str) -> str:
    """org-mode の特殊文字をエスケープ"""
    # 行頭の * はorg見出しになるのでエスケープ
    lines = text.split('\n')
    escaped = []
    for line in lines:
        if line.startswith('*'):
            line = ',' + line  # org-mode の verbatim エスケープ
        escaped.append(line)
    return '\n'.join(escaped)


def markdown_to_org(text: str) -> str:
    """Markdown 記法を org-mode 記法に変換"""
    # コードブロック ```lang ... ``` → #+begin_src lang ... #+end_src
    def replace_code_block(m):
        lang = m.group(1).strip() or 'text'
        code = m.group(2)
        return f'#+begin_src {lang}\n{code}\n#+end_src'

    text = re.sub(r'```(\w*)\n(.*?)```', replace_code_block, text, flags=re.DOTALL)

    # インラインコード `code` → =code=
    text = re.sub(r'`([^`\n]+)`', r'=\1=', text)

    # 太字 **text** → *text*
    text = re.sub(r'\*\*(.+?)\*\*', r'*\1*', text)

    # 斜体 *text* → /text/ (太字変換後に処理)
    text = re.sub(r'(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)', r'/\1/', text)

    # 見出し # → * (レベル調整: H1→**, H2→***, ...)
    def replace_heading(m):
        level = len(m.group(1))
        title = m.group(2).strip()
        return '*' * (level + 2) + ' ' + title

    text = re.sub(r'^(#{1,6})\s+(.+)$', replace_heading, text, flags=re.MULTILINE)

    # リンク [text](url) → [[url][text]]
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'[[\2][\1]]', text)

    # 箇条書き - item / * item → - item (org形式に統一)
    text = re.sub(r'^[ \t]*[-*]\s+', '- ', text, flags=re.MULTILINE)

    # 番号付きリスト 1. item → 1. item (org互換のためそのまま)

    # 水平線 --- → -----
    text = re.sub(r'^---+$', '-----', text, flags=re.MULTILINE)

    return text


def format_timestamp(ts) -> str:
    """タイムスタンプを org-mode 形式に変換"""
    if not ts:
        return ''
    try:
        if isinstance(ts, (int, float)):
            dt = datetime.fromtimestamp(ts / 1000 if ts > 1e10 else ts)
        elif isinstance(ts, str):
            # ISO 8601 形式対応
            ts_clean = ts.replace('Z', '+00:00')
            dt = datetime.fromisoformat(ts_clean)
        else:
            return str(ts)
        return dt.strftime('[%Y-%m-%d %a %H:%M]')
    except Exception:
        return str(ts)


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


def convert_conversation(conv: dict) -> str:
    """1つの会話を org-mode 形式に変換"""
    lines = []

    # 会話タイトル (最上位見出し)
    title = conv.get('name') or conv.get('title') or conv.get('id') or 'Untitled Conversation'
    lines.append(f'* {title}')

    # メタ情報
    created = format_timestamp(conv.get('created_at') or conv.get('created'))
    updated = format_timestamp(conv.get('updated_at') or conv.get('updated'))

    if created:
        lines.append(f':PROPERTIES:')
        lines.append(f':CREATED: {created}')
        if updated:
            lines.append(f':UPDATED: {updated}')
        conv_id = conv.get('uuid') or conv.get('id') or ''
        if conv_id:
            lines.append(f':ID: {conv_id}')
        lines.append(':END:')

    lines.append('')

    # メッセージ一覧を取得 (複数のキー名に対応)
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
        content_raw = msg.get('content') or msg.get('text') or ''
        text = extract_text(content_raw)
        ts = format_timestamp(
            msg.get('created_at') or msg.get('timestamp') or msg.get('updated_at')
        )

        # ロール表示
        if role in ('human', 'user'):
            role_label = '👤 Human'
            tag = ':human:'
        elif role in ('assistant', 'claude'):
            role_label = '🤖 Claude'
            tag = ':claude:'
        else:
            role_label = f'🔧 {role.capitalize()}'
            tag = f':{role}:'

        heading = f'** {role_label}'
        if ts:
            heading += f'  {ts}'
        heading += f'  {tag}'
        lines.append(heading)
        lines.append('')

        if text:
            converted = markdown_to_org(text)
            lines.append(converted)
        else:
            lines.append('/(empty message)/')

        lines.append('')

    return '\n'.join(lines)


def json_to_org(input_path: Path, output_path: Path):
    """JSON ファイルを org-mode ファイルに変換"""
    with open(input_path, encoding='utf-8') as f:
        data = json.load(f)

    org_lines = []

    # ファイルヘッダー
    org_lines.append(f'#+TITLE: Claude Chat History - {input_path.stem}')
    org_lines.append(f'#+DATE: {datetime.now().strftime("[%Y-%m-%d %a]")}')
    org_lines.append('#+AUTHOR: Claude Chat Exporter')
    org_lines.append('#+STARTUP: overview')
    org_lines.append('#+OPTIONS: toc:2 num:nil')
    org_lines.append('')

    # データ構造の判定
    # パターン1: リスト形式 [{conversation}, ...]
    # パターン2: 単一会話オブジェクト {chat_messages: [...]}
    # パターン3: {conversations: [...]} のラッパー形式

    conversations = []

    if isinstance(data, list):
        conversations = data
    elif isinstance(data, dict):
        if 'conversations' in data:
            conversations = data['conversations']
        elif 'chat_messages' in data or 'messages' in data or 'turns' in data:
            # 単一会話
            conversations = [data]
        else:
            # 不明な構造: そのまま単一会話として扱う
            conversations = [data]

    print(f'  → {len(conversations)} 件の会話を変換中...')

    for i, conv in enumerate(conversations, 1):
        try:
            org_lines.append(convert_conversation(conv))
            org_lines.append('')
        except Exception as e:
            org_lines.append(f'* [Error in conversation {i}: {e}]')
            org_lines.append('')

    output_path.write_text('\n'.join(org_lines), encoding='utf-8')
    print(f'  ✓ 保存: {output_path}')


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    input_paths = [Path(p) for p in sys.argv[1:]]

    for input_path in input_paths:
        if not input_path.exists():
            print(f'[ERROR] ファイルが見つかりません: {input_path}')
            continue

        # 出力ファイル名: 同ディレクトリに .org で保存
        output_path = input_path.with_suffix('.org')o
        print(f'\n変換中: {input_path.name}')
        try:
            json_to_org(input_path, output_path)
        except json.JSONDecodeError as e:
            print(f'  [ERROR] JSON パースエラー: {e}')
        except Exception as e:y
            print(f'  [ERROR] 変換エラー: {e}')
            raise

    print('\n完了!')


if __name__ == '__main__':
    main()
