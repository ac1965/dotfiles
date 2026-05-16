#!/usr/bin/env python3
"""
safari_bookmark_cleaner.py
Safari の Bookmarks.plist から重複・死活チェックを行い整理するスクリプト

使い方:
  # ドライラン（変更なし・レポートのみ）
  python safari_bookmark_cleaner.py --input ~/Library/Safari/Bookmarks.plist --dry-run

  # 重複のみ削除（死活チェックなし）
  python safari_bookmark_cleaner.py --input ~/Library/Safari/Bookmarks.plist --dedup-only

  # フル実行（重複 + 死活チェック、並列数 30）
  python safari_bookmark_cleaner.py --input ~/Library/Safari/Bookmarks.plist --concurrency 30

  # 出力先を明示
  python safari_bookmark_cleaner.py --input ~/Library/Safari/Bookmarks.plist \
      --output ~/Desktop/Bookmarks_clean.plist --report ~/Desktop/report.json

依存: Python 3.8+ / aiohttp
  pip install aiohttp
"""

import argparse
import asyncio
import copy
import json
import logging
import plistlib
import shutil
import sys
import time
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

try:
    import aiohttp
except ImportError:
    print("ERROR: aiohttp が必要です。  pip install aiohttp", file=sys.stderr)
    sys.exit(1)

# ---------------------------------------------------------------------------
# ログ
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# plist 走査ユーティリティ
# ---------------------------------------------------------------------------

def walk_leaves(node: dict, parent_path: str = "") -> list[dict]:
    """全リーフ（ブックマーク本体）を収集して返す。path情報を付与。"""
    results = []
    t = node.get("WebBookmarkType", "")
    title = node.get("URIDictionary", {}).get("title") or node.get("Title", "") or ""
    if t == "WebBookmarkTypeLeaf":
        node["_path"] = parent_path
        results.append(node)
    elif t == "WebBookmarkTypeList":
        folder_name = title or "Unnamed"
        new_path = f"{parent_path}/{folder_name}" if parent_path else folder_name
        for child in node.get("Children", []):
            results.extend(walk_leaves(child, new_path))
    return results


def remove_dead_from_tree(node: dict, dead_uuids: set[str]) -> dict | None:
    """
    dead_uuids に含まれる UUID のリーフを木から除去して返す。
    フォルダが空になっても残す（意図的な空フォルダ保護）。
    戻り値: 除去後のノード。None を返した場合は呼び出し元が削除する。
    """
    t = node.get("WebBookmarkType", "")
    if t == "WebBookmarkTypeLeaf":
        uid = node.get("WebBookmarkUUID", "")
        return None if uid in dead_uuids else node
    elif t == "WebBookmarkTypeList":
        new_children = []
        for child in node.get("Children", []):
            result = remove_dead_from_tree(child, dead_uuids)
            if result is not None:
                new_children.append(result)
        node = dict(node)
        node["Children"] = new_children
        return node
    else:
        return node  # Proxy など


# ---------------------------------------------------------------------------
# 重複検出
# ---------------------------------------------------------------------------

def find_duplicates(leaves: list[dict]) -> dict[str, list[dict]]:
    """URL → [node, ...] の辞書。値が 2件以上のものが重複。"""
    url_map: dict[str, list[dict]] = defaultdict(list)
    for leaf in leaves:
        url = leaf.get("URLString", "").rstrip("/")
        if url:
            url_map[url].append(leaf)
    return {url: nodes for url, nodes in url_map.items() if len(nodes) > 1}


def pick_survivor(nodes: list[dict]) -> dict:
    """
    重複の中から残す1件を選ぶ。
    優先順位: BookmarksBar > BookmarksMenu > その他
    同じ優先度ならパスが浅い方（フォルダ構造が整理済みの方を尊重）。
    """
    def priority(n: dict) -> tuple:
        path = n.get("_path", "")
        if "BookmarksBar" in path:
            depth = path.count("/")
            return (0, depth)
        elif "BookmarksMenu" in path:
            depth = path.count("/")
            return (1, depth)
        else:
            return (2, path.count("/"))

    return min(nodes, key=priority)


# ---------------------------------------------------------------------------
# 死活チェック（非同期）
# ---------------------------------------------------------------------------

