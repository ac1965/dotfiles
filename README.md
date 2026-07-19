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
dotfiles/dotfiles.zsh deploy
```

> **Note** `dotfiles.zsh` は `deploy`(repo→HOME)/ `reverse`(HOME→repo)の2モードを取る。引数省略時は使用方法を表示して終了する。

---

## macOS のセットアップ

クリーンインストールの場合は、アクティベーション解除を先に済ませる。

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

**日本語組版はデフォルトを LuaLaTeX-ja とする。** `mactex-no-gui` は TeX Live full scheme のため、LuaTeX-ja・原ノ味フォント等は追加インストール不要。

**動作確認**

```bash
which lualatex
kpsewhich haranoaji-mincho.otf
```

`~/.latexmkrc`(グローバルデフォルト、LuaLaTeX-ja):

```bash
cat <<'EOF' > ~/.latexmkrc
# 最大タイプセット回数
$max_repeat = 5;
# PDF を LuaLaTeX で直接生成(DVI 経由を廃止)
$pdf_mode = 4;
# LuaLaTeX 本体(SyncTeX 有効、初回エラーで停止)
$lualatex = 'lualatex %O -synctex=1 -halt-on-error %S';
# 索引(和文対応: upmendex)
$makeindex = 'upmendex %O -o %D %S';
# 参考文献(和文スタイル対応: upbibtex)
$bibtex = 'upbibtex %O %S';
$biber  = 'biber %O %S';
# クリーンアップ対象拡張子
$clean_ext = 'synctex.gz synctex.gz(busy) run.xml bbl bcf fdb_latexmk';
EOF
```

**最小構成テンプレート**

```tex
\documentclass[ja=standard]{ltjsarticle}
\begin{document}
日本語組版のテスト。
\end{document}
```

```bash
latexmk foo.tex
```

> **Note — 旧 pLaTeX(dvipdfmx)構成について**
> グローバルデフォルトは LuaLaTeX-ja に統一した。既存資産等で pLaTeX が必要な文書は、`.tex` ファイル先頭に以下の magic comment を入れることで latexmk がエンジンを切り替える。
>
> ```tex
> % !TEX program = platex
> ```
>
> この場合の変換コマンド(`platex %O %S -halt-on-error` → `dvipdfmx %O -o %D %S`)はグローバル `~/.latexmkrc` には含めていないため、文書側の個別 `.latexmkrc` または `latexmk -pdfdvi -e '$latex=...'` 等で都度指定すること。

---

### Emacs

```bash
build-emacs.sh
```

Emacs 設定の詳細: [Emacs-01.org](https://github.com/ac1965/dotfiles/blob/master/.docs/Emacs-01.org)

---

## プライベートファイルの管理

個人情報は AES-256-CBC(PBKDF2, 21万イテレーション)で暗号化した `private.tar.xz.enc` として管理する。

> **Note — アーカイブは git 管理外**
> `private.tar.xz.enc` は暗号化済みとはいえ86MB超のバイナリで、更新のたびに差分圧縮がほぼ効かず履歴が肥大化するため、**リポジトリには含めない**(`.gitignore` で除外済み)。実体は iCloud Drive / NAS など別チャネルで同期し、`dotfiles` リポジトリと同じ作業ディレクトリ直下に配置してから下記コマンドを実行する運用とする。

グローバルの `dotfiles.zsh` と対称的に、private 側にも `deploy`(archive→HOME)/ `reverse`(HOME→archive)の両モードを持つ **`private/dotfiles.zsh`** を用意している。従来の `private/setup.sh`(deployのみの片方向スクリプト)は廃止した。

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
COPYFILE_DISABLE=1 tar --exclude='private/.ssh/agent' -cf - private \
  | pv -s $(gdu -sb private | awk '{print $1}') \
  | xz -9 > private.tar.xz
encrypt private.tar.xz
```

> **Note — プログレスバー表示について**
> macOS 標準の `tar` にはプログレスバー機能がないため、[`pv`](https://linux.die.net/man/1/pv)(`brew install pv`)をパイプに挟んで進捗表示している。`pv -s` に渡すサイズ計算には GNU coreutils 版の `du`(`brew install coreutils` で `gdu` として導入)が必要。macOS 標準の BSD `du` には `-b`(バイト単位出力)オプションが存在しないため `gdu -sb` を使用する。なお `tar` はヘッダー・パディングのオーバーヘッドを持つため、ファイル数が多い構成では進捗が100%を超えて表示されることがあるが、実害はない。
>
> **Note — `.ssh/agent` の除外について**
> `private/.ssh/agent/` 配下には稼働中の `ssh-agent` が生成する Unix ドメインソケットが含まれる場合があり、`tar` は `pax format cannot archive sockets` エラーで停止する。ソケットは `ssh-agent` 再起動時に再生成される一時ファイルでバックアップ対象外のため `--exclude` で除外する。
>
> **Note — 拡張属性(xattr)警告について**
> `Could not pack extended attributes: Operation not supported` という警告が出ることがあるが、`com.apple.quarantine` 等の xattr を pax 形式でパックできない旨の警告に留まり、アーカイブ自体は正常に生成される。`COPYFILE_DISABLE=1` を指定することで AppleDouble 形式のリソースフォーク/xattr 処理自体をスキップさせ、警告の発生を抑制できる。

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
