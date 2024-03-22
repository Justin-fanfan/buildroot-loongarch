################################################################################
#
# mdio
#
################################################################################

MDIO_SITE = $(TOPDIR)/dl/mdio/mdio.tar.gz
MDIO_SITE_METHOD = file

define MDIO_EXTRACT_CMDS
	tar -zxf $(MDIO_SITE) -C $(@D)
endef

define MDIO_BUILD_CMDS
	cd $(@D) && $(TARGET_CC) mdio.c -o mdio
endef

define MDIO_INSTALL_TARGET_CMDS
	cd $(@D) && cp mdio $(TARGET_DIR)/usr/bin
endef

$(eval $(generic-package))
