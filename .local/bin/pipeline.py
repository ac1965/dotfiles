#!/usr/bin/env python3
"""キャプチャ画像(PNG) または PDF → 編集できるWord / PowerPoint + Excel を作るパイプライン。

流れ:
  入力がPDFの場合(複数プロセスで並列):
    ページに文字データがある → pdfplumber で文字と表を直接抽出(OCRなし・誤読なし)
    文字データがない         → ページを画像にして、下の画像の流れへ
  入力がPNGフォルダの場合(または上記の画像ページ):
    1. Pillow    : ツールバー・タスクバーを切り取る(PNGフォルダのみ)
    2. Vision    : macOS の Vision で日本語OCR(ocr.swift)
    3. LLM       : 画像とOCR結果を見比べて校正し、本文/表/図に分類してJSON化
                   --llm claude(既定) / --llm ollama [--model <モデル名>] / --no-llm(省略)
       2と3は数枚ずつの塊にして並列実行し、OCRとLLMの待ち時間を重ねる
  共通:
    4. docx-js / pptxgenjs: Claude の docx・pptx スキルの手順でWord・PowerPointを作り、validate.py で検査
    5. openpyxl  : 表シート・機器一覧・接続一覧・元画像シート

使い方:
  python3 pipeline.py --input ../capture --out ../out                       # Claude(既定)
  python3 pipeline.py --input rmf.pdf --out ../out --pages 1-9              # PDF
  python3 pipeline.py --input rmf.pdf --out ../out --llm ollama             # ollama list から選ぶ
  python3 pipeline.py --input rmf.pdf --out ../out --llm ollama --model qwen2.5vl:7b
  python3 pipeline.py --input rmf.pdf --out ../out --no-llm                 # LLMなし
  python3 pipeline.py --input ../capture --out ../out --format pptx         # PowerPoint(PPTX)で出力
  python3 pipeline.py --input rmf.pdf --out ../out --ocr-pages 20-25        # 図のあるページを画像として読む
  python3 pipeline.py --input rmf.pdf --out ../out --pdf-jobs 8 --workers 6 # 並列数を増やす

外部への送信:
  --llm claude : 画像とOCR結果が Anthropic の API に送られます。
  --llm ollama : ollama を動かしているマシンにだけ送られます(既定は localhost = この Mac の中)。
  --no-llm     : どこにも送られません。
  区分付き(部内限り等)の資料は、所属先の規則を確認してから使ってください。
"""
from __future__ import annotations

import argparse
import base64
import concurrent.futures as cf
import contextlib
import glob
import hashlib
import io
import json
import math
import os
import re
import subprocess
import sys
import threading
import time
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

from PIL import Image

HERE = Path(__file__).resolve().parent
DEFAULT_CLAUDE_MODEL = "claude-sonnet-5-5"
DEFAULT_OLLAMA_HOST = "http://localhost:11434"
PROMPT_VERSION = "v3"  # プロンプトや後処理を変えたら上げる(キャッシュを使い回さないため)
CPU = os.cpu_count() or 1

PROMPT = """あなたは日本語文書の校正者です。画像は、PDFビューアの画面を撮ったキャプチャ(1ページ分)です。
OCR結果は誤認識を含みます。必ず画像を正として、OCR結果を校正してください。

守ること:
- 画面の部品(メニュー、ツールバー、ページ番号、スクロールバー等)は無視し、文書の中身だけを扱う。
- 読めない文字は推測で埋めず「[判読不能]」と書く。ページ全体が小さすぎて読めない場合は kind を "unreadable" にする。
- 数字・日付・型番は特に慎重に確認する。自信がない箇所は uncertain に「ページ内の位置と理由」を書く。
- 全角/半角、句読点は原本どおりにする。行の折り返しは直して、1つの文を1つの段落にする。
- 前ページから文が続く場合、先頭の段落はそのまま書く(つなぎはプログラムが行う)。

次のJSONだけを返してください(説明文やコードフェンスは不要)。
{
  "kind": "body | table | diagram | unreadable",
  "paragraphs": ["段落1", "段落2"],
  "tables": [{"title": "表の題名(なければ空)", "rows": [["見出し1", "見出し2"], ["セル", "セル"]]}],
  "devices": [{"name": "機器名", "type": "種別", "location": "設置場所", "count": "台数", "note": "備考"}],
  "links":   [{"from": "接続元", "to": "接続先", "type": "回線種別(10Gb/1Gb/FC等)", "note": "備考"}],
  "uncertain": ["要確認の箇所と理由"]
}
- paragraphs は、見出しも1段落として含める(例: "4.2.1　業務実施計画書の作成")。表の中の文字は paragraphs に入れず tables に入れる。
- ネットワーク図・構成図は devices と links に書き出す(線の色や凡例から回線種別を判断する)。
- 該当しない項目は空の配列にする。

OCR結果:
"""


# ======================================================================
# 共通ユーティリティ
# ======================================================================
def log(msg):
    print(msg, flush=True)


TIMES: list[tuple[str, float]] = []


@contextlib.contextmanager
def stage(label):
    """段階の見出しを出し、処理時間を記録する"""
    log(label)
    t = time.perf_counter()
    try:
        yield
    finally:
        TIMES.append((label, time.perf_counter() - t))


def sha1_file(p):
    return hashlib.sha1(Path(p).read_bytes()).hexdigest()


