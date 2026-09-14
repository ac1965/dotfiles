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

exec "$HOME/.local/bin/emacsclient" -c -n -a "" "$@"
