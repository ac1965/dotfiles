#!/usr/bin/env zsh
# bootstrap.zsh — macOS クリーンインストール/リカバリ直後の一括セットアップ
#
# このリポジトリ内の既存スクリプトを決まった順序で呼び出すだけの入口。
# 新しいロジックは持たず、各ステップの実体は以下に委譲する:
#   1) Xcode Command Line Tools / Homebrew / iTerm2  ... .local/bin/init-setup.zsh
#   2) Brewfile の一括インストール                    ... brew bundle
#   3) 公開 dotfiles の配置                           ... dotfiles.zsh deploy
#   4) private アーカイブの復号・配置(あれば)         ... private/dotfiles.zsh deploy
#   5) Emacs のビルド                                 ... .local/bin/build-emacs-macos.sh
#
# 各ステップは元々冪等なので、失敗した/不要なステップだけ --skip-* で
# 飛ばして途中から再実行してよい。private アーカイブ(private.tar.xz.enc)
# は git 管理外かつリポジトリのディレクトリツリーにも置かない方針のため、
# iCloud Drive / NAS 等からリポジトリの「親ディレクトリ」(dotfiles/ の
# 隣)に配置してから実行すること(README.md「プライベートファイルの管理」
# 参照)。未配置なら 4) は自動的にスキップする。
set -euo pipefail

readonly REPO_ROOT="$(git rev-parse --show-toplevel)"
readonly USAGE="usage: ${0:t} [-n|--dry-run] [--skip-brew] [--skip-dotfiles] [--skip-private] [--skip-emacs] [-h|--help]"

integer DRYRUN=0 SKIP_BREW=0 SKIP_DOTFILES=0 SKIP_PRIVATE=0 SKIP_EMACS=0
for arg in "$@"; do
  case $arg in
    -n|--dry-run)    DRYRUN=1 ;;
    --skip-brew)     SKIP_BREW=1 ;;
    --skip-dotfiles) SKIP_DOTFILES=1 ;;
    --skip-private)  SKIP_PRIVATE=1 ;;
    --skip-emacs)    SKIP_EMACS=1 ;;
    -h|--help)       print -- "$USAGE"; exit 0 ;;
    *) print -u2 -- "unknown option: $arg"; print -u2 -- "$USAGE"; exit 1 ;;
  esac
done
readonly -i DRYRUN SKIP_BREW SKIP_DOTFILES SKIP_PRIVATE SKIP_EMACS
(( DRYRUN )) && print -- "-- DRY RUN: 副作用のあるコマンドは実行せず表示のみ --"

log_step() { print -- "\n==> $1"; }

log_step "1/5 Xcode Command Line Tools / Homebrew / iTerm2"
if (( SKIP_BREW )); then
  print -- "  skip (--skip-brew)"
elif (( DRYRUN )); then
  print -- "  (dry-run) zsh ${REPO_ROOT}/.local/bin/init-setup.zsh"
else
  zsh "${REPO_ROOT}/.local/bin/init-setup.zsh"
fi

log_step "2/5 Brewfile 一括インストール"
if (( SKIP_BREW )); then
  print -- "  skip (--skip-brew)"
elif (( DRYRUN )); then
  print -- "  (dry-run) brew bundle --file=${REPO_ROOT}/Brewfile"
else
  # mas (App Store) 未サインイン等で一部パッケージが失敗しても、
  # dotfiles/private/emacs の後続ステップは価値があるので続行する。
  if ! brew bundle --file="${REPO_ROOT}/Brewfile"; then
    print -u2 -- "  ⚠️ brew bundle で一部失敗しました(mas 未サインイン等の可能性)。後続ステップは続行します。"
  fi
fi

log_step "3/5 公開 dotfiles の配置"
if (( SKIP_DOTFILES )); then
  print -- "  skip (--skip-dotfiles)"
elif (( DRYRUN )); then
  zsh "${REPO_ROOT}/dotfiles.zsh" deploy -n
else
  zsh "${REPO_ROOT}/dotfiles.zsh" deploy
fi

log_step "4/5 private アーカイブの復号・配置"
# dotfiles リポジトリの「外」(親ディレクトリ)に置く前提。git 管理外なの
# はもちろん、リポジトリのディレクトリツリー自体にも実体を持ち込まない。
readonly ARCHIVE_DIR="${REPO_ROOT:h}"
readonly ARCHIVE="${ARCHIVE_DIR}/private.tar.xz.enc"
readonly PRIVATE_DIR="${ARCHIVE_DIR}/private"
if (( SKIP_PRIVATE )); then
  print -- "  skip (--skip-private)"
elif [[ ! -f "$ARCHIVE" ]]; then
  print -- "  skip (${ARCHIVE} が見つかりません。iCloud Drive / NAS 等から配置してから再実行してください)"
elif (( DRYRUN )); then
  print -- "  (dry-run) decrypt ${ARCHIVE} | tar -xJ  (展開先: ${ARCHIVE_DIR})"
  print -- "  (dry-run) (cd ${PRIVATE_DIR} && zsh dotfiles.zsh deploy)"
else
  ( cd -- "$ARCHIVE_DIR" && decrypt "$ARCHIVE" | tar -xJ )
  # private/dotfiles.zsh は $(pwd) を基準に相対解決するため、展開先
  # ディレクトリ自身に cd してから呼び出す必要がある。
  ( cd -- "$PRIVATE_DIR" && zsh dotfiles.zsh deploy )
fi

log_step "5/5 Emacs ビルド"
if (( SKIP_EMACS )); then
  print -- "  skip (--skip-emacs)"
elif (( DRYRUN )); then
  print -- "  (dry-run) zsh ${REPO_ROOT}/.local/bin/build-emacs-macos.sh"
else
  zsh "${REPO_ROOT}/.local/bin/build-emacs-macos.sh"
fi

print -- "\n✅ bootstrap 完了"
