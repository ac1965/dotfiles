# dotfiles

Personal dotfiles for macOS (Apple Silicon / Intel), managed with Homebrew and GNU Emacs.

## 目次

- [クイックスタート](#クイックスタート)
- [macOS のセットアップ](#macos-のセットアップ)
- [Homebrew](#homebrew)
- [ツール別セットアップ](#ツール別セットアップ)
  - [iTerm2](#iterm2)
  - [pyenv](#pyenv)
  - [MacTeX](#mactex)
  - [Emacs](#emacs)
- [プライベートファイルの管理](#プライベートファイルの管理)

---

## クイックスタート

```bash
git clone https://github.com/ac1965/dotfiles.git
dotfiles/setup.sh
```

---

## macOS のセットアップ

新しい Mac または再インストール時は、アクティベーション解除を先に済ませる。

**対象機種**

| モデル | チップ | 備考 |
|---|---|---|
| MacBook Pro 14-inch (Nov 2024) | Apple M4 | |
| MacBook Pro 13-inch (2020) | Intel | Four Thunderbolt 3 ports |

Apple サポート — アクティベーション解除の手順:
<https://support.apple.com/ja-jp/HT212749>

---

## Homebrew

Homebrew をインストールし、`Brewfile` に基づいて全パッケージを一括インストールする。

```bash
cd ~/Downloads && git clone https://github.com/ac1965/dotfiles
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew bundle --global
```

> **Note** `brew bundle --global` は `~/.Brewfile` を参照する。
> リポジトリ内の `Brewfile` を使う場合は `brew bundle` をリポジトリルートで実行する。

---

## ツール別セットアップ

### iTerm2

`brew bundle --global` の実行で `Brewfile` に含まれるパッケージとして自動インストールされる。
単独インストールが必要な場合:

```bash
brew install --cask iterm2
```

**参考**

- カラースキーム: <https://iterm2colorschemes.com>
- 設定ガイド: <https://zenn.dev/aldagram_tech/articles/0fc671a41021f3>

**主要キーバインド**

| キー | 動作 |
|---|---|
| `⌘ D` | 画面を左右に分割 |
| `⌘ ⇧ D` | 画面を上下に分割 |
| `⌘ N` | 新規ウィンドウ |
| `⌘ W` | ウィンドウを閉じる |
| `⌘ T` | 新規タブ |
| `⌘ ←/→` | タブの移動 |
| `⌘ [/]` | ペインの移動 |
| `⌘ Return` | 最大化 / 元のサイズ |

ホットキーウィンドウを設定すると、任意のデスクトップ上にフルスクリーンで重ねて表示できる。

---

### pyenv

```bash
brew install pyenv
```

参考: <https://qiita.com/santa_sukitoku/items/6cbb325a895653c81b36>

---

### MacTeX

`brew bundle --global` で `mactex-no-gui` がインストールされる。
インストール後にパッケージを更新し、デフォルト用紙サイズを A4 に設定する。

```bash
sudo tlmgr update --self --all
sudo tlmgr paper a4
```

`~/.latexmkrc` の推奨設定:

```bash
cat <<'EOF' > ~/.latexmkrc
# 最大タイプセット回数
$max_repeat = 5;
# DVI 経由で PDF をビルド
$pdf_mode = 3;
# pLaTeX（最初のエラーで停止）
$latex = 'platex %O %S -halt-on-error';
# pBibTeX（参考文献）
$bibtex = 'pbibtex %O %S';
# Mendex（索引）
$makeindex = 'mendex %O -o %D %S';
# DVI → PDF 変換
$dvipdf = 'dvipdfmx %O -o %D %S';
EOF
```

---

### Emacs

ネイティブコンパイル付きビルド:

```bash
build-emacs.sh --native
```

Emacs 設定の詳細: [Emacs-01.org](https://github.com/ac1965/dotfiles/blob/master/.docs/Emacs-01.org)

---

## プライベートファイルの管理

個人情報は AES-256-CBC で暗号化した `private.tar.xz.enc` として管理する。

**復号して展開**

```bash
decrypt private.tar.xz.enc | tar -xvJ
```

**アーカイブして暗号化**

```bash
tar -cJvf private.tar.xz private
encrypt private.tar.xz
```

**スクリプト定義** (`~/.local/bin/` などに配置)

```bash
# decrypt
#!/bin/bash
openssl enc -d -aes-256-cbc -pbkdf2 -iter 99999 -in "${1}"

# encrypt
#!/bin/bash
openssl enc -e -aes-256-cbc -pbkdf2 -iter 99999 -in "${1}" -out "${1}.enc"
```

> **Note** 元の `encrypt` スクリプトは `-d`（復号）フラグが誤って使われていた。
> 上記では `-e`（暗号化）に修正済み。
