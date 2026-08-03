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
	-DBUILD_PKGCONFIG_FILES=ON \
	-DCMAKE_C_FLAGS="$(TARGET_CFLAGS) -march=loongarch64 -mtune=loongarch64 -mstrict-align" \
	-DCMAKE_CXX_FLAGS="$(TARGET_CXXFLAGS) -march=loongarch64 -mtune=loongarch64 -mstrict-align" \
	-DBUILD_SHARED_LIBS=OFF

# Loongson 2K0300 has neither LSX nor LASX.
# Prevent ONNX Runtime from selecting its LoongArch SIMD MLAS kernels.
define ONNXRUNTIME_DISABLE_LOONGARCH_SIMD
	test "$$(grep -c 'set(LOONGARCH64 TRUE)' \
		$(@D)/cmake/onnxruntime_mlas.cmake)" -eq 1
	$(SED) 's|set(LOONGARCH64 TRUE)|message(STATUS "Generic LoongArch64: using scalar MLAS without LSX/LASX")|' \
		$(@D)/cmake/onnxruntime_mlas.cmake
	grep -q 'Generic LoongArch64: using scalar MLAS without LSX/LASX' \
		$(@D)/cmake/onnxruntime_mlas.cmake
	! grep -q 'set(LOONGARCH64 TRUE)' \
		$(@D)/cmake/onnxruntime_mlas.cmake
endef

ONNXRUNTIME_POST_PATCH_HOOKS += ONNXRUNTIME_DISABLE_LOONGARCH_SIMD

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

# ONNX Runtime 1.17.1 assumes that every LoongArch64 CPU supports LSX.
# Loongson 2K0300 has no LSX/LASX, so keep MLAS on its scalar path.
define ONNXRUNTIME_FIX_GENERIC_LOONGARCH_MLAS_HEADERS
	test "$$(grep -c '^#if defined(__loongarch64)$$' \
		$(@D)/onnxruntime/core/mlas/inc/mlas.h)" -eq 1
	$(SED) \
		's/^#if defined(__loongarch64)$$/#if defined(__loongarch64) \&\& defined(__loongarch_sx)/' \
		$(@D)/onnxruntime/core/mlas/inc/mlas.h

	test "$$(grep -c '^#if defined(__loongarch64)$$' \
		$(@D)/onnxruntime/core/mlas/lib/mlasi.h)" -eq 1
	$(SED) \
		's/^#if defined(__loongarch64)$$/#if defined(MLAS_TARGET_LARCH64)/' \
		$(@D)/onnxruntime/core/mlas/lib/mlasi.h

	grep -q \
		'^#if defined(__loongarch64) && defined(__loongarch_sx)$$' \
		$(@D)/onnxruntime/core/mlas/inc/mlas.h
	grep -q \
		'^#if defined(MLAS_TARGET_LARCH64)$$' \
		$(@D)/onnxruntime/core/mlas/lib/mlasi.h
endef

ONNXRUNTIME_POST_PATCH_HOOKS += \
	ONNXRUNTIME_FIX_GENERIC_LOONGARCH_MLAS_HEADERS

$(eval $(cmake-package))
