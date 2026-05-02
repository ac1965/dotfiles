#!/usr/bin/env bash
#
# capture-ocr-pipeline.sh
#
# HDMI capture card → screenshot (manual trigger) → OCR → CSV
# - Enter key triggers each capture (synchronized with manual page-flipping)
# - Batch OCR after capture session ends
# - macOS / Linux 対応（Bash 3.2+ 互換）
#

set -euo pipefail

# Bash 3.2+ compatibility check (macOS default is 3.2)
if [[ -z "${BASH_VERSION:-}" ]]; then
	echo "ERROR: This script requires bash" >&2
	exit 1
fi

readonly SCRIPT_NAME="${0##*/}"
readonly LOCK_FILE="/tmp/${SCRIPT_NAME%.sh}.lock"

# ================================================================
# Config
# ================================================================

DEVICE_NAME="${DEVICE_NAME:-UGREEN 25854}"
BASE_DIR="${BASE_DIR:-$HOME/ocr_pipeline}"
RESOLUTION="${RESOLUTION:-1920x1080}"
OCR_LANG="${OCR_LANG:-jpn}"
EXPECTED_COUNT="${EXPECTED_COUNT:-0}" # 0 = unlimited

export TESSDATA_PREFIX="$HOME/tessdata"

# ================================================================
# Dirs
# ================================================================

SESSION_TS="$(date +"%Y%m%d_%H%M%S")"
SESSION_DIR="$BASE_DIR/session_$SESSION_TS"
CAPTURE_DIR="$SESSION_DIR/capture"
PROC_DIR="$SESSION_DIR/processed"
TSV_DIR="$SESSION_DIR/tsv"
CSV_DIR="$SESSION_DIR/csv"
LOG_DIR="$SESSION_DIR/log"
LOG="$LOG_DIR/pipeline.log"

# ================================================================
# Logging
# ================================================================

log() { printf '%s [INFO]  %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | tee -a "$LOG"; }
warn() { printf '%s [WARN]  %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | tee -a "$LOG" >&2; }
die() {
	printf '%s [ERROR] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" | tee -a "$LOG" >&2
	exit 1
}

# ================================================================
# Usage
# ================================================================

usage() {
	cat <<EOF
Usage: $SCRIPT_NAME [-n EXPECTED_COUNT] [-h]

Options:
  -n COUNT   Expected number of captures (0 = unlimited, default: 0)
  -h         Show this help

Environment:
  DEVICE_NAME  Capture device name (default: "UGREEN 25854")
  BASE_DIR     Output base directory (default: \$HOME/ocr_pipeline)
  RESOLUTION   Capture resolution (default: 1920x1080)
  OCR_LANG     Tesseract language (default: jpn)

Interactive commands during capture:
  Enter   Capture current frame
  r       Retake last capture (discard previous)
  s       Skip (insert blank placeholder)
  q       Quit and run batch OCR
  ?       Show help
EOF
}

# ================================================================
# Checks
# ================================================================

check_deps() {
	for cmd in ffmpeg magick tesseract awk; do
		command -v "$cmd" &>/dev/null || die "Missing: $cmd"
	done
}

check_lang() {
	[[ -f "$TESSDATA_PREFIX/${OCR_LANG}.traineddata" ]] ||
		die "Missing: $TESSDATA_PREFIX/${OCR_LANG}.traineddata"
}

init_dirs() {
	mkdir -p "$CAPTURE_DIR" "$PROC_DIR" "$TSV_DIR" "$CSV_DIR" "$LOG_DIR"
}

detect_backend() {
	case "$(uname -s)" in
	Darwin) echo "avfoundation" ;;
	Linux) echo "v4l2" ;;
	*) die "Unsupported OS" ;;
	esac
}

# ================================================================
# Capture
# ================================================================

do_capture() {
	local backend="$1" output="$2"
	ffmpeg -f "$backend" \
		-pixel_format uyvy422 \
		-framerate 30 \
		-video_size "$RESOLUTION" \
		-i "${DEVICE_NAME}:none" \
		-frames:v 1 \
		-y -loglevel error \
		"$output"
}

# ================================================================
# Preprocess
# ================================================================

do_preprocess() {
	magick "$1" \
		-colorspace Gray \
		-resize 200% \
		-threshold 60% \
		-sharpen 0x1 \
		"$2"
}

# ================================================================
# OCR
# ================================================================

do_ocr() {
	local input="$1" base="$2"
	tesseract "$input" "$base" \
		-l "$OCR_LANG" \
		--oem 1 \
		--psm 6 \
		tsv 2>/dev/null

	[[ -f "$base.tsv" ]] || {
		warn "TSV not generated for $base → fallback to txt"
		[[ -f "$base.txt" ]] && mv "$base.txt" "$base.tsv"
	}
}

do_tsv2csv() {
	awk -F'\t' '
		NR > 1 && $12 != "" {
			gsub(/,/, "，", $12)
			printf "%s,", $12
		}
		END { print "" }
	' "$1" >"$2"
}

# ================================================================
# Lock
# ================================================================

acquire_lock() {
	if [[ -e "$LOCK_FILE" ]]; then
		local pid
		pid="$(cat "$LOCK_FILE" 2>/dev/null || echo "")"
		if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
			die "Another instance is running (pid=$pid)"
		fi
		rm -f "$LOCK_FILE"
	fi
	echo $$ >"$LOCK_FILE"
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
  q       Quit and run batch OCR
  ?       Show this help

EOF
}

