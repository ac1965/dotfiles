#!/usr/bin/env zsh
# dotfiles.zsh — deploy: repo→HOME / reverse: HOME→repo

set -euo pipefail

readonly DOTFILES=(
  .Brewfile
  .bin
  .config
  .docs
  .docker-alias
  .gitconfig_global
  .gitignore_global
  .latexmkrc
  .local
  .macos
  .vim
  .viminfo
  .vimperator
  .vimperatorrc
  .vimperatorrc.js
  .vimrc
  .zshenv
  .zshrc
  .zstyles
  Brewfile
)

readonly MODE=${1:?usage: ${0:t} [d|deploy|r|reverse]}

case $MODE in
  d|deploy)  src_base="$(pwd)"  dst_base="${HOME}" ;;
  r|reverse) src_base="${HOME}" dst_base="$(pwd)"  ;;
  *) print -u2 "usage: ${0:t} [d|deploy|r|reverse]"; exit 1 ;;
esac

local -i ok=0 skip=0 fail=0

for f in "${DOTFILES[@]}"; do
  if [[ ! -e "${src_base}/${f}" ]]; then
    print -- "  skip    ${f}"
    (( skip++ )) || true
    continue
  fi

  if rsync -ah --no-perms -- "${src_base}/${f}" "${dst_base}/."; then
    print -- "  ok      ${f}"
    (( ok++ )) || true
  else
    print -u2 "  FAILED  ${f} (rsync exit $?)"
    (( fail++ )) || true
  fi
done

print -- "\ndone: ${ok} ok, ${skip} skipped, ${fail} failed"
(( fail == 0 ))
