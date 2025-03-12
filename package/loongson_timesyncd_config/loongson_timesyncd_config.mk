define LOONGSON_TIMESYNCD_CONFIG_INSTALL_TARGET_CMDS
	cp $(TOPDIR)/package/loongson_timesyncd_config/loongson_timesyncd_config.sh $(TARGET_DIR)/usr/local/
	cp $(TOPDIR)/package/loongson_timesyncd_config/loongson_timesyncd_config.service $(TARGET_DIR)/usr/lib/systemd/system/
	cd $(TARGET_DIR)/usr/lib/systemd/system/multi-user.target.wants && ln -sf ../loongson_timesyncd_config.service loongson_timesyncd_config.service
endef

$(eval $(generic-package))
