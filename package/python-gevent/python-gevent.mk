################################################################################
#
# python-gevent
#
################################################################################

PYTHON_GEVENT_VERSION = 24.2.1
PYTHON_GEVENT_SOURCE = gevent-$(PYTHON_GEVENT_VERSION).tar.gz
PYTHON_GEVENT_SITE = https://files.pythonhosted.org/packages/27/24/a3a7b713acfcf1177207f49ec25c665123f8972f42bee641bcc9f32961f4
PYTHON_GEVENT_LICENSE = Apache-2.0
PYTHON_GEVENT_LICENSE_FILES = LICENSE
PYTHON_GEVENT_SETUP_TYPE = setuptools
PYTHON_GEVENT_DEPENDENCIES = python-greenlet
PYTHON_GEVENT_ENV = SODIUM_INSTALL=system

$(eval $(python-package))
