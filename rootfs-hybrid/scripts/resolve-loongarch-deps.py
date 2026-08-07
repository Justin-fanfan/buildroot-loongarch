#!/usr/bin/env python3
"""
Resolve DT_NEEDED dependencies for ELF files added by merge-components.py.

Key safety properties:
- Existing rootfs libraries are preferred.
- Protected base runtime libraries are never imported from QT6_TARGET.
- The resolver never overwrites an existing destination file; component-level
  replacement must be explicit in components.yaml.
- Symlink families are copied from the directory where the selected candidate
  actually lives (not only QT6_TARGET/usr/lib).
- Source locations under QT6_TARGET are preserved in the merged rootfs, which
  keeps private package RPATH/$ORIGIN layouts intact.

Environment overrides: PROJECT_ROOT, QT6_TARGET, WORKDIR, ROOTFS_DIR,
REPORTS_DIR, READELF, PYTHON_VERSION.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

DEFAULT_PROJECT_ROOT = "/home/buildroot/my_buildroot/workspace/buildroot-2024.08"
P = os.environ.get("PROJECT_ROOT", DEFAULT_PROJECT_ROOT)
QT6 = os.environ.get("QT6_TARGET", os.path.join(P, "output-qt6", "target"))
WORKDIR = os.environ.get("WORKDIR", os.path.join(P, "rootfs-hybrid"))
ROOTFS = os.environ.get("ROOTFS_DIR", os.path.join(WORKDIR, "rootfs"))
REPORTS = os.environ.get("REPORTS_DIR", os.path.join(WORKDIR, "reports"))
PYTHON_VERSION = os.environ.get("PYTHON_VERSION", "3.12")
READELF = os.environ.get(
    "READELF",
    os.path.join(P, "output-qt6", "host", "bin", "loongarch64-loongson-linux-gnu-readelf"),
)

REPORT = os.path.join(REPORTS, "dependency-resolution.txt")
REPORT_COPIED = os.path.join(REPORTS, "dependencies-copied.txt")
REPORT_COPIED_PATHS = os.path.join(REPORTS, "dependencies-copied-paths.txt")
REPORT_UNRES = os.path.join(REPORTS, "dependencies-unresolved.txt")
ROOTS_IN = os.path.join(REPORTS, "component-elf-roots.txt")

PROTECTED_BASENAMES = {"ld-linux-loongarch-lp64d.so.1"}
PROTECTED_PREFIXES = (
    "libc.so",
    "libpthread.so",
    "libm.so",
    "librt.so",
    "libdl.so",
    "libresolv.so",
    "libnss_",
    "libgcc_s.so",
    "libstdc++",
    "libsystemd",
    "libpam",
    "libpamc",
    "libpam_misc",
    "libutil",
    "libanl",
    "libcrypt",
    "libnsl",
    "libthread_db",
)
SKIP_DEPS = {"linux-vdso.so.1", "ld-linux-loongarch-lp64d.so.1"}


@dataclass(frozen=True)
class Candidate:
    path: str
    in_rootfs: bool
    priority: int


def is_elf(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def readelf_dynamic(path: str) -> tuple[list[str], str | None]:
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


def tree_resolve(path: str, tree_root: str, max_hops: int = 32) -> str | None:
    """Resolve symlinks while interpreting absolute links inside tree_root."""
    cur = os.path.normpath(path)
    seen: set[str] = set()
    for _ in range(max_hops):
        if cur in seen:
            return None
        seen.add(cur)
        if not os.path.lexists(cur):
            return None
        if not os.path.islink(cur):
            return os.path.normpath(cur)
        target = os.readlink(cur)
        if os.path.isabs(target):
            cur = os.path.join(tree_root, target.lstrip("/"))
        else:
            cur = os.path.normpath(os.path.join(os.path.dirname(cur), target))
    return None


def source_priority(path: str, in_rootfs: bool) -> int:
    if in_rootfs:
        return 0
    rel = os.path.relpath(path, QT6)
    parent = os.path.dirname(rel)
    if parent == "usr/lib":
        return 10
    if parent == "lib":
        return 20
    # Private package lib directories are fallback candidates only.
    return 30


def library_dirs(tree: str) -> list[str]:
    dirs = [os.path.join(tree, "usr/lib"), os.path.join(tree, "lib")]
    sp = os.path.join(tree, f"usr/lib/python{PYTHON_VERSION}/site-packages")
    if os.path.isdir(sp):
        for entry in sorted(os.listdir(sp)):
            p = os.path.join(sp, entry, "lib")
            if os.path.isdir(p):
                dirs.append(p)
    return dirs


def collect_candidates() -> dict[str, list[Candidate]]:
    idx: dict[str, list[Candidate]] = {}

    def add_dir(dirpath: str, tree_root: str, in_rootfs: bool) -> None:
        if not os.path.isdir(dirpath):
            return
        for name in sorted(os.listdir(dirpath)):
            full = os.path.join(dirpath, name)
            if not (os.path.isfile(full) or os.path.islink(full)):
                continue
            if not (name.startswith("lib") and ".so" in name):
                continue
            c = Candidate(full, in_rootfs, source_priority(full, in_rootfs))
            # DT_NEEDED is resolved by file name at runtime.  Do not treat a
            # different real-file basename as satisfying a missing SONAME link.
            idx.setdefault(name, []).append(c)

    for d in library_dirs(ROOTFS):
        add_dir(d, ROOTFS, True)
    for d in library_dirs(QT6):
        add_dir(d, QT6, False)

    for key in idx:
        idx[key] = sorted(set(idx[key]), key=lambda c: (c.priority, c.path))
    return idx


def pick(entries: list[Candidate] | None) -> Candidate | None:
    return entries[0] if entries else None


def chown_root(path: str) -> None:
    try:
        os.chown(path, 0, 0, follow_symlinks=False)
    except (OSError, TypeError):
        try:
            os.chown(path, 0, 0)
        except OSError:
            pass


def qt6_destination(src: str) -> str:
    rel = os.path.relpath(src, QT6)
    if rel.startswith("../") or rel == "..":
        raise ValueError(f"source is outside QT6_TARGET: {src}")
    return os.path.join(ROOTFS, rel)


def same_family_members(chosen: str) -> list[str]:
    """Return files/symlinks in chosen's directory resolving to same real file."""
    resolved = tree_resolve(chosen, QT6)
    if not resolved:
        return [chosen]
    srcdir = os.path.dirname(chosen)
    family: list[str] = []
    try:
        names = os.listdir(srcdir)
    except OSError:
        return [chosen]
    for name in names:
        full = os.path.join(srcdir, name)
        if not (os.path.isfile(full) or os.path.islink(full)):
            continue
        if tree_resolve(full, QT6) == resolved:
            family.append(full)
    if resolved.startswith(QT6 + os.sep) and resolved not in family:
        family.append(resolved)
    return sorted(set(family))


