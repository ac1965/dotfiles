#!/usr/bin/env zsh
# secure-archive.zsh — 7z暗号化 ⇄ Base64（複数ファイル・ディレクトリ対応版）
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
#
# 例:
#   ./secure-archive.zsh e report.pdf memo.txt           # 複数ファイル
#   ./secure-archive.zsh e ~/project/                    # ディレクトリ丸ごと
#   ./secure-archive.zsh e src/ dist/ -n release -o /tmp # 名前・出力先を指定
#   ./secure-archive.zsh d release-7z_b64.txt -o ~/Downloads

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
  local out="$outdir/${name}-7z_b64.txt"

  info "入力 (${#srcs[@]} パス):"
  for s in "${srcs[@]}"; do info "  $s"; done
  info "7z 暗号化 → $arc"

  # 7z a はパスを可変長で受け取れるのでそのまま展開して渡す
  "$SZ" a -t7z -p"$pass" -mhe=on -mx=5 "$arc" "${srcs[@]}"

  info "Base64 エンコード → $out"
  base64 -i "$arc" -o "$out"
  rm -f "$arc"

  local size
  size=$(wc -c <"$out" | tr -d ' ')
  ok "$out (${size} bytes)"
}

# ---------------------------------------------------------------------------
# 復号
#   $1 : Base64 テキストファイル
#   $2 : パスワード
#   $3 : 出力ディレクトリ
# ---------------------------------------------------------------------------
decrypt() {
  local src="$1" pass="$2" outdir="$3"

  # ベース名: "foo-7z_b64.txt" → "foo" / "bar_b64.txt" → "bar" / その他はそのまま
  local stem
  stem="${${${src:t}%.*}%-7z_b64}"
  stem="${stem%-7z}"

  local arc="$outdir/${stem}.7z"
  local ext="$outdir/${stem}_extracted"

  info "Base64 デコード → $arc"
  base64 -d -i "$src" -o "$arc"

  info "7z 復号 → $ext"
  mkdir -p "$ext"
  "$SZ" x -p"$pass" -o"$ext" "$arc" -y   # x = フルパス展開（e より推奨）
  rm -f "$arc"

  ok "$ext"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  (( $# >= 2 )) || usage

  local mode="$1"; shift

  # モード別に引数を分割
  # 暗号化: 残りの非オプション引数をすべて入力パスとして収集
  # 復号:   最初の引数のみ入力ファイル
  local -a srcs=()
  local pass="" name="" outdir=""

  case "$mode" in
    e|enc|encrypt)
      # オプション開始前の引数を入力パスとして収集
      while (( $# )) && [[ "$1" != -* ]]; do
        srcs+=("$1"); shift
      done
      (( ${#srcs[@]} >= 1 )) || die "入力ファイル/ディレクトリを1つ以上指定してください"

      # 入力パスの存在チェック
      for s in "${srcs[@]}"; do
        [[ -e "$s" ]] || die "存在しません: $s"
      done

      # 出力先デフォルト = 第1入力の親ディレクトリ
      outdir="${srcs[1]:h}"

      # オプション解析
      while (( $# )); do
        case "$1" in
          -p) pass="$2";   shift 2 ;;
          -n) name="$2";   shift 2 ;;
          -o) outdir="$2"; shift 2 ;;
          *)  die "不明なオプション: $1" ;;
        esac
      done

      # アーカイブ名の自動生成
      if [[ -z "$name" ]]; then
        if (( ${#srcs[@]} == 1 )); then
          # 単一パスの場合はそのベース名を使用
          name="${${srcs[1]:t}%.*}"
        else
          # 複数パスの場合はタイムスタンプ付き汎用名
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
