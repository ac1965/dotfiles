#!/usr/bin/env zsh
# private/dotfiles.zsh — deploy: archive→HOME / reverse: HOME→archive
#
# Symmetric counterpart to the global dotfiles.zsh, scoped to files
# that live in the encrypted private archive (SSH keys, GPG keyring,
# mail credentials, etc.).
#
# deploy:  restore private files from archive into $HOME / $ZDOTDIR
# reverse: snapshot current $HOME / $ZDOTDIR state back into archive
#
# NOTE ON .gnupg: this directory mixes permanent config (keys, trust
# db) with process-lifetime runtime artifacts (DB locks, agent
# sockets, entropy seed). Runtime artifacts must NEVER cross into the
# archive or be restored from it — see 2026-07-05 incident, where a
# stale .#lk* lock (dead PID) captured into the archive during a
# manual snapshot was later restored into ~/.gnupg on every setup.sh
# run, blocking `gpg --list-keys` for minutes.
set -euo pipefail

readonly HOME_FILES=(
  .elisp
  .gitconfig
  .gitignore
  .gnupg
  .hyper.js
  .mbsyncrc
  .mew-theme.el
  .mew.el
  .ssh
  .weechat
  .authinfo.gpg
)
readonly ZDOT_FILES=(
  .antidote
  .p10k.zsh
  .zshrc.d
)

# Runtime-only artifacts inside .gnupg — excluded in BOTH directions.
readonly GNUPG_EXCLUDES=(
  --exclude='.#lk*'
  --exclude='*.lock'
  --exclude='S.gpg-agent*'
  --exclude='S.dirmngr*'
  --exclude='random_seed'
)

readonly MODE=${1:?usage: ${0:t} [d|deploy|r|reverse]}
case $MODE in
  d|deploy)  src_home_base="$(pwd)" dst_home_base="${HOME}"
             src_zdot_base="$(pwd)" dst_zdot_base="${ZDOTDIR:-$HOME}" ;;
  r|reverse) src_home_base="${HOME}" dst_home_base="$(pwd)"
             src_zdot_base="${ZDOTDIR:-$HOME}" dst_zdot_base="$(pwd)" ;;
  *) print -u2 "usage: ${0:t} [d|deploy|r|reverse]"; exit 1 ;;
esac

integer ok=0 skip=0 fail=0

# restore_one SRC_BASE DST_BASE PATH
#   Copies a single file/dir from SRC_BASE to DST_BASE, applying
#   .gnupg-specific excludes when relevant. Direction-agnostic: the
#   caller decides which base is source and which is destination.
restore_one() {
  local src_base=$1 dst_base=$2 f=$3
  if [[ ! -e "${src_base}/${f}" ]]; then
    print -- "  skip    ${f}"
    (( skip++ )) || true
    return 0
  fi
  local -a extra_args=()
  [[ "$f" == ".gnupg" ]] && extra_args=("${GNUPG_EXCLUDES[@]}")
  if rsync -ah --no-perms "${extra_args[@]}" -- "${src_base}/${f}" "${dst_base}/."; then
    print -- "  ok      ${f}"
    (( ok++ )) || true
  else
    print -u2 "  FAILED  ${f} (rsync exit $?)"
    (( fail++ )) || true
  fi
}

# handle_rename_pair MODE
#   Handles the one file whose name differs between repo and $HOME
#   (.ac1965_rc <-> .${USER}_rc). $USER is intentionally dynamic —
#   this pair was designed to support multiple accounts sharing the
#   same private archive, each keeping their own rc file under their
#   own username, while the repo always stores it under a single
#   fixed name.
handle_rename_pair() {
  local mode=$1
  local repo_name=".ac1965_rc"
  local home_name=".${USER}_rc"
  local src dst
  case $mode in
    d|deploy)  src="${repo_name}"          dst="${HOME}/${home_name}" ;;
    r|reverse) src="${HOME}/${home_name}"  dst="${repo_name}" ;;
  esac
  if [[ -f "$src" ]]; then
    if rsync -ah --no-perms -- "$src" "$dst"; then
      print -- "  ok      ${dst:t}"
      return 0
    else
      print -u2 -- "  FAILED  ${dst:t} (rsync exit $?)"
      return 1
    fi
  else
    print -- "  skip    ${src:t}"
    return 0
  fi
}

for f in "${HOME_FILES[@]}"; do
  restore_one "${src_home_base}" "${dst_home_base}" "$f"
done

for f in "${ZDOT_FILES[@]}"; do
  restore_one "${src_zdot_base}" "${dst_zdot_base}" "$f"
done

if handle_rename_pair "$MODE"; then
  (( ok++ )) || true
else
  (( fail++ )) || true
fi

print -- "\ndone: ${ok} ok, ${skip} skipped, ${fail} failed"
(( fail == 0 ))
