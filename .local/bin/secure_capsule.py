#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
secure_capsule.py — 7z暗号化 ⇄ Excel偽装 ワンオペパイプライン v1.0

seal   : ファイル/ディレクトリ群 → 7z AES-256暗号化 → Hex → xlsx (UUID偽装)
unseal : xlsx → Hex復元 → 7z復号 → _extracted フォルダ

中間 Hex ファイルは一時ディレクトリ上でのみ生成され、処理後に自動削除される。
ディスク上に残るのは seal 時は .xlsx のみ、unseal 時は _extracted フォルダのみ。

【依存】
    secure_archive.py / excel_capsule.py が同ディレクトリにあること
    pip install openpyxl      （excel_capsule の依存）
    7-Zip インストール済みで PATH が通っていること

使い方:
    python3 secure_capsule.py seal   report.pdf -p P@ssw0rd
    python3 secure_capsule.py seal   secret.txt memo.txt -n bundle -o ./vault/
    python3 secure_capsule.py unseal capsule.xlsx -p P@ssw0rd -o ./out/
    python3 secure_capsule.py seal   -h
"""

from __future__ import annotations

import argparse
import getpass
import importlib.util
import sys
import tempfile
from datetime import datetime
from pathlib import Path

SEAL_CMDS   = {"seal",   "s", "lock"}
UNSEAL_CMDS = {"unseal", "u", "unlock"}

# ---------------------------------------------------------------------------
# 同ディレクトリの依存モジュールを動的ロード
# ---------------------------------------------------------------------------
_HERE = Path(__file__).resolve().parent


def _load_module(name: str):
    path = _HERE / f"{name}.py"
    if not path.exists():
        sys.exit(
            f"[ERROR] {name}.py が見つかりません。\n"
            f"        secure_capsule.py と同じディレクトリに配置してください: {_HERE}"
        )
    spec = importlib.util.spec_from_file_location(name, path)
    mod  = importlib.util.module_from_spec(spec)   # type: ignore[arg-type]
    spec.loader.exec_module(mod)                    # type: ignore[union-attr]
    return mod


_sa = _load_module("secure_archive")   # invoke_encrypt / invoke_decrypt / resolve_seven_zip
_ec = _load_module("excel_capsule")    # export_capsule / restore_capsule


# ---------------------------------------------------------------------------
# ユーティリティ出力
# ---------------------------------------------------------------------------
def _info(msg: str) -> None:
    print(f"[   ] {msg}")

def _ok(msg: str) -> None:
    print(f"[ v] {msg}")

def _err(msg: str) -> None:
    print(f"[ERR] {msg}", file=sys.stderr)

def _step(n: int, total: int, label: str) -> None:
    bar = "─" * 48
    print(f"\n{bar}")
    print(f"  Step {n}/{total}  {label}")
    print(f"{bar}")


# ---------------------------------------------------------------------------
# パスワード取得
# ---------------------------------------------------------------------------
def _read_password(cli_password: str | None) -> str:
    if cli_password:
        return cli_password
    pw = getpass.getpass("Password: ")
    if not pw:
        _err("パスワードが空です")
        sys.exit(1)
    return pw


# ---------------------------------------------------------------------------
# seal: ファイル/ディレクトリ → xlsx
# ---------------------------------------------------------------------------
def do_seal(
    sources:      list[Path],
    out_dir:      Path,
    plain_pass:   str,
    archive_name: str,
    sheet_name:   str,
) -> Path:
    """
    sources を 7z 暗号化 → Hex → xlsx (UUID偽装) のパイプラインで処理する。

    戻り値: 生成された xlsx の Path
    """
    sz_bin = _sa.resolve_seven_zip()
    _info(f"7-Zip : {sz_bin}")
    _info(f"アーカイブ名 : {archive_name}")
    _info(f"出力先       : {out_dir}")
    _info(f"シート名     : {sheet_name}")

    out_dir.mkdir(parents=True, exist_ok=True)
    xlsx_path = out_dir / f"{archive_name}.xlsx"

    with tempfile.TemporaryDirectory(prefix="secure_capsule_") as _tmp:
        tmp = Path(_tmp)

        # ── Step 1: 7z 暗号化 → temp Hex ─────────────────────────────────
        _step(1, 2, "7z AES-256 暗号化  →  Hex (一時ファイル)")
        try:
            _sa.invoke_encrypt(sz_bin, archive_name, plain_pass, tmp, sources)
        except RuntimeError as e:
            sys.exit(f"[ERROR] 暗号化に失敗しました: {e}")

        hex_file = tmp / f"{archive_name}-7z_hex.txt"
        if not hex_file.exists():
            sys.exit(f"[ERROR] Hex ファイルが生成されていません: {hex_file}")

        # ── Step 2: Hex → xlsx (UUID偽装) ─────────────────────────────────
        _step(2, 2, "Hex  →  xlsx (UUID 偽装・シャッフル)")
        try:
            _ec.export_capsule(hex_file, xlsx_path, sheet_name)
        except SystemExit:
            raise   # excel_capsule 側のエラーはそのまま伝播

        # tmp は with ブロック終了で自動削除

    print()
    _ok(f"Seal 完了  →  {xlsx_path}")
    return xlsx_path


# ---------------------------------------------------------------------------
# unseal: xlsx → _extracted フォルダ
# ---------------------------------------------------------------------------
def do_unseal(
    xlsx_path:  Path,
    out_dir:    Path,
    plain_pass: str,
    sheet_name: str,
) -> Path:
    """
    xlsx を Hex 復元 → 7z 復号 → 展開のパイプラインで処理する。

    戻り値: 展開先フォルダの Path
    """
    if not xlsx_path.exists():
        sys.exit(f"[ERROR] ファイルが見つかりません: {xlsx_path}")

    sz_bin = _sa.resolve_seven_zip()
    _info(f"7-Zip : {sz_bin}")
    _info(f"入力 xlsx : {xlsx_path}")
    _info(f"出力先    : {out_dir}")
    _info(f"シート名  : {sheet_name}")

    out_dir.mkdir(parents=True, exist_ok=True)

    # xlsx のステムからアーカイブ名を推定
    # 例: "report.xlsx" → "report" → hex: "report-7z_hex.txt" → ext: "report_extracted"
    archive_stem = xlsx_path.stem

    with tempfile.TemporaryDirectory(prefix="secure_capsule_") as _tmp:
        tmp = Path(_tmp)

        # ── Step 1: xlsx → Hex 復元 ───────────────────────────────────────
        _step(1, 2, "xlsx  →  Hex 復元 (一時ファイル)")
        hex_file = tmp / f"{archive_stem}-7z_hex.txt"
        try:
            _ec.restore_capsule(xlsx_path, hex_file, sheet_name)
        except SystemExit:
            raise   # excel_capsule 側のエラーはそのまま伝播

        if not hex_file.exists():
            sys.exit("[ERROR] Hex ファイルの復元に失敗しました。")

        # ── Step 2: Hex → 7z 復号 → 展開 ────────────────────────────────
        _step(2, 2, "Hex  →  7z 復号  →  展開")
        try:
            _sa.invoke_decrypt(sz_bin, hex_file, plain_pass, out_dir)
        except (RuntimeError, ValueError) as e:
            sys.exit(f"[ERROR] 復号に失敗しました: {e}")

        # tmp は with ブロック終了で自動削除

    # 展開先パスを再現（invoke_decrypt 内部ロジックと同じ手順）
    stem = archive_stem
    for sfx in ("-7z_hex", "-7z"):
        if stem.endswith(sfx):
            stem = stem[: -len(sfx)]
            break
    ext_dir = out_dir / f"{stem}_extracted"

    print()
    _ok(f"Unseal 完了  →  {ext_dir}")
    return ext_dir


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="secure_capsule.py",
        description=(
            "7z暗号化 ⇄ Excel偽装 ワンオペパイプライン\n\n"
            "  seal  : ファイル/ディレクトリ → 7z暗号化 → Hex → xlsx (UUID偽装)\n"
            "  unseal: xlsx → Hex復元 → 7z復号 → _extracted フォルダ\n\n"
            "中間 Hex ファイルは自動削除される一時領域にのみ作成されます。"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "エイリアス:\n"
            "  seal   : s, lock\n"
            "  unseal : u, unlock\n\n"
            "例:\n"
            "  python3 secure_capsule.py seal   report.pdf -p P@ssw0rd\n"
            "  python3 secure_capsule.py seal   secret.txt memo.txt -n bundle -o ./vault/\n"
            "  python3 secure_capsule.py unseal capsule.xlsx -p P@ssw0rd -o ./out/\n"
            "  python3 secure_capsule.py seal   ./project/ --sheet mydata\n"
        ),
    )

    sub = parser.add_subparsers(dest="command", required=True)

    # ── seal ────────────────────────────────────────────────────────────────
    s_parser = sub.add_parser(
        "seal",
        aliases=["s", "lock"],
        help="ファイル/ディレクトリ → 7z暗号化 → xlsx",
        description="ファイル/ディレクトリを AES-256 暗号化し、Hex 経由で xlsx に格納します。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    s_parser.add_argument(
        "paths", nargs="+",
        help="暗号化対象のファイル・ディレクトリ（複数可）",
    )
    s_parser.add_argument("-p", "--password", help="パスワード（省略時は対話入力）")
    s_parser.add_argument("-n", "--name",     default="", help="xlsx / アーカイブのベース名（省略時は1番目のパス名）")
    s_parser.add_argument("-o", "--output-dir", default="", help="出力先ディレクトリ（省略時は1番目のパスの親ディレクトリ）")
    s_parser.add_argument("--sheet", default="transactions", metavar="SHEET",
                          help="xlsx のシート名  [デフォルト: transactions]")

    # ── unseal ──────────────────────────────────────────────────────────────
    u_parser = sub.add_parser(
        "unseal",
        aliases=["u", "unlock"],
        help="xlsx → Hex復元 → 7z復号 → _extracted フォルダ",
        description="xlsx から Hex を復元し、7z 復号・展開を行います。",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    u_parser.add_argument("xlsx", help="入力 xlsx ファイルのパス")
    u_parser.add_argument("-p", "--password", help="パスワード（省略時は対話入力）")
    u_parser.add_argument("-o", "--output-dir", default="", help="出力先ディレクトリ（省略時は xlsx と同じディレクトリ）")
    u_parser.add_argument("--sheet", default="transactions", metavar="SHEET",
                          help="xlsx のシート名  [デフォルト: transactions]")

    return parser


def main() -> None:
    parser = build_parser()
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit(0)
    args   = parser.parse_args()

    plain_pass = _read_password(args.password)
    cmd        = args.command   # "seal" / "s" / "lock" / "unseal" / "u" / "unlock"

    # ── seal ────────────────────────────────────────────────────────────────
    if cmd in SEAL_CMDS:
        resolved: list[Path] = []
        for p in args.paths:
            path = Path(p).resolve()
            if not path.exists():
                _err(f"存在しません: {p}")
                sys.exit(1)
            resolved.append(path)

        out_dir = (
            Path(args.output_dir).resolve()
            if args.output_dir
            else resolved[0].parent
        )

        name = args.name
        if not name:
            if len(resolved) == 1:
                first = resolved[0]
                name  = first.stem if first.is_file() else first.name
                name  = name or first.name
            else:
                name = "archive_" + datetime.now().strftime("%Y%m%d_%H%M%S")

        do_seal(
            sources      = resolved,
            out_dir      = out_dir,
            plain_pass   = plain_pass,
            archive_name = name,
            sheet_name   = args.sheet,
        )

    # ── unseal ──────────────────────────────────────────────────────────────
    elif cmd in UNSEAL_CMDS:
        xlsx_path = Path(args.xlsx).resolve()
        if not xlsx_path.is_file():
            _err(f"ファイルが見つかりません: {xlsx_path}")
            sys.exit(1)

        out_dir = (
            Path(args.output_dir).resolve()
            if args.output_dir
            else xlsx_path.parent
        )

        do_unseal(
            xlsx_path  = xlsx_path,
            out_dir    = out_dir,
            plain_pass = plain_pass,
            sheet_name = args.sheet,
        )

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
