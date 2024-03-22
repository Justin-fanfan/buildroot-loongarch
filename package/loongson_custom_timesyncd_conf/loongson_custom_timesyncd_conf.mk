################################################################################
#
# loongson_custom_timesyncd_conf
#
################################################################################

LOONGSON_CUSTOM_TIMESYNCD_CONF_SITE=$(TOPDIR)/package/loongson_custom_timesyncd_conf/timesyncd.conf
LOONGSON_CUSTOM_TIMESYNCD_CONF_SITE_METHOD=file
LOONGSON_CUSTOM_TIMESYNCD_CONF_DEPENDENCIES=systemd

define LOONGSON_CUSTOM_TIMESYNCD_CONF_EXTRACT_CMDS
	echo "do nothing"
endef

define LOONGSON_CUSTOM_TIMESYNCD_CONF_BUILD_CMDS
	echo "do nothing"
endef

define LOONGSON_CUSTOM_TIMESYNCD_CONF_INSTALL_TARGET_CMDS
	cp $(LOONGSON_CUSTOM_TIMESYNCD_CONF_SITE) $(TARGET_DIR)/etc/systemd/
endef

$(eval $(generic-package))
