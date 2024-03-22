################################################################################
#
# mp4_sample
#
################################################################################

MP4_SAMPLE_SITE = $(TOPDIR)/package/mp4_sample/mp4_sample_video.tar.gz
MP4_SAMPLE_SITE_METHOD = file

define MP4_SAMPLE_EXTRACT_CMDS
	tar -zxf $(MP4_SAMPLE_SITE) -C $(@D)
endef

define MP4_SAMPLE_BUILD_CMDS
	mkdir -p $(TARGET_DIR)/root/mp4_sample_video
endef

define MP4_SAMPLE_INSTALL_TARGET_CMDS
	cd $(@D) && cp ./*.mp4 $(TARGET_DIR)/root/mp4_sample_video -a
endef

$(eval $(generic-package))

