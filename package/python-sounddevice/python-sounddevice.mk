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

$(eval $(python-package))