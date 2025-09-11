# dotfiles

## インストール

```
  $ git clone https://github.com/ac1965/dotfiles.git
  $ dotfiles/setup.sh
```

## MacOS のクリーンアップ

- アクティベーションを外す
- MacBook Pro (AppleM4 14-inch, 11.2024)
- MacBook Pro (13-inch, 2020, Four Thunderbolt 3 ports)

   https://support.apple.com/ja-jp/HT212749

## Homebrew のインストール

- ターミナルから次のコマンドをコピペ

```
	cd Downloads && git clone https://github.com/ac1965/dotfiles
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
    brew bundle --global
```

### iTerm2

`brew bundle --global` を実行すると *Brewfile* に記載されたパッケージのひとつとして iTerm2 もインストールする。

単独でイントールする場合は以下のコマンドを実行する。

```
    brew install --cask iterm2
```

https://iterm2colorschemes.com

https://zenn.dev/aldagram_tech/articles/0fc671a41021f3

- ホットキー

- 任意のデスクトップ上にフルスクリーンで重ねて表示

- ショートカットキー

```
    -- 画面の分割
    command + d 画面を左右に分割
    command + shift + d 画面を上下に分割
    command + n ウィンドウを作成
    command + w ウィンドウを閉じる
	command + t タブを作成
    command + 矢印キー タブの移動
    command + [/] 画面の移動
    command + return 最大化/元のサイズ
```

### pyenv & pipenv

```
    brew install pyenv
```

    https://qiita.com/santa_sukitoku/items/6cbb325a895653c81b36

### MacTex

MacTex(mactex-no-gui) は `Homebrew のインストール` で インストールされる。
パッケージの更新は tlmgr を使い、印刷サイズを A4サイズを設定しておく。

``` bash
sudo tlmgr update --self --all
sudo tlmgr paper a4
```

``` bash
$ cat <<EOF > ~/.latexmkrc
# 最大のタイプセット回数
$max_repeat = 5;
# DVI経由でPDFをビルドすることを明示
$pdf_mode = 3;

# pLaTeXを使う
# -halt-on-error:初めのエラーで終わらせる
$latex = 'platex %O %S -halt-on-error';

# pBibTeXを使う(参考文献)
$bibtex = 'pbibtex %O %S';

# Mendexを使う(索引)
$makeindex = 'mendex %O -o %D %S';

# DVIからPDFへの変換
$dvipdf = 'dvipdfmx %O -o %D %S';
EOF
```

### private

個人情報は private.tar.xz.enc

``` bash
decrypt private.tar.xz.enc | tar -xvJ
```

``` bash
tar -cJvf private.tar.xz private
encrypt private.tar.xz
```

decrypt
``` bash
#!/bin/bash

openssl enc -d -aes-256-cbc -pbkdf2 -iter 99999 -in "${1}"
```

encrypt
``` bash
#!/bin/bash

openssl enc -d -aes-256-cbc -pbkdf2 -iter 99999 -in "${1}"
```


### Emacs のインストール

```
  build-emacs.sh --native
```
