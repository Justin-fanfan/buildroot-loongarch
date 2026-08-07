#!/usr/bin/env bash
# ============================================================================
# build-hybrid-rootfs.sh  (manifest-driven, repeatable hybrid rootfs builder)
#
# LoongArch64 / Loongson 2K0300 (LS2K300-PAI)
#
# Base   : known-good board rootfs.tar.gz + matching uImage/ramdisk.gz
# Add    : output-qt6/target components selected by config/components.yaml
# Result : $INSTALL_DIR/{uImage,rootfs.tar.gz,ramdisk.gz,SHA256SUMS}
#
# Usage:
#   ./build-hybrid-rootfs.sh build                full merge + verify + package
#   ./build-hybrid-rootfs.sh audit                input + Qt5 + manifest dry-run
#   ./build-hybrid-rootfs.sh clean                remove generated work only
#   ./build-hybrid-rootfs.sh list-components      list manifest components
#   ./build-hybrid-rootfs.sh check-component <n>  inspect one component match
#   ./build-hybrid-rootfs.sh print-config          show resolved paths/settings
#   ./build-hybrid-rootfs.sh help                  show this help
#
# Paths may be overridden with environment variables; defaults match the
# original project layout. The script never writes to QT6_TARGET or inputs.
# ============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (environment-overridable)
# ---------------------------------------------------------------------------
PROJECT_ROOT="${PROJECT_ROOT:-/home/buildroot/my_buildroot/workspace/buildroot-2024.08}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/output-qt6}"
QT6_TARGET="${QT6_TARGET:-$OUTPUT_DIR/target}"
NEW_ROOTFS_TAR="${NEW_ROOTFS_TAR:-/home/justin/new-board/rootfs.tar.gz}"
NEW_UIMAGE="${NEW_UIMAGE:-/home/justin/new-board/uImage}"
OFFICIAL_RAMDISK="${OFFICIAL_RAMDISK:-/home/justin/new-board/ramdisk.gz}"
WORKDIR="${WORKDIR:-$PROJECT_ROOT/rootfs-hybrid}"
ROOTFS_DIR="${ROOTFS_DIR:-$WORKDIR/rootfs}"
INSTALL_DIR="${INSTALL_DIR:-$WORKDIR/install}"
REPORTS_DIR="${REPORTS_DIR:-$WORKDIR/reports}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$WORKDIR/scripts}"
CONFIG_DIR="${CONFIG_DIR:-$WORKDIR/config}"
COMPONENTS_YAML="${COMPONENTS_YAML:-$CONFIG_DIR/components.yaml}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
KERNEL_VERSION="${KERNEL_VERSION:-}"
CROSS_PREFIX="${CROSS_PREFIX:-$OUTPUT_DIR/host/bin/loongarch64-loongson-linux-gnu}"
READELF="${READELF:-$CROSS_PREFIX-readelf}"
OBJDUMP="${OBJDUMP:-$CROSS_PREFIX-objdump}"
FAKEROOT_DB="${FAKEROOT_DB:-$WORKDIR/fakeroot.db}"
SP_TARGET="$ROOTFS_DIR/usr/lib/python$PYTHON_VERSION/site-packages"
SP_QT6="$QT6_TARGET/usr/lib/python$PYTHON_VERSION/site-packages"

CMD="${1:-build}"

export PROJECT_ROOT OUTPUT_DIR QT6_TARGET NEW_ROOTFS_TAR NEW_UIMAGE OFFICIAL_RAMDISK
export WORKDIR ROOTFS_DIR INSTALL_DIR REPORTS_DIR SCRIPTS_DIR CONFIG_DIR COMPONENTS_YAML
export PYTHON_VERSION KERNEL_VERSION CROSS_PREFIX READELF OBJDUMP FAKEROOT_DB

log() { echo; echo "### [$1] ${2:-}"; }
die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  sed -n 's/^#   \(\.\/build.*\)/  \1/p' "$0"
}

print_config() {
  cat <<EOF
PROJECT_ROOT=$PROJECT_ROOT
OUTPUT_DIR=$OUTPUT_DIR
QT6_TARGET=$QT6_TARGET
NEW_ROOTFS_TAR=$NEW_ROOTFS_TAR
NEW_UIMAGE=$NEW_UIMAGE
OFFICIAL_RAMDISK=$OFFICIAL_RAMDISK
WORKDIR=$WORKDIR
ROOTFS_DIR=$ROOTFS_DIR
INSTALL_DIR=$INSTALL_DIR
REPORTS_DIR=$REPORTS_DIR
SCRIPTS_DIR=$SCRIPTS_DIR
COMPONENTS_YAML=$COMPONENTS_YAML
PYTHON_VERSION=$PYTHON_VERSION
KERNEL_VERSION=${KERNEL_VERSION:-<auto-detect>}
READELF=$READELF
OBJDUMP=$OBJDUMP
EOF
}