def safe_name(s):
    """モデル名(例: qwen2.5vl:7b)をファイル名に使える形にする"""
    return re.sub(r"[^A-Za-z0-9._-]", "_", s)


def parse_range(s, total):
    if not s:
        return range(1, total + 1)
    a, _, b = s.partition("-")
    return range(int(a), int(b or a) + 1)


def atomic_write(path, text):
    """途中で止まっても壊れたファイルを残さない"""
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


@dataclass
class Page:
    name: str
    path: Path | None = None   # 画像ページのときの画像
    res: dict | None = None    # PDFの文字データから抽出済みのとき


# ---------- 見出し・段落の判定(Wordの見出し化、ページ間のつなぎ、PDF抽出で共通利用) ----------
HEAD_RE = re.compile(r"^(\d+(?:[.．]\d+)*)[.．]?\s*[　 ]\S")
MARK_RE = re.compile(r"^([a-z]\)|[0-9０-９]+\)|[（(][0-9０-９]+[)）]|[ア-ン]　|[・●○■])")


def is_heading(t):
    return bool(HEAD_RE.match(t)) and len(t) < 45 and "。" not in t


def starts_new(t):
    return is_heading(t) or bool(MARK_RE.match(t)) or t.startswith(("表", "付図", "付表", "注", "（"))


def norm(t):
    return re.sub(r"\s+", "", t)


def tidy_jp(t):
    """日本語の間の余計な空白を除く(PDF抽出で入ることがある)"""
    return re.sub(r"(?<=[^\x00-\x7f]) +| +(?=[^\x00-\x7f])", "", t).strip()


# ---------- 画像の加工 ----------
def thumb_path(src, thumb_dir, max_w):
    """Word/Excelに埋め込む縮小画像。元画像のままだと文書が重くなるため"""
    thumb_dir.mkdir(parents=True, exist_ok=True)
    src = Path(src)
    dst = thumb_dir / f"{src.stem}_{max_w}.png"
    if not dst.exists() or dst.stat().st_mtime < src.stat().st_mtime:
        im = Image.open(src)
        if im.width > max_w:
            im = im.resize((max_w, round(im.height * max_w / im.width)), Image.Resampling.LANCZOS)
        im.save(dst, optimize=True)
    return dst


def llm_image_b64(path, max_edge):
    """LLMに送る画像。長辺が max_edge を超えるときは縮小する(0なら縮小しない)"""
    im = Image.open(path)
    if max_edge and max(im.size) > max_edge:
        s = max_edge / max(im.size)
        im = im.resize((round(im.width * s), round(im.height * s)), Image.Resampling.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "PNG")
        data = buf.getvalue()
    else:
        data = Path(path).read_bytes()
    return base64.b64encode(data).decode()


# ======================================================================
# 1. 入力の準備
# ======================================================================
def scaled_box(size, box):
    """既定の切り取り範囲は 1920x1080 の画面が前提。画像サイズに合わせて拡縮する"""
    w, h = size
    sx, sy = w / 1920, h / 1080
    l, t, r, b = box
    return (int(l * sx), int(t * sy), int(r * sx), int(b * sy))


def load_png_dir(a, work):
    files = sorted(glob.glob(os.path.join(a.input, "*.png")))
    if not files:
        sys.exit("PNG画像が見つかりません")
    files = [files[i - 1] for i in parse_range(a.pages, len(files)) if 1 <= i <= len(files)]
    box = tuple(int(x) for x in a.crop.split(","))
    out_dir = work / "cropped"
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp_file = out_dir / ".stamp.json"
    stamps = json.loads(stamp_file.read_text()) if stamp_file.exists() else {}
    pages = []
    for f in files:
        f = Path(f)
        dst = out_dir / f.name
        st = f.stat()
        key = f"{st.st_size}-{int(st.st_mtime)}-{box}"  # 元画像や --crop が変われば作り直す
        if not dst.exists() or stamps.get(f.name) != key:
            im = Image.open(f).convert("RGB")
            im.crop(scaled_box(im.size, box)).save(dst)
            stamps[f.name] = key
        pages.append(Page(dst.name, dst))
    stamp_file.write_text(json.dumps(stamps))
    return pages


def extract_pdf_text_page(page):
    """文字データがあるPDFページから、本文と表を位置順に取り出す(OCRなし)"""
    pos = []
    rest = page
    for t in page.find_tables():
        rows = [[(c or "").replace("\n", "") for c in r] for r in t.extract()]
        rows = [r for r in rows if any(c.strip() for c in r)]
        if rows:
            pos.append((t.bbox[1], {"type": "table", "table": {"title": "", "rows": rows}}))
        rest = rest.outside_bbox(t.bbox)

    buf, prev, buf_top = "", None, 0
    for ln in rest.extract_text_lines():
        text = tidy_jp(ln["text"])
        if not text:
            continue
        gap = ln["top"] - prev["bottom"] if prev else 999
        if buf and (gap > 4 or buf.endswith(("。", "：")) or is_heading(buf) or starts_new(text)):
            pos.append((buf_top, {"type": "p", "text": buf}))
            buf = ""
        if not buf:
            buf_top = ln["top"]
        buf += text
        prev = ln
    if buf:
        pos.append((buf_top, {"type": "p", "text": buf}))

    items = [it for _, it in sorted(pos, key=lambda x: x[0])]
    return {
        "kind": "body",
        "paragraphs": [i["text"] for i in items if i["type"] == "p"],
        "tables": [i["table"] for i in items if i["type"] == "table"],
        "items": items, "devices": [], "links": [], "uncertain": [],
        "quality": 1.0, "source": "pdf-text",
    }


