################################################################################
#
# loongson_custom_inputrc
#
################################################################################

LOONGSON_CUSTOM_INPUTRC_SITE=$(TOPDIR)/package/loongson_custom_inputrc/inputrc
LOONGSON_CUSTOM_INPUTRC_SITE_METHOD=file
LOONGSON_CUSTOM_INPUTRC_DEPENDENCIES=readline

define LOONGSON_CUSTOM_INPUTRC_EXTRACT_CMDS
	echo "do nothing"
endef

define LOONGSON_CUSTOM_INPUTRC_BUILD_CMDS
	echo "do nothing"
endef

define LOONGSON_CUSTOM_INPUTRC_INSTALL_TARGET_CMDS
	cp $(LOONGSON_CUSTOM_INPUTRC_SITE) $(TARGET_DIR)/etc
endef

$(eval $(generic-package))
