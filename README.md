# dotfiles

Personal dotfiles for macOS (Apple Silicon / Intel), managed with Homebrew and GNU Emacs.

## 目次

- [クイックスタート](#クイックスタート)
- [macOS のセットアップ](#macos-のセットアップ)
- [Homebrew](#homebrew)
- [Zsh 環境](#zsh-環境)
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
dotfiles/setup.zsh deploy
```

> **Note** `setup.zsh` は `deploy`(repo→HOME)/ `reverse`(HOME→repo)の2モードを取る。引数省略時は使用方法を表示して終了する。

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

## Zsh 環境

`~/.zshenv` で `ZDOTDIR=$HOME/.config/zsh` を定義しているため、`.zshrc` をはじめとする Zsh 関連設定は **`$HOME` 直下ではなく `$ZDOTDIR`(`~/.config/zsh`)に配置される**。`.zshenv` のみ `ZDOTDIR` 定義前に読まれる必要があるため例外的に `$HOME` 直下に置く。

| ファイル/ディレクトリ | 配置先 |
|---|---|
| `.zshenv` | `$HOME` |
| `.zshrc` / `.zstyles` | `$ZDOTDIR`(`.config/zsh` 経由でデプロイ) |
| `.antidote` / `.p10k.zsh` / `.zshrc.d/` | `$ZDOTDIR`(private アーカイブ経由でデプロイ) |

プラグイン管理は [antidote](https://antidote.sh) を使用。`$ZDOTDIR/.zsh_plugins.txt` にプラグインと `.zshrc.d/*.zsh` の個別バンドル(`path:` アノテーション)を列挙し、`.zshrc` から `antidote load` で一括読み込みする。`.zshrc.d/` 自体は for ループでソースせず、antidote の `path:` バンドルに一本化している(`kind:zsh` はディレクトリ内の1ファイルしか拾わない仕様のため、ファイルごとに `path:` を明示する必要がある)。

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

初期化は `$ZDOTDIR/.zshrc.d/pyenv.zsh`(antidote 経由で読み込み)で行う。

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

個人情報は AES-256-CBC(PBKDF2, 21万イテレーション)で暗号化した `private.tar.xz.enc` として管理する。

> **Note — アーカイブは git 管理外**
> `private.tar.xz.enc` は暗号化済みとはいえ86MB超のバイナリで、更新のたびに差分圧縮がほぼ効かず履歴が肥大化するため、**リポジトリには含めない**(`.gitignore` で除外済み)。実体は iCloud Drive / NAS など別チャネルで同期し、`dotfiles` リポジトリと同じ作業ディレクトリ直下に配置してから下記コマンドを実行する運用とする。

グローバルの `setup.zsh` と対称的に、private 側にも `deploy`(archive→HOME)/ `reverse`(HOME→archive)の両モードを持つ **`private/dotfiles.zsh`** を用意している。従来の `private/setup.sh`(deployのみの片方向スクリプト)は廃止した。

> **Note — `.gnupg` のランタイムファイル除外について**
> `.gnupg` ディレクトリは、鍵本体や信頼データベースなどの永続設定と、DBロックファイル(`.#lk*`)・エージェントソケット(`S.gpg-agent*`)・エントロピーシード(`random_seed`)といったプロセス生存期間限定のランタイム成果物が混在している。後者をアーカイブに含めたまま `deploy` すると、既に終了したプロセスのPIDを指す stale ロックが実行環境に復元され、`gpg` コマンド全般がロック待ちでタイムアウトする障害を引き起こす(2026-07-05 に実際に発生・特定済み)。`private/dotfiles.zsh` はこれを防ぐため、`.gnupg` に対する `rsync` にのみ以下の除外パターンを **deploy/reverse 両方向に** 適用する。
>
> ```
> --exclude='.#lk*'
> --exclude='*.lock'
> --exclude='S.gpg-agent*'
> --exclude='S.dirmngr*'
> --exclude='random_seed'
> ```
>
> 万一 `gpg --list-keys` 等が原因不明のタイムアウトを起こした場合は、まず `~/.gnupg/public-keys.d/` 配下に `.#lk*` や `*.lock` が残っていないか確認すること。

**復号して展開 → 配置**

```bash
decrypt private.tar.xz.enc | tar -xvJ
zsh private/dotfiles.zsh deploy
```

> **Note** `tar -xvJ` は `private/` ディレクトリを展開するだけで、`$HOME`/`$ZDOTDIR` への配置は行わない。必ず `private/dotfiles.zsh deploy` を実行して反映すること。

**現在の `$HOME`/`$ZDOTDIR` の状態をアーカイブへ取り込む(reverse)**

```bash
cd private
zsh dotfiles.zsh reverse
```

> **Note** `reverse` はランタイムファイル除外込みで `$HOME`/`$ZDOTDIR` → `private/` へ同期する。手動で `cp`/`rsync` を直接実行して `private/.gnupg` を作り直すと、稼働中の `gpg-agent`/`gpg` プロセスのロックファイルごとコピーしてしまう恐れがあるため、スナップショット取得は必ずこのコマンド経由で行うこと。

**アーカイブして暗号化**

```bash
tar -cJvf private.tar.xz private
encrypt private.tar.xz
```

`encrypt` は成功後、`shred`(macOS では `gshred`、無ければ `rm`)で平文の `private.tar.xz` を削除するため、手動での後始末は不要。

**スクリプト定義** (`~/.local/bin/` などに配置)

```bash
#!/bin/bash
# encrypt — AES-256-CBC + PBKDF2(既定21万回、ITER環境変数で変更可)。
# 出力パーミッションを umask 077 で絞り、平文はshred/gshredで安全削除。
set -euo pipefail
[ $# -eq 1 ] || { echo "Usage: $0 <file>"; exit 1; }
in="$1"; out="$in.enc"; iter="${ITER:-210000}"
umask 077
openssl aes-256-cbc -e -pbkdf2 -iter "$iter" -salt -in "$in" -out "$out"
if command -v gshred >/dev/null 2>&1; then gshred -u -- "$in"
elif command -v shred >/dev/null 2>&1; then shred -u -- "$in"
else rm -f -- "$in"; fi
echo "✅ Encrypted: $out"
```

```bash
#!/bin/bash
# decrypt — 標準出力へ復号(パイプ前提: `decrypt file.enc | tar -xvJ`)。
# パスフレーズは PASSPHRASE 環境変数 > /dev/tty プロンプトの優先順。
# STDOUT が端末の場合はバイナリ書き込みを拒否する。
set -euo pipefail
[ $# -eq 1 ] || { echo "Usage: $0 <file.enc>" >&2; exit 1; }
in="$1"; iter="${ITER:-210000}"
[ -t 1 ] && { echo "Refusing to write binary to terminal. Pipe or redirect the output." >&2; exit 1; }
cmd=(openssl aes-256-cbc -d -pbkdf2 -iter "$iter" -in "$in" -out -)
if [ "${PASSPHRASE:-}" != "" ]; then
  PASSPHRASE="$PASSPHRASE" "${cmd[@]}" -pass env:PASSPHRASE
elif [ -r /dev/tty ]; then
  read -s -p "Passphrase: " pass </dev/tty >&2; echo >&2
  exec 3<<<"$pass"
  "${cmd[@]}" -pass fd:3
else
  echo "No PASSPHRASE set and no /dev/tty available for prompt." >&2
  exit 1
fi
```
