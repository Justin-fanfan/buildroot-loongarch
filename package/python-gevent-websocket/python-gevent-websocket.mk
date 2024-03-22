################################################################################
#
# python-gevent-websocket
#
################################################################################

PYTHON_GEVENT_WEBSOCKET_VERSION = 0.10.1
PYTHON_GEVENT_WEBSOCKET_SOURCE = gevent-websocket-$(PYTHON_GEVENT_WEBSOCKET_VERSION).tar.gz
PYTHON_GEVENT_WEBSOCKET_SITE = https://files.pythonhosted.org/packages/98/d2/6fa19239ff1ab072af40ebf339acd91fb97f34617c2ee625b8e34bf42393
PYTHON_GEVENT_WEBSOCKET_LICENSE = Apache-2.0
PYTHON_GEVENT_WEBSOCKET_LICENSE_FILES = LICENSE
PYTHON_GEVENT_WEBSOCKET_SETUP_TYPE = setuptools
PYTHON_GEVENT_WEBSOCKET_DEPENDENCIES = python-gevent
PYTHON_GEVENT_WEBSOCKET_ENV = SODIUM_INSTALL=system

$(eval $(python-package))
