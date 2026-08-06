################################################################################
#
# onnxruntime
#
################################################################################

ONNXRUNTIME_VERSION = 1.17.1
ONNXRUNTIME_SITE = $(call github,microsoft,onnxruntime,v$(ONNXRUNTIME_VERSION))
ONNXRUNTIME_LICENSE = MIT
ONNXRUNTIME_LICENSE_FILES = LICENSE

ONNXRUNTIME_INSTALL_STAGING = YES
ONNXRUNTIME_DEPENDENCIES = host-python3

# ONNX Runtime's main CMakeLists.txt is in the cmake directory.
ONNXRUNTIME_SUBDIR = cmake

ONNXRUNTIME_CONF_OPTS = \
	-Donnxruntime_BUILD_SHARED_LIB=ON \
	-Donnxruntime_CROSS_COMPILING=ON \
	-Donnxruntime_BUILD_UNIT_TESTS=OFF \
	-Donnxruntime_BUILD_BENCHMARKS=OFF \
	-Donnxruntime_ENABLE_PYTHON=OFF \
	-Donnxruntime_ENABLE_TRAINING=OFF \
	-Donnxruntime_ENABLE_TRAINING_OPS=OFF \
	-Donnxruntime_ENABLE_LTO=OFF \
	-Donnxruntime_BUILD_FOR_NATIVE_MACHINE=OFF \
	-Donnxruntime_DONT_VECTORIZE=ON \
	-Donnxruntime_USE_NEURAL_SPEED=OFF \
	-Donnxruntime_USE_CUDA=OFF \
	-Donnxruntime_USE_DNNL=OFF \
	-Donnxruntime_USE_OPENVINO=OFF \
	-Donnxruntime_USE_XNNPACK=OFF \
	-Donnxruntime_USE_MIMALLOC=OFF \
	-Donnxruntime_USE_FULL_PROTOBUF=OFF \
	-Donnxruntime_MLAS_FORCE_SCALAR=ON \
	-DBUILD_PKGCONFIG_FILES=ON \
	-DCMAKE_C_FLAGS="$(TARGET_CFLAGS) -march=loongarch64 -mtune=loongarch64 -mstrict-align -fno-strict-aliasing" \
	-DCMAKE_CXX_FLAGS="$(TARGET_CXXFLAGS) -march=loongarch64 -mtune=loongarch64 -mstrict-align -fno-strict-aliasing" \
	-DBUILD_SHARED_LIBS=OFF

# The LoongArch MLAS scalar mode is applied by the patch
# 0001-mlas-add-generic-scalar-mode-for-loongarch64.patch:
# - Loongson 2K0300 has neither LSX nor LASX, so we enable the new
#   onnxruntime_MLAS_FORCE_SCALAR option (set above to ON).
# - With the option ON, MLAS_TARGET_LARCH64 is not defined, no LSX/LASX
#   source is compiled, and the generic scalar/*.cpp sources are selected.
# - The patch also switches the SGEMM packing to the 4-wide format that the
#   scalar kernel expects (upstream uses this format for
#   MLAS_TARGET_WASM_SCALAR). Without this, the 16-wide generic pack and the
#   4-wide scalar kernel are mixed, producing wrong GEMM results.

# GitLab regenerated the archive for the same Eigen commit.
# ONNX Runtime 1.17.1 still contains the old archive SHA1.
define ONNXRUNTIME_FIX_EIGEN_ARCHIVE_HASH
	test "$$(grep -c \
		'be8be39fdbc6e60e94fa7870b280707069b5b81a' \
		$(@D)/cmake/deps.txt)" -eq 1
	$(SED) \
		's/be8be39fdbc6e60e94fa7870b280707069b5b81a/32b145f525a8308d7ab1c09388b2e288312d8eba/' \
		$(@D)/cmake/deps.txt
	grep -q \
		'32b145f525a8308d7ab1c09388b2e288312d8eba' \
		$(@D)/cmake/deps.txt
endef

ONNXRUNTIME_POST_PATCH_HOOKS += ONNXRUNTIME_FIX_EIGEN_ARCHIVE_HASH

# ONNX Runtime 1.17.1 cannot export its CMake target because bundled
# Abseil and nsync targets are not included in the export set.
# Buildroot only needs the shared library, public headers and pkg-config file.
define ONNXRUNTIME_DISABLE_BROKEN_CMAKE_EXPORT
	test "$$(grep -c \
		'^[[:space:]]*EXPORT $${PROJECT_NAME}Targets[[:space:]]*$$' \
		$(@D)/cmake/onnxruntime.cmake)" -eq 1
	$(SED) \
		'/^[[:space:]]*EXPORT $${PROJECT_NAME}Targets[[:space:]]*$$/d' \
		$(@D)/cmake/onnxruntime.cmake

	test "$$(grep -c '^if(TARGET onnxruntime)$$' \
		$(@D)/cmake/CMakeLists.txt)" -eq 1
	$(SED) \
		's/^if(TARGET onnxruntime)$$/if(FALSE) # Buildroot: disable broken CMake package export/' \
		$(@D)/cmake/CMakeLists.txt

	! grep -q \
		'EXPORT $${PROJECT_NAME}Targets' \
		$(@D)/cmake/onnxruntime.cmake
	grep -q \
		'^if(FALSE) # Buildroot: disable broken CMake package export$$' \
		$(@D)/cmake/CMakeLists.txt
endef

ONNXRUNTIME_POST_PATCH_HOOKS += ONNXRUNTIME_DISABLE_BROKEN_CMAKE_EXPORT

$(eval $(cmake-package))
