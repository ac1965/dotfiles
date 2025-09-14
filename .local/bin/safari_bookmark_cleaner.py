#!/usr/bin/env python3
import os
import plistlib
import shutil
import subprocess
import sys


DEFAULT_BOOKMARKS_PATH = os.path.expanduser("~/Library/Safari/Bookmarks.plist")
DEFAULT_BACKUP_SUFFIX = "_backup.plist"


def is_safari_running():
    result = subprocess.run(
        ["pgrep", "-x", "Safari"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )
    return result.returncode == 0


def quit_safari():
    subprocess.run(["osascript", "-e", 'tell application "Safari" to quit'])
    print("🛑 Safari を終了しました。")


def prompt_to_quit_safari():
    if is_safari_running():
        response = input(
            "⚠️ Safariが実行中です。終了してもよろしいですか？ [y/N]: "
        ).lower()
        if response == "y":
            quit_safari()
        else:
            print(
                "🚫 Safariが開いているため中断しました。Safariを手動で終了してから再実行してください。"
            )
            sys.exit(1)


def backup_bookmarks(bookmarks_path, backup_path):
    if not os.path.exists(backup_path):
        shutil.copy2(bookmarks_path, backup_path)
        print(f"✅ バックアップ作成済み: {backup_path}")
    else:
        print(f"📦 既存のバックアップがあります: {backup_path}")


def restore_from_backup(bookmarks_path, backup_path):
    if os.path.exists(backup_path):
        shutil.copy2(backup_path, bookmarks_path)
        print(f"✅ バックアップから復元完了: {bookmarks_path}")
    else:
        print(f"❌ バックアップが見つかりません: {backup_path}")


def load_bookmarks(bookmarks_path):
    with open(bookmarks_path, "rb") as f:
        return plistlib.load(f)


def save_bookmarks(bookmarks_path, data):
    with open(bookmarks_path, "wb") as f:
        plistlib.dump(data, f)
    print(f"✅ ブックマークを更新しました: {bookmarks_path}")


def remove_duplicates_recursive(children, seen_entries, dry_run=False):
    if not isinstance(children, list):
        return []

    cleaned = []
    for item in children:
        if item.get("WebBookmarkType") == "WebBookmarkTypeList":
            item["Children"] = remove_duplicates_recursive(
                item.get("Children", []), seen_entries, dry_run
            )
            cleaned.append(item)
        elif item.get("URLString"):
            url = item["URLString"]
            title = item.get("URIDictionary", {}).get("title", "").strip()
            entry_key = (title, url)
            if entry_key not in seen_entries:
                seen_entries.add(entry_key)
                cleaned.append(item)
            else:
                print(f"🗑 重複候補: {title} - {url}")
                if dry_run:
                    cleaned.append(item)
        else:
            cleaned.append(item)
    return cleaned


def clean_bookmarks(bookmarks_path, dry_run=False, backup_path=None, restore=False):
    backup_path = backup_path or (
        bookmarks_path.replace(".plist", DEFAULT_BACKUP_SUFFIX)
    )

    if restore:
        restore_from_backup(bookmarks_path, backup_path)
        return

    prompt_to_quit_safari()
    backup_bookmarks(bookmarks_path, backup_path)
    bookmarks = load_bookmarks(bookmarks_path)

    seen_entries = set()
    modified = False

    for child in bookmarks.get("Children", []):
        if (
            child.get("WebBookmarkType") == "WebBookmarkTypeList"
            and "Children" in child
        ):
            child["Children"] = remove_duplicates_recursive(
                child["Children"], seen_entries, dry_run
            )
            modified = True

    if modified and not dry_run:
        save_bookmarks(bookmarks_path, bookmarks)
    elif dry_run:
        print(f"✅ Dry run 完了: {bookmarks_path} に変更は加えていません。")
    else:
        print(f"❌ 有効なブックマークフォルダが見つかりませんでした: {bookmarks_path}")


def show_help():
    print(
        """
Safari ブックマーク重複削除スクリプト 🧹

使い方:
  safari_bookmark_cleaner.py [オプション]

オプション:
  --bookmarks <パス>     処理するブックマークファイル（複数指定可）
  --backup-path <パス>   バックアップファイル名（単一指定のみ）
  --dry-run              実際には削除せず、重複候補を表示のみ
  --restore              指定されたバックアップから復元
  --help, -h             このヘルプを表示

例:
  safari_bookmark_cleaner.py
  safari_bookmark_cleaner.py --dry-run
  safari_bookmark_cleaner.py --bookmarks ~/Library/Safari/Bookmarks.plist ~/Downloads/Other.plist
  safari_bookmark_cleaner.py --restore --bookmarks ./Bookmarks.plist --backup-path ./Bookmarks_backup.plist
"""
    )


def parse_args():
    dry_run = False
    restore = False
    bookmarks_paths = []
    backup_path = None

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in ["--help", "-h"]:
            show_help()
            sys.exit(0)
        elif arg == "--dry-run":
            dry_run = True
        elif arg == "--restore":
            restore = True
        elif arg == "--backup-path":
            i += 1
            if i < len(args):
                backup_path = os.path.expanduser(args[i])
            else:
                print("❌ --backup-path の後にパスを指定してください")
                sys.exit(1)
        elif arg == "--bookmarks":
            i += 1
            while i < len(args) and not args[i].startswith("--"):
                bookmarks_paths.append(os.path.expanduser(args[i]))
                i += 1
            continue  # 次ループで i インクリメント済み
        else:
            print(f"❓ 不明な引数: {arg}\n--help を使ってヘルプを確認してください。")
            sys.exit(1)
        i += 1

    if not bookmarks_paths:
        bookmarks_paths = [DEFAULT_BOOKMARKS_PATH]

    return dry_run, restore, bookmarks_paths, backup_path


def main():
    dry_run, restore, bookmarks_paths, backup_path = parse_args()
    for path in bookmarks_paths:
        print(f"\n🔍 処理対象: {path}")
        clean_bookmarks(
            bookmarks_path=path,
            dry_run=dry_run,
            backup_path=backup_path,
            restore=restore,
        )


if __name__ == "__main__":
    main()
