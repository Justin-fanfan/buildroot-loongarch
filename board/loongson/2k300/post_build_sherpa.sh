#!/bin/sh

set -eu

target_dir="$1"
sherpa_lib="${target_dir}/usr/lib/python3.12/site-packages/sherpa_onnx/lib"

clean_extension="$(
    find "${BUILD_DIR}" \
        -maxdepth 4 \
        -type f \
        -path '*/sherpa-onnx-*/buildroot-build/lib/_sherpa_onnx.so' \
        -print -quit
)"

if [ -z "${clean_extension}" ] || [ ! -f "${clean_extension}" ]; then
    echo "ERROR: clean _sherpa_onnx.so not found in ${BUILD_DIR}" >&2
    exit 1
fi

if [ ! -d "${sherpa_lib}" ]; then
    echo "ERROR: sherpa library directory not found: ${sherpa_lib}" >&2
    exit 1
fi

echo "Restoring clean sherpa extension:"
echo "  source: ${clean_extension}"
echo "  target: ${sherpa_lib}/_sherpa_onnx.so"

# Restore the original 16-KiB-compatible extension after Buildroot fix-rpath.
cp -f \
    "${clean_extension}" \
    "${sherpa_lib}/_sherpa_onnx.so"

chmod 0755 "${sherpa_lib}/_sherpa_onnx.so"

# Use the canonical ONNX Runtime installed in /usr/lib.
rm -f \
    "${sherpa_lib}/libonnxruntime.so" \
    "${sherpa_lib}/libonnxruntime.so.1" \
    "${sherpa_lib}/libonnxruntime.so.1.17.1"

ln -s \
    /usr/lib/libonnxruntime.so.1.17.1 \
    "${sherpa_lib}/libonnxruntime.so.1.17.1"

ln -s \
    libonnxruntime.so.1.17.1 \
    "${sherpa_lib}/libonnxruntime.so.1"

ln -s \
    libonnxruntime.so.1.17.1 \
    "${sherpa_lib}/libonnxruntime.so"

echo "sherpa-onnx post-build fix completed"