# ---------------------------------------------------------------------------
# Safety / prerequisites. Command parsing happens before expensive checks so
# help/clean do not require build inputs to be present.
# ---------------------------------------------------------------------------
check_workdir_safety() {
  [ -n "$PROJECT_ROOT" ] || die "PROJECT_ROOT is empty"
  [ -n "$WORKDIR" ] || die "WORKDIR is empty"
  [ "$WORKDIR" != "/" ] || die "WORKDIR must not be /"
  [ "$WORKDIR" != "$PROJECT_ROOT" ] || die "WORKDIR must not equal PROJECT_ROOT"
  case "$WORKDIR" in
    "$PROJECT_ROOT"/*) : ;;
    *) die "WORKDIR must live under PROJECT_ROOT (WORKDIR=$WORKDIR)" ;;
  esac
  local d
  for d in "$ROOTFS_DIR" "$INSTALL_DIR" "$REPORTS_DIR" "$SCRIPTS_DIR" "$CONFIG_DIR"; do
    case "$d" in
      "$WORKDIR"/*) : ;;
      *) die "derived path must live under WORKDIR: $d" ;;
    esac
  done
  case "$FAKEROOT_DB" in
    "$WORKDIR"/*) : ;;
    *) die "FAKEROOT_DB must live under WORKDIR: $FAKEROOT_DB" ;;
  esac
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

require_yaml() {
  python3 -c 'import yaml' >/dev/null 2>&1 || die "python3 PyYAML required (pip install pyyaml)"
}

require_manifest() {
  [ -f "$COMPONENTS_YAML" ] || die "components.yaml missing: $COMPONENTS_YAML"
  require_cmd python3
  require_yaml
}

require_target() {
  [ -d "$QT6_TARGET" ] || die "QT6_TARGET missing: $QT6_TARGET"
}

require_build_inputs() {
  for f in "$NEW_ROOTFS_TAR" "$NEW_UIMAGE" "$OFFICIAL_RAMDISK"; do
    [ -f "$f" ] || die "missing input $f"
  done
  require_target
  require_manifest
  [ -x "$READELF" ] || die "cross readelf missing: $READELF"
  [ -x "$OBJDUMP" ] || die "cross objdump missing: $OBJDUMP"
  for s in merge-components.py resolve-loongarch-deps.py verify-rootfs-deps.py verify-loongarch-isa.py; do
    [ -f "$SCRIPTS_DIR/$s" ] || die "helper missing: $SCRIPTS_DIR/$s"
  done
  for c in fakeroot tar gzip file stat sha256sum strings awk sed grep find sort cmp xargs diff du tee head; do
    require_cmd "$c"
  done
}

fakeroot_run() {
  local opts=(-s "$FAKEROOT_DB")
  if [ -f "$FAKEROOT_DB" ]; then
    opts=(-i "$FAKEROOT_DB" -s "$FAKEROOT_DB")
  fi
  fakeroot "${opts[@]}" "$@"
}

# ---------------------------------------------------------------------------
# Phase 0: clean old generated state (never scripts/config/inputs)
# ---------------------------------------------------------------------------
clean_work() {
  log "0" "Cleaning generated work copy (inputs/scripts/config untouched)"
  rm -rf "$ROOTFS_DIR" "$INSTALL_DIR" "$REPORTS_DIR" "$FAKEROOT_DB"
  mkdir -p "$ROOTFS_DIR" "$REPORTS_DIR" "$INSTALL_DIR"
}

# ---------------------------------------------------------------------------
# Phase 1: validate/extract base and detect ABI/kernel facts
# ---------------------------------------------------------------------------
BOARD_GLIBC=""
TARGET_GLIBC=""
BOARD_GLIBCXX=""
BOARD_CXXABI=""
BASE_LIBSTDCXX_FILE=""
MAX_REQ_GLIBC="0"
MAX_REQ_GLIBCXX="0"
MAX_REQ_CXXABI="0"

validate_inputs() {
  log "1" "Validating inputs and extracting base rootfs"
  for f in "$NEW_ROOTFS_TAR" "$NEW_UIMAGE" "$OFFICIAL_RAMDISK"; do
    echo "--- $f"
    file "$f"
    stat -c "size=%s uid=%u gid=%g mode=%A" "$f"
  done
  sha256sum "$NEW_ROOTFS_TAR" "$NEW_UIMAGE" "$OFFICIAL_RAMDISK" > "$REPORTS_DIR/inputs.sha256"
  gzip -t "$NEW_ROOTFS_TAR" || die "rootfs.tar.gz is not valid gzip"
  gzip -t "$OFFICIAL_RAMDISK" || die "ramdisk.gz is not valid gzip"

  tar -tzf "$NEW_ROOTFS_TAR" > "$REPORTS_DIR/input-archive-list.txt" 2>/dev/null || die "cannot list base rootfs archive"
  awk '
    /^\.\/[^/]+\/?$/ {
      s=$0; sub(/^\.\//,"",s); sub(/\/$/,"",s); print s
    }
  ' "$REPORTS_DIR/input-archive-list.txt" | sort -u > "$REPORTS_DIR/top-level.txt"
  for d in bin boot etc lib usr; do
    grep -qxF "$d" "$REPORTS_DIR/top-level.txt" || die "archive missing ./$d"
  done
  if grep -qxF rootfs "$REPORTS_DIR/top-level.txt"; then
    die "archive has an extra rootfs/ top-level layer"
  fi

  fakeroot_run tar -xzf "$NEW_ROOTFS_TAR" -C "$ROOTFS_DIR" \
    --numeric-owner --same-owner --preserve-permissions --xattrs --acls \
    >"$REPORTS_DIR/extract.log" 2>&1 || {
      tail -20 "$REPORTS_DIR/extract.log" >&2 || true
      die "rootfs extraction failed"
    }

  [ -f "$ROOTFS_DIR/usr/lib/libc.so.6" ] || die "base libc.so.6 missing"
  BOARD_GLIBC=$(strings "$ROOTFS_DIR/usr/lib/libc.so.6" 2>/dev/null \
    | grep -oE 'version 2\.[0-9]+' | awk 'NR==1{print $2}' || true)
  [ -n "$BOARD_GLIBC" ] || die "cannot detect base glibc version"
  [ -f "$QT6_TARGET/usr/lib/libc.so.6" ] || die "QT6_TARGET libc.so.6 missing"
  TARGET_GLIBC=$(strings "$QT6_TARGET/usr/lib/libc.so.6" 2>/dev/null \
    | grep -oE 'version 2\.[0-9]+' | awk 'NR==1{print $2}' || true)
  [ -n "$TARGET_GLIBC" ] || die "cannot detect QT6_TARGET glibc version"
  [ "$TARGET_GLIBC" = "$BOARD_GLIBC" ] \
    || die "base glibc $BOARD_GLIBC != QT6_TARGET glibc $TARGET_GLIBC; refusing locale/userland merge"

  BOARD_GLIBCXX=$(strings "$ROOTFS_DIR/usr/lib/libstdc++.so.6" 2>/dev/null \
    | grep -oE 'GLIBCXX_[0-9.]+' | sed 's/GLIBCXX_//' | sort -V | awk 'END{print}' || true)
  BOARD_CXXABI=$(strings "$ROOTFS_DIR/usr/lib/libstdc++.so.6" 2>/dev/null \
    | grep -oE 'CXXABI_[0-9.]+' | sed 's/CXXABI_//' | sort -V | awk 'END{print}' || true)
  [ -n "$BOARD_GLIBCXX" ] || die "cannot detect base GLIBCXX version"
  [ -n "$BOARD_CXXABI" ] || die "cannot detect base CXXABI version"

  BASE_LIBSTDCXX_FILE=$(find "$ROOTFS_DIR/usr/lib" -maxdepth 1 -type f -name 'libstdc++.so.6.*' -print \
    | sort -V | awk 'END{print}')
  [ -n "$BASE_LIBSTDCXX_FILE" ] || die "base libstdc++ real file not found"

  [ -e "$ROOTFS_DIR/usr/bin/python$PYTHON_VERSION" ] \
    || die "base rootfs does not provide Python $PYTHON_VERSION"

  local modules_dir="$ROOTFS_DIR/usr/lib/modules"
  [ -d "$modules_dir" ] || die "base kernel module directory missing"
  if [ -z "$KERNEL_VERSION" ]; then
    mapfile -t _kernel_dirs < <(find "$modules_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
    [ "${#_kernel_dirs[@]}" -eq 1 ] \
      || die "expected exactly one kernel module directory; found ${#_kernel_dirs[@]} (${_kernel_dirs[*]:-none})"
    KERNEL_VERSION="${_kernel_dirs[0]}"
    export KERNEL_VERSION
  fi
  [ -d "$modules_dir/$KERNEL_VERSION" ] || die "kernel module dir missing: $KERNEL_VERSION"

  [ -f "$ROOTFS_DIR/boot/uImage" ] || die "base rootfs /boot/uImage missing"
  if ! cmp -s "$ROOTFS_DIR/boot/uImage" "$NEW_UIMAGE"; then
    die "base /boot/uImage does not match external NEW_UIMAGE"
  fi

  echo "board glibc=$BOARD_GLIBC target glibc=$TARGET_GLIBC GLIBCXX=$BOARD_GLIBCXX CXXABI=$BOARD_CXXABI"
  echo "board python=$PYTHON_VERSION kernel=$KERNEL_VERSION"
  echo "base libstdc++=$(basename "$BASE_LIBSTDCXX_FILE")"
}

# ---------------------------------------------------------------------------
# Phase 2: protected hashes
# ---------------------------------------------------------------------------
write_protected_hashes() {
  local out="$1"
  {
    sha256sum "$ROOTFS_DIR/boot/uImage"
    find -L "$ROOTFS_DIR/usr/lib/modules/$KERNEL_VERSION" -type f -print0 \
      | sort -z | xargs -0 -r sha256sum
    if [ -d "$ROOTFS_DIR/usr/lib/firmware" ]; then
      find -L "$ROOTFS_DIR/usr/lib/firmware" -type f -print0 \
        | sort -z | xargs -0 -r sha256sum
    fi
    sha256sum "$ROOTFS_DIR/usr/lib/ld-linux-loongarch-lp64d.so.1" \
              "$ROOTFS_DIR/usr/lib/libc.so.6" \
              "$BASE_LIBSTDCXX_FILE"
  } | sed "s#$ROOTFS_DIR/##" > "$out"
}

record_protected_before() {
  log "2" "Recording protected base hashes"
  write_protected_hashes "$REPORTS_DIR/protected-files-before.sha256"
}

# ---------------------------------------------------------------------------
# Phase 3: Qt5 audit
# ---------------------------------------------------------------------------
qt5_scan() {
  local out="$1"
  : > "$out"
  grep -rl -a "libQt5" \
    "$ROOTFS_DIR/usr/lib" "$ROOTFS_DIR/usr/bin" "$ROOTFS_DIR/usr/sbin" \
    "$ROOTFS_DIR/usr/local" "$ROOTFS_DIR/opt" "$ROOTFS_DIR/root" "$ROOTFS_DIR/etc" \
    2>/dev/null \
    | while IFS= read -r f; do
        if head -c4 "$f" 2>/dev/null | grep -q $'\x7fELF'; then
          local n
          n=$("$READELF" -d "$f" 2>/dev/null | grep NEEDED | grep -oE 'libQt5[^ ]+' | tr '\n' ' ') || true
          [ -n "$n" ] && echo "${f#$ROOTFS_DIR/} :: $n"
        fi
      done | sort -u > "$out" || true
}

audit_qt5() {
  log "3" "Auditing Qt5 consumers/autostart"
  qt5_scan "$REPORTS_DIR/qt5-consumers-before.txt"
  : > "$REPORTS_DIR/qt5-autostart-before.txt"
  grep -rl -iE 'Qt5|qt5|qmake|logo_player|driver_testcase|qt_movie|qt-movie|PyQt5|libQt5|mplayer|qtperf|qmlscene' \
    "$ROOTFS_DIR/etc/systemd/system" "$ROOTFS_DIR/usr/lib/systemd/system" \
    "$ROOTFS_DIR/etc/init.d" "$ROOTFS_DIR/etc/rc.d" "$ROOTFS_DIR/etc/profile" \
    "$ROOTFS_DIR/etc/profile.d" 2>/dev/null \
    | sed "s#$ROOTFS_DIR/##" >> "$REPORTS_DIR/qt5-autostart-before.txt" || true
  grep -n -iE 'Qt5|logo_player|mplayer|qtperf|qmlscene' "$ROOTFS_DIR/root/boot_run.sh" 2>/dev/null \
    >> "$REPORTS_DIR/qt5-autostart-before.txt" || true
  echo "Qt5 consumers before: $(wc -l < "$REPORTS_DIR/qt5-consumers-before.txt")"
  echo "Qt5 autostart refs    : $(wc -l < "$REPORTS_DIR/qt5-autostart-before.txt")"
}

# ---------------------------------------------------------------------------
# Phase 4/5: manifest merge + dependency resolution + ABI version verification
# ---------------------------------------------------------------------------
merge_components() {
  log "4" "Merging manifest components"
  fakeroot_run python3 "$SCRIPTS_DIR/merge-components.py" "$@"
}

resolve_deps() {
  log "5" "Resolving recursive DT_NEEDED dependencies"
  fakeroot_run python3 "$SCRIPTS_DIR/resolve-loongarch-deps.py"
}

version_le() {
  python3 - "$1" "$2" <<'PY'
import sys
try:
    a=[int(x) for x in sys.argv[1].split('.')]
    b=[int(x) for x in sys.argv[2].split('.')]
except ValueError:
    sys.exit(2)
n=max(len(a),len(b)); a += [0]*(n-len(a)); b += [0]*(n-len(b))
sys.exit(0 if a <= b else 1)
PY
}

version_max() {
  printf '%s\n%s\n' "$1" "$2" | sort -V | awk 'END{print}'
}

verify_added_compatibility() {
  log "5b" "Checking GLIBC/GLIBCXX/CXXABI requirements of added ELF files"
  local list="$REPORTS_DIR/added-elf-files.txt"
  {
    cat "$REPORTS_DIR/component-elf-roots.txt" 2>/dev/null || true
    cat "$REPORTS_DIR/dependencies-copied-paths.txt" 2>/dev/null || true
  } | awk 'NF && !seen[$0]++' > "$list"

  local scanned=0 failed=0 f v
  MAX_REQ_GLIBC="0"; MAX_REQ_GLIBCXX="0"; MAX_REQ_CXXABI="0"
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    scanned=$((scanned+1))
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      MAX_REQ_GLIBC=$(version_max "$MAX_REQ_GLIBC" "$v")
      if ! version_le "$v" "$BOARD_GLIBC"; then
        echo "INCOMPATIBLE: ${f#$ROOTFS_DIR/} needs GLIBC_$v > GLIBC_$BOARD_GLIBC" | tee -a "$REPORTS_DIR/compatibility-errors.txt"
        failed=1
      fi
    done < <("$READELF" --version-info "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sed 's/GLIBC_//' | sort -Vu || true)

    while IFS= read -r v; do
      [ -n "$v" ] || continue
      MAX_REQ_GLIBCXX=$(version_max "$MAX_REQ_GLIBCXX" "$v")
      if ! version_le "$v" "$BOARD_GLIBCXX"; then
        echo "INCOMPATIBLE: ${f#$ROOTFS_DIR/} needs GLIBCXX_$v > GLIBCXX_$BOARD_GLIBCXX" | tee -a "$REPORTS_DIR/compatibility-errors.txt"
        failed=1
      fi
    done < <("$READELF" --version-info "$f" 2>/dev/null | grep -oE 'GLIBCXX_[0-9.]+' | sed 's/GLIBCXX_//' | sort -Vu || true)

    while IFS= read -r v; do
      [ -n "$v" ] || continue
      MAX_REQ_CXXABI=$(version_max "$MAX_REQ_CXXABI" "$v")
      if ! version_le "$v" "$BOARD_CXXABI"; then
        echo "INCOMPATIBLE: ${f#$ROOTFS_DIR/} needs CXXABI_$v > CXXABI_$BOARD_CXXABI" | tee -a "$REPORTS_DIR/compatibility-errors.txt"
        failed=1
      fi
    done < <("$READELF" --version-info "$f" 2>/dev/null | grep -oE 'CXXABI_[0-9.]+' | sed 's/CXXABI_//' | sort -Vu || true)
  done < "$list"

  [ "$scanned" -gt 0 ] || die "no added ELF files available for compatibility verification"
  cat > "$REPORTS_DIR/compatibility-summary.txt" <<EOF
added_elf_scanned=$scanned
board_glibc=$BOARD_GLIBC
board_glibcxx=$BOARD_GLIBCXX
board_cxxabi=$BOARD_CXXABI
max_required_glibc=$MAX_REQ_GLIBC
max_required_glibcxx=$MAX_REQ_GLIBCXX
max_required_cxxabi=$MAX_REQ_CXXABI
compatible=$(( failed == 0 ? 1 : 0 ))
EOF
  [ "$failed" -eq 0 ] || die "added ELF ABI requirements exceed base runtime"
  echo "compatibility OK: $scanned added ELF files"
}

# ---------------------------------------------------------------------------
# Phase 6: Qt5 removal and mandatory post-removal consumer check
# ---------------------------------------------------------------------------
remove_qt5() {
  log "6" "Removing Qt5 runtime/demo environment"
  if grep -qE 'systemd|/init$|NetworkManager|systemctl|/sbin/' "$REPORTS_DIR/qt5-consumers-before.txt"; then
    die "core program depends on Qt5; refusing full Qt5 removal"
  fi

  {
    find "$ROOTFS_DIR/usr/lib" -maxdepth 1 -name 'libQt5*.so*' 2>/dev/null || true
    for b in qml qmlscene qmltime qmlpreview qmltestrunner xmlpatterns xmlpatternsvalidator qtperf_qt5 canbusutil ls_system_tool_qt; do
      [ -e "$ROOTFS_DIR/usr/bin/$b" ] && echo "$ROOTFS_DIR/usr/bin/$b"
    done
    [ -e "$ROOTFS_DIR/usr/lib/qt" ] && echo "$ROOTFS_DIR/usr/lib/qt/"
    [ -e "$ROOTFS_DIR/usr/qml" ] && echo "$ROOTFS_DIR/usr/qml/"
    for p in "$ROOTFS_DIR/root/logo_player" "$ROOTFS_DIR/root/mplayer" "$ROOTFS_DIR/root/mp4_sample_video" \
             "$SP_TARGET/PyQt5" "$SP_TARGET/PyQt5_sip-4.19.25.dist-info"; do
      [ -e "$p" ] && echo "$p"
    done
  } | sed "s#$ROOTFS_DIR/##" > "$REPORTS_DIR/qt5-files-before-removal.txt"

  fakeroot_run bash -euo pipefail -c '
    ROOTFS_DIR="$1"; SP_TARGET="$2"
    find "$ROOTFS_DIR/usr/lib" -maxdepth 1 -name "libQt5*.so*" -exec rm -f {} +
    for b in qml qmlscene qmltime qmlpreview qmltestrunner xmlpatterns xmlpatternsvalidator qtperf_qt5 canbusutil ls_system_tool_qt; do
      rm -f "$ROOTFS_DIR/usr/bin/$b"
    done
    rm -rf "$ROOTFS_DIR/usr/lib/qt" "$ROOTFS_DIR/usr/qml"
    rm -rf "$ROOTFS_DIR/root/logo_player" "$ROOTFS_DIR/root/mplayer" "$ROOTFS_DIR/root/mp4_sample_video"
    rm -rf "$SP_TARGET/PyQt5" "$SP_TARGET/PyQt5_sip-4.19.25.dist-info"
  ' _ "$ROOTFS_DIR" "$SP_TARGET"

  qt5_scan "$REPORTS_DIR/qt5-consumers-after.txt"
  local remain
  remain=$(wc -l < "$REPORTS_DIR/qt5-consumers-after.txt")
  echo "Qt5 consumers after: $remain"
  if [ "$remain" -ne 0 ]; then
    cat "$REPORTS_DIR/qt5-consumers-after.txt" >&2
    die "Qt5 consumers remain after Qt5 runtime removal"
  fi
}

# ---------------------------------------------------------------------------
# Phase 7: cleanup only merged package leftovers (do not mutate arbitrary base
# static libraries). Then perform full-rootfs dependency closure.
# ---------------------------------------------------------------------------
cleanup_files() {
  log "7" "Cleaning package-local development/test leftovers"
  fakeroot_run bash -euo pipefail -c '
    ROOTFS_DIR="$1"; PYVER="$2"
    NP="$ROOTFS_DIR/usr/lib/python$PYVER/site-packages/numpy"
    if [ -d "$NP" ]; then
      find "$NP" -type d -name tests -prune -exec rm -rf {} + 2>/dev/null || true
      rm -rf "$NP/doc" "$NP/core/include" 2>/dev/null || true
      rm -f "$NP/f2py/src/fortranobject.h" 2>/dev/null || true
    fi
  ' _ "$ROOTFS_DIR" "$PYTHON_VERSION"
}

verify_full_dependencies() {
  log "8" "Verifying full-rootfs DT_NEEDED closure after Qt5 removal/cleanup"
  python3 "$SCRIPTS_DIR/verify-rootfs-deps.py"
}

# ---------------------------------------------------------------------------
# Phase 9: architecture and full LSX/LASX mnemonic audit for added ELFs
# ---------------------------------------------------------------------------
arch_checks() {
  log "9" "Architecture + LSX/LASX checks"
  python3 "$SCRIPTS_DIR/verify-loongarch-isa.py"
}

# ---------------------------------------------------------------------------
# Phase 10: protected files and locale integration
# ---------------------------------------------------------------------------
verify_protected() {
  log "10" "Re-verifying protected base files"
  write_protected_hashes "$REPORTS_DIR/protected-files-after.sha256"
  if ! diff -q "$REPORTS_DIR/protected-files-before.sha256" "$REPORTS_DIR/protected-files-after.sha256" >/dev/null; then
    diff -u "$REPORTS_DIR/protected-files-before.sha256" "$REPORTS_DIR/protected-files-after.sha256" \
      > "$REPORTS_DIR/protected-files.diff" || true
    die "protected base files changed (see protected-files.diff)"
  fi

  mapfile -t _module_dirs < <(find "$ROOTFS_DIR/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
  [ "${#_module_dirs[@]}" -eq 1 ] && [ "${_module_dirs[0]}" = "$KERNEL_VERSION" ] \
    || die "stray kernel module directory present: ${_module_dirs[*]:-none}"
  echo "protected files unchanged"
}

verify_locale_in_rootfs() {
  log "10b" "Verifying Qt6 UTF-8 locale payload"
  local archive="$ROOTFS_DIR/usr/lib/locale/locale-archive"
  local profile="$ROOTFS_DIR/etc/profile.d/locale.sh"
  [ -s "$archive" ] || die "locale archive missing/empty: /usr/lib/locale/locale-archive"
  [ -f "$profile" ] || die "locale profile missing: /etc/profile.d/locale.sh"
  grep -qxF 'export LANG=C.UTF-8' "$profile" || die "locale.sh does not export LANG=C.UTF-8"
  stat -c 'locale-archive size=%s mode=%a' "$archive" > "$REPORTS_DIR/locale-validation.txt"
  sha256sum "$archive" >> "$REPORTS_DIR/locale-validation.txt"
  echo 'LANG=C.UTF-8' >> "$REPORTS_DIR/locale-validation.txt"
  local host_localedef="${HOST_LOCALEDEF:-$OUTPUT_DIR/host/bin/localedef}"
  if [ -x "$host_localedef" ]; then
    if "$host_localedef" --list-archive --prefix="$ROOTFS_DIR" > "$REPORTS_DIR/locale-archive-list.txt" 2>/dev/null; then
      if grep -qiE '^C\.(UTF-8|utf8)$' "$REPORTS_DIR/locale-archive-list.txt"; then
        echo 'archive_contains_C.UTF-8=yes' >> "$REPORTS_DIR/locale-validation.txt"
      else
        die "locale archive does not contain C.UTF-8/C.utf8"
      fi
    else
      echo 'archive_list_check=host-localedef-failed (size/hash checks still passed)' >> "$REPORTS_DIR/locale-validation.txt"
    fi
  else
    echo 'archive_list_check=host-localedef-unavailable (size/hash checks only)' >> "$REPORTS_DIR/locale-validation.txt"
  fi
}

# ---------------------------------------------------------------------------
# Phase 11: package + archive acceptance
# ---------------------------------------------------------------------------
archive_has_exact() {
  grep -qxF "$1" "$REPORTS_DIR/final-archive-list.txt"
}

archive_has_regex() {
  grep -Eq "$1" "$REPORTS_DIR/final-archive-list.txt"
}

repackage() {
  log "11" "Repackaging and validating final artifacts"
  fakeroot_run tar -czf "$INSTALL_DIR/rootfs.tar.gz" \
    --numeric-owner --preserve-permissions --xattrs --acls \
    -C "$ROOTFS_DIR" . 2>"$REPORTS_DIR/repack.log" \
    || { tail -20 "$REPORTS_DIR/repack.log" >&2 || true; die "repack tar failed"; }

  gzip -t "$INSTALL_DIR/rootfs.tar.gz" || die "repacked rootfs gzip invalid"
  tar -tzf "$INSTALL_DIR/rootfs.tar.gz" > "$REPORTS_DIR/final-archive-list.txt" 2>/dev/null \
    || die "cannot list final archive"

  local required=(
    "./boot/uImage"
    "./usr/lib/libQt6Core.so.6"
    "./usr/lib/qt6/plugins/platforms/libqlinuxfb.so"
    "./usr/lib/qt6/plugins/platforminputcontexts/libqtvirtualkeyboardplugin.so"
    "./usr/lib/python$PYTHON_VERSION/site-packages/sherpa_onnx/lib/_sherpa_onnx.so"
    "./usr/lib/libonnxruntime.so"
    "./usr/lib/locale/locale-archive"
    "./etc/profile.d/qt6.sh"
    "./etc/profile.d/locale.sh"
    "./usr/lib/modules/$KERNEL_VERSION/modules.order"
  )
  local p
  for p in "${required[@]}"; do
    archive_has_exact "$p" || die "$p missing in final archive"
  done
  archive_has_regex "^\\./usr/lib/python$PYTHON_VERSION/site-packages/numpy/.*(__init__\\.pyc|_multiarray_umath.*\\.so)$" \
    || die "NumPy runtime missing in final archive"
  archive_has_regex "^\\./usr/lib/python$PYTHON_VERSION/site-packages/cv2/.*/cv2.*loongarch64.*\\.so$" \
    || die "OpenCV Python extension missing in final archive"
  archive_has_regex "^\\./usr/lib/python$PYTHON_VERSION/site-packages/sounddevice(\\.pyc|[^/]*\\.pyc)$" \
    || die "sounddevice runtime missing in final archive"
  archive_has_regex '^\./usr/lib/libopencv_core\.so\.' || die "OpenCV core library missing"
  archive_has_regex '^\./usr/lib/libavcodec\.so\.' || die "FFmpeg libavcodec missing"

  if grep -Eq '^\./usr/lib/libQt5|^\./usr/lib/qt/|^\./usr/qml/' "$REPORTS_DIR/final-archive-list.txt"; then
    grep -E '^\./usr/lib/libQt5|^\./usr/lib/qt/|^\./usr/qml/' "$REPORTS_DIR/final-archive-list.txt" \
      > "$REPORTS_DIR/final-archive-forbidden-qt5.txt" || true
    die "Qt5 runtime paths remain in final archive"
  fi

  if grep -E '^\./usr/lib/modules/[^/]+/?$' "$REPORTS_DIR/final-archive-list.txt" \
      | grep -v -xF "./usr/lib/modules/$KERNEL_VERSION/" >/dev/null; then
    die "stray kernel module directory in final archive"
  fi

  local root_locale_sha tar_locale_sha
  root_locale_sha=$(sha256sum "$ROOTFS_DIR/usr/lib/locale/locale-archive" | awk '{print $1}')
  tar_locale_sha=$(tar -xOzf "$INSTALL_DIR/rootfs.tar.gz" ./usr/lib/locale/locale-archive | sha256sum | awk '{print $1}')
  [ "$root_locale_sha" = "$tar_locale_sha" ] || die "locale-archive changed/missing during packaging"

  cp -a "$NEW_UIMAGE" "$INSTALL_DIR/uImage"
  cp -a "$OFFICIAL_RAMDISK" "$INSTALL_DIR/ramdisk.gz"
  (
    cd "$INSTALL_DIR"
    sha256sum uImage rootfs.tar.gz ramdisk.gz > SHA256SUMS
    sha256sum -c SHA256SUMS
  ) > "$REPORTS_DIR/final-sha256-check.txt"
  echo "archive acceptance OK"
}

