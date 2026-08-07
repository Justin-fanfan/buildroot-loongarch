#!/usr/bin/env python3
"""Architecture and LSX/LASX audit for the hybrid rootfs.

- Architecture: scans every regular ELF in rootfs and requires Machine=LoongArch.
- ISA: scans ELF files added by manifest merge + dependency resolver and rejects
  any disassembled LoongArch vector mnemonic beginning with v* or xv*.
  On LoongArch these mnemonics belong to LSX/LASX; this is broader than only
  checking vld/vst/xvld/xvst.

Set STRICT_ISA_SCAN_ALL=1 to scan every rootfs ELF for LSX/LASX as well.
Environment overrides: PROJECT_ROOT, WORKDIR, ROOTFS_DIR, REPORTS_DIR,
READELF, OBJDUMP.
"""
from __future__ import annotations

import os
import re
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
OBJDUMP = os.environ.get(
    "OBJDUMP",
    os.path.join(P, "output-qt6", "host", "bin", "loongarch64-loongson-linux-gnu-objdump"),
)
ARCH_OUT = os.path.join(REPORTS, "arch-scan.txt")
ISA_OUT = os.path.join(REPORTS, "lsx-scan.txt")
ROOT_FILES = [
    os.path.join(REPORTS, "component-elf-roots.txt"),
    os.path.join(REPORTS, "dependencies-copied-paths.txt"),
]
STRICT_ALL = os.environ.get("STRICT_ISA_SCAN_ALL", "0") == "1"
VECTOR_MNEMONIC = re.compile(r"^(?:v|xv)[a-z0-9_.]+$", re.IGNORECASE)
DIS_LINE = re.compile(r"^\s*[0-9a-f]+:\s+([^\s]+)")


def is_elf(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def all_elfs() -> list[str]:
    out: list[str] = []
    for base, dirs, files in os.walk(ROOTFS):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(base, d))]
        for name in files:
            p = os.path.join(base, name)
            if not os.path.islink(p) and is_elf(p):
                out.append(p)
    return sorted(out)


def machine(path: str) -> str | None:
    try:
        cp = subprocess.run(
            [READELF, "-h", path], capture_output=True, text=True, timeout=30, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return None
    for line in cp.stdout.splitlines():
        if "Machine:" in line:
            return line.split("Machine:", 1)[1].strip()
    return None


def added_elfs() -> list[str]:
    if STRICT_ALL:
        return all_elfs()
    roots: set[str] = set()
    for listfile in ROOT_FILES:
        if not os.path.isfile(listfile):
            continue
        with open(listfile, encoding="utf-8") as f:
            for line in f:
                p = line.strip()
                if p and os.path.isfile(p) and not os.path.islink(p) and is_elf(p):
                    roots.add(p)
    return sorted(roots)


def vector_mnemonics(path: str) -> set[str]:
    try:
        cp = subprocess.run(
            [OBJDUMP, "-d", "--no-show-raw-insn", path],
            capture_output=True,
            text=True,
            timeout=180,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return {"<objdump-failed>"}
    hits: set[str] = set()
    for line in cp.stdout.splitlines():
        m = DIS_LINE.match(line)
        if not m:
            continue
        mnemonic = m.group(1)
        if VECTOR_MNEMONIC.match(mnemonic):
            hits.add(mnemonic)
    if cp.returncode != 0 and not cp.stdout:
        hits.add("<objdump-failed>")
    return hits


def main() -> int:
    os.makedirs(REPORTS, exist_ok=True)
    elfs = all_elfs()
    bad_arch: list[tuple[str, str]] = []
    for p in elfs:
        m = machine(p) or "UNKNOWN"
        if m != "LoongArch":
            bad_arch.append((os.path.relpath(p, ROOTFS), m))
    with open(ARCH_OUT, "w", encoding="utf-8") as f:
        for rel, m in bad_arch:
            f.write(f"{rel} :: Machine={m}\n")

    isa_targets = added_elfs()
    isa_hits: list[tuple[str, list[str]]] = []
    for p in isa_targets:
        hits = vector_mnemonics(p)
        if hits:
            isa_hits.append((os.path.relpath(p, ROOTFS), sorted(hits)))
    with open(ISA_OUT, "w", encoding="utf-8") as f:
        for rel, hits in isa_hits:
            f.write(f"{rel} :: {','.join(hits)}\n")

    print(f"ELF architecture scan: {len(elfs)} files, non-LoongArch={len(bad_arch)}")
    print(
        f"LSX/LASX scan: {len(isa_targets)} {'all-rootfs' if STRICT_ALL else 'added'} ELF files, hits={len(isa_hits)}"
    )
    print(f"arch report: {ARCH_OUT}")
    print(f"ISA report : {ISA_OUT}")
    if bad_arch:
        for rel, m in bad_arch[:20]:
            print(f"  NON-LOONGARCH: {rel} ({m})")
    if isa_hits:
        for rel, hits in isa_hits[:20]:
            print(f"  VECTOR ISA: {rel} ({','.join(hits[:12])})")
    return 2 if bad_arch or isa_hits else 0


if __name__ == "__main__":
    sys.exit(main())
