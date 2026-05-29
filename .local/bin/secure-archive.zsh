#!/usr/bin/env zsh
# secure-archive.zsh v2.0 — 7z暗号化 ⇄ Hex（複数ファイル・ディレクトリ対応版）
#
# v2 変更点:
#   - エンコード形式を Base64 → Hex（16進数文字列）に変更
#     出力文字種が 0-9, a-f のみになり UUID と完全一致するため
#     VBA ExcelCapsule の UUID 偽装と連携可能になる
#   - 出力拡張子を .b64 → .hex に変更
#   - 復号時の入力ファイルも .hex を想定（.b64 ファイルは非互換）
#
# 使い方:
#   暗号化: ./secure-archive.zsh <e|enc|encrypt> <file|dir> [file|dir ...] [-p pass] [-n name] [-o dir]
#   復号:   ./secure-archive.zsh <d|dec|decrypt> <file>                    [-p pass] [-o dir]
#
# オプション:
#   -p <pass>  パスワード（省略時は対話入力）
#   -n <name>  アーカイブのベース名（暗号化時のみ有効。省略時は自動生成）
#   -o <dir>   出力先ディレクトリ（省略時は第1入力パスの親ディレクトリ）
#
# 依存: brew install sevenzip
#       python3（macOS/Linux 標準で存在）
#
# 例:
#   ./secure-archive.zsh e report.pdf memo.txt
#   ./secure-archive.zsh e ~/project/
#   ./secure-archive.zsh e src/ dist/ -n release -o /tmp
#   ./secure-archive.zsh d release-7z_hex.txt -o ~/Downloads

set -euo pipefail

# ---------------------------------------------------------------------------
# 7z バイナリ解決
# ---------------------------------------------------------------------------
readonly SZ=$(command -v 7zz 2>/dev/null || command -v 7z 2>/dev/null) \
  || { print -u2 "7zz not found: brew install sevenzip"; exit 1 }

# ---------------------------------------------------------------------------
# ユーティリティ
# ---------------------------------------------------------------------------
die()  { print -u2 "[ERR] $*"; exit 1 }
info() { print      "[   ] $*" }
ok()   { print      "[ ✓] $*" }

usage() {
  cat >&2 <<'EOF'
使い方:
  暗号化: secure-archive.zsh <e|enc|encrypt> <file|dir> [file|dir ...] [-p pass] [-n name] [-o dir]
  復号:   secure-archive.zsh <d|dec|decrypt> <file>                    [-p pass] [-o dir]

オプション:
  -p <pass>  パスワード（省略時は対話入力）
  -n <name>  アーカイブのベース名（暗号化時のみ。省略時は自動生成）
  -o <dir>   出力先ディレクトリ（省略時は第1入力の親ディレクトリ）

出力形式:
  暗号化: <name>-7z_hex.txt  （Hex エンコード済みテキスト）
  復号:   <name>_extracted/  （展開済みディレクトリ）
EOF
  exit 1
}

read_pass() {
  local pw
  print -n "Password: " >/dev/tty
  stty -echo
  IFS= read -r pw </dev/tty
  stty echo
  print "" >/dev/tty
  print -n "$pw"
}

# ---------------------------------------------------------------------------
# 暗号化
#   $1        : アーカイブのベース名（拡張子なし）
#   $2        : パスワード
#   $3        : 出力ディレクトリ
#   $@[4..-1] : 入力パス（ファイル / ディレクトリ 複数可）
# ---------------------------------------------------------------------------
encrypt() {
  local name="$1" pass="$2" outdir="$3"
  shift 3
  local -a srcs=("$@")

  local arc="$outdir/${name}.7z"
  # v2: 出力拡張子を -7z_hex.txt に変更（ExcelCapsule との連携を明示）
  local out="$outdir/${name}-7z_hex.txt"

  info "入力 (${#srcs[@]} パス):"
  for s in "${srcs[@]}"; do info "  $s"; done
  info "7z 暗号化 → $arc"

  "$SZ" a -t7z -p"$pass" -mhe=on -mx=5 "$arc" "${srcs[@]}"

  info "Hex エンコード → $out"
  # v2: Base64 → Hex 変換
  #     python3 の binascii.hexlify を使用（標準ライブラリのみ、macOS/Linux 共通）
  python3 -c "
import binascii, sys
with open(sys.argv[1], 'rb') as f:
    data = f.read()
with open(sys.argv[2], 'w') as g:
    g.write(binascii.hexlify(data).decode('ascii'))
" "$arc" "$out"

  rm -f "$arc"

  local size
  size=$(wc -c <"$out" | tr -d ' ')
  ok "$out (${size} bytes)"
  info "注: Hex 出力は Base64 比で約 2 倍のサイズになります"
}

