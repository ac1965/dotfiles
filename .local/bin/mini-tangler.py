#!/usr/bin/env python3
"""
Minimal Org tangler for literate Emacs configs.

Supports (subset):
- #+begin_src ... #+end_src blocks
- :tangle no|yes|FILENAME
- :padline yes|no
- Simple noweb: <<name>> replaced by content of named src blocks (#+name:)
from pathlib import Path
  (Partial; not full org-babel noweb semantics.)

"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path
from urllib.request import urlopen, Request


SRC_BEGIN_RE = re.compile(r"^\s*#\+begin_src\s+(\S+)(.*)$", re.IGNORECASE)
SRC_END_RE = re.compile(r"^\s*#\+end_src\s*$", re.IGNORECASE)
NAME_RE = re.compile(r"^\s*#\+name:\s*(\S+)\s*$", re.IGNORECASE)
PROP_RE = re.compile(r"^\s*#\+property:\s*(.+?)\s*$", re.IGNORECASE)

NOWEB_REF_RE = re.compile(r"<<\s*([A-Za-z0-9_.:-]+)\s*>>")


def fetch_text(src: str) -> str:
    # URL (http/https)
    if src.startswith(("http://", "https://")):
        req = Request(src, headers={"User-Agent": "minimal-org-tangler/1.0"})
        with urlopen(req) as r:
            raw = r.read()
        return raw.decode("utf-8")

    # Local file path
    path = Path(src).expanduser()
    if not path.is_file():
        raise FileNotFoundError(f"Org file not found: {src}")

    return path.read_text(encoding="utf-8")


def parse_header_args(argstr: str) -> dict[str, str]:
    """
    Parse a very small subset of org header args:
    :key value :key2 value2 ...
    Values may be quoted or unquoted.
    """
    out: dict[str, str] = {}
    # tokenization: handles quoted "..." or '...' minimally
    tokens = re.findall(r"""(?:"[^"]*"|'[^']*'|\S+)""", argstr)
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t.startswith(":"):
            key = t[1:].strip()
            val = ""
            if i + 1 < len(tokens) and not tokens[i + 1].startswith(":"):
                val = tokens[i + 1].strip()
                # strip quotes
                if (val.startswith('"') and val.endswith('"')) or (
                    val.startswith("'") and val.endswith("'")
                ):
                    val = val[1:-1]
                i += 2
            else:
                i += 1
            out[key.lower()] = val
        else:
            i += 1
    return out


@dataclass
class SrcBlock:
    lang: str
    args: dict[str, str]
    body: str
    name: str | None
    lineno: int


def extract_global_header_args(lines: list[str]) -> dict[str, dict[str, str]]:
    """
    Reads #+PROPERTY: header-args... lines.
    Returns mapping:
      {"*": {...}, "emacs-lisp": {...}, ...}
    """
    global_args: dict[str, dict[str, str]] = {}
    for line in lines:
        m = PROP_RE.match(line)
        if not m:
            continue
        payload = m.group(1).strip()
        # Examples:
        # header-args :tangle yes
        # header-args:emacs-lisp :tangle lisp/init.el
        if payload.lower().startswith("header-args"):
            key, _, rest = payload.partition(" ")
            rest = rest.strip()
            if ":" in key:
                # header-args:LANG
                _, _, lang = key.partition(":")
                lang = lang.strip().lower()
            else:
                lang = "*"  # applies to all
            if rest:
                global_args.setdefault(lang, {}).update(parse_header_args(rest))
    return global_args


def merge_args(
    global_all: dict[str, str], global_lang: dict[str, str], local: dict[str, str]
) -> dict[str, str]:
    merged = dict(global_all)
    merged.update(global_lang)
    merged.update(local)
    return merged


def scan_blocks(org_text: str) -> tuple[list[SrcBlock], dict[str, str]]:
    lines = org_text.splitlines(keepends=False)
    global_args = extract_global_header_args(lines)

    blocks: list[SrcBlock] = []
    in_src = False
    cur_lang = ""
    cur_args: dict[str, str] = {}
    cur_body_lines: list[str] = []
    cur_name: str | None = None
    begin_lineno = 0

    pending_name: str | None = None

    for idx, line in enumerate(lines, start=1):
        nm = NAME_RE.match(line)
        if nm and not in_src:
            pending_name = nm.group(1)
            continue

        m = SRC_BEGIN_RE.match(line)
        if m and not in_src:
            in_src = True
            cur_lang = m.group(1).strip().lower()
            argstr = m.group(2).strip()
            local_args = parse_header_args(argstr)
            cur_args = merge_args(
                global_args.get("*", {}),
                global_args.get(cur_lang, {}),
                local_args,
            )
            cur_body_lines = []
            cur_name = pending_name
            pending_name = None
            begin_lineno = idx
            continue

        if SRC_END_RE.match(line) and in_src:
            in_src = False
            body = "\n".join(cur_body_lines).rstrip("\n")
            blocks.append(SrcBlock(cur_lang, cur_args, body, cur_name, begin_lineno))
            cur_lang = ""
            cur_args = {}
            cur_body_lines = []
            cur_name = None
            begin_lineno = 0
            continue

        if in_src:
            cur_body_lines.append(line)

    return blocks, {
        k: v for k, v in global_args.items()
    }  # second return mostly for debugging


