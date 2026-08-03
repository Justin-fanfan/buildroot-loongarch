################################################################################
#
# sherpa-onnx
#
################################################################################

SHERPA_ONNX_VERSION = 1.12.15
SHERPA_ONNX_SITE = $(call github,k2-fsa,sherpa-onnx,v$(SHERPA_ONNX_VERSION))
SHERPA_ONNX_LICENSE = Apache-2.0
SHERPA_ONNX_LICENSE_FILES = LICENSE

SHERPA_ONNX_INSTALL_STAGING = YES

SHERPA_ONNX_DEPENDENCIES = \
	onnxruntime \
	python3 \
	host-python3 \
	alsa-lib

SHERPA_ONNX_PYTHON_DIR = \
	/usr/lib/python$(PYTHON3_VERSION_MAJOR)/site-packages/sherpa_onnx

# The directory must directly contain onnxruntime_cxx_api.h.
SHERPA_ONNX_CONF_ENV = \
	SHERPA_ONNXRUNTIME_INCLUDE_DIR=$(STAGING_DIR)/usr/include/onnxruntime \
	SHERPA_ONNXRUNTIME_LIB_DIR=$(STAGING_DIR)/usr/lib \
	SHERPA_ONNX_ALSA_LIB_DIR=$(STAGING_DIR)/usr/lib

SHERPA_ONNX_CONF_OPTS = \
	-DCMAKE_INSTALL_PREFIX=$(SHERPA_ONNX_PYTHON_DIR) \
	-DCMAKE_SYSTEM_PROCESSOR=loongarch64 \
	-DCMAKE_C_FLAGS="$(TARGET_CFLAGS) -march=loongarch64 -mtune=loongarch64 -mstrict-align" \
	-DCMAKE_CXX_FLAGS="$(TARGET_CXXFLAGS) -march=loongarch64 -mtune=loongarch64 -mstrict-align" \
	-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
	-DBUILD_SHARED_LIBS=ON \
	-DSHERPA_ONNX_ENABLE_PYTHON=ON \
	-DSHERPA_ONNX_ENABLE_BINARY=OFF \
	-DSHERPA_ONNX_ENABLE_TESTS=OFF \
	-DSHERPA_ONNX_ENABLE_CHECK=OFF \
	-DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
	-DSHERPA_ONNX_ENABLE_C_API=OFF \
	-DSHERPA_ONNX_BUILD_C_API_EXAMPLES=OFF \
	-DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF \
	-DSHERPA_ONNX_ENABLE_TTS=OFF \
	-DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF \
	-DSHERPA_ONNX_ENABLE_GPU=OFF \
	-DSHERPA_ONNX_ENABLE_RKNN=OFF \
	-DSHERPA_ONNX_LINK_LIBSTDCPP_STATICALLY=OFF \
	-DSHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=ON \
	-DPYTHON_EXECUTABLE=$(HOST_DIR)/bin/python3 \
	-DPython_EXECUTABLE=$(HOST_DIR)/bin/python3 \
	-DPython3_EXECUTABLE=$(HOST_DIR)/bin/python3 \
	-DPYTHON_INCLUDE_DIR=$(STAGING_DIR)/usr/include/python$(PYTHON3_VERSION_MAJOR) \
	-DPython3_INCLUDE_DIR=$(STAGING_DIR)/usr/include/python$(PYTHON3_VERSION_MAJOR)

# CMake installs the native extension, but not the package's pure Python
# source files when it is invoked directly rather than through setup.py.
define SHERPA_ONNX_INSTALL_PURE_PYTHON
	$(INSTALL) -d \
		$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_DIR)
	cp -a \
		$(@D)/sherpa-onnx/python/sherpa_onnx/. \
		$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_DIR)/
	printf '\n__version__ = "$(SHERPA_ONNX_VERSION)"\n' >> \
		$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_DIR)/__init__.py
endef

SHERPA_ONNX_POST_INSTALL_TARGET_HOOKS += \
	SHERPA_ONNX_INSTALL_PURE_PYTHON

# pybind11 can derive a host architecture suffix during cross compilation.
# Python accepts the generic _sherpa_onnx.so filename, so normalize it.
define SHERPA_ONNX_NORMALIZE_EXTENSION_NAME
	ext="$$(find \
		$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_DIR)/lib \
		-maxdepth 1 -type f \
		-name '_sherpa_onnx*.so' \
		-print -quit)"; \
	test -n "$$ext"; \
	if test "$$(basename "$$ext")" != "_sherpa_onnx.so"; then \
		mv "$$ext" \
			$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_DIR)/lib/_sherpa_onnx.so; \
	fi
endef

SHERPA_ONNX_POST_INSTALL_TARGET_HOOKS += \
	SHERPA_ONNX_NORMALIZE_EXTENSION_NAME

$(eval $(cmake-package))