capture_loop() {
	local backend="$1"
	local count=0
	local last_raw=""

	echo
	echo "================================================"
	echo "  Capture session started"
	echo "  Device: $DEVICE_NAME"
	echo "  Output: $SESSION_DIR"
	if [[ "$EXPECTED_COUNT" -gt 0 ]]; then
		echo "  Expected: $EXPECTED_COUNT captures"
	fi
	echo "================================================"
	show_help

	while true; do
		local prompt
		if [[ "$EXPECTED_COUNT" -gt 0 ]]; then
			prompt="[${count}/${EXPECTED_COUNT}] Enter=capture, r=retake, s=skip, q=quit > "
		else
			prompt="[${count}] Enter=capture, r=retake, s=skip, q=quit > "
		fi

		local input
		read -rp "$prompt" input || {
			echo
			break
		}

		case "$input" in
		"")
			# Capture
			count=$((count + 1))
			local seq
			seq="$(printf '%04d' "$count")"
			local ts
			ts="$(date +"%Y%m%d_%H%M%S")"
			local raw="$CAPTURE_DIR/${seq}_${ts}.png"

			if do_capture "$backend" "$raw" 2>/dev/null; then
				log "Captured #${seq} → $(basename "$raw")"
				last_raw="$raw"
				if [[ "$EXPECTED_COUNT" -gt 0 ]] && [[ "$count" -ge "$EXPECTED_COUNT" ]]; then
					echo
					local yn
					read -rp "Reached expected count ($EXPECTED_COUNT). Continue? (y/N) > " yn
					case "$yn" in
					[yY]*) ;;
					*) break ;;
					esac
				fi
			else
				warn "Capture failed (#${seq}) — not counted"
				count=$((count - 1))
			fi
			;;
		r | R)
			if [[ -n "$last_raw" ]] && [[ -f "$last_raw" ]]; then
				rm -f "$last_raw"
				log "Discarded $(basename "$last_raw") — please re-capture"
				count=$((count - 1))
				last_raw=""
			else
				warn "No previous capture to retake"
			fi
			;;
		s | S)
			count=$((count + 1))
			local seq
			seq="$(printf '%04d' "$count")"
			local placeholder="$CAPTURE_DIR/${seq}_SKIPPED.txt"
			: >"$placeholder"
			log "Skipped #${seq} (placeholder created)"
			last_raw=""
			;;
		q | Q)
			break
			;;
		\?)
			show_help
			;;
		*)
			echo "Unknown command: '$input' (? for help)"
			;;
		esac
	done

	echo
	log "Capture session ended: $count frames"
	return 0
}

# ================================================================
# Batch OCR
# ================================================================

batch_ocr() {
	# Bash 3.2 compatible: avoid `mapfile` (Bash 4+)
	local images=()
	local f
	while IFS= read -r f; do
		images+=("$f")
	done < <(find "$CAPTURE_DIR" -name '*.png' | sort)

	if [[ ${#images[@]} -eq 0 ]]; then
		warn "No captures to process"
		return 0
	fi

	echo
	echo "================================================"
	echo "  Running batch OCR on ${#images[@]} images"
	echo "================================================"

	local idx=0
	local total=${#images[@]}
	local ok=0
	local ng=0

	local raw
	for raw in "${images[@]}"; do
		idx=$((idx + 1))
		local name
		name="$(basename "$raw" .png)"
		local proc="$PROC_DIR/${name}.png"
		local base="$TSV_DIR/${name}"
		local tsv="${base}.tsv"
		local csv="$CSV_DIR/${name}.csv"

		printf '[%d/%d] %s ... ' "$idx" "$total" "$name"

		if ! do_preprocess "$raw" "$proc" 2>/dev/null; then
			echo "preprocess FAILED"
			ng=$((ng + 1))
			continue
		fi

		if ! do_ocr "$proc" "$base" 2>/dev/null; then
			echo "OCR FAILED"
			ng=$((ng + 1))
			continue
		fi

		if ! do_tsv2csv "$tsv" "$csv" 2>/dev/null; then
			echo "CSV FAILED"
			ng=$((ng + 1))
			continue
		fi

		echo "OK"
		ok=$((ok + 1))
	done

	# Combined CSV (Bash 3.2 compatible: use find instead of brace glob with cat)
	local combined="$CSV_DIR/_combined.csv"
	: >"$combined"
	local c
	while IFS= read -r c; do
		cat "$c" >>"$combined"
	done < <(find "$CSV_DIR" -name '[0-9]*.csv' | sort)

	echo
	log "Batch OCR finished: $ok success, $ng failed"
	log "Combined CSV: $combined"
}

# ================================================================
# Main
# ================================================================

main() {
	while getopts ":n:h" opt; do
		case "$opt" in
		n) EXPECTED_COUNT="$OPTARG" ;;
		h)
			usage
			exit 0
			;;
		\?) die "Invalid option: -$OPTARG" ;;
		:) die "Option -$OPTARG requires an argument" ;;
		esac
	done

	check_deps
	check_lang
	init_dirs
	acquire_lock
	trap cleanup EXIT

	local backend
	backend="$(detect_backend)"

	log "START device='$DEVICE_NAME' lang=$OCR_LANG session=$SESSION_TS"

	capture_loop "$backend"
	batch_ocr

	echo
	echo "================================================"
	echo "  All done"
	echo "  Session dir: $SESSION_DIR"
	echo "================================================"
}

main "$@"
