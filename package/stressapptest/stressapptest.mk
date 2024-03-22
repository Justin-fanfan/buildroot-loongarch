################################################################################
#
# stressapptest
#
################################################################################

STRESSAPPTEST_VERSION = 1.0.11
STRESSAPPTEST_SOURCE = stressapptest-$(STRESSAPPTEST_VERSION).tar.gz
STRESSAPPTEST_SITE = $(CURDIR)/dl/stressapptest
# STRESSAPPTEST_SITE_METHOD = local
# STRESSAPPTEST_SITE = https://github.com/stressapptest/stressapptest
STRESS_LICENSE = GPL-2.0+
STRESS_LICENSE_FILES = COPYING
STRESSAPPTEST_INSTALL_STAGING = YES

$(eval $(autotools-package))
