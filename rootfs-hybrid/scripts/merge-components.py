#!/usr/bin/env python3
"""
merge-components.py — manifest-driven component merger.

Reads config/components.yaml, copies every enabled component's matched files
from QT6_TARGET into the work rootfs (under fakeroot so ownership is recorded),
writes component reports, and emits the list of newly copied ELF files for the
dependency resolver.

Environment overrides (all optional):
  PROJECT_ROOT, QT6_TARGET, WORKDIR, ROOTFS_DIR, COMPONENTS_YAML,
  REPORTS_DIR, READELF, PYTHON_VERSION

Invocation (normal build path runs this under fakeroot):
  python3 merge-components.py [--dry-run]

Options:
  --dry-run     match/report only; no files are copied and no post_install runs
  --list        print component summary and exit
  --check NAME  report matches for one component and exit
"""
from __future__ import annotations

import argparse
import fnmatch
import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

DEFAULT_PROJECT_ROOT = "/home/buildroot/my_buildroot/workspace/buildroot-2024.08"
P = os.environ.get("PROJECT_ROOT", DEFAULT_PROJECT_ROOT)
QT6 = os.environ.get("QT6_TARGET", os.path.join(P, "output-qt6", "target"))
WORKDIR = os.environ.get("WORKDIR", os.path.join(P, "rootfs-hybrid"))
ROOTFS = os.environ.get("ROOTFS_DIR", os.path.join(WORKDIR, "rootfs"))
CONFIG = os.environ.get("COMPONENTS_YAML", os.path.join(WORKDIR, "config", "components.yaml"))
REPORTS = os.environ.get("REPORTS_DIR", os.path.join(WORKDIR, "reports"))
READELF = os.environ.get(
    "READELF",
    os.path.join(P, "output-qt6", "host", "bin", "loongarch64-loongson-linux-gnu-readelf"),
)
PYTHON_VERSION = os.environ.get("PYTHON_VERSION", "3.12")
ROOTS_OUT = os.path.join(REPORTS, "component-elf-roots.txt")


def normalize(rel: str) -> str:
    """Normalize a rootfs-relative path: strip leading/trailing slashes."""
    return rel.lstrip("/").rstrip("/")


def alias_paths(rel: str) -> set[str]:
    """Return logical aliases for a rel path (/lib and /usr/lib)."""
    rel = normalize(rel)
    out = {rel}
    if rel.startswith("usr/lib/"):
        out.add("lib/" + rel[len("usr/lib/") :])
    elif rel.startswith("lib/"):
        out.add("usr/lib/" + rel[len("lib/") :])
    return out


def matches_any(rel: str, patterns: list[str]) -> bool:
    for p in patterns:
        p = normalize(str(p))
        for alt in alias_paths(rel):
            if fnmatch.fnmatch(alt, p):
                return True
    return False


def expand_include(pattern: str) -> set[str]:
    rel = normalize(pattern)
    hits: set[str] = set()
    full = os.path.join(QT6, rel)
    for h in glob.glob(full, recursive=True):
        if not os.path.lexists(h):
            continue
        hits.add(normalize(os.path.relpath(h, QT6)))
    return hits


def load_config() -> dict:
    with open(CONFIG, encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}
    if not isinstance(cfg, dict):
        raise ValueError("components.yaml top level must be a mapping")
    if not isinstance(cfg.get("components", {}), dict):
        raise ValueError("components must be a mapping")
    return cfg


