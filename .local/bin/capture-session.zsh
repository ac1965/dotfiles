#!/usr/bin/env zsh
#
# capture-session.zsh
#
# HDMI capture card からインタラクティブにスナップショットを取得
# - Enterキーで都度キャプチャ（手動ページめくりと同期）
# - capture-session.sh の zsh リライト版
# - macOS / Linux 対応（zsh 5.0+）
#
# Output structure:
#   $BASE_DIR/session_YYYYMMDD_HHMMSS/
#     ├── capture/NNNN_TIMESTAMP.png
#     └── log/capture.log
#

emulate zsh
setopt err_exit no_unset pipe_fail
setopt no_bg_nice no_hup     # 子プロセスの挙動を安定化

readonly SCRIPT_NAME="${0:t}"
readonly LOCK_FILE="/tmp/${SCRIPT_NAME:r}.lock"

# ================================================================
# Config
# ================================================================

: ${DEVICE_NAME:=}
: ${BASE_DIR:=$HOME/capture_session}
: ${RESOLUTION:=1920x1080}
: ${PIXEL_FORMAT:=uyvy422}
: ${FRAMERATE:=30}
: ${EXPECTED_COUNT:=0}                  # 0 = unlimited

# ================================================================
# Dirs
# ================================================================

SESSION_TS=$(date +"%Y%m%d_%H%M%S")
SESSION_DIR="$BASE_DIR/session_$SESSION_TS"
CAPTURE_DIR="$SESSION_DIR/capture"
LOG_DIR="$SESSION_DIR/log"
LOG="$LOG_DIR/capture.log"

# ================================================================
# Logging
# ================================================================

log()  { print -r -- "$(date '+%Y-%m-%dT%H:%M:%S') [INFO]  $*" | tee -a "$LOG" }
warn() { print -r -- "$(date '+%Y-%m-%dT%H:%M:%S') [WARN]  $*" | tee -a "$LOG" >&2 }
die()  {
    print -r -- "$(date '+%Y-%m-%dT%H:%M:%S') [ERROR] $*" | tee -a "$LOG" >&2
    exit 1
}

# ================================================================
# Usage
# ================================================================

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [-n COUNT] [-d PATTERN] [-l] [-h]

HDMI キャプチャデバイスからインタラクティブにスナップショットを取得します。

Options:
  -n COUNT    Expected number of captures (0 = unlimited, default: 0)
  -d PATTERN  Video device name pattern (partial match, case-sensitive)
  -l          List available video devices and exit
  -h          Show this help

Environment:
  DEVICE_NAME   Default device pattern (overridden by -d)
  BASE_DIR      Output base directory (default: \$HOME/capture_session)
  RESOLUTION    Capture resolution (default: 1920x1080)
  PIXEL_FORMAT  Pixel format (default: uyvy422; use nv12 for 4K)
  FRAMERATE     Capture framerate (default: 30)

Device resolution priority:
  1. -d PATTERN
  2. \$DEVICE_NAME
  3. Interactive selection

Interactive commands:
  Enter   Capture current frame
  r       Retake last capture (discard previous)
  s       Skip (insert blank placeholder)
  q       Quit
  ?       Show help

Examples:
  $SCRIPT_NAME -l                    # List devices
  $SCRIPT_NAME -d HUVC               # Use GV-HUVC/4KV
  $SCRIPT_NAME -d HUVC -n 30         # 30枚予定
  RESOLUTION=3840x2160 PIXEL_FORMAT=nv12 $SCRIPT_NAME -d HUVC   # 4K
EOF
}

# ================================================================
# Checks
# ================================================================

check_deps() {
    local cmd
    for cmd in ffmpeg sed; do
        (( $+commands[$cmd] )) || die "Missing: $cmd"
    done
}

init_dirs() {
    mkdir -p "$CAPTURE_DIR" "$LOG_DIR"
}

detect_backend() {
    case "$(uname -s)" in
        Darwin) print -r -- "avfoundation" ;;
        Linux)  print -r -- "v4l2" ;;
        *)      die "Unsupported OS: $(uname -s)" ;;
    esac
}

# ================================================================
# Device Detection
# ================================================================

