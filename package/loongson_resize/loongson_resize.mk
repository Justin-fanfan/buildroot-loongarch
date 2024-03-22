################################################################################
#
# loongson_resize
#
################################################################################

LOONGSON_RESIZE_SITE = $(TOPDIR)/package/loongson_resize/loongson_resize.tar.gz
LOONGSON_RESIZE_SITE_METHOD = file

define LOONGSON_RESIZE_EXTRACT_CMDS
	echo $(LOONGSON_RESIZE_SITE)
	tar -zxf $(LOONGSON_RESIZE_SITE) -C $(@D)/
endef

define LOONGSON_RESIZE_INSTALL_STAGING_CMDS
	echo "nothing to do"
endef

ifeq ($(BR2_INIT_SYSTEMD) ,y)
define LOONGSON_RESIZE_INSTALL_TARGET_CMDS
	echo "install loongson resize init.d/profile.d"
	mkdir -p $(TARGET_DIR)/usr/local/ls_resize
	cd $(@D) && chmod a+x ./resizerootfs.sh && cp resizerootfs.sh $(TARGET_DIR)/usr/local/ls_resize/
	cd $(@D) && chmod a+x ./fdisk_resize.sh && cp fdisk_resize.sh $(TARGET_DIR)/usr/local/ls_resize/
	mkdir -p $(TARGET_DIR)/etc/init.d
	cd $(@D) && chmod a+x ./S03resizerootfs && cp S03resizerootfs $(TARGET_DIR)/etc/init.d
	cd $(@D) && cp loongson-resize.service $(TARGET_DIR)/usr/lib/systemd/system/
	cd $(TARGET_DIR)/usr/lib/systemd/system/sysinit.target.wants && ln -sf ../loongson-resize.service loongson-resize.service
endef
endif

$(eval $(generic-package))
