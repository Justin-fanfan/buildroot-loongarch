################################################################################
#
# LoongsonGD Linux kernel target
#
################################################################################

LOONGSON_KERNEL_SITE = $(TOPDIR)/package/loongson_kernel/loongson_kernel.tar.gz
LOONGSON_KERNEL_SITE_METHOD = file

ifeq ($(BR2_PACKAGE_LOONGSON_KERNEL_MODULES),y)
define INSTALL_KERNEL_OR_WITH_MODULES
	mkdir -p $(TARGET_DIR)/boot
	cd $(@D) && cp uImage $(TARGET_DIR)/boot
	cd $(@D) && mv lib/modules/ $(TARGET_DIR)/usr/lib/
endef
else
define INSTALL_KERNEL_OR_WITH_MODULES
	mkdir -p $(TARGET_DIR)/boot
	cd $(@D) && cp uImage $(TARGET_DIR)/boot
endef
endif

define LOONGSON_KERNEL_EXTRACT_CMDS
	tar -xzf $(LOONGSON_KERNEL_SITE) -C $(@D)/ --strip-components 1
endef

define LOONGSON_KERNEL_INSTALL_TARGET_CMDS
	echo "install LSGD Kernel"
	$(INSTALL_KERNEL_OR_WITH_MODULES)
endef

$(eval $(generic-package))