# 利用可能なビデオデバイス一覧を "INDEX|NAME" 形式で出力
list_devices() {
    case "$(uname -s)" in
        Darwin)
            ffmpeg -f avfoundation -list_devices true -i "" 2>&1 |
                sed -n '/AVFoundation video devices:/,/AVFoundation audio devices:/{
                    s/.*\[\([0-9][0-9]*\)\] \(.*\)$/\1|\2/p
                }'
            ;;
        Linux)
            local dev
            setopt local_options null_glob
            for dev in /dev/video*; do
                printf '%s|%s\n' "$dev" \
                    "$(<"/sys/class/video4linux/${dev:t}/name" 2>/dev/null || print -r -- unknown)"
            done
            ;;
    esac
}

show_devices() {
    print -- "Available video devices:"
    local idx name found=0
    while IFS='|' read -r idx name; do
        printf '  [%s] %s\n' "$idx" "$name"
        found=1
    done < <(list_devices)
    (( found )) || print -- "  (none)"
}

# パターン部分一致でデバイス名(フルネーム)を解決
resolve_device() {
    local pattern="$1"
    local idx name
    while IFS='|' read -r idx name; do
        if [[ "$name" == *"$pattern"* ]]; then
            print -r -- "$name"
            return 0
        fi
    done < <(list_devices)
    return 1
}

