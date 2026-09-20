#!/usr/bin/env zsh
#
# dotfiles-autosync.zsh
# dotfiles リポジトリに対して定期的に reverse($HOME→repo)→commit→push を
# 行う準自動同期(mise の `bootstrap dotfiles` の autosave/auto-publish に
# 相当する機能を、常駐監視プロセスなしで launchd の定期実行として実現する)。
#
# 使い方:
#   dotfiles-autosync.zsh run           - 1回だけ同期を実行(launchd から呼ばれる本体)
#   dotfiles-autosync.zsh run -n        - 何が起きるかだけ確認(書き込み・commit・push なし)
#   dotfiles-autosync.zsh install       - launchd エージェントを登録して有効化
#   dotfiles-autosync.zsh uninstall     - launchd エージェントを停止して削除
#   dotfiles-autosync.zsh status        - 登録状態とログの末尾を表示
#
# 必須環境変数: なし
# 任意環境変数:
#   DOTFILES_REPO - dotfiles リポジトリの場所(既定: ${HOME}/Projects/dotfiles)
#   DOTFILES_AUTOSYNC_INTERVAL - 実行間隔(秒、既定: 3600 = 1時間。install 時のみ参照)
#
# 同期対象は dotfiles.zsh の DOTFILES 配列に列挙された範囲のみ(git add も
# その範囲に限定する)。リポジトリ内で進行中の他の作業(README編集やスクリプト
# 開発など)を巻き込んで自動コミット・自動pushしてしまわないための安全策。
#
# push は upstream が設定されているブランチでのみ行う。リモートが自分より
# 先行している場合は `git pull --rebase --autostash` を試み、それでも
# コンフリクトする場合は rebase を中断してエラー終了する(強制上書きはしない)。

set -o errexit
set -o nounset
set -o pipefail
zmodload zsh/system

SCRIPT_NAME="${0:t}"
DOTFILES_REPO="${DOTFILES_REPO:-${HOME}/Projects/dotfiles}"
INTERVAL="${DOTFILES_AUTOSYNC_INTERVAL:-3600}"

STATE_DIR="${HOME}/.local/state/dotfiles-autosync"
LOG_FILE="${STATE_DIR}/autosync.log"
LOCK_FILE="${STATE_DIR}/autosync.lock"

LABEL="com.ac1965.dotfiles-autosync"
PLIST_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"

log_info()  { print -- "→ $*" }
log_error() { print -u2 -- "❌ [${SCRIPT_NAME}] $*" }

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} run [-n|--dry-run]
       ${SCRIPT_NAME} install|uninstall|status

  run        : reverse → commit → push を1回実行(通常は launchd から呼ばれる)
  install    : launchd エージェントを登録し即座に有効化(${INTERVAL}秒間隔)
  uninstall  : launchd エージェントを停止・削除
  status     : 登録状態とログ末尾を表示

  対象リポジトリ: ${DOTFILES_REPO}(DOTFILES_REPO で上書き可)
  ログ          : ${LOG_FILE}
EOF
  exit 1
}

append_log() {
  mkdir -p -- "${STATE_DIR}"
  print -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}"
}

# dotfiles.zsh の DOTFILES 配列を単一の情報源として再利用する(ここで独自に
# 一覧を持つと片方だけ更新されて乖離する事故を防ぐ)。配列本体を実行せずに
# テキストとして抜き出すだけなので、dotfiles.zsh 側の set -euo pipefail や
# 位置引数の扱いに影響されない。
dotfiles_entries() {
  sed -n '/^readonly DOTFILES=(/,/^)/p' "${DOTFILES_REPO}/dotfiles.zsh" \
    | sed -e '1d' -e '$d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v '^$'
}

# repo 側が $HOME より内容的に先行しているファイルを検出する。
#
# 背景: reverse は $HOME → repo の一方向コピーで、どちらが「新しい」かを
# 判断せず機械的に repo を上書きする。そのため「repo だけを直接編集・commit
# したが、まだ deploy していない」状態で autosync が走ると、その repo 側の
# 変更が $HOME の古い内容でサイレントに打ち消され、そのまま commit・push
# されてしまう(2026-09-14 の autosync が 48ed353 の backup-all/restore-all
# 実装を巻き戻した事故が実例)。
#
# `./dotfiles.zsh deploy -n` の出力(.gitignore 判定済みの実コピー候補一覧)
# は中身を比較せず対象を無条件列挙するだけなので、ここでさらに cmp で実際
# に内容が異なるものだけに絞り込む。
detect_repo_ahead() {
  local -a candidates=()
  local rel=""
  while IFS= read -r rel; do
    [[ -n $rel ]] && candidates+=("$rel")
  done < <(./dotfiles.zsh deploy -n 2>/dev/null | sed -n 's/^  would copy  //p' || true)

  local repo_f="" home_f=""
  for rel in "${candidates[@]}"; do
    repo_f="${DOTFILES_REPO}/${rel}"
    home_f="${HOME}/${rel}"
    [[ -f "$repo_f" ]] || continue
    if [[ ! -e "$home_f" ]] || ! cmp -s -- "$repo_f" "$home_f"; then
      print -- "$rel"
    fi
  done
}

