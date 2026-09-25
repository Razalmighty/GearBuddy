#!/usr/bin/env python3
"""Verify release paths and every SHA-256 entry in RELEASE_MANIFEST.json."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import PurePosixPath


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive")
    args = parser.parse_args()

    with zipfile.ZipFile(args.archive) as bundle:
        names = bundle.namelist()
        for name in names:
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts:
                raise SystemExit(f"Unsafe archive path: {name}")
        manifest_name = "GearBuddy/RELEASE_MANIFEST.json"
        manifest = json.loads(bundle.read(manifest_name))
        expected = {manifest_name}
        for record in manifest["files"]:
            name = "GearBuddy/" + record["path"]
            expected.add(name)
            payload = bundle.read(name)
            digest = hashlib.sha256(payload).hexdigest()
            if digest != record["sha256"]:
                raise SystemExit(f"Hash mismatch: {name}")
            if len(payload) != record["size"]:
                raise SystemExit(f"Size mismatch: {name}")
        if set(names) != expected:
            extra = sorted(set(names) - expected)
            missing = sorted(expected - set(names))
            raise SystemExit(f"Archive inventory mismatch; extra={extra}, missing={missing}")

    print(
        f"Release verified: {manifest['name']} {manifest['version']} "
        f"({len(manifest['files'])} source files, {manifest['mode']})."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
