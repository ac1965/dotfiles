#!/usr/bin/env python3
"""
claude_project_sorter.py

claude.ai の会話(チャット)を、指定したプロジェクトへ一括で振り分ける汎用CLIツール。
非公式の内部APIエンドポイント(move_many)を利用するため、仕様変更で動かなくなる可能性がある。

## 不変条件(invariants)
- このスクリプトはユーザー自身のセッションCookieを使い、ユーザー自身のアカウント内の
  データのみを操作する。他アカウント・他組織への操作は行わない。
- 既定は dry-run。実際に移動を実行するには明示的に --apply を指定する。
- Cookieは平文で保存しない。GPG暗号化したファイル(例: cookie.txt.gpg)として保持し、
  --cookie-gpg-file で指定する。復号は都度 `gpg --decrypt` を呼び出して行い、
  この環境の gpg-agent.conf(pinentry-program に pinentry-touchid を設定済み)により
  Touch ID での認証が求められる。復号結果はメモリ上でのみ扱い、平文をディスクに
  書き出さない。
  pinentry-touchid は生体認証失敗時にmacOSログインパスコードへフォールバックしない
  (Touch ID必須・代替経路なし)。これは意図した選択であり、SSH経由・外部ディスプレイ
  ・lid closed等Touch IDが使えない環境では復号が失敗するのが正しい挙動。
  「失敗するから」という理由で pinentry-mac 等フォールバックありの実装に変更しないこと。
  (検証用途に限り --cookie-file で平文ファイルからの読み込みも可能だが、
  そのファイルは絶対にVCS管理下に置かない。cookie.txt / cookie.txt.gpg /
  assignments.json は .gitignore に追加すること。)
- assignments(振り分け定義)は外部JSONファイルとして分離する。コード本体を編集せずに
  対象を変更できるようにするため。

## アンチ最適化チェックリスト(意図的にやらないこと)
- [ ] Cookieをコード内にハードコードしない(GPG暗号化ファイルの復号、または平文ファイルからの読み込みのみ)
- [ ] 復号したCookieを平文でディスクに書き出さない(メモリ上でのみ扱う)
- [ ] --apply なしでの実行では実際のPOSTを送らない(dry-runのみ)
- [ ] エラー発生時に他のプロジェクトへの移動処理を止めない(1件ずつ独立して結果を出す)
- [ ] レート制限対策のsleepを省略しない

## 使い方
    # 0. Cookie文字列を取得したら、平文ファイルに保存せずGPGで暗号化する
    echo -n '<cookie文字列>' | gpg --encrypt --recipient <自分のGPG鍵ID> -o cookie.txt.gpg

    # 1. プロジェクト一覧を確認(project_uuidを控えるため)
    #    実行時にTouch IDでの認証が求められる(gpg-agentがpinentry-touchidを使用)
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg --list-projects

    # 2. 直近のチャット一覧を確認(conversation_uuidを控えるため)
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg --list-conversations --limit 30

    # 3. assignments.json を作成(下記フォーマット参照)し、まずdry-runで確認
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg --assignments assignments.json

    # 4. 問題なければ --apply を付けて実行
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg --assignments assignments.json --apply

## assignments.json のフォーマット
{
  "019ce2a0-71b2-7245-81a6-ef4775d9df7b": [
    "cff8d4a8-3bf4-48c2-b775-ef76a16f7d3f",
    "dbe0ed5e-885d-4b53-9ba8-36e1dd387a04"
  ],
  "019e62ae-31c9-77dc-ae45-360be963c3f8": [
    "2770900d-e6f6-41ce-a6bb-243c4dacb782"
  ]
}
key: 移動先の project_uuid / value: そのプロジェクトへ移動する conversation_uuid のリスト
"""

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

import requests

BASE_URL = "https://claude.ai/api"

# 元のcURLから取得した、通信を通すために必要だったヘッダー群。
# Cloudflareのボット対策があるため、これらを揃えても弾かれる場合は
# curl_cffi やブラウザ自動操作(Playwright等)への切り替えを検討すること。
DEFAULT_HEADERS = {
    "Content-Type": "application/json",
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.6.2 Safari/605.1.15"
    ),
    "Origin": "https://claude.ai",
    "Accept": "*/*",
    "Accept-Language": "ja",
    "anthropic-client-platform": "web_claude_ai",
    "anthropic-client-version": "1.0.0",
}


def load_cookie(cookie_file: str) -> str:
    """平文のCookieファイルからCookie文字列を読み込み、改行を除去して1行にする。
    検証用途のみ。恒常的な保存にはGPG暗号化した --cookie-gpg-file を使うこと。
    """
    path = Path(cookie_file)
    if not path.exists():
        sys.exit(f"[ERROR] Cookieファイルが見つかりません: {cookie_file}")
    raw = path.read_text(encoding="utf-8")
    cookie = raw.replace("\n", "").replace("\r", "").strip()
    if not cookie:
        sys.exit(f"[ERROR] Cookieファイルが空です: {cookie_file}")
    return cookie


