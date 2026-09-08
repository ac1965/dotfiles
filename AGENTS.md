# AGENTS.md

このリポジトリで作業する AI コーディングエージェント向けの指示書。人間向けのセットアップ手順は [README.md](README.md) を参照。

## リポジトリの構造

macOS 用の個人 dotfiles。`dotfiles.zsh` が **リポジトリ → `$HOME`**（deploy）/ **`$HOME` → リポジトリ**（reverse）の同期を行う。リポジトリのファイル配置は基本的に `$HOME` 直下の配置をそのまま反映している（例: `.config/` → `~/.config/`、`.local/bin/xxx.sh` → `~/.local/bin/xxx.sh`）。

```bash
./dotfiles.zsh deploy -n   # dry-run で差分確認
./dotfiles.zsh deploy      # repo → $HOME
./dotfiles.zsh reverse -n  # $HOME → repo の dry-run
```

`dotfiles.zsh` 冒頭の `DOTFILES` 配列に列挙されたトップレベルのファイル/ディレクトリだけが同期対象になる。**新しいトップレベルの設定ディレクトリを追加したら、この配列にも追記すること。**

## `.gitignore` は「まず全部無視、必要な物だけ許可」方式

これがこのリポジトリで最も踏み外しやすい点。冒頭で

```
*
!*/
```

によって全ファイルを無視した上で、`!/path/to/file` のような否定パターンで個別に許可している。つまり **新しいファイルを追加しても、`.gitignore` に許可ルールを足さない限り `git add` できない**。

- ルート直下の設定ファイルは `!/foo` の形（先頭の `/` 必須。無いと `.config/emacs/README.md` のような同名ファイルにも誤爆する）。
- `.local/bin` はスクリプト拡張子ごとに許可（`!.local/bin/*.sh` など）。
- `.local/share` はデフォルトで丸ごと無視した上で、`.local/share/favorite-repos.json` のように **ファイル単位で個別に許可**している。ディレクトリパターン（`dir/`）で一度無視されたディレクトリは、後から `!dir/file` を書いても再度追跡対象にはできない（git の仕様）。許可したい場合は該当ディレクトリの無視パターンを `dir/*`（グロブ）にした上で個別ファイルを否定する。
- ファイル末尾付近の「明示的に除外」セクションは、allow-list を通り抜けてしまう可能性のあるパスへの二重ブロック（`.zsh_history` や機種固有バイナリなど）。

新規ファイルを追加したら、`git status --short` と `git check-ignore -v <path>` で意図通りに allow/deny されているか必ず確認する。

## `.local/bin/` のスクリプト規約

既存スクリプト（`hub-clone.sh`, `hub-repos.sh`, `clone-favorite-repos.sh` など）の作法に合わせる:

- shebang は `#!/usr/bin/env zsh`。zsh は関数内で `$0` が関数名に化ける（`FUNCTION_ARGZERO`）、`read -p` はプロンプト表示ではなくコプロセス読み込みを意味する、bash の `PIPESTATUS` 配列が無く `pipestatus`（小文字・1-indexed）を使う、といった bash との違いがあるので、bash から移植する際は要注意。
- **`echo "$var"` は使わない。** zsh の組み込み `echo` はデフォルトで `\n` 等のバックスラッシュエスケープを解釈してしまう（bash の `echo` は解釈しない）。JSON レスポンスや LLM の出力など、変数の中身に `\n`/`\"`/`\\` が含まれ得る場合、`echo "$var" | jq ...` や `echo "$var" | python3 -c 'json.load(...)'` のようにパーサへ渡すと、パース対象の文字列そのものが壊れて `Invalid control character` 等のエラーになる（実際に踏んだ不具合）。`printf '%s\n' "$var"` を使うか、可能なら変数を経由せずファイル/`jq`の引数に直接読ませる。
- `set -o errexit / -o nounset / -o pipefail`。
- ファイル先頭に日本語コメントで用途・使い方・必須/任意環境変数を書く。
- `log_info()` / `log_error()` / `usage()` / `require_command()` のような小さなヘルパーを定義し、標準エラーへのログは `❌ [${SCRIPT_NAME}] ...` の形式。
- 引数パースは `case` ベース、`-h/--help` と `-n/--dry-run` を用意するものが多い。
- 新規スクリプトを追加したら実行権限を付与し（`chmod +x`）、`.gitignore` の `.local/bin/*.sh` 等の許可ルールに引っかかることを確認する。

## `private/` ディレクトリと暗号化アーカイブ

個人情報は `private.tar.xz.enc`（AES-256-CBC, PBKDF2）として管理し、**このリポジトリには含めない**（`.gitignore` で除外済み・86MB 超のバイナリ）。`private/dotfiles.zsh` が同様の deploy/reverse を private アーカイブ展開先に対して行う。エージェントは `private/` 配下の復号済みファイルや `.gnupg` のようなランタイム鍵ディレクトリを **読む・コミットする対象にしない**。`.gnupg` は永続鍵とプロセス生存期間限定のランタイムファイル（`.#lk*`, `S.gpg-agent*`, `random_seed` 等）が混在しており、後者を巻き込むと stale lock で `gpg` がタイムアウトする既知の問題があるため特に注意（README.md 参照）。

## Zsh 環境

`~/.zshenv` で `ZDOTDIR=$HOME/.config/zsh` を設定しているため、`.zshrc` 等の Zsh 関連ファイルは `$HOME` 直下ではなく `.config/zsh/` 配下に置く。`.zshenv` だけは `ZDOTDIR` が定義される前に読まれる必要があるため例外的に `$HOME` 直下（リポジトリでは `/.zshenv`）に置かれている。

## ドキュメント

Emacs 設定など長文の解説は `.docs/*.org`（Org-mode）に置く。README.md からリンクする。

## コミットメッセージ規約

`git log` から読み取れる規約:

- 日本語で記述する。
- `type(scope): 要約` の Conventional Commits 風（例: `feat(bin): ...`, `fix(zsh): ...`, `chore(gitignore): ...`, `docs: ...`）。scope はディレクトリ名や機能名（`bin`, `zsh`, `dotfiles`, `gitignore` など）。
- 本文（任意）は `- ` の箇条書きで変更点を列挙することが多い。

`.local/bin/gen-commit-msg.sh` は Ollama を使ってステージ済み diff からこの形式のメッセージを生成するローカルツール（要 `ollama serve`）。エージェントはこれを実行する必要はなく、同じ規約に沿って自分でメッセージを書けばよい。

## 変更後の確認

UI や設定変更を含むタスクでは、可能な範囲で実際に動作確認する:

- スクリプトは `-n/--dry-run` があれば先にそれで対象を確認してから本実行する。
- `dotfiles.zsh` の deploy/reverse を試すときは必ず `-n` を先に付ける（`$HOME` 上の実ファイルを上書き/削除しうるため）。
- `.gitignore` を変更したら、対象ファイルが `git add` できる/できないを実際に確認する。
