################################################################################
#
# python-RPi-GPIO-ls
#
################################################################################

PYTHON_RPI_GPIO_LS_VERSION = origin/ls-dev-0.7.0
PYTHON_RPI_GPIO_LS_SITE = http://192.168.1.5/RPi-GPIO-LS
PYTHON_RPI_GPIO_LS_SITE_METHOD = git
PYTHON_RPI_GPIO_LS_SETUP_TYPE = setuptools

$(eval $(python-package))
