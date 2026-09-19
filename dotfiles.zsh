#!/usr/bin/env zsh
# dotfiles.zsh — deploy: repo→HOME / reverse: HOME→repo
#
# Directory entries (.config, .local, .vim, .vimperator) are walked
# file-by-file and filtered through this repo's .gitignore *before*
# copying, in both directions. Without this, a bulk directory rsync
# would pull untracked app data (e.g. ~/.config/emacs, ~/.local/share)
# and mode-600 credential files into the repo working tree, even
# though git itself would never track them.
set -euo pipefail
readonly DOTFILES=(
  .Brewfile
  .config
  .docs
  .docker-alias
  .gitconfig_global
  .gitignore_global
  .latexmkrc
  .local
  .vim
  .vimperator
  .vimperatorrc
  .vimperatorrc.js
  .vimrc
  .zshenv
  Brewfile
)
readonly REPO_ROOT="$(git rev-parse --show-toplevel)"
readonly USAGE="usage: ${0:t} [d|deploy|r|reverse] [-n|--dry-run]
       ${0:t} rb|rollback <relpath> [n] [-n|--dry-run]"
readonly MODE=${1:?${USAGE}}
local -i _dryrun=0
local _a=""
for _a in "$@"; do
  case $_a in
    -n|--dry-run) _dryrun=1 ;;
  esac
done
readonly -i DRYRUN=$_dryrun

