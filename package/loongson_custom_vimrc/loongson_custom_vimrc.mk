################################################################################
#
# loongson_custom_vimrc
#
################################################################################

LOONGSON_CUSTOM_VIMRC_SITE=$(TOPDIR)/package/loongson_custom_vimrc/vimrc
LOONGSON_CUSTOM_VIMRC_SITE_METHOD=file
LOONGSON_CUSTOM_VIMRC_DEPENDENCIES=vim

define LOONGSON_CUSTOM_VIMRC_EXTRACT_CMDS
	echo "do nothing"
endef

define LOONGSON_CUSTOM_VIMRC_BUILD_CMDS
	echo "do nothing"
endef

define LOONGSON_CUSTOM_VIMRC_INSTALL_TARGET_CMDS
	cp $(LOONGSON_CUSTOM_VIMRC_SITE) $(TARGET_DIR)/usr/share/vim/
endef

$(eval $(generic-package))