# ---------------------------------------------------------------------------
# Phase 12: report
# ---------------------------------------------------------------------------
count_noncomment() { awk 'NF && $0 !~ /^#/ {n++} END{print n+0}' "$1" 2>/dev/null || echo 0; }

write_report() {
  log "12" "Generating merge-report.md"
  local rf_size rt_size rt_sha ui_size ui_sha rd_size rd_sha
  local qt5cons qt5before qt5auto unres fullunres broken prot archbad lsxhits
  local compcount compmiss compcounts qt5removed locale_sha now

  rf_size=$(du -sb "$ROOTFS_DIR" | cut -f1)
  rt_size=$(stat -c %s "$INSTALL_DIR/rootfs.tar.gz"); rt_sha=$(sha256sum "$INSTALL_DIR/rootfs.tar.gz" | awk '{print $1}')
  ui_size=$(stat -c %s "$INSTALL_DIR/uImage"); ui_sha=$(sha256sum "$INSTALL_DIR/uImage" | awk '{print $1}')
  rd_size=$(stat -c %s "$INSTALL_DIR/ramdisk.gz"); rd_sha=$(sha256sum "$INSTALL_DIR/ramdisk.gz" | awk '{print $1}')
  qt5cons=$(wc -l < "$REPORTS_DIR/qt5-consumers-after.txt")
  qt5before=$(wc -l < "$REPORTS_DIR/qt5-consumers-before.txt")
  qt5auto=$(wc -l < "$REPORTS_DIR/qt5-autostart-before.txt")
  unres=$(awk '/^## UNRESOLVED dependencies:/{print $4; found=1} END{if(!found) print "UNKNOWN"}' "$REPORTS_DIR/dependency-resolution.txt")
  fullunres=$(awk '/^MISSING:/{n++} END{print n+0}' "$REPORTS_DIR/full-rootfs-deps.txt")
  broken=$(awk '/^BROKEN_SYMLINK:/{n++} END{print n+0}' "$REPORTS_DIR/full-rootfs-deps.txt")
  prot=$(diff -q "$REPORTS_DIR/protected-files-before.sha256" "$REPORTS_DIR/protected-files-after.sha256" >/dev/null 2>&1 && echo IDENTICAL || echo CHANGED)
  archbad=$(wc -l < "$REPORTS_DIR/arch-scan.txt")
  lsxhits=$(wc -l < "$REPORTS_DIR/lsx-scan.txt")
  compcount=$(awk '/^\[.*\]/{n++} END{print n+0}' "$REPORTS_DIR/components-installed.txt")
  compmiss=$(count_noncomment "$REPORTS_DIR/components-missing.txt")
  compcounts=$(awk '/^\[.*\]/{name=$1; gsub(/^\[|\]$/,"",name); printf "%s%s=%s",(n++?";":""),name,$2}' "$REPORTS_DIR/components-installed.txt" 2>/dev/null || true)
  qt5removed=$(awk 'NF{n++} END{print n+0}' "$REPORTS_DIR/qt5-files-before-removal.txt")
  locale_sha=$(sha256sum "$ROOTFS_DIR/usr/lib/locale/locale-archive" | awk '{print $1}')
  now=$(date -u +%Y-%m-%dT%H:%MZ)

  cat > "$REPORTS_DIR/merge-report.md" <<EOF
# LoongArch64 Buildroot Hybrid Rootfs Merge Report
Generated: $now
Builder: fixed manifest-driven pipeline (locale + closure + ISA hardening)

## Inputs
- rootfs.tar.gz : $NEW_ROOTFS_TAR
- uImage        : $NEW_UIMAGE
- ramdisk.gz    : $OFFICIAL_RAMDISK
- QT6_TARGET    : $QT6_TARGET
- manifest      : $COMPONENTS_YAML
- kernel        : $KERNEL_VERSION
- Python        : $PYTHON_VERSION

## Compatibility
- Base glibc: $BOARD_GLIBC; QT6_TARGET glibc: $TARGET_GLIBC (required equal for locale archive); max GLIBCXX: $BOARD_GLIBCXX; max CXXABI: $BOARD_CXXABI
- Added ELF max requirements: GLIBC $MAX_REQ_GLIBC; GLIBCXX $MAX_REQ_GLIBCXX; CXXABI $MAX_REQ_CXXABI
- Result: compatible

## Components
- enabled components merged/reported: $compcount
- required components missing: $compmiss
- summary: ${compcounts:-see components-installed.txt}

## UTF-8 locale / Qt6
- /usr/lib/locale/locale-archive: present, sha256 $locale_sha
- /etc/profile.d/locale.sh: exports LANG=C.UTF-8
- /etc/profile.d/qt6.sh: present
- This fixes the board-side Qt6 failure where C/ANSI_X3.4-1968 was detected because locale-archive was absent.

## Qt5 removal
- consumers before: $qt5before
- consumers after : $qt5cons (required 0)
- autostart refs before: $qt5auto
- removal inventory lines: $qt5removed

## Dependencies
- resolver unresolved: $unres
- full-rootfs DT_NEEDED unresolved after Qt5 cleanup: $fullunres
- broken shared-library symlinks: $broken
- reports: dependency-resolution.txt, full-rootfs-deps.txt

## Protected base files
- before/after: $prot
- kernel module directory: $KERNEL_VERSION only

## Architecture / ISA
- non-LoongArch ELF: $archbad
- added ELF files with LSX/LASX vector mnemonics: $lsxhits
- ISA scan detects all disassembled v*/xv* vector mnemonics, not only vld/vst/xvld/xvst.

## Artifacts
- extracted rootfs size: $rf_size bytes
- rootfs.tar.gz: $rt_size bytes; sha256 $rt_sha
- uImage: $ui_size bytes; sha256 $ui_sha
- ramdisk.gz: $rd_size bytes; sha256 $rd_sha
- SHA256SUMS: $INSTALL_DIR/SHA256SUMS

## Board verification after deployment
\`\`\`sh
echo "LANG=\$LANG LC_ALL=\$LC_ALL"
python3 - <<'PY'
import locale
print("setlocale =", locale.setlocale(locale.LC_ALL, ''))
print("encoding  =", locale.getpreferredencoding(False))
PY
# Expected after a fresh login: setlocale=C.UTF-8, encoding=UTF-8

ldd /usr/lib/libQt6Core.so.6
ldd /usr/lib/qt6/plugins/platforms/libqlinuxfb.so
python3 - <<'PY'
import numpy
print("numpy:", numpy.__version__, numpy.arange(100,dtype=numpy.float32).sum())
PY
python3 - <<'PY'
import cv2
print("opencv:", cv2.__version__)
PY
python3 - <<'PY'
import sounddevice
print("sounddevice:", sounddevice.__version__)
print(sounddevice.query_devices())
PY
python3 - <<'PY'
import sherpa_onnx
print("sherpa_onnx:", sherpa_onnx.__file__)
PY
source /etc/profile.d/qt6.sh
./qt_first_project
\`\`\`

For a systemd-launched Qt application, also set \`Environment=LANG=C.UTF-8\` in that application's service unit.
EOF
  echo "merge-report.md written: $REPORTS_DIR/merge-report.md"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
check_workdir_safety

case "$CMD" in
  help|-h|--help)
    usage
    exit 0
    ;;

  print-config)
    print_config
    exit 0
    ;;

  clean)
    clean_work
    echo "generated work cleaned; inputs/scripts/config untouched"
    exit 0
    ;;

  list-components)
    require_manifest
    export PROJECT_ROOT QT6_TARGET WORKDIR ROOTFS_DIR REPORTS_DIR COMPONENTS_YAML READELF PYTHON_VERSION
    python3 "$SCRIPTS_DIR/merge-components.py" --list
    exit $?
    ;;

  check-component)
    [ $# -ge 2 ] || { echo "usage: $0 check-component <name>" >&2; exit 1; }
    require_manifest
    require_target
    export PROJECT_ROOT QT6_TARGET WORKDIR ROOTFS_DIR REPORTS_DIR COMPONENTS_YAML READELF PYTHON_VERSION
    python3 "$SCRIPTS_DIR/merge-components.py" --check "$2"
    exit $?
    ;;

  audit)
    require_build_inputs
    clean_work
    validate_inputs
    record_protected_before
    audit_qt5
    merge_components --dry-run
    local_missing=$(count_noncomment "$REPORTS_DIR/components-missing.txt")
    echo
    echo "### [audit] summary"
    echo "required components missing : $local_missing"
    echo "Qt5 consumers before       : $(wc -l < "$REPORTS_DIR/qt5-consumers-before.txt")"
    echo "Qt5 autostart refs         : $(wc -l < "$REPORTS_DIR/qt5-autostart-before.txt")"
    if [ "$local_missing" -ne 0 ]; then
      echo "Missing required components:" >&2
      awk 'NF && $0 !~ /^#/' "$REPORTS_DIR/components-missing.txt" >&2
      exit 2
    fi
    exit 0
    ;;

  build)
    require_build_inputs
    clean_work
    validate_inputs
    record_protected_before
    audit_qt5
    merge_components
    resolve_deps
    verify_added_compatibility
    remove_qt5
    cleanup_files
    verify_full_dependencies
    arch_checks
    verify_protected
    verify_locale_in_rootfs
    repackage
    write_report
    log "DONE" "Install directory: $INSTALL_DIR"
    ls -lah "$INSTALL_DIR"
    echo
    cat "$INSTALL_DIR/SHA256SUMS"
    ;;

  *)
    echo "unknown command: $CMD" >&2
    usage >&2
    exit 1
    ;;
esac
