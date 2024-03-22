################################################################################
#
# qtperf
#
################################################################################

QTPERF_SITE = $(TOPDIR)/package/qtperf/qtperf.tar.gz
QTPERF_SITE_METHOD = file
QTPERF_CFLAGS = $(TARGET_CFLAGS)

QTPERF_DEPENDENCIES = qt5base

define QTPERF_EXTRACT_CMDS
	echo $(QTPERF_SITE)
	tar -zxf $(QTPERF_SITE) -C $(@D)/
endef

#$(TARGET_MAKE_ENV) $(MAKE) CC=$(TARGET_CC) AR=$(TARGET_AR) -C $(@D)

define QTPERF_BUILD_CMDS
	cd $(@D) && $(HOST_DIR)/bin/qmake qtperf.pro && $(TARGET_MAKE_ENV) $(MAKE) -C $(@D)
endef

define QTPERF_INSTALL_STAGING_CMDS
	echo "nothing to do"
endef

define QTPERF_INSTALL_TARGET_CMDS
	cd $(@D) && cp qtperf_qt5 $(TARGET_DIR)/usr/bin/
endef

$(eval $(generic-package))
