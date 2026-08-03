################################################################################
#
# sherpa-onnx
#
################################################################################

SHERPA_ONNX_VERSION = 1.12.15
SHERPA_ONNX_SITE = $(call github,k2-fsa,sherpa-onnx,v$(SHERPA_ONNX_VERSION))
SHERPA_ONNX_LICENSE = Apache-2.0
SHERPA_ONNX_LICENSE_FILES = LICENSE

# sherpa-onnx and kaldi-native-fbank reject in-source builds.
SHERPA_ONNX_SUPPORTS_IN_SOURCE_BUILD = NO

SHERPA_ONNX_DEPENDENCIES = \
	onnxruntime \
	python3 \
	python-numpy \
	host-python3 \
	alsa-lib

SHERPA_ONNX_PYTHON_BASE = \
	/usr/lib/python$(PYTHON3_VERSION_MAJOR)/site-packages

SHERPA_ONNX_PYTHON_PACKAGE = \
	$(SHERPA_ONNX_PYTHON_BASE)/sherpa_onnx

# sherpa-onnx expects onnxruntime_cxx_api.h to be directly inside the
# directory specified by SHERPA_ONNXRUNTIME_INCLUDE_DIR.
# Normalize the Buildroot ONNX Runtime header layout before configuring.
define SHERPA_ONNX_PREPARE_ONNXRUNTIME_HEADERS
	$(INSTALL) -d $(STAGING_DIR)/usr/include/onnxruntime
	ort_header="$$(find $(STAGING_DIR)/usr/include \
		-name onnxruntime_cxx_api.h -print -quit)"; \
	test -n "$$ort_header"; \
	ort_header_dir="$$(dirname "$$ort_header")"; \
	if [ "$$ort_header_dir" != \
		"$(STAGING_DIR)/usr/include/onnxruntime" ]; then \
		cp -a "$$ort_header_dir"/*.h \
			$(STAGING_DIR)/usr/include/onnxruntime/; \
	fi
	test -f \
		$(STAGING_DIR)/usr/include/onnxruntime/onnxruntime_cxx_api.h
	test -e $(STAGING_DIR)/usr/lib/libonnxruntime.so
endef

SHERPA_ONNX_PRE_CONFIGURE_HOOKS += \
	SHERPA_ONNX_PREPARE_ONNXRUNTIME_HEADERS

SHERPA_ONNX_CONF_ENV = \
	SHERPA_ONNXRUNTIME_INCLUDE_DIR="$(STAGING_DIR)/usr/include/onnxruntime" \
	SHERPA_ONNXRUNTIME_LIB_DIR="$(STAGING_DIR)/usr/lib" \
	SHERPA_ONNX_ALSA_LIB_DIR="$(STAGING_DIR)/usr/lib"

SHERPA_ONNX_CONF_OPTS = \
	-DCMAKE_BUILD_TYPE=MinSizeRel \
	-DCMAKE_INSTALL_PREFIX="$(SHERPA_ONNX_PYTHON_PACKAGE)" \
	-DBUILD_SHARED_LIBS=ON \
	-DSHERPA_ONNX_ENABLE_PYTHON=ON \
	-DSHERPA_ONNX_ENABLE_BINARY=OFF \
	-DSHERPA_ONNX_ENABLE_TESTS=OFF \
	-DSHERPA_ONNX_ENABLE_CHECK=OFF \
	-DSHERPA_ONNX_ENABLE_C_API=OFF \
	-DSHERPA_ONNX_BUILD_C_API_EXAMPLES=OFF \
	-DSHERPA_ONNX_ENABLE_PORTAUDIO=OFF \
	-DSHERPA_ONNX_ENABLE_WEBSOCKET=OFF \
	-DSHERPA_ONNX_ENABLE_TTS=OFF \
	-DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=OFF \
	-DSHERPA_ONNX_ENABLE_GPU=OFF \
	-DSHERPA_ONNX_ENABLE_DIRECTML=OFF \
	-DSHERPA_ONNX_ENABLE_RKNN=OFF \
	-DSHERPA_ONNX_ENABLE_SANITIZER=OFF \
	-DSHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=ON \
	-DSHERPA_ONNX_LINK_LIBSTDCPP_STATICALLY=OFF \
	-DPYBIND11_FINDPYTHON=OFF \
	-DPYBIND11_PYTHONLIBS_OVERWRITE=OFF \
	-DPYTHON_EXECUTABLE="$(HOST_DIR)/bin/python3" \
	-DPYTHON_INCLUDE_DIR="$(STAGING_DIR)/usr/include/python$(PYTHON3_VERSION_MAJOR)" \
	-DPYTHON_LIBRARY="$(STAGING_DIR)/usr/lib/libpython$(PYTHON3_VERSION_MAJOR).so" \
	-DPYTHON_MODULE_EXTENSION=.so \
	-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF \
	-DCMAKE_C_FLAGS="$(TARGET_CFLAGS) -march=loongarch64 -mtune=loongarch64 -mstrict-align" \
	-DCMAKE_CXX_FLAGS="$(TARGET_CXXFLAGS) -march=loongarch64 -mtune=loongarch64 -mstrict-align -DEIGEN_DONT_VECTORIZE=1"

# TTS and speaker diarization are disabled above. The upstream __init__.py
# imports those optional symbols unconditionally, so remove those names from
# the import list.
define SHERPA_ONNX_INSTALL_PURE_PYTHON
	$(INSTALL) -d \
		$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_PACKAGE)

	cp -a \
		$(@D)/sherpa-onnx/python/sherpa_onnx/. \
		$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_PACKAGE)/

	$(SED) \
		'/^[[:space:]]*FastClustering/d; \
		 /^[[:space:]]*OfflineSpeaker/d; \
		 /^[[:space:]]*OfflineTts/d; \
		 /^__version__[[:space:]]*=/d' \
		$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_PACKAGE)/__init__.py

	printf "\n__version__ = '%s'\n" "$(SHERPA_ONNX_VERSION)" >> \
		$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_PACKAGE)/__init__.py

	extension="$$(find \
		$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_PACKAGE)/lib \
		-maxdepth 1 -type f \
		-name '_sherpa_onnx*.so' \
		-print -quit)"; \
	test -n "$$extension"; \
	if [ "$$(basename "$$extension")" != "_sherpa_onnx.so" ]; then \
		mv "$$extension" \
			$(TARGET_DIR)$(SHERPA_ONNX_PYTHON_PACKAGE)/lib/_sherpa_onnx.so; \
	fi
endef

SHERPA_ONNX_POST_INSTALL_TARGET_HOOKS += \
	SHERPA_ONNX_INSTALL_PURE_PYTHON

$(eval $(cmake-package))