# rollback: <relpath> を n 個前(既定 1)にコミットされたバージョンへ戻し、
# repo と $HOME 両方に反映して commit する。deploy/reverse の一括コピーとは
# 独立した単一ファイル操作なので、下の DOTFILES ループには合流させない。
do_rollback() {
  local relpath=$1
  local -i n=${2:-1}
  relpath="${relpath#${HOME}/}"
  relpath="${relpath#${REPO_ROOT}/}"
  relpath="${relpath#./}"
  local repo_path="${REPO_ROOT}/${relpath}"
  local home_path="${HOME}/${relpath}"

  if (( n < 1 )); then
    print -u2 "rollback: n は 1 以上を指定してください"
    return 1
  fi
  if [[ ! -e "$repo_path" ]]; then
    print -u2 "rollback: リポジトリ内に見つかりません: ${relpath}"
    return 1
  fi

  local -a hashes
  hashes=(${(f)"$(git -C "${REPO_ROOT}" log --follow --format=%H -- "${relpath}")"})
  if (( ${#hashes} == 0 )); then
    print -u2 "rollback: git 履歴が見つかりません: ${relpath}"
    return 1
  fi
  if (( n > ${#hashes} - 1 )); then
    print -u2 "rollback: n は 1〜$(( ${#hashes} - 1 )) の範囲で指定してください(${relpath} の履歴は ${#hashes} コミット)"
    return 1
  fi

  local target_hash=${hashes[$(( 1 + n ))]}
  local meta
  meta="$(git -C "${REPO_ROOT}" show -s --format='%h %ad %s' --date=short "${target_hash}")"

  if (( DRYRUN )); then
    print -- "-- DRY RUN: ${relpath} を ${n} 個前のバージョン(${meta})に戻します(何も書き込みません) --"
    return 0
  fi

  git -C "${REPO_ROOT}" show "${target_hash}:${relpath}" > "${repo_path}"
  mkdir -p -- "${home_path:h}"
  rsync -ah --no-perms -- "${repo_path}" "${home_path}"
  git -C "${REPO_ROOT}" add -- "${relpath}"
  if git -C "${REPO_ROOT}" diff --cached --quiet -- "${relpath}"; then
    print -- "rollback: ${relpath} は既に ${meta} の内容と同じです(変更なし)"
    git -C "${REPO_ROOT}" reset -q -- "${relpath}"
    return 0
  fi
  git -C "${REPO_ROOT}" commit -q -m "revert(rollback): ${relpath} を ${meta} の内容に戻す"
  print -- "✅ rollback: ${relpath} を ${meta} の内容に戻し、\$HOME にも反映してコミットしました"
}

if [[ $MODE == rb || $MODE == rollback ]]; then
  do_rollback "${2:?${USAGE}}" "${3:-1}"
  exit $?
fi

case $MODE in
  d|deploy)  src_base="${REPO_ROOT}" dst_base="${HOME}"     ;;
  r|reverse) src_base="${HOME}"      dst_base="${REPO_ROOT}" ;;
  *) print -u2 "${USAGE}"; exit 1 ;;
esac
(( DRYRUN )) && print -- "-- DRY RUN: no files will be written (${src_base} -> ${dst_base}) --"

# Batch-classify relative paths against this repo's .gitignore in a single
# git process (a naive one-`check-ignore`-call-per-file loop takes minutes
# across the ~60k files under real ~/.config + ~/.local). Prints the subset
# that IS ignored, NUL-separated; anything git itself can't classify (e.g.
# a submodule boundary) is silently omitted from that "ignored" output, so
# treat "not reported as ignored" as the only green light to copy.
#
# To manually reproduce the "N ignored" count printed per entry below,
# check-ignore *without* -v against the exact same relative paths — `-v`
# additionally reports paths inside a nested repo's .git/ (e.g.
# .config/zsh/.antidote/.git/*) as matching the catch-all `*` pattern,
# which this non-verbose call does not, and inflates the count.
ignored_rels() {
  git -C "${REPO_ROOT}" check-ignore -z --stdin < "$1" 2>/dev/null || true
}

copy_rel() {
  local rel=$1
  local dst="${dst_base}/${rel}"
  if (( DRYRUN )); then
    print -- "  would copy  ${rel}"
    return 0
  fi
  mkdir -p -- "${dst:h}"
  rsync -ah --no-perms -- "${src_base}/${rel}" "${dst}"
}

local -i ok=0 skip=0 fail=0 ignored=0
for f in "${DOTFILES[@]}"; do
  local src="${src_base}/${f}"
  if [[ ! -e "$src" ]]; then
    print -- "  skip     ${f}"
    (( skip++ )) || true
    continue
  fi

  local -i entry_ok=0 entry_ignored=0 entry_fail=0
  if [[ -d "$src" && ! -L "$src" ]]; then
    local -a rels=()
    while IFS= read -r -d '' filepath; do
      rels+=("${filepath#${src_base}/}")
    done < <(find "$src" -type f -print0)

    if (( ${#rels} > 0 )); then
      local relfile="$(mktemp)"
      printf '%s\0' "${rels[@]}" > "$relfile"
      local -A ignored_set
      local rel=""
      for rel in ${(0)"$(ignored_rels "$relfile")"}; do
        [[ -n $rel ]] && ignored_set[$rel]=1
      done
      command rm -f -- "$relfile"

      for rel in "${rels[@]}"; do
        if (( ${+ignored_set[$rel]} )); then
          (( entry_ignored++ )) || true
        elif copy_rel "$rel"; then
          (( entry_ok++ )) || true
        else
          print -u2 "  FAILED   ${rel} (rsync exit $?)"
          (( entry_fail++ )) || true
        fi
      done
    fi
  else
    local -i rc
    git -C "${REPO_ROOT}" check-ignore -q -- "${f}" && rc=0 || rc=$?
    # 0 = ignored, 1 = not ignored, >1 = check-ignore itself errored.
    # Only copy on a clean 1; everything else skips — fail safe, not open.
    if (( rc != 1 )); then
      entry_ignored=1
    elif copy_rel "$f"; then
      entry_ok=1
    else
      print -u2 "  FAILED   ${f} (rsync exit $?)"
      entry_fail=1
    fi
  fi

  if (( entry_fail > 0 )); then
    print -u2 "  FAILED   ${f}  (${entry_fail} file(s) failed)"
    (( fail++ )) || true
  else
    print -- "  ok       ${f}  (${entry_ok} copied, ${entry_ignored} ignored)"
    (( ok++ )) || true
    (( ignored += entry_ignored )) || true
  fi
done
if (( DRYRUN )); then
  print -- "\ndry run: ${ok} would-copy, ${skip} skipped, ${fail} failed, ${ignored} file(s) skipped via .gitignore (nothing written)"
else
  print -- "\ndone: ${ok} ok, ${skip} skipped, ${fail} failed, ${ignored} file(s) skipped via .gitignore"
fi
(( fail == 0 ))