# ---------------------------------------------------------------------------
# 復号
#   $1 : Hex テキストファイル（-7z_hex.txt）
#   $2 : パスワード
#   $3 : 出力ディレクトリ
# ---------------------------------------------------------------------------
decrypt() {
  local src="$1" pass="$2" outdir="$3"

  # ベース名の正規化: "foo-7z_hex.txt" → "foo"
  local stem
  stem="${${${src:t}%.*}%-7z_hex}"
  stem="${stem%-7z}"

  local arc="$outdir/${stem}.7z"
  local ext="$outdir/${stem}_extracted"

  info "Hex デコード → $arc"
  # v2: Hex → バイナリ変換
  #     BOM が付いている場合も python3 で除去（防御的処理）
  python3 - "$src" "$arc" << 'PYEOF'
import binascii, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, 'rb') as f:
    raw = f.read()
# BOM 除去（念のため）
if raw[:3] == b'\xef\xbb\xbf':
    raw = raw[3:]
# 末尾の改行・空白を除去してからデコード
hex_str = raw.strip()
with open(dst, 'wb') as f:
    f.write(binascii.unhexlify(hex_str))
PYEOF

  info "7z 復号 → $ext"
  mkdir -p "$ext"
  "$SZ" x -p"$pass" -o"$ext" "$arc" -y
  rm -f "$arc"

  ok "$ext"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  (( $# >= 2 )) || usage

  local mode="$1"; shift

  local -a srcs=()
  local pass="" name="" outdir=""

  case "$mode" in
    e|enc|encrypt)
      while (( $# )) && [[ "$1" != -* ]]; do
        srcs+=("$1"); shift
      done
      (( ${#srcs[@]} >= 1 )) || die "入力ファイル/ディレクトリを1つ以上指定してください"

      for s in "${srcs[@]}"; do
        [[ -e "$s" ]] || die "存在しません: $s"
      done

      outdir="${srcs[1]:h}"

      while (( $# )); do
        case "$1" in
          -p) pass="$2";   shift 2 ;;
          -n) name="$2";   shift 2 ;;
          -o) outdir="$2"; shift 2 ;;
          *)  die "不明なオプション: $1" ;;
        esac
      done

      if [[ -z "$name" ]]; then
        if (( ${#srcs[@]} == 1 )); then
          name="${${srcs[1]:t}%.*}"
        else
          name="archive_$( date '+%Y%m%d_%H%M%S' )"
        fi
      fi

      mkdir -p "$outdir"
      [[ -n "$pass" ]] || pass=$(read_pass)
      [[ -n "$pass" ]] || die "パスワードが空です"

      encrypt "$name" "$pass" "$outdir" "${srcs[@]}"
      ;;

    d|dec|decrypt)
      [[ -n "${1:-}" ]] || die "復号対象のファイルを指定してください"
      local src="$1"; shift
      [[ -f "$src" ]] || die "ファイルが見つかりません: $src"
      outdir="${src:h}"

      while (( $# )); do
        case "$1" in
          -p) pass="$2";   shift 2 ;;
          -o) outdir="$2"; shift 2 ;;
          -n) shift 2 ;;
          *)  die "不明なオプション: $1" ;;
        esac
      done

      mkdir -p "$outdir"
      [[ -n "$pass" ]] || pass=$(read_pass)
      [[ -n "$pass" ]] || die "パスワードが空です"

      decrypt "$src" "$pass" "$outdir"
      ;;

    -h|--help) usage ;;
    *) die "モード指定が不正: $mode（e[nc[rypt]] または d[ec[rypt]]）" ;;
  esac
}

main "$@"
