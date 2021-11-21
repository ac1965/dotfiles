# dotfiles

## インストール

```
  $ git clone https://github.com/ac1965/dotfiles.git
  $ bash dotfiles/setup.sh
  $ cp dotfiles/.gitconfig ~/.gitconfig
  $ vi ~/.gitconfig
  $ chmod +x ~/.bin/*.sh
```


## MacOS のクリーンアップ

* backup

  Time Machine でバックアップを取っておく

* クリーンアップ

  1. shutdown
  1. command + R
  1. ディスクユーティリティを使ってディスクを削除
  1. 再インストール

   https://support.apple.com/ja-jp/HT208496

** 私のMac は Monterey が動作しているIntel搭載なので

- MacBook Pro (13-inch, 2020, Four Thunderbolt 3 ports)

   https://support.apple.com/ja-jp/HT212749

## Xcode のインストール

## Homebrew のインストール

```
  $ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  $ test -f ~/.Brewfile && brew bundle --global
```

* emacs のインストール

```
  $ build-emacs.sh
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

https://dev.classmethod.jp/articles/zsh-prezto/

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

## pyenv & pipenv

https://qiita.com/santa_sukitoku/items/6cbb325a895653c81b36

## basictex

basictex は `Homebrew のインストール` で インストールされる。
パッケージの更新は tlmgr を使い、印刷サイズを A4サイズを設定しておく。

``` bash
sudo tlmgr update --self --all
sudo tlmgr paper a4
for col in collection-langjapanese collection-luatex collection-latexextra; do
sudo tlmgr install $col; done
```