def pdf_worker(job):
    """別プロセスで実行する。PDFを自分で開き、担当ページの抽出または画像化を行う"""
    src, nums, text_min, force, scale, img_dir = job
    import pdfplumber
    import pypdfium2 as pdfium

    out, pdfi = [], None
    with pdfplumber.open(src) as pdf:
        for n in nums:
            page = pdf.pages[n - 1]
            nchar = sum(1 for c in page.chars if c["text"].strip())  # 全文抽出より軽い
            if nchar >= text_min and n not in force:
                out.append((n, f"p{n:04d}.png", None, extract_pdf_text_page(page)))
            else:
                dst = Path(img_dir) / f"p{n:04d}.png"
                if not dst.exists():
                    pdfi = pdfi or pdfium.PdfDocument(str(src))
                    pdfi[n - 1].render(scale=scale).to_pil().convert("RGB").save(dst)
                out.append((n, dst.name, str(dst), None))
            if hasattr(page, "flush_cache"):
                page.flush_cache()  # メモリを溜めない
    return out


def load_pdf(a, work, force):
    try:
        import pdfplumber  # noqa: F401  ワーカーで使う。ここでは存在確認のみ
        import pypdfium2 as pdfium
    except ImportError:
        sys.exit("PDF入力には pip install pdfplumber pypdfium2 が必要です")
    src = Path(a.input)
    img_dir = work / "pdf_pages"
    img_dir.mkdir(parents=True, exist_ok=True)
    stamp = f"{src.stat().st_size}-{int(src.stat().st_mtime)}-{a.pdf_scale}"
    stamp_file = img_dir / ".stamp"
    if not stamp_file.exists() or stamp_file.read_text() != stamp:  # PDFが変われば画像を作り直す
        for f in img_dir.glob("*.png"):
            f.unlink()
        stamp_file.write_text(stamp)

    total = len(pdfium.PdfDocument(str(src)))
    nums = [n for n in parse_range(a.pages, total) if 1 <= n <= total]
    if not nums:
        return []
    jobs = max(1, a.pdf_jobs)
    size = max(4, math.ceil(len(nums) / (jobs * 4)))
    chunks = [(str(src), nums[i:i + size], a.text_min, force, a.pdf_scale, str(img_dir))
              for i in range(0, len(nums), size)]
    if jobs == 1 or len(chunks) == 1:
        results = [pdf_worker(c) for c in chunks]
    else:
        with cf.ProcessPoolExecutor(max_workers=jobs) as ex:
            results = list(ex.map(pdf_worker, chunks))

    pages = []
    for part in results:
        for n, name, path, res in part:
            pages.append(Page(name, Path(path) if path else None, res))
            log(f"  p.{n}: " + ("文字データから直接抽出" if res else
                               "画像としてOCR(指定)" if n in force else "画像としてOCR(文字データなし)"))
    return pages


# ======================================================================
# 2. OCR(macOS Vision)
# ======================================================================
class OcrStore:
    """画像の内容ハッシュでキャッシュするOCR。スレッドセーフ。
    画像を差し替えても古い結果は使わず、塊が終わるたびに保存するので、途中で止めても再開できる"""

    def __init__(self, work):
        if sys.platform != "darwin":
            sys.exit("Vision OCR は macOS でのみ動作します")
        self.work = work
        self.file = work / "ocr_cache.json"
        self.cache = json.loads(self.file.read_text()) if self.file.exists() else {}
        self.lock = threading.Lock()
        self._bin = None

    def _binary(self):
        with self.lock:
            if self._bin is None:
                binary, src = self.work / "ocr_bin", HERE / "ocr.swift"
                if not binary.exists() or binary.stat().st_mtime < src.stat().st_mtime:
                    log("OCRプログラムをコンパイルしています…")
                    subprocess.run(["swiftc", "-O", str(src), "-o", str(binary)], check=True)
                self._bin = binary
            return self._bin

    def ensure(self, paths):
        """paths のOCR結果を揃えて ({名前: 行のリスト}, {名前: ハッシュ}) を返す"""
        hashes = {Path(p).name: sha1_file(p) for p in paths}
        with self.lock:
            todo = [p for p in paths if hashes[Path(p).name] not in self.cache]
        if todo:
            res = subprocess.run([str(self._binary())] + [str(p) for p in todo],
                                 capture_output=True, check=True)
            data = json.loads(res.stdout)
            with self.lock:
                for d in data:
                    self.cache[hashes[d["f"]]] = d["lines"]
                atomic_write(self.file, json.dumps(self.cache, ensure_ascii=False))
        with self.lock:
            return {n: self.cache.get(h, []) for n, h in hashes.items()}, hashes


def ocr_text(lines):
    rows = sorted(lines, key=lambda l: (round(l["y"] * 200), l["x"]))
    return "\n".join(l["t"] for l in rows)


def ocr_quality(lines):
    """OCRの信頼度(文字数で重み付けした平均)。小さすぎる文字は低くなる。"""
    n = sum(len(l["t"]) for l in lines)
    if n == 0:
        return 0.0
    return sum(l["c"] * len(l["t"]) for l in lines) / n


