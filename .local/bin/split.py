#!/usr/bin/env python3
import argparse
from pathlib import Path


SRC_BEGIN = "#+begin_src"
SRC_END = "#+end_src"


def split_org_safely(text: str, target_bytes: int):
    lines = text.splitlines(keepends=True)
    parts = []
    buf = []
    buf_bytes = 0
    in_src = False

    def flush():
        nonlocal buf, buf_bytes
        if buf:
            parts.append("".join(buf))
            buf = []
            buf_bytes = 0

    for line in lines:
        l = line.lstrip()

        if l.lower().startswith(SRC_BEGIN):
            in_src = True

        if (not in_src) and buf_bytes >= target_bytes:
            flush()

        buf.append(line)
        buf_bytes += len(line.encode("utf-8"))

        if l.lower().startswith(SRC_END):
            in_src = False
            if buf_bytes >= target_bytes:
                flush()

    flush()
    return parts


def parse_args():
    parser = argparse.ArgumentParser(
        description="Safely split Org file without breaking src blocks"
    )

    parser.add_argument(
        "file",
        nargs="?",
        default="README.org",
        help="target Org file (default: README.org)",
    )

    parser.add_argument(
        "bytes",
        nargs="?",
        type=int,
        default=95000,
        help="max bytes per part (default: 95000)",
    )

    parser.add_argument(
        "--no-header",
        action="store_true",
        help="do not prepend part header",
    )

    return parser.parse_args()


def main():
    args = parse_args()

    src = Path(args.file)
    if not src.exists():
        raise SystemExit(f"Error: file not found: {src}")

    outdir = Path("parts")
    outdir.mkdir(exist_ok=True)

    text = src.read_text(encoding="utf-8")
    parts = split_org_safely(text, target_bytes=args.bytes)

    total = len(parts)
    stem = src.name

    for i, chunk in enumerate(parts, 1):
        p = outdir / f"{stem}.part.{i:03d}.txt"

        if args.no_header:
            content = chunk
        else:
            header = f"{stem} part {i}/{total}\n" + "-" * 20 + "\n"
            content = header + chunk

        p.write_text(content, encoding="utf-8")

    print(f"wrote {total} parts into {outdir}/")
    print(f"source: {src}")
    print(f"bytes per part: {args.bytes}")
    print(f"header: {'disabled' if args.no_header else 'enabled'}")


if __name__ == "__main__":
    main()
