################################################################################
#
# libxkbcommon_rules
#
################################################################################

LIBXKBCOMMON_RULES_BUILD_DIR_NAME = libxkbcommon_rules
LIBXKBCOMMON_RULES_SITE = $(TOPDIR)/package/libxkbcommon_rules/xkb.tar.gz
LIBXKBCOMMON_RULES_METHOD = file
LIBXKBCOMMON_RULES_DEPENDENCIES = libxkbcommon

define LIBXKBCOMMON_RULES_EXTRACT_CMDS
	tar -zxf $(LIBXKBCOMMON_RULES_SITE) -C $(BUILD_DIR)/$(LIBXKBCOMMON_RULES_BUILD_DIR_NAME)
endef

define LIBXKBCOMMON_RULES_CONFIGURE_CMDS
        echo "nothing to do"
endef

define LIBXKBCOMMON_RULES_BUILD_CMDS
        echo "nothing to do"
endef

define LIBXKBCOMMON_RULES_INSTALL_TARGET_CMDS
        cd $(BUILD_DIR)/$(LIBXKBCOMMON_RULES_BUILD_DIR_NAME) && cp -r xkb $(TOPDIR)/output/target/etc/
endef

$(eval $(generic-package))