# 明らかに到達不能なスキームは即 dead
_DEAD_SCHEMES = {"chrome", "about", "javascript", "data", "file"}

# HTTP ステータスで dead と判定するコード
_DEAD_STATUS = {404, 410, 451}

# ドメイン自体が廃止/移転済みと既知のパターン（正規表現不使用・単純文字列マッチ）
_KNOWN_DEAD_DOMAINS = {
    "manga-zip.net",
    "anitube.se",
    "matome.naver.jp",       # サービス終了
    "homepage2.nifty.com",
    "geocities.jp",
    "inoreader.com",         # 存続確認要
    "bbs.cnhonker.com",
    "cnhonkerarmy.com",
    "backtrack-linux.org",
    "niku.name",
    "lab.raqda.com",
    "d.hatena.ne.jp",        # 多くが閉鎖済み（個別確認推奨）
}

TIMEOUT_SEC = 10
MAX_REDIRECTS = 5


def is_trivially_dead(url: str) -> str | None:
    """スキームやドメインだけで即判定できる場合は理由文字列を返す。"""
    try:
        parsed = urlparse(url)
    except Exception:
        return "parse_error"
    scheme = parsed.scheme.lower()
    if scheme in _DEAD_SCHEMES:
        return f"dead_scheme:{scheme}"
    domain = parsed.netloc.lower().lstrip("www.")
    if any(domain == d or domain.endswith("." + d) for d in _KNOWN_DEAD_DOMAINS):
        return f"known_dead_domain:{domain}"
    return None


async def check_url(
    session: aiohttp.ClientSession,
    url: str,
    semaphore: asyncio.Semaphore,
) -> tuple[str, str, int | None]:
    """
    Returns (url, status_label, http_code)
    status_label: "ok" | "dead" | "redirect" | "timeout" | "error" | "skip"
    """
    trivial = is_trivially_dead(url)
    if trivial:
        return (url, "dead", None)

    async with semaphore:
        try:
            async with session.head(
                url,
                allow_redirects=True,
                max_redirects=MAX_REDIRECTS,
                timeout=aiohttp.ClientTimeout(total=TIMEOUT_SEC),
                ssl=False,
            ) as resp:
                code = resp.status
                if code in _DEAD_STATUS:
                    return (url, "dead", code)
                elif code >= 400:
                    # 一部サーバーは HEAD を拒否する → GET で再試行
                    pass
                else:
                    return (url, "ok", code)
        except (aiohttp.ClientConnectorError, aiohttp.ClientOSError):
            return (url, "dead", None)
        except asyncio.TimeoutError:
            return (url, "timeout", None)
        except Exception:
            pass  # HEAD 失敗 → GET fallback

        # GET fallback（HEAD を拒否するサーバー向け）
        try:
            async with session.get(
                url,
                allow_redirects=True,
                max_redirects=MAX_REDIRECTS,
                timeout=aiohttp.ClientTimeout(total=TIMEOUT_SEC),
                ssl=False,
            ) as resp:
                code = resp.status
                if code in _DEAD_STATUS:
                    return (url, "dead", code)
                elif code >= 500:
                    return (url, "error", code)
                else:
                    return (url, "ok", code)
        except (aiohttp.ClientConnectorError, aiohttp.ClientOSError):
            return (url, "dead", None)
        except asyncio.TimeoutError:
            return (url, "timeout", None)
        except Exception as e:
            return (url, "error", None)


async def check_all_urls(
    urls: list[str],
    concurrency: int,
    progress_interval: int = 50,
) -> dict[str, tuple[str, int | None]]:
    """url → (status_label, http_code) の辞書を返す。"""
    semaphore = asyncio.Semaphore(concurrency)
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            "Version/17.0 Safari/605.1.15"
        )
    }
    connector = aiohttp.TCPConnector(limit=concurrency, force_close=True)
    results: dict[str, tuple[str, int | None]] = {}
    total = len(urls)
    done = 0
    start = time.time()

    async with aiohttp.ClientSession(headers=headers, connector=connector) as session:
        tasks = [check_url(session, url, semaphore) for url in urls]
        for coro in asyncio.as_completed(tasks):
            url, label, code = await coro
            results[url] = (label, code)
            done += 1
            if done % progress_interval == 0 or done == total:
                elapsed = time.time() - start
                eta = (elapsed / done) * (total - done) if done else 0
                log.info(
                    f"  進捗: {done}/{total}  "
                    f"経過 {elapsed:.0f}s  残り推定 {eta:.0f}s"
                )

    return results


