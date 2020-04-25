= dotfiles

- MacOS のクリーンアップ

* backup
  Time Machine でバックアップを取っておく

* クリーンアップ
  #1 shutdown
  #2 command + r
  #3 ディスクユーティリティを使ってディスク中身を削除する
  #4 再インストール

* Homebrew のインストール
  $ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  $ test -f ~/.Brewfiles && brew bundle

- iterm2
--　画面の分割
command + d 画面を左右に分割
command + shift + d 画面を上下に分割
command + [/]　画面の移動
command + w
command + t タブ
command + return 最大化/元のサイズ

- zprezzo

git clone --recursive https://github.com/sorin-ionescu/prezto.git "${ZDOTDIR:-$HOME}/.zprezto"
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
