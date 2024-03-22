################################################################################
#
# wqy-zenhei
#
################################################################################

SOURCEHANSERIF_SITE = $(TOPDIR)/package/sourcehanserif/sourcehanserif.tar.gz
SOURCEHANSERIF_SITE_METHOD = file

ifeq ($(strip $(BR2_PACKAGE_SOURCEHANSERIF_CN_REGULAR_INSTALL_PATH)),"")
	SOURCEHANSERIF_INSTALL_PATH = "/usr/share/fonts"
else
	SOURCEHANSERIF_INSTALL_PATH = $(BR2_PACKAGE_SOURCEHANSERIF_CN_REGULAR_INSTALL_PATH)
endif

define SOURCEHANSERIF_EXTRACT_CMDS
	tar -zxf $(SOURCEHANSERIF_SITE) -C $(@D)/
endef

ifeq ($(BR2_PACKAGE_SOURCEHANSERIF_CN_REGULAR),y)
define SOURCEHANSERIF_INSTALL_CN_REGULAR_CMD
	$(INSTALL) -D -m 0644 $(@D)/SourceHanSerifCN-Regular.ttf \
		$(TARGET_DIR)$(SOURCEHANSERIF_INSTALL_PATH)/SourceHanSerifCN-Regular.ttf
endef
endif

ifeq ($(BR2_PACKAGE_SOURCEHANSERIF_CN_REGULAR_SMALL),y)
define SOURCEHANSERIF_INSTALL_CN_REGULAR_CMD
	$(INSTALL) -D -m 0644 $(@D)/SourceHanSerifCN-Regular-small.ttf \
		$(TARGET_DIR)$(SOURCEHANSERIF_INSTALL_PATH)/SourceHanSerifCN-Regular.ttf

endef
endif

define SOURCEHANSERIF_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)$(SOURCEHANSERIF_INSTALL_PATH)
	$(SOURCEHANSERIF_INSTALL_CN_REGULAR_CMD)
endef

$(eval $(generic-package))