def ocr_only_result(lines):
    ordered = sorted(lines, key=lambda l: (l["y"], l["x"]))
    return {"kind": "body", "paragraphs": [l["t"] for l in ordered],
            "tables": [], "devices": [], "links": [], "uncertain": []}


# ======================================================================
# 3. LLM による校正・分類(claude / ollama)
# ======================================================================
def extract_json(text):
    text = text.strip()
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text)
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        m = re.search(r"\{.*\}", text, re.S)
        if m:
            return json.loads(m.group(0))
        raise


def sanitize(res):
    """LLMの出力の形を整える(小さなモデルは、キーの欠けや型の崩れが起きやすいため)"""
    if not isinstance(res, dict):
        res = {}

    def lst(k):
        v = res.get(k)
        return v if isinstance(v, list) else []

    res["paragraphs"] = [str(p) for p in lst("paragraphs") if p not in (None, "")]
    tables = []
    for t in lst("tables"):
        if isinstance(t, dict) and isinstance(t.get("rows"), list):
            rows = [[str(c) for c in r] for r in t["rows"] if isinstance(r, list)]
            if rows:
                tables.append({"title": str(t.get("title") or ""), "rows": rows})
    res["tables"] = tables
    res["devices"] = [d for d in lst("devices") if isinstance(d, dict)]
    res["links"] = [l for l in lst("links") if isinstance(l, dict)]
    res["uncertain"] = [str(u) for u in lst("uncertain")]
    if res.get("kind") not in ("body", "table", "diagram", "unreadable"):
        res["kind"] = "body"
    return res


class ClaudeBackend:
    name = "claude"
    default_edge = 1568  # これより大きい画像はサーバー側で縮小されるため、先に縮小して送信量を減らす

    def __init__(self, model):
        if not os.environ.get("ANTHROPIC_API_KEY"):
            sys.exit("ANTHROPIC_API_KEY が未設定です(ローカルなら --llm ollama、LLMなしなら --no-llm)")
        try:
            import anthropic
        except ImportError:
            sys.exit("pip install anthropic が必要です(LLMなしなら --no-llm、ローカルなら --llm ollama)")
        self.model = model
        self.client = anthropic.Anthropic()  # ANTHROPIC_API_KEY を環境変数から読む
        self.sent = "画像とOCR結果を Anthropic の API に送信"

    def complete(self, b64, text):
        msg = self.client.messages.create(
            model=self.model, max_tokens=16000,
            messages=[{"role": "user", "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": b64}},
                {"type": "text", "text": PROMPT + text},
            ]}],
        )
        return "".join(b.text for b in msg.content if b.type == "text")


