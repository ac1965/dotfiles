#!/usr/bin/env python3
"""日本語を含むPDFをテキスト化する単体スクリプト（スキャンPDFは自動でOCR）。

使い方:
  python3 extract_pdf.py INPUT.pdf [-o OUT.txt] [--format txt|md]
        [--layout] [--ocr auto|always|never] [--lang jpn+eng] [--pages 1-5,8]
        [--clean] [--join-lines]

ページごとの処理:
  1. テキスト埋め込みPDFは pdftotext（無ければ pdfplumber、pypdf の順）で抽出する。
  2. 抽出結果が空のページ（スキャン画像）だけを OCR（pdftoppm/pypdfium2 + tesseract）にかける。
     短い見出しだけのページは正しいテキストなので OCR に回さない。
  3. 指定した OCR 言語のデータが1つでも欠けていれば、そのページの OCR はしない。
     日本語ページを英語だけで読むと誤認識の文字列になり、気づきにくいため。

必要なもの: Python 3.8+ と、次のいずれか（あるものを自動で使う）
  pdftotext（poppler） / pdfplumber / pypdf
OCR を使う場合は tesseract（日本語は jpn 言語データ）と pdftoppm か pypdfium2。
  macOS: brew install poppler tesseract tesseract-lang
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unicodedata

CJK = r"぀-ヿ㐀-鿿＀-￯　-〿"
# 条・項・号の先頭（この行頭は改行を残す）
HEAD_RE = re.compile(
    r"^(第[0-9０-９一二三四五六七八九十百]+[章節条項款目]|"
    r"[（(][0-9０-９一二三四五六七八九十ア-ン]+[）)]|"
    r"[0-9０-９]+[\s　.．、]|[①-⑳]|[ア-ン][\s　]|[-・●■□◆◇]\s?)"
)
# 「第１条（目的）」のように見出しだけの行（次の行をつなげない）
TITLE_RE = re.compile(r"^第[0-9０-９一二三四五六七八九十百]+[章節条款目]\s*([（(][^）)]*[）)])?$")


def parse_pages(spec, total):
    if not spec:
        return list(range(1, total + 1))
    pages = set()
    for part in spec.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-", 1)
            pages.update(range(int(a), int(b) + 1))
        elif part:
            pages.add(int(part))
    return sorted(p for p in pages if 1 <= p <= total)


PASSWORD = None  # --password で指定（暗号化PDF用）


def pw_args():
    return ["-upw", PASSWORD] if PASSWORD else []


def page_count(pdf):
    """ページ数。暗号化PDFでも読める poppler の pdfinfo を最優先にする。"""
    if shutil.which("pdfinfo"):
        r = subprocess.run(["pdfinfo"] + pw_args() + [pdf], capture_output=True, text=True)
        m = re.search(r"Pages:\s+(\d+)", r.stdout)
        if m:
            return int(m.group(1))
        if "ncorrect password" in r.stderr:
            sys.exit("パスワードが必要なPDFです。--password パスワード を指定してください。")
    errors = []
    try:
        from pypdf import PdfReader
        rd = PdfReader(pdf)
        if rd.is_encrypted and PASSWORD:
            rd.decrypt(PASSWORD)
        return len(rd.pages)
    except Exception as e:  # ImportError、暗号化に必要な cryptography 未導入など
        errors.append(f"pypdf: {e}")
    try:
        import pdfplumber
        with pdfplumber.open(pdf, password=PASSWORD) as d:
            return len(d.pages)
    except Exception as e:
        errors.append(f"pdfplumber: {e}")
    sys.exit("ページ数を取得できません。\n  " + "\n  ".join(errors) +
             "\n対処: brew install poppler（推奨）、または pip install cryptography")


def extract_text(pdf, n, layout):
    """埋め込みテキストを取り出す。(text, 使ったバックエンド) を返す。"""
    if shutil.which("pdftotext"):
        cmd = ["pdftotext", "-f", str(n), "-l", str(n), "-enc", "UTF-8"] + pw_args()
        if layout:
            cmd.append("-layout")
        r = subprocess.run(cmd + [pdf, "-"], capture_output=True, text=True)
        return r.stdout, "pdftotext"
    try:
        import pdfplumber
        with pdfplumber.open(pdf, password=PASSWORD) as d:
            return (d.pages[n - 1].extract_text(layout=layout) or ""), "pdfplumber"
    except Exception:
        pass
    try:
        from pypdf import PdfReader
        rd = PdfReader(pdf)
        if rd.is_encrypted and PASSWORD:
            rd.decrypt(PASSWORD)
        return (rd.pages[n - 1].extract_text() or ""), "pypdf"
    except Exception:
        sys.exit("テキスト抽出に使えるものがありません。brew install poppler か pip install pdfplumber を実行してください。")


def tesseract_langs():
    if not shutil.which("tesseract"):
        return None
    r = subprocess.run(["tesseract", "--list-langs"], capture_output=True, text=True)
    return set(r.stdout.split()[1:]) if r.returncode == 0 else set()


def render_page(pdf, n, tmp):
    """ページを 300dpi の PNG にして、そのパスを返す。"""
    base = os.path.join(tmp, f"p{n}")
    if shutil.which("pdftoppm"):
        subprocess.run(["pdftoppm", "-f", str(n), "-l", str(n), "-r", "300", "-png"] + pw_args() + [pdf, base],
                       check=True, capture_output=True)
        names = [f for f in os.listdir(tmp) if f.startswith(f"p{n}") and f.endswith(".png")]
        return os.path.join(tmp, sorted(names)[0])
    try:
        import pypdfium2 as pdfium
        img = pdfium.PdfDocument(pdf, password=PASSWORD)[n - 1].render(scale=300 / 72).to_pil()
        path = base + ".png"
        img.save(path)
        return path
    except ImportError:
        return None


def ocr_page(pdf, n, lang, tmp):
    img = render_page(pdf, n, tmp)
    if img is None:
        return None
    r = subprocess.run(["tesseract", img, "-", "-l", lang, "--psm", "6"],
                       capture_output=True, text=True)
    os.remove(img)
    return r.stdout


def clean_text(t, join_lines=False):
    """日本語向けの整形。原文の文字は変えず、空白と改行だけを整える。"""
    t = t.replace("\r", "").replace("\x0c", "")
    # 日本語どうしの間に入った不要な半角スペースを除去
    # （項番号の直後の空白は区切りなので残す）
    t = re.sub(rf"(?<=[{CJK}])(?<![0-9０-９])[ \t]+(?=[{CJK}])", "", t)
    t = re.sub(r"[ \t]+$", "", t, flags=re.M)
    if join_lines:
        out = []
        for line in t.split("\n"):
            s = line.strip()
            if not s:
                out.append("")
            elif (out and out[-1] and not HEAD_RE.match(s)
                  and not re.search(r"[。．！？:：]$", out[-1])
                  and not TITLE_RE.match(out[-1])):
                out[-1] += s  # 折り返しで切れた行を前の行につなぐ
            else:
                out.append(s)
        t = "\n".join(out)
    return re.sub(r"\n{3,}", "\n\n", t).strip()


def main():
    ap = argparse.ArgumentParser(description="日本語PDFをテキスト化（スキャンは自動OCR）")
    ap.add_argument("pdf")
    ap.add_argument("-o", "--output", help="出力先（省略時は標準出力）")
    ap.add_argument("--format", choices=["txt", "md"], default="txt")
    ap.add_argument("--layout", action="store_true", help="段組み・表の位置関係を保つ")
    ap.add_argument("--ocr", choices=["auto", "always", "never"], default="auto")
    ap.add_argument("--lang", default="jpn+eng", help="OCR言語（既定: jpn+eng）")
    ap.add_argument("--pages", help="例: 1-5,8")
    ap.add_argument("--password", help="PDFのパスワード（閲覧に必要な場合のみ）")
    ap.add_argument("--clean", action="store_true", help="日本語間の不要な空白を除去")
    ap.add_argument("--join-lines", action="store_true",
                    help="折り返しで切れた行をつなぐ（条・項・号の行頭は改行を残す）。--clean を含む")
    ap.add_argument("--min-chars", type=int, default=1,
                    help="これ未満の文字数のページだけ画像ページとみなす（既定: 1＝完全に空のときのみ）")
    a = ap.parse_args()

    global PASSWORD
    PASSWORD = a.password
    if not os.path.isfile(a.pdf):
        sys.exit(f"ファイルが見つかりません: {a.pdf}")
    total = page_count(a.pdf)
    pages = parse_pages(a.pages, total)
    do_clean = a.clean or a.join_lines

    langs_have = tesseract_langs() if a.ocr != "never" else None
    want = a.lang.split("+")
    missing = [l for l in want if langs_have is not None and l not in langs_have]

    out, report = [], []
    tmp = tempfile.mkdtemp()
    try:
        for n in pages:
            method, txt = "text", ""
            if a.ocr != "always":
                txt, method = extract_text(a.pdf, n, a.layout)
            need_ocr = a.ocr == "always" or len(txt.strip()) < a.min_chars
            if need_ocr and a.ocr != "never":
                if langs_have is None:
                    report.append(f"p{n}: 画像ページの可能性。tesseract が無いため OCR できません")
                elif missing:
                    report.append(f"p{n}: 画像ページの可能性。OCR言語データ {'+'.join(missing)} が未導入のため OCR しません")
                else:
                    res = ocr_page(a.pdf, n, a.lang, tmp)
                    if res is None:
                        report.append(f"p{n}: ページ画像化に失敗（pdftoppm か pypdfium2 が必要）")
                    else:
                        txt, method = res, "ocr"
            txt = clean_text(txt, a.join_lines) if do_clean else re.sub(r"\n{3,}", "\n\n", txt.replace("\x0c", "")).strip()
            report.append(f"p{n}: {method}, {len(txt)}文字")
            out.append((n, txt))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if a.format == "md":
        body = "\n\n".join(f"<!-- page {n} -->\n\n{t}" for n, t in out)
    else:
        body = "\n\n".join(f"===== Page {n} =====\n{t}" for n, t in out)
    body = unicodedata.normalize("NFC", body)

    if a.output:
        with open(a.output, "w", encoding="utf-8") as f:
            f.write(body + "\n")
    else:
        sys.stdout.write(body + "\n")

    print("\n".join(report), file=sys.stderr)
    ocr_pages = [n for n, _ in out if any(r.startswith(f"p{n}: ocr,") for r in report)]
    if ocr_pages:
        print(f"注意: OCR で読み取ったページ {ocr_pages} は誤認識が混じる可能性があります。原本と照合してください。", file=sys.stderr)
    empty = [n for n, t in out if not t]
    if empty:
        print(f"WARNING: テキストを取得できなかったページ: {empty}", file=sys.stderr)


if __name__ == "__main__":
    main()
