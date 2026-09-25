#!/usr/bin/env python3
"""Validate and build a deterministic, reviewer-auditable release ZIP."""

from __future__ import annotations

import hashlib
import argparse
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
VERSION = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
ARCHIVE = DIST / f"GearBuddy-v{VERSION}-read-only.zip"
CHECKSUM = ARCHIVE.with_suffix(ARCHIVE.suffix + ".sha256")
EXCLUDED_PARTS = {".git", "dist", "__pycache__"}


def included_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if not path.is_file():
            continue
        if any(part in EXCLUDED_PARTS for part in relative.parts):
            continue
        if path.suffix == ".pyc":
            continue
        files.append(path)
    return sorted(files, key=lambda value: value.relative_to(ROOT).as_posix())


def zip_info(name: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    return info


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--replace-existing",
        action="store_true",
        help="Allow rebuilding the same VERSION filename intentionally.",
    )
    args = parser.parse_args()

    subprocess.run([sys.executable, "tools/validate_repo.py"], cwd=ROOT, check=True)
    subprocess.run(
        [sys.executable, "-m", "unittest", "discover", "-s", "tests"],
        cwd=ROOT,
        check=True,
    )
    texlua = shutil.which("texlua")
    if texlua:
        subprocess.run(
            [texlua, "tests/runtime_smoke.lua"],
            cwd=ROOT,
            check=True,
        )

    DIST.mkdir(exist_ok=True)
    if not args.replace_existing and (ARCHIVE.exists() or CHECKSUM.exists()):
        raise SystemExit(
            f"Release already exists: {ARCHIVE.name}. "
            "Bump VERSION or pass --replace-existing intentionally."
        )
    files = included_files()
    manifest_files = []
    for path in files:
        relative = path.relative_to(ROOT).as_posix()
        payload = path.read_bytes()
        manifest_files.append(
            {
                "path": relative,
                "sha256": hashlib.sha256(payload).hexdigest(),
                "size": len(payload),
            }
        )
    manifest = {
        "name": "GearBuddy",
        "version": VERSION,
        "mode": "read-only",
        "files": manifest_files,
    }
    manifest_payload = (
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    ).encode("utf-8")

    with zipfile.ZipFile(ARCHIVE, "w") as bundle:
        for path in files:
            relative = path.relative_to(ROOT).as_posix()
            bundle.writestr(zip_info(f"GearBuddy/{relative}"), path.read_bytes())
        bundle.writestr(
            zip_info("GearBuddy/RELEASE_MANIFEST.json"),
            manifest_payload,
        )

    digest = hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()
    CHECKSUM.write_text(f"{digest}  {ARCHIVE.name}\n", encoding="utf-8")
    print(f"Built {ARCHIVE}")
    print(f"SHA-256 {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
