################################################################################
#
# python-sounddevice
#
################################################################################

PYTHON_SOUNDDEVICE_VERSION = 0.5.1
PYTHON_SOUNDDEVICE_SOURCE = sounddevice-$(PYTHON_SOUNDDEVICE_VERSION).tar.gz
PYTHON_SOUNDDEVICE_SITE = https://files.pythonhosted.org/packages/source/s/sounddevice
PYTHON_SOUNDDEVICE_SETUP_TYPE = setuptools
PYTHON_SOUNDDEVICE_LICENSE = MIT
PYTHON_SOUNDDEVICE_LICENSE_FILES = LICENSE
PYTHON_SOUNDDEVICE_DEPENDENCIES = host-python-cffi portaudio

# Minimal Buildroot systems do not provide the tools/cache required by
# ctypes.util.find_library(), so use the installed PortAudio SONAME.
define PYTHON_SOUNDDEVICE_FIX_PORTAUDIO_LOOKUP
	test "$$(grep -c \
		'_libname = _find_library(_libname)' \
		$(@D)/sounddevice.py)" -eq 1

	$(SED) \
		"s|_libname = _find_library(_libname)|_libname = _find_library(_libname) or ('/usr/lib/libportaudio.so.2' if _libname == 'portaudio' else None)|" \
		$(@D)/sounddevice.py

	grep -q \
		"libportaudio.so.2" \
		$(@D)/sounddevice.py
endef

PYTHON_SOUNDDEVICE_POST_PATCH_HOOKS += \
	PYTHON_SOUNDDEVICE_FIX_PORTAUDIO_LOOKUP

$(eval $(python-package))