def build_noweb_map(blocks: list[SrcBlock]) -> dict[str, str]:
    """
    Very simple noweb: named blocks become entries.
    If multiple blocks share the same name, concatenate with newlines.
    """
    m: dict[str, list[str]] = {}
    for b in blocks:
        if b.name:
            m.setdefault(b.name, []).append(b.body)
    return {k: "\n".join(v).rstrip("\n") for k, v in m.items()}


def expand_noweb(text: str, noweb_map: dict[str, str], max_depth: int = 10) -> str:
    """
    Expand <<name>> references using noweb_map. Repeats until stable or max_depth.
    Partial implementation; org has more modes (strip-tangle etc.).:contentReference[oaicite:6]{index=6}
    """
    cur = text
    for _ in range(max_depth):

        def repl(match: re.Match) -> str:
            key = match.group(1)
            return noweb_map.get(key, match.group(0))  # leave as-is if unknown

        nxt = NOWEB_REF_RE.sub(repl, cur)
        if nxt == cur:
            return cur
        cur = nxt
    return cur


def default_tangle_name(org_url: str, lang: str) -> str:
    """
    If :tangle yes, org derives filename from org file name and language extension.:contentReference[oaicite:7]{index=7}
    We approximate: README.org -> README.<ext>
    """
    base = Path(org_url.split("?")[0]).name
    stem = Path(base).stem
    # Minimal language -> extension map (customize as needed)
    ext_map = {
        "emacs-lisp": "el",
        "elisp": "el",
        "sh": "sh",
        "shell": "sh",
        "python": "py",
    }
    ext = ext_map.get(lang, lang)
    return f"{stem}.{ext}"


def tangle(org_url: str, out_root: Path) -> list[Path]:
    org_text = fetch_text(org_url)
    blocks, _ = scan_blocks(org_text)
    noweb_map = build_noweb_map(blocks)

    # Aggregate per output file
    out_buckets: dict[Path, list[str]] = {}

    for b in blocks:
        tangle_val = (b.args.get("tangle", "") or "").strip()
        if not tangle_val or tangle_val.lower() == "no":
            continue

        if tangle_val.lower() == "yes":
            rel = default_tangle_name(org_url, b.lang)
        else:
            rel = tangle_val

        rel_path = Path(rel)
        out_path = (out_root / rel_path).resolve()

        body = b.body
        # noweb expansion control: org's :noweb supports multiple modes; here we expand only if "yes" or "tangle".:contentReference[oaicite:8]{index=8}
        noweb_mode = (b.args.get("noweb", "") or "").strip().lower()
        if noweb_mode in ("yes", "tangle", "no-export", "strip-tangle", "strip-export"):
            body = expand_noweb(body, noweb_map)

        # padline
        padline = (b.args.get("padline", "") or "").strip().lower()
        if padline == "yes":
            body = body.rstrip("\n") + "\n"

        out_buckets.setdefault(out_path, []).append(body.rstrip("\n"))

        # mkdirp
        mkdirp = (b.args.get("mkdirp", "") or "").strip().lower()
        if mkdirp == "yes":
            out_path.parent.mkdir(parents=True, exist_ok=True)

    written: list[Path] = []
    for path, chunks in out_buckets.items():
        path.parent.mkdir(parents=True, exist_ok=True)  # safe default
        content = "\n".join(chunks).rstrip("\n") + "\n"
        path.write_text(content, encoding="utf-8")
        written.append(path)

    return sorted(set(written))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "org_url",
        help="Org file raw URL (e.g., README.org on raw.githubusercontent.com)",
    )
    ap.add_argument(
        "--root", default=".", help="Output root directory for tangled files"
    )
    args = ap.parse_args()

    out_root = Path(args.root).expanduser().resolve()
    out_root.mkdir(parents=True, exist_ok=True)

    written = tangle(args.org_url, out_root)
    for p in written:
        print(str(p))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
