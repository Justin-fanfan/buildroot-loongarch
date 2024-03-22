################################################################################
#
# python-lumaoled
#
################################################################################

PYTHON_LUMAOLED_VERSION = 3.13.0
PYTHON_LUMAOLED_SOURCE = luma.oled-$(PYTHON_LUMAOLED_VERSION).tar.gz
PYTHON_LUMAOLED_SITE = https://files.pythonhosted.org/packages/bd/fe/2eb49e764f14ac729ee9d5b42095094db9dc1cc6f8d653c6c1e5d7d869e6
PYTHON_LUMAOLED_SETUP_TYPE = setuptools

$(eval $(python-package))
