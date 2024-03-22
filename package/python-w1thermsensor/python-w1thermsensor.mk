################################################################################
#
# python-w1thermsensor
#
################################################################################

PYTHON_W1THERMSENSOR_VERSION = 2.3.0
PYTHON_W1THERMSENSOR_SOURCE = w1thermsensor-$(PYTHON_W1THERMSENSOR_VERSION).tar.gz
PYTHON_W1THERMSENSOR_SITE = https://files.pythonhosted.org/packages/dd/60/e2dbb207a2b6ed7813aeb976bfb69ef084b3586d5378597e5e5eb225582a
PYTHON_W1THERMSENSOR_SETUP_TYPE = setuptools

$(eval $(python-package))