def copy_one_no_overwrite(src: str) -> tuple[str, bool]:
    dst = qt6_destination(src)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.lexists(dst):
        return dst, False
    if os.path.islink(src):
        os.symlink(os.readlink(src), dst)
    else:
        shutil.copy2(src, dst, follow_symlinks=False)
    chown_root(dst)
    return dst, True


def load_roots() -> list[str]:
    roots: list[str] = []
    if os.path.isfile(ROOTS_IN):
        with open(ROOTS_IN, encoding="utf-8") as f:
            for line in f:
                p = line.strip()
                if p and os.path.isfile(p) and is_elf(p):
                    roots.append(p)
    return sorted(set(roots))


def main() -> int:
    os.makedirs(REPORTS, exist_ok=True)
    roots = load_roots()
    if not roots:
        print(f"ERROR: no component ELF roots found in {ROOTS_IN}", file=sys.stderr)
        return 2

    idx = collect_candidates()
    satisfied: set[tuple[str, str, str]] = set()
    unresolved: set[tuple[str, str]] = set()
    copied_paths: set[str] = set()
    visited: set[str] = set()

    def resolve_source(path: str) -> None:
        resolved = tree_resolve(path, QT6) if path.startswith(QT6 + os.sep) else path
        scan_path = resolved or path
        key = os.path.normpath(scan_path)
        if key in visited:
            return
        visited.add(key)
        needed, _ = readelf_dynamic(scan_path)
        for dep in needed:
            if dep in SKIP_DEPS:
                continue
            chosen = pick(idx.get(dep))
            if chosen is None:
                unresolved.add((path, dep))
                continue
            if chosen.in_rootfs:
                satisfied.add((path, dep, chosen.path))
                continue

            base = os.path.basename(chosen.path)
            if base in PROTECTED_BASENAMES or base.startswith(PROTECTED_PREFIXES):
                unresolved.add(
                    (
                        path,
                        dep + " (protected base runtime missing in rootfs; refused target copy)",
                    )
                )
                continue

            # Resolve the dependency's own closure before copying its family.
            resolve_source(chosen.path)
            for member in same_family_members(chosen.path):
                try:
                    dst, was_copied = copy_one_no_overwrite(member)
                except Exception as exc:
                    unresolved.add((path, f"{dep} (copy failed: {exc})"))
                    continue
                if was_copied:
                    copied_paths.add(dst)

    # Component roots live in ROOTFS, but their missing dependencies are found in
    # the candidate index. For recursive target libraries, resolve_source handles
    # QT6_TARGET paths directly.
    for root in roots:
        needed, _ = readelf_dynamic(root)
        for dep in needed:
            if dep in SKIP_DEPS:
                continue
            chosen = pick(idx.get(dep))
            if chosen is None:
                unresolved.add((root, dep))
                continue
            if chosen.in_rootfs:
                satisfied.add((root, dep, chosen.path))
                continue
            base = os.path.basename(chosen.path)
            if base in PROTECTED_BASENAMES or base.startswith(PROTECTED_PREFIXES):
                unresolved.add(
                    (
                        root,
                        dep + " (protected base runtime missing in rootfs; refused target copy)",
                    )
                )
                continue
            resolve_source(chosen.path)
            for member in same_family_members(chosen.path):
                try:
                    dst, was_copied = copy_one_no_overwrite(member)
                except Exception as exc:
                    unresolved.add((root, f"{dep} (copy failed: {exc})"))
                    continue
                if was_copied:
                    copied_paths.add(dst)

    with open(REPORT, "w", encoding="utf-8") as f:
        f.write("# LoongArch64 dynamic dependency resolution\n")
        f.write(f"# rootfs={ROOTFS}\n# qt6={QT6}\n")
        f.write(f"\n## Newly-added ELF roots scanned: {len(roots)}\n")
        f.write(f"\n## Deps satisfied by existing rootfs: {len(satisfied)}\n")
        f.write(f"\n## Copied paths from QT6_TARGET: {len(copied_paths)}\n")
        for p in sorted(copied_paths):
            f.write("  " + os.path.relpath(p, ROOTFS) + "\n")
        f.write(f"\n## UNRESOLVED dependencies: {len(unresolved)}\n")
        for path, dep in sorted(unresolved):
            disp = os.path.relpath(path, ROOTFS) if path.startswith(ROOTFS + os.sep) else path
            f.write(f"  {disp}  ->  {dep}\n")
        f.write(f"\n## Rootfs-satisfied deps (all {len(satisfied)})\n")
        for path, dep, chosen in sorted(satisfied):
            disp = os.path.relpath(path, ROOTFS) if path.startswith(ROOTFS + os.sep) else path
            f.write(f"  {disp} : {dep} <= {os.path.relpath(chosen, ROOTFS)}\n")

    with open(REPORT_COPIED, "w", encoding="utf-8") as f:
        f.write("# dependencies-copied.txt (rootfs-relative paths copied from QT6_TARGET)\n")
        for p in sorted(copied_paths):
            f.write(os.path.relpath(p, ROOTFS) + "\n")

    with open(REPORT_COPIED_PATHS, "w", encoding="utf-8") as f:
        for p in sorted(copied_paths):
            if os.path.isfile(p) and is_elf(p):
                f.write(p + "\n")

    with open(REPORT_UNRES, "w", encoding="utf-8") as f:
        f.write("# dependencies-unresolved.txt (header-only = all resolved)\n")
        for path, dep in sorted(unresolved):
            disp = os.path.relpath(path, ROOTFS) if path.startswith(ROOTFS + os.sep) else path
            f.write(f"{disp} -> {dep}\n")

    print(f"REPORT={REPORT}")
    print(
        "roots=%d rootfs-satisfied=%d copied=%d unresolved=%d"
        % (len(roots), len(satisfied), len(copied_paths), len(unresolved))
    )
    for path, dep in sorted(unresolved):
        disp = os.path.relpath(path, ROOTFS) if path.startswith(ROOTFS + os.sep) else path
        print(f"  UNRESOLVED: {disp} -> {dep}")
    return 2 if unresolved else 0


if __name__ == "__main__":
    sys.exit(main())
