#!/bin/bash
# ~/.local/bin/toggle-emacs-daemon.sh
#
# com.ac1965.emacs-daemon.plist と対で使う launchd トグルスクリプト。
#
# launchctl bootstrap/bootout（macOS 10.10+ の正しい API）を使う。
# launchctl kickstart/kill は使わない — plist の KeepAlive(SuccessfulExit=false)
# により、SIGTERM 相当の停止は「異常終了」と見なされ即座に再起動されてしまうため。
# bootout はジョブ定義ごと launchd から取り除くので、KeepAlive による自動復帰は
# 起こらない。

set -euo pipefail

DOMAIN="gui/$(id -u)"
LABEL="com.ac1965.emacs-daemon"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

if [ ! -f "$PLIST" ]; then
  osascript -e 'display notification "plist が見つかりません: '"$PLIST"'" with title "Emacs Daemon" subtitle "エラー"'
  exit 1
fi

if launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
  # 稼働中 → 停止
  launchctl bootout "${DOMAIN}" "${PLIST}"
  osascript -e 'display notification "daemon を停止しました" with title "Emacs Daemon"'
else
  # 停止中 → 起動
  launchctl bootstrap "${DOMAIN}" "${PLIST}"
  osascript -e 'display notification "daemon を起動しました" with title "Emacs Daemon"'
fi
