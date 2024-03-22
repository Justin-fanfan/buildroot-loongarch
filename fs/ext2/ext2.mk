################################################################################
#
# Build the ext2 root filesystem image
#
################################################################################

ifeq ($(BR2_TARGET_ROOTFS_IMG_WITH_PARTITION),y)
ROOTFS_EXT2_SIZE = $(shell expr $(BR2_TARGET_ROOTFS_IMG_WITH_PARTITION_SIZE) - 1)M
else
ROOTFS_EXT2_SIZE = $(call qstrip,$(BR2_TARGET_ROOTFS_EXT2_SIZE))
endif
ifeq ($(BR2_TARGET_ROOTFS_EXT2)-$(ROOTFS_EXT2_SIZE),y-)
$(error BR2_TARGET_ROOTFS_EXT2_SIZE cannot be empty)
endif

ROOTFS_EXT2_MKFS_OPTS = $(call qstrip,$(BR2_TARGET_ROOTFS_EXT2_MKFS_OPTIONS))

# qstrip results in stripping consecutive spaces into a single one. So the
# variable is not qstrip-ed to preserve the integrity of the string value.
ROOTFS_EXT2_LABEL = $(subst ",,$(BR2_TARGET_ROOTFS_EXT2_LABEL))
#" Syntax highlighting... :-/ )

ROOTFS_EXT2_OPTS = \
	-d $(TARGET_DIR) \
	-r $(BR2_TARGET_ROOTFS_EXT2_REV) \
	-N $(BR2_TARGET_ROOTFS_EXT2_INODES) \
	-m $(BR2_TARGET_ROOTFS_EXT2_RESBLKS) \
	-L "$(ROOTFS_EXT2_LABEL)" \
	-I $(BR2_TARGET_ROOTFS_EXT2_INODE_SIZE) \
	$(ROOTFS_EXT2_MKFS_OPTS)

ROOTFS_EXT2_DEPENDENCIES = host-e2fsprogs

ifeq ($(BR2_TARGET_ROOTFS_IMG_WITH_PARTITION),y)
define ROOTFS_PARTITION_TABLE_CMD
	dd if=/dev/zero of=$(BINARIES_DIR)/table.img bs=1M count=$(BR2_TARGET_ROOTFS_IMG_WITH_PARTITION_SIZE)
	echo "o" > $(BINARIES_DIR)/fdisk.txt
	echo "n" >> $(BINARIES_DIR)/fdisk.txt
	echo "p" >> $(BINARIES_DIR)/fdisk.txt
	echo "1" >> $(BINARIES_DIR)/fdisk.txt
	echo "" >> $(BINARIES_DIR)/fdisk.txt
	echo "" >> $(BINARIES_DIR)/fdisk.txt
	echo "w" >> $(BINARIES_DIR)/fdisk.txt
	$(HOST_DIR)/sbin/fdisk $(BINARIES_DIR)/table.img < $(BINARIES_DIR)/fdisk.txt
	dd if=$(BINARIES_DIR)/table.img of=$(BINARIES_DIR)/table-1.img bs=1M count=1
	mv $(BINARIES_DIR)/table-1.img $(BINARIES_DIR)/table.img
	cat $(BINARIES_DIR)/table.img $(BINARIES_DIR)/rootfs.ext2 > $(BINARIES_DIR)/rootfs.ext2.new
	mv $(BINARIES_DIR)/rootfs.ext2.new $(BINARIES_DIR)/rootfs.ext2
	rm -rf $(BINARIES_DIR)/table.img
	rm -rf $(BINARIES_DIR)/fdisk.txt
endef
else
define ROOTFS_PARTITION_TABLE_CMD
	echo ""
endef
endif

define ROOTFS_EXT2_CMD
	rm -f $@
	$(HOST_DIR)/sbin/mkfs.ext$(BR2_TARGET_ROOTFS_EXT2_GEN) $(ROOTFS_EXT2_OPTS) $@ \
		"$(ROOTFS_EXT2_SIZE)" \
	|| { ret=$$?; \
	     echo "*** Maybe you need to increase the filesystem size (BR2_TARGET_ROOTFS_EXT2_SIZE)" 1>&2; \
	     exit $$ret; \
	}
	$(ROOTFS_PARTITION_TABLE_CMD)
endef

ifneq ($(BR2_TARGET_ROOTFS_EXT2_GEN),2)
define ROOTFS_EXT2_SYMLINK
	ln -sf rootfs.ext2$(ROOTFS_EXT2_COMPRESS_EXT) $(BINARIES_DIR)/rootfs.ext$(BR2_TARGET_ROOTFS_EXT2_GEN)$(ROOTFS_EXT2_COMPRESS_EXT)
endef

ROOTFS_EXT2_POST_GEN_HOOKS += ROOTFS_EXT2_SYMLINK
endif

ifeq ($(BR2_TARGET_ROOTFS_IMG), y)
define ROOTFS_IMG
	ln -sf rootfs.ext2$(ROOTFS_EXT2_COMPRESS_EXT) $(BINARIES_DIR)/rootfs.img
endef

ROOTFS_EXT2_POST_GEN_HOOKS += ROOTFS_IMG
endif

$(eval $(rootfs))