# ---------------------------------------------------------------------------
# メイン処理
# ---------------------------------------------------------------------------

def build_report(
    all_leaves: list[dict],
    dup_map: dict[str, list[dict]],
    dead_uuids: set[str],
    url_results: dict[str, tuple[str, int | None]],
    removed_uuids: set[str],
) -> dict:
    """JSON レポート用辞書を構築。"""
    removed_as_dup = []
    removed_as_dead = []
    removed_as_dup_dead = []

    for leaf in all_leaves:
        uid = leaf.get("WebBookmarkUUID", "")
        url = leaf.get("URLString", "")
        title = leaf.get("URIDictionary", {}).get("title", "")
        path = leaf.get("_path", "")
        entry = {"uuid": uid, "url": url, "title": title, "path": path}

        is_dup_removed = uid in removed_uuids and url in dup_map
        is_dead = uid in dead_uuids

        if is_dup_removed and is_dead:
            removed_as_dup_dead.append(entry)
        elif is_dup_removed:
            removed_as_dup.append(entry)
        elif is_dead:
            removed_as_dead.append(entry)

    return {
        "generated_at": datetime.now().isoformat(),
        "summary": {
            "total_input": len(all_leaves),
            "removed_duplicates": len(removed_as_dup),
            "removed_dead": len(removed_as_dead),
            "removed_dup_and_dead": len(removed_as_dup_dead),
            "total_removed": len(removed_uuids | dead_uuids),
            "remaining": len(all_leaves) - len(removed_uuids | dead_uuids),
        },
        "url_check_results": {
            label: len([v for v in url_results.values() if v[0] == label])
            for label in ("ok", "dead", "timeout", "error", "skip")
        },
        "removed_as_duplicate": removed_as_dup,
        "removed_as_dead": removed_as_dead,
        "removed_as_both": removed_as_dup_dead,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Safari Bookmarks.plist の重複・死活チェックと整理",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--input", "-i",
        default="~/Library/Safari/Bookmarks.plist",
        help="入力 plist パス（デフォルト: ~/Library/Safari/Bookmarks.plist）",
    )
    parser.add_argument(
        "--output", "-o",
        default=None,
        help="出力 plist パス（省略時: 入力ファイルを .bak バックアップ後に上書き）",
    )
    parser.add_argument(
        "--report", "-r",
        default=None,
        help="JSON レポート出力先（省略時: 入力と同ディレクトリに _report.json）",
    )
    parser.add_argument(
        "--dry-run", "-n",
        action="store_true",
        help="変更を保存せずレポートのみ出力",
    )
    parser.add_argument(
        "--dedup-only",
        action="store_true",
        help="重複削除のみ実行（死活チェックをスキップ）",
    )
    parser.add_argument(
        "--concurrency", "-c",
        type=int,
        default=30,
        help="死活チェックの並列数（デフォルト: 30）",
    )
    parser.add_argument(
        "--skip-timeout",
        action="store_true",
        help="タイムアウトしたURLを dead 扱いにする（デフォルト: 保持）",
    )
    parser.add_argument(
        "--keep-empty-folders",
        action="store_true",
        default=True,
        help="ブックマーク削除後に空になったフォルダを残す（デフォルト: True）",
    )
    args = parser.parse_args()

    # パス解決
    input_path = Path(args.input).expanduser().resolve()
    if not input_path.exists():
        log.error(f"入力ファイルが見つかりません: {input_path}")
        sys.exit(1)

    output_path = (
        Path(args.output).expanduser().resolve()
        if args.output
        else input_path
    )
    report_path = (
        Path(args.report).expanduser().resolve()
        if args.report
        else input_path.parent / (input_path.stem + "_report.json")
    )

    # ---------------------------------------------------------------------------
    # 1. plist 読み込み
    # ---------------------------------------------------------------------------
    log.info(f"読み込み: {input_path}")
    with input_path.open("rb") as f:
        root = plistlib.load(f)

    all_leaves = walk_leaves(root)
    log.info(f"ブックマーク総数: {len(all_leaves)}")

    # ---------------------------------------------------------------------------
    # 2. 重複検出
    # ---------------------------------------------------------------------------
    log.info("── 重複チェック ──")
    dup_map = find_duplicates(all_leaves)
    log.info(f"重複URL数: {len(dup_map)}  (重複インスタンス合計: {sum(len(v) for v in dup_map.values())})")

    # 重複の中で「削除」する UUID を収集（survivor 以外）
    dup_remove_uuids: set[str] = set()
    for url, nodes in dup_map.items():
        survivor = pick_survivor(nodes)
        for n in nodes:
            if n.get("WebBookmarkUUID") != survivor.get("WebBookmarkUUID"):
                dup_remove_uuids.add(n.get("WebBookmarkUUID", ""))

    log.info(f"重複により削除対象: {len(dup_remove_uuids)} 件")

    # ---------------------------------------------------------------------------
    # 3. 死活チェック
    # ---------------------------------------------------------------------------
    dead_uuids: set[str] = set()
    url_results: dict[str, tuple[str, int | None]] = {}

    if not args.dedup_only:
        # 重複の survivor のみをチェック対象にする（削除済みは不要）
        check_targets = [
            leaf for leaf in all_leaves
            if leaf.get("WebBookmarkUUID", "") not in dup_remove_uuids
        ]
        urls_to_check = [
            leaf.get("URLString", "")
            for leaf in check_targets
            if leaf.get("URLString", "")
        ]
        urls_to_check = list(dict.fromkeys(urls_to_check))  # dedup

        log.info(f"── 死活チェック開始: {len(urls_to_check)} URL, 並列数 {args.concurrency} ──")
        url_results = asyncio.run(
            check_all_urls(urls_to_check, args.concurrency)
        )

        # dead / timeout → UUID 収集
        for leaf in check_targets:
            url = leaf.get("URLString", "")
            label, code = url_results.get(url, ("skip", None))
            if label == "dead":
                dead_uuids.add(leaf.get("WebBookmarkUUID", ""))
            elif label == "timeout" and args.skip_timeout:
                dead_uuids.add(leaf.get("WebBookmarkUUID", ""))

        dead_cnt = len([v for v in url_results.values() if v[0] == "dead"])
        timeout_cnt = len([v for v in url_results.values() if v[0] == "timeout"])
        log.info(f"dead: {dead_cnt}  timeout: {timeout_cnt}  → 削除対象: {len(dead_uuids)} 件")
    else:
        log.info("死活チェックをスキップ（--dedup-only）")

    # ---------------------------------------------------------------------------
    # 4. レポート生成
    # ---------------------------------------------------------------------------
    all_remove_uuids = dup_remove_uuids | dead_uuids
    report = build_report(all_leaves, dup_map, dead_uuids, url_results, dup_remove_uuids)

    log.info("── サマリー ──")
    s = report["summary"]
    log.info(f"  入力総数       : {s['total_input']}")
    log.info(f"  重複削除       : {s['removed_duplicates']} 件")
    log.info(f"  dead 削除      : {s['removed_dead']} 件")
    log.info(f"  重複+dead      : {s['removed_dup_and_dead']} 件")
    log.info(f"  削除合計       : {len(all_remove_uuids)} 件")
    log.info(f"  残存           : {s['total_input'] - len(all_remove_uuids)} 件")

    if args.dry_run:
        log.info("ドライランのため plist は保存しません")
    else:
        # -----------------------------------------------------------------------
        # 5. plist 書き出し
        # -----------------------------------------------------------------------
        # バックアップ（入力と出力が同一パスの場合のみ）
        if output_path == input_path:
            bak_path = input_path.with_suffix(
                f".bak_{datetime.now().strftime('%Y%m%d_%H%M%S')}.plist"
            )
            shutil.copy2(input_path, bak_path)
            log.info(f"バックアップ: {bak_path}")

        # 木から除去
        new_root = remove_dead_from_tree(copy.deepcopy(root), all_remove_uuids)

        with output_path.open("wb") as f:
            plistlib.dump(new_root, f, fmt=plistlib.FMT_XML)
        log.info(f"出力: {output_path}")

    # レポート保存
    with report_path.open("w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    log.info(f"レポート: {report_path}")


if __name__ == "__main__":
    main()