def load_cookie_gpg(gpg_file: str) -> str:
    """GPG暗号化されたCookieファイルを復号し、Cookie文字列を返す。

    復号は `gpg --decrypt` の呼び出しに委ね、この環境の gpg-agent.conf
    (pinentry-program = pinentry-touchid) によりTouch IDでの認証が求められる。
    復号結果はメモリ上でのみ扱い、平文をディスクへ書き出すことはない。
    """
    path = Path(gpg_file)
    if not path.exists():
        sys.exit(f"[ERROR] GPG暗号化Cookieファイルが見つかりません: {gpg_file}")
    try:
        result = subprocess.run(
            ["gpg", "--quiet", "--decrypt", str(path)],
            capture_output=True,
            check=True,
        )
    except FileNotFoundError:
        sys.exit("[ERROR] gpg コマンドが見つかりません。GPGをインストールしてください。")
    except subprocess.CalledProcessError as e:
        stderr = e.stderr.decode("utf-8", errors="replace").strip() if e.stderr else ""
        sys.exit(f"[ERROR] GPG復号に失敗しました: {stderr}")
    cookie = result.stdout.decode("utf-8").replace("\n", "").replace("\r", "").strip()
    if not cookie:
        sys.exit(f"[ERROR] 復号したCookieが空です: {gpg_file}")
    return cookie


def build_session(cookie: str) -> requests.Session:
    session = requests.Session()
    headers = dict(DEFAULT_HEADERS)
    headers["Cookie"] = cookie
    session.headers.update(headers)
    return session


def get_org_id(session: requests.Session) -> str:
    """所属組織一覧を取得し、先頭の組織IDを返す。
    複数組織に所属している場合は一覧を表示して選択を促す。
    """
    resp = session.get(f"{BASE_URL}/organizations")
    resp.raise_for_status()
    orgs = resp.json()
    if not orgs:
        sys.exit("[ERROR] 所属組織が見つかりませんでした。")
    if len(orgs) > 1:
        print("[INFO] 複数の組織が見つかりました。--org-id で明示的に指定してください:")
        for org in orgs:
            print(f"  {org.get('uuid')}  {org.get('name')}")
        sys.exit(1)
    return orgs[0]["uuid"]


def list_projects(session: requests.Session, org_id: str) -> None:
    resp = session.get(f"{BASE_URL}/organizations/{org_id}/projects")
    resp.raise_for_status()
    projects = resp.json()
    print(f"{'project_uuid':<38} name")
    print("-" * 60)
    for p in projects:
        print(f"{p.get('uuid'):<38} {p.get('name')}")


def list_conversations(session: requests.Session, org_id: str, limit: int) -> None:
    resp = session.get(
        f"{BASE_URL}/organizations/{org_id}/chat_conversations_v2",
        params={"limit": limit, "archived": "false", "consistency": "strong"},
    )
    resp.raise_for_status()
    conversations = resp.json()
    print(f"{'conversation_uuid':<38} name")
    print("-" * 60)
    for c in conversations:
        name = c.get("name") or "(無題)"
        print(f"{c.get('uuid'):<38} {name}")


def move_many(
    session: requests.Session,
    org_id: str,
    conversation_uuids: list[str],
    project_uuid: str,
    apply: bool,
) -> None:
    if not apply:
        print(f"[DRY-RUN] {len(conversation_uuids)}件 -> {project_uuid}")
        for cid in conversation_uuids:
            print(f"           - {cid}")
        return

    url = f"{BASE_URL}/organizations/{org_id}/chat_conversations/move_many"
    resp = session.post(
        url,
        json={"conversation_uuids": conversation_uuids, "project_uuid": project_uuid},
    )
    try:
        resp.raise_for_status()
        print(f"[OK] {len(conversation_uuids)}件 -> {project_uuid}")
    except requests.HTTPError as e:
        print(f"[NG] {project_uuid}: {e}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    cookie_group = parser.add_mutually_exclusive_group(required=True)
    cookie_group.add_argument(
        "--cookie-gpg-file",
        default=None,
        help="GPG暗号化されたCookieファイル(推奨。復号時にTouch ID認証が求められます)",
    )
    cookie_group.add_argument(
        "--cookie-file",
        default=None,
        help="Cookie文字列を保存した平文テキストファイル(検証用途のみ。VCS管理下に絶対に置かないこと)",
    )
    parser.add_argument("--org-id", default=None, help="組織ID(省略時は自動取得を試みる)")
    parser.add_argument("--assignments", default=None, help="振り分け定義のJSONファイル")
    parser.add_argument("--apply", action="store_true", help="実際に移動を実行する(省略時はdry-run)")
    parser.add_argument("--list-projects", action="store_true", help="プロジェクト一覧を表示して終了")
    parser.add_argument("--list-conversations", action="store_true", help="チャット一覧を表示して終了")
    parser.add_argument("--limit", type=int, default=30, help="--list-conversations 時の取得件数")
    parser.add_argument("--sleep", type=float, default=1.0, help="各リクエスト間のスリープ秒数")
    args = parser.parse_args()

    cookie = load_cookie_gpg(args.cookie_gpg_file) if args.cookie_gpg_file else load_cookie(args.cookie_file)
    session = build_session(cookie)
    org_id = args.org_id or get_org_id(session)

    if args.list_projects:
        list_projects(session, org_id)
        return

    if args.list_conversations:
        list_conversations(session, org_id, args.limit)
        return

    if not args.assignments:
        sys.exit("[ERROR] --assignments を指定するか、--list-projects / --list-conversations を使ってください。")

    assignments_path = Path(args.assignments)
    if not assignments_path.exists():
        sys.exit(f"[ERROR] assignmentsファイルが見つかりません: {args.assignments}")
    assignments = json.loads(assignments_path.read_text(encoding="utf-8"))

    if not args.apply:
        print("[INFO] dry-runモードです。実際には移動しません。--apply を付けると実行します。\n")

    for project_uuid, conv_ids in assignments.items():
        move_many(session, org_id, conv_ids, project_uuid, apply=args.apply)
        time.sleep(args.sleep)


if __name__ == "__main__":
    main()
