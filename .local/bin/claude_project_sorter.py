#!/usr/bin/env python3
"""
claude_project_sorter.py

claude.ai の会話(チャット)を、指定したプロジェクトへ一括で振り分ける汎用CLIツール。
会話のスター付け/解除にも対応する。非公式の内部APIエンドポイント(move_many,
chat_conversations の PUT)を利用するため、仕様変更で動かなくなる可能性がある。

## 不変条件(invariants)
- このスクリプトはユーザー自身のセッションCookieを使い、ユーザー自身のアカウント内の
  データのみを操作する。他アカウント・他組織への操作は行わない。
- 既定は dry-run。実際に移動を実行するには明示的に --apply を指定する。
- Cookieは平文で保存しない。GPG暗号化したファイル(例: cookie.txt.gpg)として保持し、
  --cookie-gpg-file で指定する。復号は都度 `gpg --decrypt` を呼び出して行い、
  この環境の gpg-agent.conf(pinentry-program に pinentry-mac を設定済み)による
  認証が求められる(Touch IDも使えるが、失敗時は通常のパスフレーズダイアログに
  フォールバックする)。復号結果はメモリ上でのみ扱い、平文をディスクに書き出さない。
  以前はTouch ID専用の pinentry-touchid(フォールバックなし)を使っていたが、
  macOS 27でTouch ID認証セッションが正しく有効化されず、パスワードでの代替入力も
  失敗する不具合を確認したため pinentry-mac に切り替えた(詳細はAGENTS.md参照)。
  (検証用途に限り --cookie-file で平文ファイルからの読み込みも可能だが、
  そのファイルは絶対にVCS管理下に置かない。cookie.txt / cookie.txt.gpg /
  assignments.json は .gitignore に追加すること。)
- assignments(振り分け定義)は外部JSONファイルとして分離する。コード本体を編集せずに
  対象を変更できるようにするため。
- --star / --unstar / --unassign / --delete も --apply なしではdry-runのみ
  (move_manyと同じ安全設計)。
- --delete は**取り消せない破壊的操作**。他の操作(移動・スター・割り当て解除)は
  すべて元に戻せるが、削除だけは元に戻せない。実装や動作確認で --apply を付けて
  実際に叩くテストは行わないこと(dry-runの出力確認までに留める)。
- --auto-refresh-cookie 指定時、APIが `account_session_invalid`(Cookieセッション
  無効)を返した場合に限り、--refresh-browser で指定したブラウザ(既定: safari)の
  ローカルcookieストアから claude.ai のCookieを読み直し、GPGで再暗号化して
  --cookie-gpg-file を上書きする。ユーザー名/パスワードを自動入力してログインし
  直す処理は行わない(あくまで、ブラウザで既にログイン済みのセッションを読み取る
  だけ)。account_session_invalid 以外の403(組織権限エラー等)では再取得しない。
  Chromeは復号鍵をmacOS Keychainの同意ダイアログ経由で取得する必要があり、
  macOS 27でこのダイアログがフォーカスを受け取れず操作不能になる不具合を確認して
  いるため、既定はSafari(ダイアログを経由せずファイルを直接パースするだけ)。

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
    #    実行時にgpg-agent(pinentry-mac)による認証が求められる
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg --list-projects

    # 2. 直近のチャット一覧を確認(conversation_uuidを控えるため)
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg --list-conversations --limit 30

    # 3. assignments.json を作成(下記フォーマット参照)し、まずdry-runで確認
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg --assignments assignments.json

    # 4. 問題なければ --apply を付けて実行
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg --assignments assignments.json --apply

    # Cookie期限切れ時にSafariから自動再取得したい場合は --auto-refresh-cookie と
    # --gpg-recipient を追加する(要: Safariでclaude.aiにログイン済み、要:
    # pip install browser_cookie3)
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg --list-projects \
        --auto-refresh-cookie --gpg-recipient ac1965@ty07.net

    # 会話にスターを付ける/外す(--apply が必要、複数UUID指定可)
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg \
        --star <conversation_uuid1> <conversation_uuid2> --apply
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg \
        --unstar <conversation_uuid> --apply

    # 会話名を変更する(--rename UUID NEW_NAME、複数回指定可)
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg \
        --rename <conversation_uuid> "新しい名前" --apply

    # 会話をプロジェクトから割り当て解除する(move_manyにproject_uuid=nullを送信)
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg \
        --unassign <conversation_uuid> --apply

    # スター付きの会話だけ一覧表示
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg \
        --list-conversations --starred-only --limit 30

    # 会話を完全に削除する(取り消せません。実行前に --list-conversations で
    # UUIDと会話名を必ず確認すること)
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg \
        --delete <conversation_uuid> --apply

    # 複数件まとめて処理したい場合は、CLI引数の代わりにJSONファイルでも指定できる
    # (star.example.json / unstar.example.json / rename.example.json /
    #  unassign.example.json / delete.example.json 参照。インライン引数と併用可)
    python claude_project_sorter.py --cookie-gpg-file cookie.txt.gpg \
        --star-file star.json --apply

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


def fetch_cookie_from_browser(browser: str) -> str:
    """指定したブラウザのローカルcookieストアから claude.ai のCookieを読み取る。

    ユーザー名/パスワードの自動入力は一切行わない。あくまでブラウザで既に
    ログイン済みのセッションを読み取るだけ。

    - safari(既定): `~/Library/.../Cookies.binarycookies` を直接パースするだけで、
      Keychainの同意ダイアログを経由しない。フルディスクアクセス権限のみ必要。
    - chrome: 復号鍵をmacOS Keychain(Chrome Safe Storage)から取得するため、
      対話的な同意ダイアログが出る。macOS 27でこのダイアログがフォーカスを
      受け取れず操作不能になる不具合を確認しているため、直るまで非推奨。
    """
    try:
        import browser_cookie3
    except ImportError:
        sys.exit(
            "[ERROR] --auto-refresh-cookie には browser_cookie3 が必要です: "
            "pip install browser_cookie3"
        )
    if browser == "safari":
        cookiejar = browser_cookie3.safari(domain_name="claude.ai")
    elif browser == "chrome":
        cookiejar = browser_cookie3.chrome(domain_name="claude.ai")
    else:
        sys.exit(f"[ERROR] 未対応のブラウザです: {browser}")
    cookie = "; ".join(f"{c.name}={c.value}" for c in cookiejar)
    if not cookie:
        sys.exit(
            f"[ERROR] {browser}からclaude.aiのCookieを取得できませんでした。"
            f"{browser}でclaude.aiにログインしているか確認してください。"
        )
    return cookie


def encrypt_cookie_gpg(cookie: str, gpg_file: str, recipient: str) -> None:
    """Cookie文字列をGPGで暗号化し、gpg_file に書き出す(既存ファイルは上書き)。
    平文をディスクへ書き出すことはない(gpgへの標準入力経由のみ)。
    """
    try:
        subprocess.run(
            ["gpg", "--yes", "--encrypt", "--recipient", recipient, "-o", gpg_file],
            input=cookie.encode("utf-8"),
            check=True,
            capture_output=True,
        )
    except FileNotFoundError:
        sys.exit("[ERROR] gpg コマンドが見つかりません。GPGをインストールしてください。")
    except subprocess.CalledProcessError as e:
        stderr = e.stderr.decode("utf-8", errors="replace").strip() if e.stderr else ""
        sys.exit(f"[ERROR] Cookieの再暗号化に失敗しました: {stderr}")


def is_session_invalid_response(resp: requests.Response) -> bool:
    """claude.aiが返す account_session_invalid エラーかどうかを判定する。
    account_session_invalid 以外の403(組織権限エラー等)はここではFalseになり、
    自動再取得の対象にしない。
    """
    if resp.status_code not in (401, 403):
        return False
    try:
        body = resp.json()
    except ValueError:
        return False
    error_code = body.get("error", {}).get("details", {}).get("error_code")
    return error_code == "account_session_invalid"


class AutoRefreshSession:
    """requests.Session をラップし、account_session_invalid を検知したら
    ブラウザから新しいCookieを取得してGPG再暗号化し、1回だけリトライする。
    それ以外のエラー(組織権限エラー等)はそのまま呼び出し元に返す。
    """

    def __init__(self, session: requests.Session, gpg_file: str, recipient: str, browser: str = "safari"):
        self._session = session
        self._gpg_file = gpg_file
        self._recipient = recipient
        self._browser = browser

    def _refresh(self) -> None:
        print(f"[INFO] Cookieセッションが無効です。{self._browser}から再取得してGPG再暗号化します...")
        cookie = fetch_cookie_from_browser(self._browser)
        encrypt_cookie_gpg(cookie, self._gpg_file, self._recipient)
        self._session.headers["Cookie"] = cookie
        print(f"[INFO] {self._gpg_file} を更新しました。")

    def request(self, method: str, url: str, **kwargs) -> requests.Response:
        resp = getattr(self._session, method)(url, **kwargs)
        if is_session_invalid_response(resp):
            self._refresh()
            resp = getattr(self._session, method)(url, **kwargs)
        return resp

    def get(self, url: str, **kwargs) -> requests.Response:
        return self.request("get", url, **kwargs)

    def post(self, url: str, **kwargs) -> requests.Response:
        return self.request("post", url, **kwargs)


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


def list_conversations(session: requests.Session, org_id: str, limit: int, starred_only: bool = False) -> None:
    params = {"limit": limit, "archived": "false", "consistency": "strong"}
    if starred_only:
        params["starred"] = "true"
    resp = session.get(
        f"{BASE_URL}/organizations/{org_id}/chat_conversations_v2",
        params=params,
    )
    resp.raise_for_status()
    payload = resp.json()
    # chat_conversations_v2 は {"data": [...], "has_more": bool} 形式を返す
    # (以前は素の配列だったため、仕様変更で構造が変わった)
    conversations = payload["data"] if isinstance(payload, dict) else payload
    print(f"{'conversation_uuid':<38} name")
    print("-" * 60)
    for c in conversations:
        name = c.get("name") or "(無題)"
        print(f"{c.get('uuid'):<38} {name}")
    if isinstance(payload, dict) and payload.get("has_more"):
        print(f"\n[INFO] 他にも会話があります(has_more=true)。--limit を増やして確認してください。")


MOVE_MANY_MAX_PER_REQUEST = 50  # API制限: 1回のmove_manyで送れるのは最大50件


def move_many(
    session: requests.Session,
    org_id: str,
    conversation_uuids: list[str],
    project_uuid: str | None,
    apply: bool,
    sleep: float = 1.0,
) -> None:
    """project_uuid に None を渡すと、プロジェクトからの割り当て解除になる
    (claude.aiのWeb UIでの「プロジェクトから削除」操作と同じリクエスト)。

    APIは1回のリクエストで最大 MOVE_MANY_MAX_PER_REQUEST 件までしか受け付けない
    (超えると "Cannot move more than 50 conversations at once" で400エラーになる)
    ため、50件ずつのチャンクに分割して送信する。
    """
    label = project_uuid if project_uuid is not None else "(プロジェクト解除)"
    if not apply:
        print(f"[DRY-RUN] {len(conversation_uuids)}件 -> {label}")
        for cid in conversation_uuids:
            print(f"           - {cid}")
        return

    url = f"{BASE_URL}/organizations/{org_id}/chat_conversations/move_many"
    chunks = [
        conversation_uuids[i : i + MOVE_MANY_MAX_PER_REQUEST]
        for i in range(0, len(conversation_uuids), MOVE_MANY_MAX_PER_REQUEST)
    ]
    for i, chunk in enumerate(chunks):
        resp = session.post(url, json={"conversation_uuids": chunk, "project_uuid": project_uuid})
        try:
            resp.raise_for_status()
            print(f"[OK] {len(chunk)}件 -> {label}")
        except requests.HTTPError as e:
            print(f"[NG] {label}: {e}")
        if i < len(chunks) - 1:
            time.sleep(sleep)


def set_starred(
    session: requests.Session,
    org_id: str,
    conversation_uuid: str,
    starred: bool,
    apply: bool,
) -> None:
    """会話のスター付け/解除。move_many同様、--apply なしではdry-runのみ。"""
    action = "スター付け" if starred else "スター解除"
    if not apply:
        print(f"[DRY-RUN] {action}: {conversation_uuid}")
        return

    url = f"{BASE_URL}/organizations/{org_id}/chat_conversations/{conversation_uuid}"
    resp = session.put(
        url,
        params={"rendering_mode": "raw"},
        json={"is_starred": starred},
    )
    try:
        resp.raise_for_status()
        print(f"[OK] {action}: {conversation_uuid}")
    except requests.HTTPError as e:
        print(f"[NG] {conversation_uuid}: {e}")


def rename_conversation(
    session: requests.Session,
    org_id: str,
    conversation_uuid: str,
    name: str,
    apply: bool,
) -> None:
    """会話名を変更する。set_starredと同じエンドポイントだが、こちらは
    rendering_mode=raw クエリパラメータなしでキャプチャされた。
    --apply なしではdry-runのみ。
    """
    if not apply:
        print(f"[DRY-RUN] リネーム: {conversation_uuid} -> {name!r}")
        return

    url = f"{BASE_URL}/organizations/{org_id}/chat_conversations/{conversation_uuid}"
    resp = session.put(url, json={"name": name})
    try:
        resp.raise_for_status()
        print(f"[OK] リネーム: {conversation_uuid} -> {name!r}")
    except requests.HTTPError as e:
        print(f"[NG] {conversation_uuid}: {e}")


def delete_conversation(
    session: requests.Session,
    org_id: str,
    conversation_uuid: str,
    apply: bool,
) -> None:
    """会話を完全に削除する。**取り消せない破壊的操作**。move_many/set_starredと
    同じくdry-run既定だが、他の操作(移動・スター)と違って元に戻せないため、
    --apply 実行時は追加の警告を出す(呼び出し元のmain()側で表示)。
    """
    if not apply:
        print(f"[DRY-RUN] 削除: {conversation_uuid}")
        return

    url = f"{BASE_URL}/organizations/{org_id}/chat_conversations/{conversation_uuid}"
    resp = session.delete(url)
    try:
        resp.raise_for_status()
        print(f"[OK] 削除: {conversation_uuid}")
    except requests.HTTPError as e:
        print(f"[NG] {conversation_uuid}: {e}")


def load_uuid_list_json(path: str) -> list[str]:
    """会話UUIDの配列(JSON list)を読み込む。
    star.example.json / unstar.example.json / unassign.example.json /
    delete.example.json と同じフォーマット。
    """
    p = Path(path)
    if not p.exists():
        sys.exit(f"[ERROR] ファイルが見つかりません: {path}")
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        sys.exit(f"[ERROR] {path} はUUIDの配列(JSON list)である必要があります。")
    return data


def load_rename_map_json(path: str) -> dict[str, str]:
    """{conversation_uuid: 新しい名前} 形式のJSONを読み込む。
    rename.example.json と同じフォーマット。
    """
    p = Path(path)
    if not p.exists():
        sys.exit(f"[ERROR] ファイルが見つかりません: {path}")
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        sys.exit(f"[ERROR] {path} は {{uuid: 新しい名前}} 形式のJSONオブジェクトである必要があります。")
    return data


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
    parser.add_argument(
        "--star",
        nargs="+",
        metavar="CONVERSATION_UUID",
        default=None,
        help="指定した会話にスターを付ける(複数指定可、--apply が必要)",
    )
    parser.add_argument(
        "--star-file",
        default=None,
        help="スターを付ける会話UUIDのJSON配列ファイル(star.example.json参照。--starと併用可)",
    )
    parser.add_argument(
        "--unstar",
        nargs="+",
        metavar="CONVERSATION_UUID",
        default=None,
        help="指定した会話のスターを外す(複数指定可、--apply が必要)",
    )
    parser.add_argument(
        "--unstar-file",
        default=None,
        help="スターを外す会話UUIDのJSON配列ファイル(unstar.example.json参照。--unstarと併用可)",
    )
    parser.add_argument(
        "--rename",
        nargs=2,
        action="append",
        metavar=("CONVERSATION_UUID", "NEW_NAME"),
        default=None,
        help="会話名を変更する(--rename UUID NEW_NAME。複数回指定可、--apply が必要)",
    )
    parser.add_argument(
        "--rename-file",
        default=None,
        help="{uuid: 新しい名前} 形式のJSONファイル(rename.example.json参照。--renameと併用可)",
    )
    parser.add_argument(
        "--unassign",
        nargs="+",
        metavar="CONVERSATION_UUID",
        default=None,
        help=(
            "指定した会話をプロジェクトから割り当て解除する"
            "(move_manyにproject_uuid=nullを送信。複数指定可、--apply が必要)"
        ),
    )
    parser.add_argument(
        "--unassign-file",
        default=None,
        help="割り当て解除する会話UUIDのJSON配列ファイル(unassign.example.json参照。--unassignと併用可)",
    )
    parser.add_argument(
        "--starred-only",
        action="store_true",
        help="--list-conversations でスター付きの会話のみ表示する",
    )
    parser.add_argument(
        "--delete",
        nargs="+",
        metavar="CONVERSATION_UUID",
        default=None,
        help=(
            "指定した会話を完全に削除する。取り消せません。"
            "実行前に --list-conversations でUUIDを必ず確認すること"
            "(複数指定可、--apply が必要)"
        ),
    )
    parser.add_argument(
        "--delete-file",
        default=None,
        help=(
            "削除する会話UUIDのJSON配列ファイル(delete.example.json参照。取り消せません。"
            "--deleteと併用可)"
        ),
    )
    parser.add_argument("--limit", type=int, default=30, help="--list-conversations 時の取得件数")
    parser.add_argument("--sleep", type=float, default=1.0, help="各リクエスト間のスリープ秒数")
    parser.add_argument(
        "--auto-refresh-cookie",
        action="store_true",
        help=(
            "Cookieセッション無効(account_session_invalid)時にブラウザから自動再取得し、"
            "--cookie-gpg-file を上書きする(要 --gpg-recipient, pip install browser_cookie3)"
        ),
    )
    parser.add_argument(
        "--refresh-browser",
        default="safari",
        choices=["safari", "chrome"],
        help=(
            "--auto-refresh-cookie 使用時にCookieを読み取るブラウザ(既定: safari)。"
            "chromeは復号鍵取得でmacOSのKeychain同意ダイアログが必要"
        ),
    )
    parser.add_argument(
        "--gpg-recipient",
        default=None,
        help="--auto-refresh-cookie 使用時の暗号化先(メールアドレスまたは鍵ID)",
    )
    args = parser.parse_args()

    if args.auto_refresh_cookie and not (args.cookie_gpg_file and args.gpg_recipient):
        sys.exit("[ERROR] --auto-refresh-cookie には --cookie-gpg-file と --gpg-recipient の両方が必要です。")

    cookie = load_cookie_gpg(args.cookie_gpg_file) if args.cookie_gpg_file else load_cookie(args.cookie_file)
    raw_session = build_session(cookie)
    if args.auto_refresh_cookie:
        session = AutoRefreshSession(raw_session, args.cookie_gpg_file, args.gpg_recipient, args.refresh_browser)
    else:
        session = raw_session
    org_id = args.org_id or get_org_id(session)

    if args.list_projects:
        list_projects(session, org_id)
        return

    if args.list_conversations:
        list_conversations(session, org_id, args.limit, starred_only=args.starred_only)
        return

    star_uuids = list(args.star or [])
    if args.star_file:
        star_uuids += load_uuid_list_json(args.star_file)

    unstar_uuids = list(args.unstar or [])
    if args.unstar_file:
        unstar_uuids += load_uuid_list_json(args.unstar_file)

    rename_pairs = list(args.rename or [])
    if args.rename_file:
        rename_pairs += list(load_rename_map_json(args.rename_file).items())

    unassign_uuids = list(args.unassign or [])
    if args.unassign_file:
        unassign_uuids += load_uuid_list_json(args.unassign_file)

    delete_uuids = list(args.delete or [])
    if args.delete_file:
        delete_uuids += load_uuid_list_json(args.delete_file)

    if star_uuids or unstar_uuids or rename_pairs or unassign_uuids or delete_uuids:
        if not args.apply:
            print("[INFO] dry-runモードです。実際には変更しません。--apply を付けると実行します。\n")
        for cid in star_uuids:
            set_starred(session, org_id, cid, True, apply=args.apply)
            time.sleep(args.sleep)
        for cid in unstar_uuids:
            set_starred(session, org_id, cid, False, apply=args.apply)
            time.sleep(args.sleep)
        for cid, name in rename_pairs:
            rename_conversation(session, org_id, cid, name, apply=args.apply)
            time.sleep(args.sleep)
        if unassign_uuids:
            move_many(session, org_id, unassign_uuids, None, apply=args.apply, sleep=args.sleep)
        if delete_uuids:
            if args.apply:
                print(f"[WARNING] {len(delete_uuids)}件の会話を完全に削除します。この操作は取り消せません。")
            for cid in delete_uuids:
                delete_conversation(session, org_id, cid, apply=args.apply)
                time.sleep(args.sleep)
        return

    if not args.assignments:
        sys.exit(
            "[ERROR] --assignments を指定するか、--list-projects / --list-conversations / "
            "--star[-file] / --unstar[-file] / --rename[-file] / --unassign[-file] / "
            "--delete[-file] を使ってください。"
        )

    assignments_path = Path(args.assignments)
    if not assignments_path.exists():
        sys.exit(f"[ERROR] assignmentsファイルが見つかりません: {args.assignments}")
    assignments = json.loads(assignments_path.read_text(encoding="utf-8"))

    if not args.apply:
        print("[INFO] dry-runモードです。実際には移動しません。--apply を付けると実行します。\n")

    for project_uuid, conv_ids in assignments.items():
        move_many(session, org_id, conv_ids, project_uuid, apply=args.apply, sleep=args.sleep)
        time.sleep(args.sleep)


if __name__ == "__main__":
    main()
