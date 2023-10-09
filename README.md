# dotfiles

## インストール

```
  $ git clone https://github.com/ac1965/dotfiles.git
  $ dotfiles/setup.sh
```

## MacOS のクリーンアップ

** 私のMac は Sonoma 以降が動作しているIntel搭載なので

- MacBook Pro (13-inch, 2020, Four Thunderbolt 3 ports)

   https://support.apple.com/ja-jp/HT212749

## Homebrew のインストール

```
  $ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  $ brew bundle --global
```

* iTerm2

```
--　画面の分割
command + d 画面を左右に分割
command + shift + d 画面を上下に分割
command + [/]　画面の移動
command + w
command + t タブ
command + return 最大化/元のサイズ
```

* zprezto

https://dev.classmethod.jp/articles/zsh-prezto/

```
git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
```

```
setopt EXTENDED_GLOB
for rcfile in "${ZDOTDIR:-$HOME}"/.zprezto/runcoms/^README.md(.N); do
  ln -s "$rcfile" "${ZDOTDIR:-$HOME}/.${rcfile:t}"
done
```

* Emacs のインストール

```
  $ build-emacs.sh
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
