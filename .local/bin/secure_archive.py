#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
secure_archive.py — 7z 暗号化 ⇄ Hex 変換ツール v2.0（Python 移植版）

複数のファイル・ディレクトリを AES-256 暗号化 7z アーカイブにまとめ、
Hex テキストとして出力する。復号は逆手順で展開する。

【暗号化の流れ】
    入力パス群 → 7z a（AES-256 + ヘッダー暗号化） → .7z → Hex → .txt
    ※ 中間 .7z ファイルは処理後に自動削除。

【復号の流れ】
    .txt → Hex デコード → .7z → 7z x（ディレクトリ構造を保持） → _extracted フォルダ
    ※ 中間 .7z ファイルは処理後に自動削除。

【依存】
    7-Zip がインストール済みで、7z / 7zz / 7za のいずれかに PATH が通っていること。
    Windows: winget install 7zip.7zip
    macOS  : brew install sevenzip
    Linux  : apt install p7zip-full  など

【サイズ注意】
    Hex エンコードは Base64 比で約 2 倍のファイルサイズになる。
    大容量ファイルの場合はストレージ容量に注意すること。

使い方:
    python3 secure_archive.py e report.pdf memo.txt
    python3 secure_archive.py e ./project/
    python3 secure_archive.py d release_v2-7z_hex.txt -o ./out/
    python3 secure_archive.py e secret.txt -p "P@ssw0rd" -n myarchive
