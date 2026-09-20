#!/bin/bash
# ~/.local/bin/open-emacs-client.sh
#
# emacsclient -c でGUIフレームを開く。
#
# -a "" (alternate-editor を空文字) を付けているのが要点: サーバーソケットが
# 見つからない場合（daemonがまだ起動していない、launchdのplistをまだ
# 導入していない等）、emacsclient は自動的に通常の `emacs` として
# フォールバック起動する。daemon経由かどうかを意識せず、常にこのアプリを
# ダブルクリックすればEmacsが開く、という単純な体験にするための保険。
#
# daemonが既に起動していれば（launchdのplistでRunAtLoad済みなら通常そう）、
# 一瞬でクライアントフレームが開く。daemonが無ければ、通常起動と同じだけ
# 待たされるが、エラーにはならない。


# Dock/Finder からGUIアプリとして起動された場合、PATHが最小限
# (/usr/bin:/bin:/usr/sbin:/sbin 等) しか渡されず、emacsclient が
# `-a ""` で内部的に daemon を自動起動しようとして `emacs` コマンドを
# execvp で探す際に見つからず失敗する。~/.local/bin を明示的に
# PATH へ追加して回避する。
export PATH="$HOME/.local/bin:$PATH"

exec "$HOME/.local/bin/emacsclient" -c -n -a "" "$@"