def is_elf(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def arch_ok(path: str) -> bool:
    try:
        cp = subprocess.run(
            [READELF, "-h", path], capture_output=True, text=True, timeout=20, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return False
    for line in cp.stdout.splitlines():
        if "Machine:" in line:
            return line.split("Machine:", 1)[1].strip() == "LoongArch"
    return False


def chown_root(path: str) -> None:
    try:
        os.chown(path, 0, 0, follow_symlinks=False)
    except (OSError, TypeError):
        try:
            os.chown(path, 0, 0)
        except OSError:
            pass


def remove_existing_destination(dst: str) -> None:
    if not os.path.lexists(dst):
        return
    if os.path.isdir(dst) and not os.path.islink(dst):
        shutil.rmtree(dst)
    else:
        os.remove(dst)


def copy_one(src: str, dst: str) -> None:
    if os.path.islink(src):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        target = os.readlink(src)
        remove_existing_destination(dst)
        os.symlink(target, dst)
        chown_root(dst)
        return

    if os.path.isdir(src):
        if os.path.lexists(dst) and not os.path.isdir(dst):
            remove_existing_destination(dst)
        os.makedirs(dst, exist_ok=True)
        try:
            os.chmod(dst, os.stat(src).st_mode & 0o7777)
        except OSError:
            pass
        chown_root(dst)
        return

    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.lexists(dst):
        remove_existing_destination(dst)
    shutil.copy2(src, dst, follow_symlinks=False)
    chown_root(dst)


def is_protected_dest(rel: str, protected: list[str]) -> bool:
    """Protected paths block overwrite of files already present in base rootfs."""
    if not matches_any(rel, protected):
        return False
    return os.path.lexists(os.path.join(ROOTFS, normalize(rel)))


def destination_rel(source_rel: str, destination: str | None) -> str:
    if not destination:
        return normalize(source_rel)
    # destination is explicitly a prefix, preserving the source relative path.
    return normalize(destination) + "/" + normalize(source_rel)


def usable_matches_for_pattern(spec: dict, protected: list[str], pattern: str) -> list[str]:
    """Return matches that survive exclude rules and protected-destination checks."""
    exclude = spec.get("exclude", []) or []
    destination = spec.get("destination")
    hits = expand_include(str(pattern))
    return sorted(
        r
        for r in hits
        if not matches_any(r, exclude)
        and not is_protected_dest(destination_rel(r, destination), protected)
    )


def required_misses(spec: dict, protected: list[str]) -> list[str]:
    """Return required glob patterns with no usable source match."""
    required = spec.get("require", []) or []
    if not isinstance(required, list):
        raise ValueError("component require must be a list")
    return [str(pat) for pat in required if not usable_matches_for_pattern(spec, protected, str(pat))]


def match_component(spec: dict, protected: list[str]) -> tuple[list[str], list[str]]:
    include = spec.get("include", []) or []
    exclude = spec.get("exclude", []) or []
    destination = spec.get("destination")
    if not isinstance(include, list) or not isinstance(exclude, list):
        raise ValueError("component include/exclude must be lists")

    matched: set[str] = set()
    for pat in include:
        matched |= expand_include(str(pat))

    kept: list[str] = []
    skipped: list[str] = []
    for r in sorted(matched):
        if matches_any(r, exclude):
            continue
        dst_rel = destination_rel(r, destination)
        if is_protected_dest(dst_rel, protected):
            skipped.append(dst_rel)
            continue
        kept.append(r)
    return kept, skipped


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--check", metavar="NAME")
    args = ap.parse_args()

    try:
        cfg = load_config()
    except Exception as exc:
        print(f"ERROR: cannot load {CONFIG}: {exc}", file=sys.stderr)
        return 1

    protected = cfg.get("protected_paths", []) or []
    components = cfg.get("components", {}) or {}

    if args.list:
        for name, spec in components.items():
            print(
                "%-16s enabled=%-5s optional=%-5s include=%d require=%d"
                % (
                    name,
                    spec.get("enabled", True),
                    spec.get("optional", False),
                    len(spec.get("include", []) or []),
                    len(spec.get("require", []) or []),
                )
            )
        return 0

    if args.check:
        if args.check not in components:
            print("ERROR: unknown component '%s'" % args.check)
            return 1
        spec = components[args.check]
        kept, skipped = match_component(spec, protected)
        misses = []
        for pat in spec.get("include", []) or []:
            if not usable_matches_for_pattern(spec, protected, str(pat)):
                misses.append(str(pat))
        req_misses = required_misses(spec, protected)
        print("component: %s" % args.check)
        print("  include patterns: %d" % len(spec.get("include", []) or []))
        print("  required patterns: %d" % len(spec.get("require", []) or []))
        print("  kept paths: %d" % len(kept))
        print("  protected-existing paths skipped: %d" % len(skipped))
        print("  include patterns with no kept paths: %d" % len(misses))
        for p in misses:
            print("    (no files) %s" % p)
        print("  REQUIRED patterns missing: %d" % len(req_misses))
        for p in req_misses:
            print("    (REQUIRED MISSING) %s" % p)
        for r in kept[:25]:
            print("    %s" % r)
        if len(kept) > 25:
            print("    ... (%d more)" % (len(kept) - 25))
        return 2 if req_misses else 0

    installed: dict[str, list[str]] = {}
    missing: list[str] = []
    missing_required: list[str] = []
    skipped_protected: list[str] = []
    bad_arch: list[str] = []
    elf_roots: list[str] = []

    for name, spec in components.items():
        if not spec.get("enabled", True):
            continue
        optional = bool(spec.get("optional", False))
        destination = spec.get("destination")
        post_install = spec.get("post_install")

        try:
            kept, skipped = match_component(spec, protected)
            req_misses = required_misses(spec, protected)
        except Exception as exc:
            print(f"[FAIL] component '{name}': {exc}")
            return 1
        skipped_protected.extend(f"{name}: {r}" for r in skipped)

        if req_misses:
            for pat in req_misses:
                missing_required.append(f"{name}: {pat}")
            print("[FAIL] component '%s': %d required runtime pattern(s) missing" % (name, len(req_misses)))
            for pat in req_misses:
                print("       REQUIRED MISSING: %s" % pat)
            installed[name] = kept
            continue

        if not kept:
            if optional:
                print("[warn] component '%s': optional, no files matched (skipped)" % name)
            else:
                missing.append(name)
                print("[FAIL] component '%s': required, no files matched" % name)
            installed[name] = []
            continue

        installed[name] = kept
        print("[ok] component '%s': %d paths" % (name, len(kept)))
        if args.dry_run:
            continue

        for r in kept:
            src = os.path.join(QT6, normalize(r))
            dst_rel = destination_rel(r, destination)
            dst = os.path.join(ROOTFS, dst_rel)
            copy_one(src, dst)
            if is_elf(src) and not os.path.islink(src):
                elf_roots.append(dst)
                if not arch_ok(dst):
                    bad_arch.append(dst_rel)

        # Preserve directory modes. Respect destination prefix here as well.
        for r in kept:
            src = os.path.join(QT6, normalize(r))
            if not os.path.isdir(src) or os.path.islink(src):
                continue
            dst_rel = destination_rel(r, destination)
            dst = os.path.join(ROOTFS, dst_rel)
            os.makedirs(dst, exist_ok=True)
            try:
                os.chmod(dst, os.stat(src).st_mode & 0o7777)
            except OSError:
                pass
            chown_root(dst)

        if post_install:
            env = dict(os.environ)
            env.update(
                {
                    "ROOTFS": ROOTFS,
                    "QT6_TARGET": QT6,
                    "WORKDIR": WORKDIR,
                    "PYTHON_VERSION": PYTHON_VERSION,
                }
            )
            rc = subprocess.call(["bash", "-euo", "pipefail", "-c", post_install], env=env)
            if rc != 0:
                print("[FAIL] component '%s': post_install returned %d" % (name, rc))
                return 1

    os.makedirs(REPORTS, exist_ok=True)
    with open(os.path.join(REPORTS, "components-installed.txt"), "w", encoding="utf-8") as f:
        f.write("# components-installed.txt\n")
        for name, files in installed.items():
            f.write("\n[%s] %d paths\n" % (name, len(files)))
            for r in files:
                f.write("  %s\n" % r)

    with open(os.path.join(REPORTS, "components-missing.txt"), "w", encoding="utf-8") as f:
        f.write("# components-missing.txt (required components with no matched files)\n")
        for name in missing:
            f.write("%s\n" % name)

    with open(os.path.join(REPORTS, "components-required-missing.txt"), "w", encoding="utf-8") as f:
        f.write("# components-required-missing.txt (header-only = all required runtime patterns present)\n")
        for item in missing_required:
            f.write(item + "\n")

    with open(
        os.path.join(REPORTS, "components-protected-skipped.txt"), "w", encoding="utf-8"
    ) as f:
        f.write("# existing protected destinations skipped by component copy\n")
        for item in sorted(set(skipped_protected)):
            f.write(item + "\n")

    # Dry-run intentionally writes reports, but never writes an ELF-root state file.
    if args.dry_run:
        if os.path.exists(ROOTS_OUT):
            os.remove(ROOTS_OUT)
    else:
        with open(ROOTS_OUT, "w", encoding="utf-8") as f:
            for e in sorted(set(elf_roots)):
                f.write(e + "\n")

    print()
    print("components-installed.txt        : %s" % os.path.join(REPORTS, "components-installed.txt"))
    print("components-missing.txt          : %s" % os.path.join(REPORTS, "components-missing.txt"))
    print("components-required-missing.txt : %s" % os.path.join(REPORTS, "components-required-missing.txt"))
    print("protected-skipped               : %d" % len(set(skipped_protected)))
    print("elf-roots for resolver          : %d" % (0 if args.dry_run else len(set(elf_roots))))

    if bad_arch:
        print("BAD ARCHITECTURE files:")
        for r in sorted(set(bad_arch)):
            print("  %s" % r)
        return 1
    if missing_required:
        print("FATAL: %d required runtime pattern(s) missing" % len(missing_required))
        return 1
    if missing and not args.dry_run:
        print("FATAL: %d required component(s) had no files" % len(missing))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