"""

from __future__ import annotations

import argparse
import getpass
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ENCRYPT_ALIASES = {"e", "enc", "encrypt"}
DECRYPT_ALIASES = {"d", "dec", "decrypt"}


# ---------------------------------------------------------------------------
# ユーティリティ出力
# ---------------------------------------------------------------------------
def info(msg: str) -> None:
    print(f"[   ] {msg}")


def ok(msg: str) -> None:
    print(f"[ v] {msg}")


def err(msg: str) -> None:
    print(f"[ERR] {msg}", file=sys.stderr)


# ---------------------------------------------------------------------------
# 7z バイナリ解決
# ---------------------------------------------------------------------------
def resolve_seven_zip() -> str:
    for bin_name in ("7zz", "7z", "7za"):
        found = shutil.which(bin_name)
        if found:
            return found

    candidates = [
        r"C:\Program Files\7-Zip\7z.exe",
        r"C:\Program Files (x86)\7-Zip\7z.exe",
        "/opt/homebrew/bin/7zz",
        "/usr/local/bin/7zz",
        "/usr/bin/7z",
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c

    raise FileNotFoundError(
        "7-Zip が見つかりません。"
        "winget install 7zip.7zip（Windows）／ brew install sevenzip（macOS）"
        "でインストールしてください。"
    )


# ---------------------------------------------------------------------------
# Hex エンコード・デコード（標準ライブラリのみ）
# ---------------------------------------------------------------------------
def encode_hex(data: bytes) -> str:
    return data.hex()


def decode_hex(text: str) -> bytes:
    text = text.strip().lower()
    if len(text) % 2 != 0:
        raise ValueError(
            "Hex 文字列の長さが奇数です。ファイルが破損している可能性があります。"
        )
    try:
        return bytes.fromhex(text)
    except ValueError as e:
        raise ValueError(f"Hex デコードに失敗しました: {e}") from e


# ---------------------------------------------------------------------------
# パスワード取得
# ---------------------------------------------------------------------------
def read_password(cli_password: str | None) -> str:
    if cli_password:
        return cli_password
    pw = getpass.getpass("Password: ")
    if not pw:
        err("パスワードが空です")
        sys.exit(1)
    return pw


# ---------------------------------------------------------------------------
# 一時ファイル削除
# ---------------------------------------------------------------------------
def remove_temp_file(path: Path) -> None:
    try:
        if path.exists():
            path.unlink()
    except OSError:
        pass


# ---------------------------------------------------------------------------
# 暗号化
# ---------------------------------------------------------------------------
def invoke_encrypt(
    sz_bin: str,
    archive_name: str,
    plain_pass: str,
    out_dir: Path,
    sources: list[Path],
) -> None:
    arc = out_dir / f"{archive_name}.7z"
    out = out_dir / f"{archive_name}-7z_hex.txt"

    info(f"入力 ({len(sources)} パス):")
    for s in sources:
        info(f"  {s}")
    info(f"7z 暗号化 → {arc}")

    cmd = [
        sz_bin, "a", "-t7z",
        f"-p{plain_pass}",
        "-mhe=on", "-mx=5",
        str(arc),
        *[str(s) for s in sources],
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        err(result.stdout)
        err(result.stderr)
        raise RuntimeError(f"7z 暗号化に失敗しました (exit {result.returncode})")

    info(f"Hex エンコード → {out}")
    data = arc.read_bytes()
    hex_str = encode_hex(data)
    out.write_text(hex_str, encoding="ascii")

    remove_temp_file(arc)

    size = out.stat().st_size
    ok(f"{out} ({size} bytes)")
    info("注: Hex 出力は Base64 比で約 2 倍のサイズになります")


# ---------------------------------------------------------------------------
# 復号
# ---------------------------------------------------------------------------
def invoke_decrypt(
    sz_bin: str,
    src_file: Path,
    plain_pass: str,
    out_dir: Path,
) -> None:
    leaf = src_file.stem
    stem = leaf
    for suffix in ("-7z_hex", "-7z"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
            break

    arc = out_dir / f"{stem}.7z"
    ext_dir = out_dir / f"{stem}_extracted"

    info(f"Hex デコード → {arc}")
    hex_str = src_file.read_text(encoding="ascii")
    data = decode_hex(hex_str)
    arc.write_bytes(data)

    info(f"7z 展開 → {ext_dir}")
    ext_dir.mkdir(parents=True, exist_ok=True)

    cmd = [sz_bin, "x", f"-p{plain_pass}", f"-o{ext_dir}", str(arc), "-y"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        remove_temp_file(arc)
        err(result.stdout)
        err(result.stderr)
        raise RuntimeError(
            f"7z 展開に失敗しました (exit {result.returncode})。"
            "パスワードが正しいか確認してください。"
        )

    remove_temp_file(arc)
    ok(str(ext_dir))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="secure_archive.py",
        description="7z 暗号化 ⇄ Hex 変換ツール v2.0",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "例:\n"
            "  python3 secure_archive.py e report.pdf memo.txt\n"
            "  python3 secure_archive.py e ./project/\n"
            "  python3 secure_archive.py d release_v2-7z_hex.txt -o ./out/\n"
        ),
    )
    parser.add_argument(
        "mode",
        choices=sorted(ENCRYPT_ALIASES | DECRYPT_ALIASES),
        metavar="mode",
        help="e/enc/encrypt（暗号化） または d/dec/decrypt（復号）",
    )
    parser.add_argument(
        "paths",
        nargs="+",
        help="暗号化: 対象ファイル・ディレクトリ（複数可） / 復号: Hex テキストファイル（1つ）",
    )
    parser.add_argument("-p", "--password", help="パスワード（省略時は対話入力）")
    parser.add_argument("-n", "--name", default="", help="アーカイブのベース名（暗号化時のみ）")
    parser.add_argument("-o", "--output-dir", default="", help="出力先ディレクトリ")
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    try:
        sz_bin = resolve_seven_zip()
    except FileNotFoundError as e:
        err(str(e))
        sys.exit(1)
    info(f"7-Zip: {sz_bin}")

    is_encrypt = args.mode in ENCRYPT_ALIASES
    plain_pass = read_password(args.password)

    if is_encrypt:
        resolved_paths: list[Path] = []
        for p in args.paths:
            path = Path(p).resolve()
            if not path.exists():
                err(f"存在しません: {p}")
                sys.exit(1)
            resolved_paths.append(path)

        out_dir = (
            Path(args.output_dir).resolve()
            if args.output_dir
            else resolved_paths[0].parent
        )

        name = args.name
        if not name:
            if len(resolved_paths) == 1:
                leaf = resolved_paths[0].name
                name = resolved_paths[0].stem if resolved_paths[0].is_file() else leaf
                if not name:
                    name = leaf
            else:
                name = "archive_" + datetime.now().strftime("%Y%m%d_%H%M%S")

        out_dir.mkdir(parents=True, exist_ok=True)

        info(f"アーカイブ名: {name}")
        info(f"出力先: {out_dir}")

        try:
            invoke_encrypt(sz_bin, name, plain_pass, out_dir, resolved_paths)
        except RuntimeError as e:
            err(str(e))
            sys.exit(1)

    else:
        src_file = Path(args.paths[0]).resolve()
        if not src_file.is_file():
            err(f"ファイルが見つかりません: {src_file}")
            sys.exit(1)

        out_dir = (
            Path(args.output_dir).resolve() if args.output_dir else src_file.parent
        )
        out_dir.mkdir(parents=True, exist_ok=True)

        info(f"入力: {src_file}")
        info(f"出力先: {out_dir}")

        try:
            invoke_decrypt(sz_bin, src_file, plain_pass, out_dir)
        except (RuntimeError, ValueError) as e:
            err(str(e))
            sys.exit(1)


if __name__ == "__main__":
    main()