do_run() {
  local -i dryrun=0
  local a=""
  for a in "$@"; do
    case $a in
      -n|--dry-run) dryrun=1 ;;
    esac
  done

  mkdir -p -- "${STATE_DIR}"
  : >>"${LOCK_FILE}"
  if ! zsystem flock -t 0 "${LOCK_FILE}" 2>/dev/null; then
    log_error "前回の実行がまだロックを保持しています。スキップします。"
    append_log "skip: lock busy"
    return 1
  fi

  if [[ ! -d "${DOTFILES_REPO}/.git" ]]; then
    log_error "dotfiles リポジトリが見つかりません: ${DOTFILES_REPO}"
    append_log "error: repo not found at ${DOTFILES_REPO}"
    return 1
  fi

  cd -- "${DOTFILES_REPO}"

  if (( dryrun )); then
    log_info "-- DRY RUN: reverse の対象確認のみ(commit/push は行いません) --"
    ./dotfiles.zsh reverse -n
    return 0
  fi

  local -a ahead
  ahead=("${(@f)$(detect_repo_ahead)}")
  ahead=("${ahead[@]:#}")  # 空文字要素(該当なし)を除去

  local -A protect_backup
  if (( ${#ahead} > 0 )); then
    local rel="" tmp=""
    for rel in "${ahead[@]}"; do
      tmp="$(mktemp)"
      cp -- "${DOTFILES_REPO}/${rel}" "$tmp"
      protect_backup[$rel]="$tmp"
    done
  fi

  ./dotfiles.zsh reverse >/dev/null

  if (( ${#ahead} > 0 )); then
    local rel=""
    for rel in "${(k)protect_backup[@]}"; do
      mkdir -p -- "${DOTFILES_REPO}/${rel:h}"
      cp -- "${protect_backup[$rel]}" "${DOTFILES_REPO}/${rel}"
      command rm -f -- "${protect_backup[$rel]}"
    done
    log_error "repo が \$HOME より先行しているため reverse による上書きから保護しました(deploy 未反映の可能性): ${ahead[*]}"
    append_log "warning: protected from reverse (repo ahead of \$HOME,要 deploy): ${ahead[*]}"
  fi

  local -a entries
  entries=($(dotfiles_entries))
  if (( ${#entries} == 0 )); then
    log_error "DOTFILES 配列を読み取れませんでした"
    append_log "error: failed to parse DOTFILES array"
    return 1
  fi
  local -a existing=()
  local e=""
  for e in "${entries[@]}"; do
    [[ -e "${DOTFILES_REPO}/${e}" ]] && existing+=("$e")
  done
  (( ${#existing} > 0 )) && git add -- "${existing[@]}"

  if git diff --cached --quiet; then
    append_log "no changes"
    return 0
  fi

  local host="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
  git commit -q -m "chore(autosync): ${host} $(date '+%Y-%m-%d %H:%M') の自動同期"

  if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    log_info "upstream 未設定のため push はスキップします"
    append_log "committed, no upstream — push skipped"
    return 0
  fi

  git fetch -q origin
  if ! git pull -q --rebase --autostash; then
    git rebase --abort 2>/dev/null || true
    log_error "pull --rebase がコンフリクトしました。手動で解決してください。push は行いません。"
    append_log "error: rebase conflict, push skipped"
    return 1
  fi

  if git push -q; then
    append_log "committed and pushed"
  else
    log_error "push に失敗しました(ネットワーク/認証等)。commit はローカルに残っています。"
    append_log "error: push failed"
    return 1
  fi
}

do_install() {
  mkdir -p -- "${STATE_DIR}" "${HOME}/Library/LaunchAgents"
  local script_path="${HOME}/.local/bin/${SCRIPT_NAME}"
  if [[ ! -x "$script_path" ]]; then
    log_error "${script_path} が見つかりません。先に dotfiles.zsh deploy を実行してください。"
    exit 1
  fi

  cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${script_path}</string>
    <string>run</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>DOTFILES_REPO</key>
    <string>${DOTFILES_REPO}</string>
  </dict>
  <key>StartInterval</key>
  <integer>${INTERVAL}</integer>
  <key>StandardOutPath</key>
  <string>${LOG_FILE}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_FILE}</string>
</dict>
</plist>
EOF

  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "${PLIST_PATH}"
  log_info "✅ ${LABEL} を登録しました(${INTERVAL}秒間隔、対象: ${DOTFILES_REPO})"
  log_info "   停止するには: ${SCRIPT_NAME} uninstall"
}

do_uninstall() {
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  rm -f -- "${PLIST_PATH}"
  log_info "✅ ${LABEL} を停止・削除しました"
}

do_status() {
  if launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1; then
    log_info "登録済み: ${PLIST_PATH}"
  else
    log_info "未登録です(install で有効化できます)"
  fi
  if [[ -f "${LOG_FILE}" ]]; then
    log_info "--- ログ末尾 (${LOG_FILE}) ---"
    tail -n 10 -- "${LOG_FILE}"
  fi
}

if (( $# == 0 )); then
  usage
fi

case "$1" in
  run)       shift; do_run "$@" ;;
  install)   do_install ;;
  uninstall) do_uninstall ;;
  status)    do_status ;;
  -h|--help) usage ;;
  *)         usage ;;
esac
