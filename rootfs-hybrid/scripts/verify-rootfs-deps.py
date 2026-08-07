#!/usr/bin/env python3
"""Verify DT_NEEDED presence closure for every ELF file in the merged rootfs.

This is a static presence check (not an execution test): every DT_NEEDED name
must be provided by a non-broken shared-library filename or SONAME somewhere in
the rootfs. It catches broken dependency closure after Qt5 removal/cleanup.

Environment overrides: PROJECT_ROOT, WORKDIR, ROOTFS_DIR, REPORTS_DIR, READELF.
"""
from __future__ import annotations

import os
import subprocess
import sys

DEFAULT_PROJECT_ROOT = "/home/buildroot/my_buildroot/workspace/buildroot-2024.08"
P = os.environ.get("PROJECT_ROOT", DEFAULT_PROJECT_ROOT)
WORKDIR = os.environ.get("WORKDIR", os.path.join(P, "rootfs-hybrid"))
ROOTFS = os.environ.get("ROOTFS_DIR", os.path.join(WORKDIR, "rootfs"))
REPORTS = os.environ.get("REPORTS_DIR", os.path.join(WORKDIR, "reports"))
READELF = os.environ.get(
    "READELF",
    os.path.join(P, "output-qt6", "host", "bin", "loongarch64-loongson-linux-gnu-readelf"),
)
OUT = os.path.join(REPORTS, "full-rootfs-deps.txt")
SUMMARY = os.path.join(REPORTS, "full-rootfs-deps-summary.txt")
SKIP = {"linux-vdso.so.1", "ld-linux-loongarch-lp64d.so.1"}


def is_elf(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def dynamic(path: str) -> tuple[list[str], str | None]:
    try:
        cp = subprocess.run(
            [READELF, "-d", path], capture_output=True, text=True, timeout=30, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return [], None
    needed: list[str] = []
    soname: str | None = None
    for line in cp.stdout.splitlines():
        if "NEEDED" in line and "[" in line:
            needed.append(line.split("[", 1)[1].split("]", 1)[0])
        elif "SONAME" in line and "[" in line:
            soname = line.split("[", 1)[1].split("]", 1)[0]
    return needed, soname


def tree_resolve(path: str, max_hops: int = 32) -> str | None:
    cur = os.path.normpath(path)
    seen: set[str] = set()
    for _ in range(max_hops):
        if cur in seen:
            return None
        seen.add(cur)
        if not os.path.lexists(cur):
            return None
        if not os.path.islink(cur):
            return cur
        target = os.readlink(cur)
        if os.path.isabs(target):
            cur = os.path.join(ROOTFS, target.lstrip("/"))
        else:
            cur = os.path.normpath(os.path.join(os.path.dirname(cur), target))
    return None


def main() -> int:
    os.makedirs(REPORTS, exist_ok=True)
    providers: dict[str, set[str]] = {}
    broken_shared_links: list[str] = []
    elf_files: list[str] = []

    for base, dirs, files in os.walk(ROOTFS):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(base, d))]
        for name in files:
            path = os.path.join(base, name)
            if ".so" in name and (os.path.islink(path) or os.path.isfile(path)):
                resolved = tree_resolve(path)
                if os.path.islink(path) and not resolved:
                    broken_shared_links.append(os.path.relpath(path, ROOTFS))
                elif resolved:
                    providers.setdefault(name, set()).add(os.path.relpath(path, ROOTFS))
            if not os.path.islink(path) and is_elf(path):
                elf_files.append(path)

    missing: list[tuple[str, str]] = []
    for path in sorted(elf_files):
        needed, _ = dynamic(path)
        for dep in needed:
            if dep in SKIP:
                continue
            if dep not in providers:
                missing.append((os.path.relpath(path, ROOTFS), dep))

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("# Full rootfs DT_NEEDED presence closure\n")
        f.write(f"# ELF files scanned: {len(elf_files)}\n")
        f.write(f"# provider names: {len(providers)}\n")
        f.write(f"# broken shared-library symlinks: {len(broken_shared_links)}\n")
        f.write(f"# unresolved count: {len(missing)}\n")
        for rel in sorted(broken_shared_links):
            f.write(f"BROKEN_SYMLINK: {rel}\n")
        for rel, dep in sorted(set(missing)):
            f.write(f"MISSING: {rel} -> {dep}\n")

    with open(SUMMARY, "w", encoding="utf-8") as f:
        f.write(f"elf_files={len(elf_files)}\n")
        f.write(f"providers={len(providers)}\n")
        f.write(f"broken_symlinks={len(broken_shared_links)}\n")
        f.write(f"unresolved={len(set(missing))}\n")

    print(f"ELF files scanned: {len(elf_files)}")
    print(f"provider names: {len(providers)}")
    print(f"broken shared-library symlinks: {len(broken_shared_links)}")
    print(f"unresolved count: {len(set(missing))}")
    print(f"report: {OUT}")

    if broken_shared_links or missing:
        for rel in sorted(broken_shared_links)[:20]:
            print(f"  BROKEN_SYMLINK: {rel}")
        for rel, dep in sorted(set(missing))[:50]:
            print(f"  MISSING: {rel} -> {dep}")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
