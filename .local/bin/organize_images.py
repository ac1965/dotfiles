#!/usr/bin/env python3
"""画像の重複検出・隔離・連番リネーム。--undo でCSVに基づき復元する。"""

import argparse
import csv
import hashlib
import shutil
import sys
import uuid
from pathlib import Path

from PIL import Image, ImageOps

try:
    import pillow_heif
    pillow_heif.register_heif_opener()
except ImportError:
    pass

EXTENSIONS = {
    ".jpg", ".jpeg", ".png", ".webp", ".gif",
    ".bmp", ".tif", ".tiff", ".heic", ".heif",
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def perceptual_hash(path):
    """EXIF回転を補正し、先頭フレームから知覚ハッシュを作成。"""
    import imagehash
    with Image.open(path) as image:
        image.seek(0)
        image = ImageOps.exif_transpose(image).convert("RGB")
        return imagehash.phash(image)


def sort_key(path):
    return (path.name.casefold(), path.name)


def write_report(report, rows, similar_pairs):
    fields = [
        "original", "sha256", "phash", "status",
        "duplicate_of", "reason", "planned_name", "result",
    ]
    with report.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
        writer.writerow({})
        writer.writerow({
            "original": "SIMILAR_IMAGE_PAIRS",
        })
        writer.writerow({
            "original": "image_a",
            "sha256": "image_b",
            "phash": "hamming_distance",
        })
        for a, b, distance in similar_pairs:
            writer.writerow({
                "original": a,
                "sha256": b,
                "phash": distance,
            })


def undo(root, report, apply):
    """image_report.csv に記録された改名・隔離を元に戻す。"""
    if not report.is_file():
        raise SystemExit(f"レポートが見つかりません: {report}")

    with report.open("r", newline="", encoding="utf-8-sig") as stream:
        rows = list(csv.DictReader(stream))

    rows = [
        row for row in rows
        if row.get("original")
        and row.get("status") in {"keep", "duplicate", "error"}
    ]
    if not rows:
        raise SystemExit("CSVに復元対象の記録がありません。")

    quarantine_dirs = [root / "_duplicate", root / "_duplicates"]
    operations = []
    errors = []
    skipped = []

    for row in rows:
        original = row["original"]
        status = row.get("status", "")
        result = row.get("result", "")
        planned = row.get("planned_name", "")
        destination = root / original

        if status == "error":
            skipped.append(f"{original}: 元処理で読み取りエラーのため対象外")
            continue

        if status == "duplicate":
            sources = [
                directory / original for directory in quarantine_dirs
                if (directory / original).is_file()
            ]
            if len(sources) == 1:
                operations.append((sources[0], destination))
            elif len(sources) > 1:
                errors.append(f"隔離元が複数あります: {original}")
            elif destination.is_file():
                skipped.append(f"{original}: すでに元フォルダにあります")
            else:
                errors.append(f"隔離元が見つかりません: {original}")
            continue

        # keep画像。実行済みなら planned_name から original へ戻す。
        if result == "renamed" and planned:
            source = root / planned
            if source.is_file():
                if source == destination:
                    skipped.append(f"{original}: 変更不要")
                else:
                    operations.append((source, destination))
            elif destination.is_file():
                skipped.append(f"{original}: すでに元の名前です")
            else:
                errors.append(f"改名後のファイルが見つかりません: {planned}")
        else:
            if destination.is_file():
                skipped.append(f"{original}: 変更済みでないため対象外")
            elif planned and (root / planned).is_file():
                # レポートが事前生成された状態でも復元を試みられる
                source = root / planned
                if source != destination:
                    operations.append((source, destination))
            else:
                errors.append(f"復元元が見つかりません: {original}")

    sources = [src for src, _ in operations]
    destinations = [dst for _, dst in operations]

    if len(set(sources)) != len(sources):
        errors.append("同じファイルが複数回、復元元に指定されています")
    if len(set(destinations)) != len(destinations):
        errors.append("複数のファイルが同じ復元先を要求しています")

    source_set = set(sources)
    for src, dst in operations:
        if dst.exists() and dst not in source_set:
            errors.append(f"復元先に同名ファイルがあります: {dst.name}")

    print(f"対象フォルダ: {root}")
    print(f"復元予定: {len(operations)}")
    print(f"変更不要・対象外: {len(skipped)}")
    print(f"エラー: {len(errors)}")
    print(f"モード: {'復元実行' if apply else 'ドライラン'}")

    for src, dst in operations:
        print(f"復元: {src.relative_to(root)} -> {dst.name}")
    for item in skipped:
        print(f"SKIP: {item}")
    for item in errors:
        print(f"ERROR: {item}")

    if errors:
        print("\n安全のため、復元は実行しません。エラーを解消してください。")
        raise SystemExit(1)

    if not apply:
        print("\n内容を確認後、--undo --apply を指定して実行してください。")
        return

    # 全対象を一時名に退避してから元の名前へ移動する。
    staged = []
    try:
        for src, dst in operations:
            temp = src.parent / f".undo-{uuid.uuid4().hex}.tmp"
            src.rename(temp)
            staged.append((temp, dst, src))

        for temp, dst, src in staged:
            if dst.exists():
                raise FileExistsError(f"復元先が衝突しました: {dst}")
            temp.rename(dst)

    except Exception:
            print(
                "復元中にエラーが発生しました。"
                "ファイルの状態を確認してください。",
                file=sys.stderr,
            )
            # 可能な範囲で変更前の場所へ戻す
            for temp, dst, src in reversed(staged):
                current = dst if dst.exists() else temp
                if current.exists() and not src.exists():
                    try:
                        current.rename(src)
                    except OSError:
                        pass
            raise

    print(f"\n復元完了: {len(operations)} ファイル")
    print("復元処理では image_report.csv を変更していません。")


def organize(root, report, args):
    import imagehash

    quarantine = root / "_duplicates"
    files = sorted(
        (
            p for p in root.iterdir()
            if p.is_file() and p.suffix.lower() in EXTENSIONS
        ),
        key=sort_key,
    )
    if not files:
        print("対象画像がありません。")
        return

    records = {}
    errors = {}
    for path in files:
        try:
            digest = sha256(path)
            phash = str(perceptual_hash(path)) if args.threshold else ""
            records[path] = {"sha256": digest, "phash": phash}
        except Exception as exc:
            errors[path] = str(exc)
            print(f"読み取り失敗（変更対象外）: {path.name}: {exc}")

    exact_groups = {}
    for path in files:
        if path in records:
            exact_groups.setdefault(records[path]["sha256"], []).append(path)

    duplicate_of = {}
    reason = {}
    for group in exact_groups.values():
        for path in group[1:]:
            duplicate_of[path] = group[0]
            reason[path] = "exact_sha256"

    similar_pairs = []
    if args.threshold:
        kept = [p for p in files if p in records and p not in duplicate_of]
        for index, path in enumerate(kept):
            current_hash = imagehash.hex_to_hash(records[path]["phash"])
            for earlier in kept[:index]:
                previous_hash = imagehash.hex_to_hash(records[earlier]["phash"])
                distance = current_hash - previous_hash
                if (
                    records[path]["sha256"] != records[earlier]["sha256"]
                    and distance <= args.threshold
                ):
                    similar_pairs.append((path.name, earlier.name, distance))
                    if path not in duplicate_of:
                        duplicate_of[path] = earlier
                        reason[path] = f"similar_phash_{distance}"

    duplicates = set(duplicate_of)
    retained = [
        p for p in files if p not in duplicates and p not in errors
    ]
    width = max(args.digits, len(str(len(retained))))
    plan = [
        (path, f"{args.prefix}_{i:0{width}d}{path.suffix.lower()}")
        for i, path in enumerate(retained, start=1)
    ]
    plan_by_path = dict(plan)

    rows = []
    for path in files:
        rec = records.get(path, {})
        if path in errors:
            status, action = "error", "unchanged"
        elif path in duplicates:
            status, action = "duplicate", "quarantine"
        else:
            status, action = "keep", "rename"
        rows.append({
            "original": path.name,
            "sha256": rec.get("sha256", ""),
            "phash": rec.get("phash", ""),
            "status": status,
            "duplicate_of": duplicate_of[path].name if path in duplicate_of else "",
            "reason": reason.get(path, errors.get(path, "")),
            "planned_name": plan_by_path.get(path, ""),
            "result": "planned" if not args.apply else action,
        })

    print(f"対象画像: {len(files)}")
    print(f"読み取り成功: {len(records)}")
    print(f"読み取り失敗: {len(errors)}")
    print(f"重複候補: {len(duplicates)}")
    print(f"類似画像ペア: {len(similar_pairs)}")
    print(f"連番改名対象: {len(retained)}")
    print(f"モード: {'実行' if args.apply else 'ドライラン'}")

    for old, new in plan:
        if old.name != new:
            print(f"改名: {old.name} -> {new}")
    for path in sorted(duplicates, key=sort_key):
        print(f"隔離: {path.name} -> {duplicate_of[path].name} を保持 ({reason[path]})")

    # ドライランでは計画を記録。実行時は成功後に実績を記録する。
    write_report(report, rows, similar_pairs)
    if not args.apply:
        print(f"\n予定レポート: {report}")
        print("確認後、--apply を付けて実行してください。")
        return

    destinations = [root / new for _, new in plan]
    source_paths = set(files)
    if len(set(destinations)) != len(destinations):
        raise RuntimeError("連番の改名先が重複しています")
    for dest in destinations:
        if dest.exists() and dest not in source_paths:
            raise RuntimeError(f"改名先が既に存在します: {dest}")

    quarantine_targets = [quarantine / p.name for p in duplicates]
    if len(set(quarantine_targets)) != len(quarantine_targets):
        raise RuntimeError("隔離先の名前が重複しています")
    if quarantine.exists() and not quarantine.is_dir():
        raise RuntimeError("_duplicates がディレクトリではありません")
    if any(p.exists() for p in quarantine_targets):
        raise RuntimeError("隔離先に同名ファイルがあります。処理を中止します。")

    temporary = []
    moved_duplicates = []
    created_quarantine = False
    try:
        for old, new in plan:
            temp = root / f".organize-{uuid.uuid4().hex}.tmp"
            old.rename(temp)
            temporary.append((temp, root / new, old))

        if duplicates:
            if not quarantine.exists():
                quarantine.mkdir()
                created_quarantine = True
            for src in sorted(duplicates, key=sort_key):
                target = quarantine / src.name
                shutil.move(str(src), str(target))
                moved_duplicates.append((target, src))

        for temp, dest, old in temporary:
            temp.rename(dest)

    except Exception:
        print("エラー: 処理が完了していません。ファイルの状態を確認してください。", file=sys.stderr)
        for temp, dest, old in reversed(temporary):
            current = dest if dest.exists() else temp
            if current.exists() and not old.exists():
                try:
                    current.rename(old)
                except OSError:
                    pass
        for moved, original in reversed(moved_duplicates):
            if moved.exists() and not original.exists():
                try:
                    shutil.move(str(moved), str(original))
                except OSError:
                    pass
        if created_quarantine and quarantine.exists():
            try:
                quarantine.rmdir()
            except OSError:
                pass
        raise

    for row in rows:
        if row["status"] == "duplicate":
            row["result"] = "quarantined"
        elif row["status"] == "keep":
            row["result"] = "renamed"
        else:
            row["result"] = "unchanged"
    write_report(report, rows, similar_pairs)
    print(f"\n処理完了\n隔離フォルダ: {quarantine}\n処理結果CSV: {report}")


def main():
    parser = argparse.ArgumentParser(
        description="画像の重複検出・隔離・連番リネーム。--undo で復元。"
    )
    parser.add_argument("folder", type=Path, help="対象フォルダ")
    parser.add_argument("--apply", action="store_true",
                        help="実際に処理する（--undo と併用可能）")
    parser.add_argument("--undo", action="store_true",
                        help="image_report.csv に基づき元に戻す")
    parser.add_argument("--prefix", default="image",
                        help="連番ファイル名の接頭辞")
    parser.add_argument("--digits", type=int, default=4,
                        help="連番の最小桁数")
    parser.add_argument("--threshold", type=int, default=6,
                        help="類似画像のpHash距離閾値（0～64）")
    args = parser.parse_args()

    root = args.folder.expanduser().resolve()
    if not root.is_dir():
        parser.error(f"フォルダが存在しません: {root}")

    report = root / "image_report.csv"
    if args.undo:
        undo(root, report, args.apply)
        return

    if args.digits < 1:
        parser.error("--digits は1以上にしてください")
    if not 0 <= args.threshold <= 64:
        parser.error("--threshold は0～64にしてください")
    if not args.prefix or "/" in args.prefix or "\\" in args.prefix:
        parser.error("--prefix は空文字やパス区切りを含められません")

    organize(root, report, args)


if __name__ == "__main__":
    main()
