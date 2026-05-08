#!/usr/bin/env python3
"""Validate inputs and resolve kernel build matrix.

Each kernel version is identified by a content hash of its configs and
patches. The version_name is `vmlinux-<version>_<hash7>`. We skip
arch+version pairs whose artifact already exists in the GitHub release.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parent.parent
HASH_LEN = 7

ARCH_TO_RUNNER = {
    "amd64": "ubuntu-24.04",
    "arm64": "ubuntu-24.04-arm",
}


def read_default_versions() -> list[str]:
    versions_file = REPO_ROOT / "kernel_versions.txt"
    versions: list[str] = []
    for raw in versions_file.read_text().splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            versions.append(line)
    return versions


def parse_versions(arg: str) -> list[str]:
    if not arg.strip():
        return read_default_versions()
    return [v.strip() for v in arg.split(",") if v.strip()]


def hash_inputs_for_version(version: str) -> str:
    """Hash the configs and any patches that determine this kernel build."""
    paths: list[Path] = []
    for arch in ("x86_64", "arm64"):
        cfg = REPO_ROOT / "configs" / arch / f"{version}.config"
        if cfg.is_file():
            paths.append(cfg)
    patches_dir = REPO_ROOT / "patches" / version
    if patches_dir.is_dir():
        paths.extend(sorted(p for p in patches_dir.glob("*.patch") if p.is_file()))

    if not paths:
        raise SystemExit(f"::error::No configs found for kernel version {version}")

    digest = hashlib.sha256()
    for path in paths:
        rel = path.relative_to(REPO_ROOT).as_posix()
        digest.update(rel.encode())
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()[:HASH_LEN]


def gh_release_assets(version_name: str) -> set[str]:
    """Return existing asset names for the given release, empty if none."""
    result = subprocess.run(
        ["gh", "release", "view", version_name, "--json", "assets", "-q", ".assets[].name"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return set()
    return {line for line in result.stdout.strip().split("\n") if line}


def asset_name(arch: str) -> str:
    return f"vmlinux-{arch}.bin"


def build_entries(
    versions: list[str],
    archs: list[str],
) -> tuple[list[dict], list[dict]]:
    """Return (build_matrix_entries, all_version_entries)."""
    build_entries: list[dict] = []
    version_entries: list[dict] = []
    for version in versions:
        version_hash = hash_inputs_for_version(version)
        version_name = f"vmlinux-{version}_{version_hash}"
        existing = gh_release_assets(version_name)
        version_entries.append({
            "kernel_version": version,
            "version_hash": version_hash,
            "version_name": version_name,
        })
        for arch in archs:
            if asset_name(arch) in existing:
                print(
                    f"{version_name}/{arch}: artifact exists, skipping build",
                    file=sys.stderr,
                )
                continue
            build_entries.append({
                "kernel_version": version,
                "arch": arch,
                "version_hash": version_hash,
                "version_name": version_name,
                "runner": ARCH_TO_RUNNER[arch],
            })
    return build_entries, version_entries


def write_github_output(outputs: dict[str, str]) -> None:
    out_path = os.environ.get("GITHUB_OUTPUT")
    if not out_path:
        for k, v in outputs.items():
            print(f"{k}={v}")
        return
    with open(out_path, "a") as f:
        for k, v in outputs.items():
            f.write(f"{k}={v}\n")


def collect_archs(amd64: bool, arm64: bool) -> list[str]:
    archs: list[str] = []
    if amd64:
        archs.append("amd64")
    if arm64:
        archs.append("arm64")
    return archs


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate kernel release inputs")
    parser.add_argument("--kernel-versions", default="",
                        help="Comma-separated kernel versions (default: kernel_versions.txt)")
    parser.add_argument("--build-amd64", type=lambda x: x.lower() == "true", default=True)
    parser.add_argument("--build-arm64", type=lambda x: x.lower() == "true", default=True)
    args = parser.parse_args(list(argv) if argv is not None else None)

    archs = collect_archs(args.build_amd64, args.build_arm64)
    if not archs:
        print("::error::At least one architecture must be selected", file=sys.stderr)
        return 1

    versions = parse_versions(args.kernel_versions)
    if not versions:
        print("::error::No kernel versions to build", file=sys.stderr)
        return 1

    build_list, version_list = build_entries(versions, archs)

    matrix = {"include": build_list} if build_list else {"include": [{"skip": "true"}]}

    print(f"Versions: {[v['version_name'] for v in version_list]}", file=sys.stderr)
    print(f"Build matrix: {json.dumps(matrix)}", file=sys.stderr)
    print(f"Has new artifacts: {bool(build_list)}", file=sys.stderr)

    write_github_output({
        "build_matrix": json.dumps(matrix),
        "versions": json.dumps(version_list),
        "has_new_artifacts": "true" if build_list else "false",
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())
