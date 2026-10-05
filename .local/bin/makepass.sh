#!/usr/bin/env zsh
# パスワード/トークン用のランダム文字列を3種類出力する。
#
# pipefail は意図的に付けない: `tr ... | head -c N` は head が先に終了して
# tr が SIGPIPE で落ちるのが正常動作で、pipefail を付けると errexit で
# 途中終了してしまうため。
set -o errexit -o nounset

# ① 英数字+記号 89種、20文字(最高エントロピー)
#    tr の文字クラスでは `)-_` が範囲指定になってしまうため、`-` は末尾に置く
LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_=+[]{}|;:,.<>?-' </dev/urandom | head -c 20; echo

# ② 英数字のみ 62種、20文字(記号NGの場合)
LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20; echo

# ③ 16進数 256種相当、32文字(スクリプト内部用)
openssl rand -hex 16