def ollama_request(host, path, body=None, timeout=10):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(host.rstrip("/") + path, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


class OllamaBackend:
    name = "ollama"
    default_edge = 0  # ローカルは送信コストがないため、既定では縮小しない

    def __init__(self, host, model, ctx):
        self.host, self.model, self.ctx = host, model, ctx
        self.sent = f"画像とOCR結果を ollama({host})に送信"

    def complete(self, b64, text):
        body = {
            "model": self.model, "stream": False, "format": "json",
            "options": {"temperature": 0, "num_ctx": self.ctx},
            "messages": [{"role": "user", "content": PROMPT + text, "images": [b64]}],
        }
        data = ollama_request(self.host, "/api/chat", body, timeout=900)  # ローカルLLMは遅いので長めに待つ
        return data["message"]["content"]


def ask(backend, b64, text, tries=3):
    last = None
    for i in range(tries):
        try:
            return extract_json(backend.complete(b64, text))
        except Exception as e:  # 通信エラー・JSON崩れは再試行
            last = e
            if i < tries - 1:
                time.sleep(2 * (i + 1))
    raise RuntimeError(f"{backend.name} の呼び出しに失敗: {last}")


# --- ollama のモデル選択 ---
def warn_if_remote(host):
    host_name = urlparse(host).hostname or ""
    if host_name not in ("localhost", "127.0.0.1", "::1"):
        log(f"  注意: ollama の接続先が {host_name} です(この Mac の外へ画像を送ります)")


def list_ollama_models(host):
    """ollama list と同じ内容(インストール済みモデル名)を返す"""
    try:
        data = ollama_request(host, "/api/tags")
    except Exception as e:
        sys.exit(f"ollama に接続できません({host}): {e}\n  ollama serve で起動しているか確認してください")
    return [m["name"] for m in data.get("models", []) if m.get("name")]


def ollama_has_vision(host, name):
    """画像に対応しているか。True / False / None(不明。古い ollama では取れない)"""
    try:
        caps = ollama_request(host, "/api/show", {"model": name}).get("capabilities")
    except Exception:
        return None
    return ("vision" in caps) if isinstance(caps, list) else None


def choose_ollama_model(host):
    """--model が未指定のとき、ollama list の一覧から対話で選ぶ"""
    names = list_ollama_models(host)
    if not names:
        sys.exit("ollama にモデルが入っていません。例: ollama pull qwen2.5vl:7b")
    caps = {n: ollama_has_vision(host, n) for n in names}
    label = {True: "[画像対応]", False: "[画像非対応]", None: "[画像対応は不明]"}
    default = next((n for n in names if caps[n] is True), names[0])

    if not sys.stdin.isatty():  # 対話できない環境(cron・パイプ等)
        listing = "\n".join(f"  - {n} {label[caps[n]]}" for n in names)
        sys.exit("--model が未指定で、対話もできません。--model で指定してください。\n"
                 f"入っているモデル:\n{listing}")

    print(f"\nollama のモデルを選んでください(接続先: {host})")
    for i, n in enumerate(names, 1):
        print(f"  {i}) {n:<28} {label[caps[n]]}" + ("  ← 既定" if n == default else ""))
    while True:
        ans = input(f"番号またはモデル名(Enter で {names.index(default) + 1}): ").strip()
        if not ans:
            pick = default
        elif ans.isdigit() and 1 <= int(ans) <= len(names):
            pick = names[int(ans) - 1]
        elif ans in names:
            pick = ans
        else:
            print("  一覧にない入力です。もう一度入力してください。")
            continue
        if caps[pick] is False:
            if input("  このモデルは画像に対応していません(OCRの結果だけで校正するため効果が下がります)。"
                     "それでも使いますか? [y/N]: ").strip().lower() != "y":
                continue
        print(f"  → {pick} を使います\n")
        return pick


def make_backend(a, need):
    """画像ページがあり、LLMを使う設定のときだけバックエンドを作る"""
    if a.no_llm or not need:
        return None
    if a.llm == "claude":
        return ClaudeBackend(a.model or DEFAULT_CLAUDE_MODEL)
    warn_if_remote(a.ollama_host)
    model = a.model or choose_ollama_model(a.ollama_host)
    names = list_ollama_models(a.ollama_host)
    if model not in names and f"{model}:latest" not in names:
        sys.exit(f"ollama にモデル '{model}' がありません。\n  ollama pull {model}\n"
                 f"  入っているモデル: {', '.join(names) or '(なし)'}")
    return OllamaBackend(a.ollama_host, model, a.ollama_ctx)


class Analyzer:
    """1ページ分のOCR結果(とLLM)から、本文・表・図の構造を作る"""

    def __init__(self, backend, work, max_edge, min_quality):
        self.backend = backend
        self.max_edge = max_edge
        self.min_quality = min_quality
        self.dir = work / "llm"
        self.dir.mkdir(parents=True, exist_ok=True)

    def run(self, page, lines, h):
        b = self.backend
        q = ocr_quality(lines)
        res = None
        if b:
            cache = self.dir / f"{h}_{b.name}_{safe_name(b.model)}_{PROMPT_VERSION}_e{self.max_edge}.json"
            if cache.exists():
                try:
                    res = json.loads(cache.read_text(encoding="utf-8"))
                except json.JSONDecodeError:
                    res = None
            if res is None:
                try:
                    res = ask(b, llm_image_b64(page.path, self.max_edge), ocr_text(lines))
                    atomic_write(cache, json.dumps(res, ensure_ascii=False))
                except Exception as ex:  # 1ページの失敗で全体を止めない
                    res = ocr_only_result(lines)
                    res["uncertain"] = [f"LLMでの校正に失敗したため、OCR結果のままです({ex})"]
        else:
            res = ocr_only_result(lines)
        res = sanitize(res)
        res["quality"] = q
        text_all = "".join(res["paragraphs"])
        if (res["kind"] == "unreadable"
                or (not b and q < self.min_quality)
                or (b and not text_all and not res["tables"] and not res["devices"])):
            res["kind"] = "unreadable"
        res["items"] = ([{"type": "p", "text": p} for p in res["paragraphs"]]  # 位置情報がないので「段落 → 表」の順
                        + [{"type": "table", "table": t} for t in res["tables"]])
        return res


def analyze_all(pages, work, backend, a, max_edge, workers):
    """画像ページを数枚ずつの塊にし、塊ごとに『OCR → LLM』を並列で実行する(OCRとLLMの待ちが重なる)"""
    result = {p.name: p.res for p in pages if p.res is not None}
    todo = [p for p in pages if p.res is None]
    if todo:
        store = OcrStore(work)
        analyzer = Analyzer(backend, work, max_edge, a.min_quality)
        chunks = [todo[i:i + a.chunk] for i in range(0, len(todo), a.chunk)]

        def task(chunk):
            ocr, hashes = store.ensure([p.path for p in chunk])
            return [(p.name, analyzer.run(p, ocr[p.name], hashes[p.name])) for p in chunk]

        done = 0
        with cf.ThreadPoolExecutor(max_workers=workers) as ex:
            for f in cf.as_completed([ex.submit(task, c) for c in chunks]):
                for name, res in f.result():
                    result[name] = res
                    done += 1
                    log(f"  [{done}/{len(todo)}] {name}: {res['kind']} (OCR信頼度 {res['quality']:.2f})")
    return {p.name: result[p.name] for p in pages}


# ======================================================================
# ページ間の処理(重複除去・文のつなぎ)
# ======================================================================
def ikey(it):
    if it["type"] == "p":
        return norm(it["text"])
    rows = it["table"].get("rows") or []
    return "T" + norm("".join("".join(str(c) for c in r) for r in rows))


def leading_overlap(pk, ck):
    """前ページの末尾と今ページの先頭が、連続して同じ内容の項目数(スクロールの重なり)"""
    for k in range(min(len(pk), len(ck), 30), 0, -1):
        if pk[-k:] == ck[:k] and sum(len(x) for x in ck[:k]) >= 12:
            return k
    return 0


def merge_pages(order, pages, marks):
    """重複ページの除去、スクロールの重なりの除去(段落・表)、ページをまたぐ文のつなぎ"""
    merged, dup_pages, removed, joins = [], [], [], 0
    prev_keys, prev_sig = [], None
    for name in order:
        res = pages[name]
        items = res["items"]
        keys = [ikey(i) for i in items]  # ページごとに1回だけ計算
        sig = hashlib.md5("|".join(keys).encode()).hexdigest()
        if items and sig == prev_sig:  # 直前ページと同じ内容 → 重複画像
            dup_pages.append(name)
            continue
        k = leading_overlap(prev_keys, keys)  # 先頭の連続した重なりだけを除く
        removed += [(name, key[:40]) for key in keys[:k]]
        cur = items[k:]
        prev_keys, prev_sig = keys, sig

        if merged and merged[-1]["type"] == "p" and cur and cur[0]["type"] == "p":
            x, y = merged[-1]["text"], cur[0]["text"]
            if (len(x) >= 30 and not is_heading(x)
                    and not x.endswith(("。", "」", "）", "：", ")")) and not starts_new(y)):
                merged[-1]["text"] = x + y
                cur = cur[1:]
                joins += 1
        is_image = res["kind"] in ("diagram", "unreadable")
        if marks and (cur or is_image):
            merged.append({"type": "mark", "page": name})
        for it in cur:
            merged.append({**it, "page": name})
        if is_image:
            merged.append({"type": "image", "page": name, "kind": res["kind"]})
    return merged, dup_pages, joins, removed


# ======================================================================
# 4. Word / PowerPoint(Claude の docx / pptx スキルの手順: docx-js・pptxgenjs で作り、validate.py で検査)
# ======================================================================
DEFAULT_SKILLS = Path.home() / ("Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/"
                                "643fadaa-7d99-42ce-a8ef-7ce0875e07e3/9d594516-83a3-46a7-b249-ca0ceef94d65/skills")


def heading_level(t):
    """見出しなら 1〜3(番号の深さ)、本文なら 0"""
    if not is_heading(t):
        return 0
    return min(len(re.findall(r"[.．]", HEAD_RE.match(t).group(1))) + 1, 3)


def export_json(merged, img_of, img_width, note, path):
    """docx-js / pptxgenjs のスクリプトに渡す中間ファイル。画像は縮小版の絶対パスにする"""
    items = []
    for it in merged:
        d = dict(it)
        if it["type"] == "p":
            d["level"] = heading_level(it["text"])
        elif it["type"] == "image":
            d["img"] = str(Path(img_of(it["page"], img_width)).resolve())
        items.append(d)
    path.write_text(json.dumps({"note": note, "items": items}, ensure_ascii=False), encoding="utf-8")


def run_node(script, args, skills):
    """node のスクリプトを実行する。NODE_PATH に作業フォルダの node_modules を足す"""
    env = dict(os.environ, NODE_PATH=os.pathsep.join(
        [str(HERE / "node_modules"), os.environ.get("NODE_PATH", "")]), SKILLS_DIR=str(skills))
    r = subprocess.run(["node", str(HERE / script), *map(str, args)], capture_output=True, text=True, env=env)
    if r.returncode:
        sys.exit(f"{script} が失敗しました:\n{r.stderr or r.stdout}\n"
                 f"  初回は {HERE} で npm install docx pptxgenjs を実行してください")
    return r.stdout.strip()


def validate_office(path, skills):
    """スキル付属の validate.py で検査する。結果の1行を返す(スキルが見つからなければ未検査と返す)"""
    v = Path(skills) / ("pptx" if str(path).endswith(".pptx") else "docx") / "scripts/office/validate.py"
    if not v.exists():
        return "未検査(validate.py が見つかりません)"
    r = subprocess.run([sys.executable, str(v), str(path)], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip().splitlines()
    return ("OK" if r.returncode == 0 else "NG: ") + (out[-1] if out and r.returncode else "")


# ======================================================================
# 5. Excel
# ======================================================================
def build_xlsx(merged, pages, img_of, path):
    from openpyxl import Workbook
    from openpyxl.drawing.image import Image as XImage
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

    wb = Workbook()
    thin = Side(style="thin", color="999999")
    bd = Border(left=thin, right=thin, top=thin, bottom=thin)
    head_fill = PatternFill("solid", fgColor="DDEBF7")

    def write_rows(ws, rows, start=1, header=True):
        for ri, r in enumerate(rows, start):
            for ci, v in enumerate(r, 1):
                c = ws.cell(row=ri, column=ci, value=v)
                c.border = bd; c.alignment = Alignment(wrap_text=True, vertical="top")
                if header and ri == start:
                    c.font = Font(bold=True); c.fill = head_fill
        for ci in range(1, (max(len(r) for r in rows) if rows else 0) + 1):
            width = max((len(str(r[ci - 1])) for r in rows if ci - 1 < len(r)), default=8)
            ws.column_dimensions[ws.cell(row=1, column=ci).column_letter].width = min(max(width * 1.6, 8), 60)

    idx = wb.active
    idx.title = "目次"
    idx_rows = [["シート", "内容", "元ページ"]]

    n = 0
    for it in merged:
        if it["type"] != "table" or not it["table"].get("rows"):
            continue
        n += 1
        ws = wb.create_sheet(f"表{n:02d}")
        title = it["table"].get("title") or ""
        ws["A1"] = title or f"表{n:02d}"; ws["A1"].font = Font(bold=True, size=12)
        write_rows(ws, it["table"]["rows"], start=3)
        idx_rows.append([f"表{n:02d}", title, Path(it["page"]).stem])

    dev_rows = [["No", "機器名", "種別", "設置場所", "台数", "備考", "元ページ"]]
    link_rows = [["No", "接続元", "接続先", "回線種別", "備考", "元ページ"]]
    seen_d, seen_l = set(), set()
    for name, res in pages.items():
        for d in res["devices"]:
            key = (d.get("name"), d.get("location"), d.get("count"))
            if key in seen_d:
                continue
            seen_d.add(key)
            dev_rows.append([len(dev_rows), d.get("name", ""), d.get("type", ""), d.get("location", ""),
                             d.get("count", ""), d.get("note", ""), Path(name).stem])
        for l in res["links"]:
            key = (l.get("from"), l.get("to"), l.get("type"))
            if key in seen_l:
                continue
            seen_l.add(key)
            link_rows.append([len(link_rows), l.get("from", ""), l.get("to", ""), l.get("type", ""),
                              l.get("note", ""), Path(name).stem])
    ws = wb.create_sheet("機器一覧"); write_rows(ws, dev_rows)
    ws = wb.create_sheet("接続一覧"); write_rows(ws, link_rows)
    idx_rows += [["機器一覧", f"{len(dev_rows) - 1}件", ""], ["接続一覧", f"{len(link_rows) - 1}件", ""]]

    ws = wb.create_sheet("元画像")
    row = 1
    for name, res in pages.items():
        if res["kind"] not in ("diagram", "unreadable"):
            continue
        ws.cell(row=row, column=1, value=f"{Path(name).stem}({'図' if res['kind'] == 'diagram' else '判読不能'})").font = Font(bold=True)
        img = XImage(str(img_of(name, 1000)))  # Excel用はさらに小さい画像を埋め込む
        scale = 900 / img.width
        img.width, img.height = int(img.width * scale), int(img.height * scale)
        ws.add_image(img, f"A{row + 1}")
        row += int(img.height / 20) + 3
    idx_rows.append(["元画像", "図・判読不能ページの画像", ""])
    write_rows(idx, idx_rows)
    wb.save(path)
    return n, len(dev_rows) - 1, len(link_rows) - 1


# ======================================================================
# メイン
# ======================================================================
def parse_args():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", required=True, help="PNG画像が入ったフォルダ、または PDFファイル")
    ap.add_argument("--out", required=True, help="出力先フォルダ")
    ap.add_argument("--llm", choices=["claude", "ollama"], default="claude",
                    help="校正・分類に使うLLM。既定は claude。ollama はローカル実行")
    ap.add_argument("--model",
                    help="モデル名。claude は省略可(既定 %s)。ollama は省略すると ollama list から選択" % DEFAULT_CLAUDE_MODEL)
    ap.add_argument("--ollama-host", default=DEFAULT_OLLAMA_HOST, help="ollama の接続先(既定 %s)" % DEFAULT_OLLAMA_HOST)
    ap.add_argument("--ollama-ctx", type=int, default=8192, help="ollama のコンテキスト長(num_ctx)")
    ap.add_argument("--no-llm", action="store_true", help="LLMを使わず、OCRのみで処理する(外部送信なし)")
    ap.add_argument("--crop", default="0,82,1920,1030",
                    help="PNGの切り取り範囲 left,top,right,bottom(1920x1080基準。画像サイズに合わせて自動で拡縮)")
    ap.add_argument("--pages", help="処理する範囲(例: 1-5)。PDFの場合はPDFのページ番号")
    ap.add_argument("--ocr-pages", help="PDFで文字データがあっても画像としてOCRするページ(例: 20-25。図を含むページ用)")
    ap.add_argument("--text-min", type=int, default=30, help="PDFで『文字データあり』とみなす最小文字数(空白を除く)")
    ap.add_argument("--pdf-scale", type=float, default=3.0, help="PDFを画像にするときの倍率")
    ap.add_argument("--pdf-jobs", type=int, default=min(4, CPU), help="PDF処理の並列プロセス数(既定: CPU数、最大4)")
    ap.add_argument("--workers", type=int, help="OCR・LLMの並列数(既定: claude 4、ollama 1、LLMなし CPU数、最大4)")
    ap.add_argument("--chunk", type=int, default=4, help="OCR・LLMを1つの塊として処理するページ数")
    ap.add_argument("--llm-img-max", type=int,
                    help="LLMに送る画像の長辺の上限(px)。0で縮小しない。既定: claude 1568、ollama 0")
    ap.add_argument("--img-width", type=int, default=1600, help="Wordに埋め込む画像の幅(px)")
    ap.add_argument("--min-quality", type=float, default=0.5,
                    help="LLMなしのとき、これ未満を判読不能とみなすOCR信頼度")
    ap.add_argument("--no-marks", action="store_true", help="Wordに元ページの目印を入れない")
    ap.add_argument("--skill-dir", default=os.environ.get("CLAUDE_SKILLS_DIR", str(DEFAULT_SKILLS)),
                    help="Claude の skills フォルダ(pptx/docx スキル。apply_theme.js と validate.py を使う)")
    ap.add_argument("--format", choices=["docx", "pptx", "both"], default="docx",
                    help="文書の出力形式。docx=Word(既定) / pptx=PowerPoint / both=両方。Excelは常に出力")
    return ap.parse_args()


def main():
    a = parse_args()
    inp, out = Path(a.input), Path(a.out)
    work = out / "work"
    work.mkdir(parents=True, exist_ok=True)
    if a.no_llm and a.model:
        log("注意: --no-llm のため --model は使われません")
    t_all = time.perf_counter()

    with stage("1/5 入力の準備"):
        if inp.is_dir():
            pages = load_png_dir(a, work)
        elif inp.suffix.lower() == ".pdf":
            force = set(parse_range(a.ocr_pages, 0)) if a.ocr_pages else set()
            pages = load_pdf(a, work, force)
        else:
            sys.exit("--input は PNGフォルダ か PDFファイル を指定してください")
        if not pages:
            sys.exit("処理するページがありません")
    image_pages = [p for p in pages if p.path]

    backend = make_backend(a, need=bool(image_pages))  # 対話のモデル選択があるため、段階の計測の外で行う
    if backend:
        workers = a.workers or (4 if backend.name == "claude" else 1)
        llm_label = f"{backend.name}:{backend.model}"
        sent = backend.sent
    else:
        workers = a.workers or min(4, CPU)
        llm_label = "なし(OCRのみ)" if a.no_llm else "未使用(画像ページなし)"
        sent = "外部送信なし"
    max_edge = a.llm_img_max if a.llm_img_max is not None else (backend.default_edge if backend else 0)

    with stage(f"2/5 OCR・校正(画像ページ {len(image_pages)}枚 / 並列 {workers} / {llm_label})"):
        analyzed = analyze_all(pages, work, backend, a, max_edge, workers)

    with stage("3/5 ページの結合"):
        order = [p.name for p in pages]
        paths = {p.name: p.path for p in image_pages}
        merged, dups, joins, removed = merge_pages(order, analyzed, marks=not a.no_marks)
        thumbs = work / "thumbs"
        img_of = lambda name, w: thumb_path(paths[name], thumbs, w)  # noqa: E731

    unreadable = [n for n in order if analyzed[n]["kind"] == "unreadable"]
    n_text = sum(1 for n in order if analyzed[n].get("source") == "pdf-text")
    note = (f"※ 本書は{'PDF' if inp.suffix.lower() == '.pdf' else '画面キャプチャ'}{len(pages)}ページから自動で文字起こしし、"
            f"{'画像ページは ' + llm_label + ' で校正したものです' if backend else '画像ページはOCRの結果です(校正なし)'}。"
            f"判読不能のページ({len(unreadable)}枚)は画像のまま掲載しています。数値・日付・型番は原本で確認してください。")

    outputs = []
    skills = Path(a.skill_dir).expanduser()
    with stage(f"4/5 文書作成({a.format})"):
        data = work / "merged.json"
        export_json(merged, img_of, a.img_width, note, data)
        for fmt, script, name, label in (("docx", "build_docx.js", "capture_editable.docx", "Word"),
                                         ("pptx", "build_pptx.js", "capture_editable.pptx", "PowerPoint")):
            if a.format in (fmt, "both"):
                dst = out / name
                run_node(script, [data, dst], skills)
                outputs.append(f"- {label}: {dst}(validate.py: {validate_office(dst, skills)})")
    with stage("5/5 Excel作成"):
        xlsx_path = out / "capture_tables.xlsx"
        n_tables, n_dev, n_link = build_xlsx(merged, analyzed, img_of, xlsx_path)

    lines = ["# 実行結果", "",
             f"- LLM: {llm_label}({sent}。PDFの文字ページは送信なし)",
             f"- 処理したページ数: {len(pages)}"
             f"(PDFの文字データから直接抽出: {n_text}、画像としてOCR: {len(image_pages)})",
             f"- 重複で除外したページ: {len(dups)}、スクロールの重なりで除いた段落・表: {len(removed)}、"
             f"ページ間でつないだ文: {joins}",
             f"- 判読不能(画像のまま): {len(unreadable)}",
             f"- Excel: 表 {n_tables}、機器 {n_dev}、接続 {n_link}",
             *outputs, f"- Excel: {xlsx_path}", ""]
    if dups:
        lines += ["## 重複として除外したページ", *[f"- {n}" for n in dups], ""]
    if removed:
        lines += ["## 重なりとして除いた項目(正当な繰り返しを消していないか確認)",
                  *[f"- {Path(n).stem}: {t}" for n, t in removed], ""]
    if unreadable:
        lines += ["## 判読不能のページ(画像のまま残した)",
                  *[f"- {Path(n).stem}(OCR信頼度 {analyzed[n]['quality']:.2f})" for n in unreadable], ""]
    unc = [(n, u) for n in order for u in analyzed[n]["uncertain"]]
    if unc:
        lines += ["## 要確認の箇所", *[f"- {Path(n).stem}: {u}" for n, u in unc], ""]
    lines += ["## 処理時間",
              *[f"- {label}: {sec:.1f}秒" for label, sec in TIMES],
              f"- 合計: {time.perf_counter() - t_all:.1f}秒", ""]
    report = "\n".join(lines)
    (out / "report.md").write_text(report, encoding="utf-8")
    log("\n" + report)


if __name__ == "__main__":
    main()