# 対話的にデバイスを選択（1-indexed）
select_device() {
    local -a devices
    local line
    while IFS= read -r line; do
        devices+=("$line")
    done < <(list_devices)

    (( ${#devices[@]} > 0 )) || die "No video devices found"

    {
        print --
        print -- "Available video devices:"
        local i d
        for i in {1..${#devices[@]}}; do
            d="${devices[$i]}"
            printf '  [%d] %s\n' "$i" "${d#*|}"
        done
        print --
    } >&2

    local sel
    read -r "sel?Select device number [1-${#devices[@]}]: " </dev/tty
    [[ "$sel" == <-> ]] && (( sel >= 1 && sel <= ${#devices[@]} )) ||
        die "Invalid selection: '$sel'"

    # ${devices[$sel]} は zsh の 1-indexed アクセス
    print -r -- "${devices[$sel]#*|}"
}

# DEVICE_NAME を最終決定（パターン → 環境変数 → 対話）
determine_device() {
    local pattern="$1"
    local resolved=""

    if [[ -n "$pattern" ]]; then
        resolved=$(resolve_device "$pattern") ||
            die "No device matches pattern: '$pattern'
Hint: run \`$SCRIPT_NAME -l\` to see available devices"
        print -r -- "$resolved"
        return 0
    fi

    if [[ -n "$DEVICE_NAME" ]]; then
        if resolved=$(resolve_device "$DEVICE_NAME"); then
            print -r -- "$resolved"
            return 0
        fi
        warn "DEVICE_NAME='$DEVICE_NAME' not found → interactive selection"
    fi

    select_device
}

# ================================================================
# Capture
# ================================================================

do_capture() {
    local backend="$1" output="$2"
    local input_spec
    case "$backend" in
        avfoundation) input_spec="${DEVICE_NAME}:none" ;;
        v4l2)         input_spec="$DEVICE_NAME" ;;
        *)            die "Unsupported backend: $backend" ;;
    esac

    ffmpeg -f "$backend" \
        -pixel_format "$PIXEL_FORMAT" \
        -framerate "$FRAMERATE" \
        -video_size "$RESOLUTION" \
        -i "$input_spec" \
        -frames:v 1 \
        -y -loglevel error \
        "$output"
}

# ================================================================
# Lock
# ================================================================

acquire_lock() {
    if [[ -e "$LOCK_FILE" ]]; then
        local pid
        pid="$(<"$LOCK_FILE" 2>/dev/null || print -r -- "")"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            die "Another instance is running (pid=$pid)"
        fi
        rm -f "$LOCK_FILE"
    fi
    print -r -- $$ > "$LOCK_FILE"
}

cleanup() {
    rm -f "$LOCK_FILE"
}

# ================================================================
# Interactive Capture Loop
# ================================================================

show_help() {
    cat <<EOF

  Enter   Capture current frame
  r       Retake last capture (discard previous)
  s       Skip (insert blank placeholder)
  q       Quit
  ?       Show this help

EOF
}

capture_loop() {
    local backend="$1"
    local count=0
    local last_raw=""

    print --
    print -- "================================================"
    print -- "  Capture session started"
    print -- "  Device: $DEVICE_NAME"
    print -- "  Output: $SESSION_DIR"
    (( EXPECTED_COUNT > 0 )) && print -- "  Expected: $EXPECTED_COUNT captures"
    print -- "================================================"
    show_help

    while true; do
        local prompt
        if (( EXPECTED_COUNT > 0 )); then
            prompt="[${count}/${EXPECTED_COUNT}] Enter=capture, r=retake, s=skip, q=quit > "
        else
            prompt="[${count}] Enter=capture, r=retake, s=skip, q=quit > "
        fi

        local input
        if ! read -r "input?$prompt"; then
            print --
            break
        fi

        case "$input" in
            "")
                count=$((count + 1))
                local seq ts raw
                seq="$(printf '%04d' "$count")"
                ts="$(date +"%Y%m%d_%H%M%S")"
                raw="$CAPTURE_DIR/${seq}_${ts}.png"

                if do_capture "$backend" "$raw" 2>/dev/null; then
                    log "Captured #${seq} → ${raw:t}"
                    last_raw="$raw"
                    if (( EXPECTED_COUNT > 0 && count >= EXPECTED_COUNT )); then
                        print --
                        local yn
                        read -r "yn?Reached expected count ($EXPECTED_COUNT). Continue? (y/N) > "
                        [[ "$yn" == [yY]* ]] || break
                    fi
                else
                    warn "Capture failed (#${seq}) — not counted"
                    count=$((count - 1))
                fi
                ;;
            r|R)
                if [[ -n "$last_raw" && -f "$last_raw" ]]; then
                    rm -f "$last_raw"
                    log "Discarded ${last_raw:t} — please re-capture"
                    count=$((count - 1))
                    last_raw=""
                else
                    warn "No previous capture to retake"
                fi
                ;;
            s|S)
                count=$((count + 1))
                local seq placeholder
                seq="$(printf '%04d' "$count")"
                placeholder="$CAPTURE_DIR/${seq}_SKIPPED.txt"
                : > "$placeholder"
                log "Skipped #${seq} (placeholder created)"
                last_raw=""
                ;;
            q|Q)  break ;;
            \?)   show_help ;;
            *)    print -- "Unknown command: '$input' (? for help)" ;;
        esac
    done

    print --
    log "Capture session ended: $count frames"
    return 0
}

# ================================================================
# Main
# ================================================================

main() {
    local list_only=0
    local device_pattern=""
    local opt

    while getopts ":n:d:lh" opt; do
        case "$opt" in
            n) EXPECTED_COUNT="$OPTARG" ;;
            d) device_pattern="$OPTARG" ;;
            l) list_only=1 ;;
            h) usage; exit 0 ;;
            \?) die "Invalid option: -$OPTARG" ;;
            :)  die "Option -$OPTARG requires an argument" ;;
        esac
    done

    check_deps

    if (( list_only )); then
        show_devices
        exit 0
    fi

    DEVICE_NAME="$(determine_device "$device_pattern")"

    init_dirs
    acquire_lock
    trap cleanup EXIT

    local backend
    backend="$(detect_backend)"

    log "START device='$DEVICE_NAME' resolution=$RESOLUTION session=$SESSION_TS"

    capture_loop "$backend"

    # 結果サマリ（zsh glob qualifier を活用）
    local -a pngs skipped
    pngs=("$CAPTURE_DIR"/*.png(N))
    skipped=("$CAPTURE_DIR"/*_SKIPPED.txt(N))

    print --
    print -- "================================================"
    print -- "  Capture done"
    print -- "  Captured : ${#pngs[@]} PNG"
    (( ${#skipped[@]} > 0 )) && print -- "  Skipped  : ${#skipped[@]} placeholder"
    print -- "  Session  : $SESSION_DIR"
    print -- "================================================"
}

main "$@"
