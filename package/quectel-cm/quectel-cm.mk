################################################################################
#
# quectel-cm
#
################################################################################

QUECTEL_CM_SITE = $(TOPDIR)/package/quectel-cm/quectel-cm.tar.gz
QUECTEL_CM_SITE_METHOD = file
QUECTEL_CM_CFLAGS = $(TARGET_CFLAGS)

define QUECTEL_CM_EXTRACT_CMDS
	echo $(QUECTEL_CM_SITE)
	tar -zxf $(QUECTEL_CM_SITE) --strip-components=1 -C $(@D)/
endef

#define QUECTEL_CM_BUILD_CMDS
#	cd $(@D) && $(TARGET_MAKE_ENV) $(MAKE) CC=$(TARGET_CC) AR=$(TARGET_AR) -C $(@D)
#endef
#
#define QUECTEL_CM_INSTALL_STAGING_CMDS
#	echo "nothing to do"
#endef
#
#define QUECTEL_CM_INSTALL_TARGET_CMDS
#	echo quectel-cm install to $(BR2_PACKAGE_QUECTEL_INSTALL_PATH)
#	mkdir -p $(TARGET_DIR)$(BR2_PACKAGE_QUECTEL_INSTALL_PATH)
#	cd $(@D) && cp quectel-CM $(TARGET_DIR)$(BR2_PACKAGE_QUECTEL_INSTALL_PATH) && cp quectel-mbim-proxy $(TARGET_DIR)$(BR2_PACKAGE_QUECTEL_INSTALL_PATH) && cp quectel-qmi-proxy $(TARGET_DIR)$(BR2_PACKAGE_QUECTEL_INSTALL_PATH)
#endef

ifeq ($(BR2_PACKAGE_QUECTEL_CM_LINK),y)
define QUECTEL_CM_LINK
	echo quectel-cm link to /opt/quectel-cm
	mkdir -p $(TARGET_DIR)/opt/quectel-cm
	cd $(TARGET_DIR)/opt/quectel-cm && ln -sf ../../usr/bin/quectel-CM quectel-CM
	cd $(TARGET_DIR)/opt/quectel-cm && ln -sf ../../usr/bin/quectel-qmi-proxy quectel-qmi-proxy
	cd $(TARGET_DIR)/opt/quectel-cm && ln -sf ../../usr/bin/quectel-mbim-proxy quectel-mbim-proxy
	cd $(TARGET_DIR)/opt/quectel-cm && ln -sf ../../usr/bin/quectel-atc-proxy quectel-atc-proxy
endef

QUECTEL_CM_POST_INSTALL_TARGET_HOOKS += QUECTEL_CM_LINK

endif

QUECTEL_CM_CONF_OPTS += -DCMAKE_CXX_FLAGS="-Wno-unused-result"

$(eval $(cmake-package))
