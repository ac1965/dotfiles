# dotfiles

## MacOS のクリーンアップ

* backup

  Time Machine でバックアップを取っておく

* クリーンアップ

  1. shutdown
  1. command + r
  1. ディスクユーティリティを使ってディスクを削除 
  1. 再インストール

   https://support.apple.com/ja-jp/HT208496

   https://www.youtube.com/watch?v=h4vj78euzKQ

## Homebrew のインストール

```
  $ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  $ test -f ~/.Brewfiles && brew bundle --global
```

* emacs のインストール

```
  $ git clone https://github.com/emacs-mirror/emacs
  $ cd emacs
  $ ./autogen.sh
  $ CFLAGS=`xml2-config --cflags` ./configure --with-ns
  $ make
  $ sudo make install
  $ cd nextstep && cp -a Emacs.app /Applications
  ```


## iTerm2

```
--　画面の分割
command + d 画面を左右に分割
command + shift + d 画面を上下に分割
command + [/]　画面の移動
command + w
command + t タブ
command + return 最大化/元のサイズ
```

## zprezto

```
git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
```

```
setopt EXTENDED_GLOB
for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^README.md(.N); do
  ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
done


zstyle ':prezto:load' pmodule \
  'environment' \
  'terminal' \
  'editor' \
  'history' \
  'directory' \
  'spectrum' \
  'utility' \
  'completion' \
  'syntax-highlighting' \  <- 追加
  'autosuggestions' \      <- 追加
  'prompt' \
```
