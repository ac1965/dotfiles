#!/usr/bin/env bash
#
# epub_speak.sh — EPUBを本文順にテキスト抽出し、macOSのsayコマンドで
# 読み上げる（または音声ファイルに書き出す）ためのスクリプト。
#
# 使い方:
#   ./epub_speak.sh book.epub                # そのまま読み上げる
#   ./epub_speak.sh book.epub --save          # book.m4a として保存（再生はしない）
#   ./epub_speak.sh book.epub --voice Otoya   # 声を指定（デフォルト: Kyoko）
#   ./epub_speak.sh book.epub --text-only     # テキスト抽出だけ行い、book.txtを出力
#
# 依存: unzip（標準搭載）, python3（標準搭載）, say（標準搭載）
#
# 仕組み:
#   1. epub（実体はzip）を一時ディレクトリに展開
#   2. META-INF/container.xml から content.opf の場所を特定
#   3. content.opf の <spine> を読み、本文ファイルの「読む順序」を取得
#      （目次のクリック順ではなく実際の読書順）
#   4. 各ファイルのHTMLタグを除去してテキストのみ連結
#   5. say コマンドに渡す（-o 指定時は音声ファイルとして保存）

set -euo pipefail

EPUB=""
VOICE="Kyoko"
SAVE=false
TEXT_ONLY=false
RATE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --save) SAVE=true; shift ;;
    --text-only) TEXT_ONLY=true; shift ;;
    --voice) VOICE="$2"; shift 2 ;;
    --rate) RATE="$2"; shift 2 ;;
    *) EPUB="$1"; shift ;;
  esac
done

if [[ -z "$EPUB" || ! -f "$EPUB" ]]; then
  echo "使い方: $0 <book.epub> [--save] [--text-only] [--voice 声の名前] [--rate 語/分]" >&2
  exit 1
fi

BASENAME="$(basename "$EPUB" .epub)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "epubを展開中..." >&2
unzip -qq -o "$EPUB" -d "$WORKDIR"

# --- content.opf のパスを container.xml から取得 ---
OPF_PATH="$(python3 - "$WORKDIR" <<'PY'
import sys, xml.etree.ElementTree as ET
workdir = sys.argv[1]
tree = ET.parse(f"{workdir}/META-INF/container.xml")
ns = {"c": "urn:oasis:names:tc:opendocument:xmlns:container"}
rootfile = tree.find(".//c:rootfile", ns)
print(rootfile.attrib["full-path"])
PY
)"

OPF_FULL="$WORKDIR/$OPF_PATH"
OPF_DIR="$(dirname "$OPF_FULL")"

echo "読む順序（spine）を解析中..." >&2

# --- spine順にファイル一覧を取得し、テキストを抽出して連結 ---
python3 - "$OPF_FULL" "$OPF_DIR" > "$WORKDIR/$BASENAME.txt" <<'PY'
import sys, re, html
import xml.etree.ElementTree as ET

opf_path, opf_dir = sys.argv[1], sys.argv[2]
tree = ET.parse(opf_path)
root = tree.getroot()

# namespace は epub のバージョンによって多少揺れるので動的に取得
ns_uri = root.tag.split("}")[0].strip("{")
ns = {"opf": ns_uri}

# manifest: id -> href
manifest = {}
for item in root.find("opf:manifest", ns):
    manifest[item.attrib["id"]] = item.attrib["href"]

# spine: 読む順序のidref一覧
spine = root.find("opf:spine", ns)
order = [itemref.attrib["idref"] for itemref in spine]

tag_re = re.compile(r"<[^>]+>")
script_style_re = re.compile(r"<(script|style)[^>]*>.*?</\1>", re.DOTALL | re.IGNORECASE)

for idref in order:
    href = manifest.get(idref)
    if not href:
        continue
    filepath = f"{opf_dir}/{href}"
    try:
        with open(filepath, encoding="utf-8", errors="ignore") as f:
            content = f.read()
    except FileNotFoundError:
        continue

    content = script_style_re.sub(" ", content)
    # ブロック要素の終わりを改行に変換してから残りのタグを除去
    content = re.sub(r"</(p|div|h[1-6]|li|br)\s*>", "\n", content, flags=re.IGNORECASE)
    text = tag_re.sub(" ", content)
    text = html.unescape(text)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n{2,}", "\n\n", text)
    print(text.strip())
    print()  # 章の区切りに空行
PY

WORDCOUNT=$(wc -m < "$WORKDIR/$BASENAME.txt" | tr -d ' ')
echo "テキスト抽出完了（約 ${WORDCOUNT} 文字）" >&2

if $TEXT_ONLY; then
  cp "$WORKDIR/$BASENAME.txt" "./$BASENAME.txt"
  echo "保存しました: ./$BASENAME.txt" >&2
  exit 0
fi

SAY_ARGS=(-v "$VOICE" -f "$WORKDIR/$BASENAME.txt")
if [[ -n "$RATE" ]]; then
  SAY_ARGS+=(-r "$RATE")
fi

if $SAVE; then
  OUTFILE="./$BASENAME.m4a"
  echo "音声ファイルに書き出し中: $OUTFILE" >&2
  say "${SAY_ARGS[@]}" -o "$OUTFILE"
  echo "完了: $OUTFILE" >&2
else
  echo "読み上げを開始します（Ctrl+Cで中断）..." >&2
  say "${SAY_ARGS[@]}"
fi
