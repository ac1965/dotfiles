"""
3_rewrite_messages.py

git filter-repo の --commit-callback に渡すスクリプト。
messages.json (旧hash -> 新メッセージ) を読み込み、該当コミットの
メッセージを置き換える。マッピングに存在しないコミットは元のまま維持する。

事前準備:
    pip install git-filter-repo --break-system-packages
    (または https://github.com/newren/git-filter-repo をPATHに置く)

使い方:
    # 必ずバックアップブランチを作ってから実行すること
    git branch backup-before-rewrite

    cd /path/to/your/repo
    git filter-repo --force --commit-callback "$(cat 3_rewrite_messages.py)"

    # 結果をローカルで目視確認
    git log --oneline | head -50

    # 問題なければリモートへ反映
    git push --force-with-lease
"""

import json
import os

_MESSAGES_PATH = os.environ.get("REWRITE_MESSAGES_JSON", "messages.json")

with open(_MESSAGES_PATH, encoding="utf-8") as _f:
    _messages = json.load(_f)

old_hash = commit.original_id.decode("ascii")  # noqa: F821  (filter-repoが注入する変数)

if old_hash in _messages:
    commit.message = _messages[old_hash].encode("utf-8")  # noqa: F821
# マッピングにない場合は commit.message を変更しない(元のまま)
