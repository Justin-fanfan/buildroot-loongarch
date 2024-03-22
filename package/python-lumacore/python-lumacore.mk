################################################################################
#
# python-lumacore
#
################################################################################

PYTHON_LUMACORE_VERSION = 2.4.2
PYTHON_LUMACORE_SOURCE = luma.core-$(PYTHON_LUMACORE_VERSION).tar.gz
PYTHON_LUMACORE_SITE = https://files.pythonhosted.org/packages/64/fe/026b50adfedf0d6bef583f8b005ad7e75b6501c973fad77a871d020fb63f
PYTHON_LUMACORE_SETUP_TYPE = setuptools

$(eval $(python-package))
