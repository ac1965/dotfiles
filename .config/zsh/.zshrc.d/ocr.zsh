#!/bin/zsh
#
# ocr.zsh - macOS Vision Framework + ffmpeg を使ったOCRユーティリティ
#
# 依存:
#   - ffmpeg          (brew install ffmpeg)
#   - ocrmac (Python) (pip install ocrmac --break-system-packages)
#   - macOS 13+ (日本語OCR対応)
#
# 使い方:
#   ocr            : スクリーン領域を選択してOCR
#   ocr_huvc       : I-O DATA GV-HUVC/4KV からOCR
#   ocr_desk       : iPhoneデスクビューカメラからOCR
#   ocr_file FILE  : 画像ファイルをOCR
#   ocr_devices    : 利用可能なAVFoundationデバイス一覧

# --- 内部関数: Apple Vision で画像をOCR ---
_ocr_run() {
  local img="$1"
  [[ -s "$img" ]] || { echo "画像なし: $img" >&2; return 1; }
  python3 - "$img" <<'PY' | pbcopy
import sys
from ocrmac import ocrmac
r = ocrmac.OCR(sys.argv[1],
               language_preference=['ja-JP', 'en-US'],
               recognition_level='accurate').recognize()
print('\n'.join(x[0] for x in r))
PY
  echo "OCR結果をクリップボードへコピー完了"
}

# --- 内部関数: AVFoundationデバイスからスナップショット ---
_ocr_capture() {
  local idx="$1" size="${2:-1920x1080}"
  local tmp=$(mktemp -t ocr).png
  ffmpeg -hide_banner -loglevel error \
    -f avfoundation -framerate 30 -video_size "$size" \
    -i "$idx" -frames:v 1 -y "$tmp" || return 1
  _ocr_run "$tmp"
  rm -f "$tmp"
}

# --- 公開関数 ---

# スクリーン領域選択 → OCR
ocr() {
  local tmp=$(mktemp -t ocr).png
  screencapture -i "$tmp" || return 1
  [[ -s "$tmp" ]] || { echo "キャンセル"; return 1; }
  _ocr_run "$tmp"
  rm -f "$tmp"
}

# GV-HUVC/4KV (HDMI入力) → OCR
ocr_huvc() { _ocr_capture "1" "${1:-1920x1080}"; }

# iPhoneデスクビューカメラ → OCR
ocr_desk() { _ocr_capture "3"; }

# 画像ファイル → OCR
ocr_file() { _ocr_run "$1"; }

# デバイス一覧確認 (インデックスがズレた時に使う)
ocr_devices() {
  ffmpeg -f avfoundation -list_devices true -i "" 2>&1 \
    | grep -E 'AVFoundation (video|audio) devices:|\[[0-9]+\]'
}
