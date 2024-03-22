################################################################################
#
# LS_DEFAULT_ETH_CONFIG
#
################################################################################

LS_DEFAULT_ETH_CONFIG_SITE = $(TOPDIR)/package/ls_default_eth_config/ls_default_eth_config.tar.gz
LS_DEFAULT_ETH_CONFIG_SITE_METHOD = file

define LS_DEFAULT_ETH_CONFIG_EXTRACT_CMDS
	echo $(LS_DEFAULT_ETH_CONFIG_SITE)
	tar -zxf $(LS_DEFAULT_ETH_CONFIG_SITE) -C $(@D)/
endef

ifeq ($(BR2_PACKAGE_IFUPDOWN_SCRIPTS),y)

BOOT_RUN_DEPENDENCIES = ifupdown-scripts

define BUILD_LS_DEFAULT_ETH_CONFIG_GEN
	echo "generate new interface";
	cd $(@D) && ./gen_interfaces.sh $(BR2_PACKAGE_LS_DEFAULT_ETH_NAME) $(BR2_PACKAGE_LS_DEFAULT_ETH_IP)
endef

define INSTALL_LS_DEFAULT_ETH_CONFIG_GEN
	echo "install interface"
	cd $(@D) && cp interfaces $(TARGET_DIR)/etc/network/
endef

endif

ifeq ($(BR2_PACKAGE_NETWORK_MANAGER),y)

BOOT_RUN_DEPENDENCIES = systemd network-manager

define BUILD_LS_DEFAULT_ETH_CONFIG_GEN
	echo "generate new keep-nmcli.sh"
	cd $(@D) && ./gen-keep-nmcli.sh $(BR2_PACKAGE_LS_DEFAULT_ETH_NAME) $(BR2_PACKAGE_LS_DEFAULT_ETH_IP)
endef

define INSTALL_LS_DEFAULT_ETH_CONFIG_GEN
	echo "install keep-nmcli.sh and keep-nmcli.service"
	mkdir -p $(TARGET_DIR)/usr/local
	cd $(@D) && cp keep-nmcli.sh $(TARGET_DIR)/usr/local
	cd $(@D) && cp keep-nmcli.service $(TARGET_DIR)/usr/lib/systemd/system/
	cd $(TARGET_DIR)/usr/lib/systemd/system/multi-user.target.wants && ln -sf ../keep-nmcli.service keep-nmcli.service
endef

endif

define LS_DEFAULT_ETH_CONFIG_BUILD_CMDS
	$(BUILD_LS_DEFAULT_ETH_CONFIG_GEN)
endef

define LS_DEFAULT_ETH_CONFIG_INSTALL_STAGING_CMDS
	echo "nothing to do"
endef

define LS_DEFAULT_ETH_CONFIG_INSTALL_TARGET_CMDS
	$(INSTALL_LS_DEFAULT_ETH_CONFIG_GEN)
endef

$(eval $(generic-package))
