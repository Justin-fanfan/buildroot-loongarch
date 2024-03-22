################################################################################
#
# boot_run
#
################################################################################

BOOT_RUN_SITE = $(TOPDIR)/package/boot_run/boot_run.tar.gz
BOOT_RUN_SITE_METHOD = file

ifeq ($(BR2_INIT_SYSTEMD),y)
BOOT_RUN_DEPENDENCIES = busybox systemd
endif

define BOOT_RUN_EXTRACT_CMDS
	echo $(BOOT_RUN_SITE)
	tar -zxf $(BOOT_RUN_SITE) -C $(@D)/
endef

ifeq ($(BR2_PACKAGE_PSPLASH),y)
define BUILD_BOOT_RUN_PSPLASH_END_SETUP
	cd $(@D) && echo -n "psplash-write \"MSG " >> boot_run.sh
	cd $(@D) && echo -n $(BR2_TARGET_GENERIC_ISSUE) >> boot_run.sh
	cd $(@D) && echo "\"" >> boot_run.sh
	cd $(@D) && echo "psplash-write \"PROGRESS 100\"" >> boot_run.sh
	cd $(@D) && echo "psplash-write \"QUIT\"" >> boot_run.sh
endef
else
define BUILD_BOOT_RUN_PSPLASH_END_SETUP
	echo ""
endef
endif

ifneq ($(findstring $(BR2_PACKAGE_DRIVER_TESTCASE_QT_AUTO_START)$(BR2_PACKAGE_QT_MOVIE_AUTOBOOT),yy),)
define BUILD_BOOT_RUN_QT_START_SLEEP_SETUP
	cd $(@D) && echo "if [ -z \"\$$(cat /proc/cmdline | grep ubifs)\" ]; then" >> boot_run.sh
	cd $(@D) && echo "	sleep 5" >> boot_run.sh
	cd $(@D) && echo "fi" >> boot_run.sh
endef
else
define BUILD_BOOT_RUN_QT_START_SLEEP_SETUP
	echo ""
endef
endif

ifeq ($(BR2_PACKAGE_QT_USE_TSLIB),y)
define BUILD_BOOT_RUN_QT_TSLIB_EXPORT_SETUP
	cd $(@D) && echo "export QT_QPA_FB_TSLIB=1" >> boot_run.sh
endef

define BUILD_BOOT_RUN_PROFILE_ADD_QT_TSLIB_EXPORT
	cd $(TARGET_DIR)/etc/ && if ! grep -q QT_QPA_FB_TSLIB=1 profile ; then echo "export QT_QPA_FB_TSLIB=1" >> profile; fi
endef

else
define BUILD_BOOT_RUN_QT_TSLIB_EXPORT_SETUP
	echo "not tslib not setup"
endef

define BUILD_BOOT_RUN_PROFILE_ADD_QT_TSLIB_EXPORT
	echo "not tslib export add to profile"
endef

endif

ifeq ($(BR2_PACKAGE_DRIVER_TESTCASE_QT_AUTO_START),y)
define BUILD_BOOT_RUN_QT_DRIVER_TESTCASE_SETUP
	echo "setup driver_testcase Qt ver run after boot" && cd $(@D) && echo "/root/loongson_test_case/driver_testcase &" >> boot_run.sh
endef
else
define BUILD_BOOT_RUN_QT_DRIVER_TESTCASE_SETUP
	echo ""
endef
endif

ifeq ($(BR2_PACKAGE_QT_MOVIE_AUTOBOOT),y)
define BUILD_BOOT_RUN_LOGO_PLAYER_SETUP
	echo "setup logo_player run after boot"
	cd $(@D) && echo "if [ -f \"/sys/firmware/devicetree/base/factory/tags\" ]; then" >> boot_run.sh
	cd $(@D) && echo "	cd /root/ && ls_system_tool_qt &" >> boot_run.sh
	cd $(@D) && echo "else" >> boot_run.sh
	cd $(@D) && echo "	cd /root/logo_player && ./logo_player &" >> boot_run.sh
	cd $(@D) && echo "fi" >> boot_run.sh
endef
else
define BUILD_BOOT_RUN_LOGO_PLAYER_SETUP
	echo ""
endef
endif

ifeq ($(BR2_PACKAGE_LS3_SYSTEM_TOOL_QT_AUTO_START),y)
define BUILD_BOOT_RUN_QT_LS3_SYSTEM_TOOL_SETUP
	echo "setup ls3_system_tool Qt ver run after boot" && cd $(@D) && echo "sleep 5;ls_system_tool_qt &" >> boot_run.sh
endef
else
define BUILD_BOOT_RUN_QT_LS3_SYSTEM_TOOL_SETUP
	echo ""
endef
endif

define BOOT_RUN_BUILD_CMDS
	echo "create boot_run.sh"
	cd $(@D) && cp boot_run_ori.sh boot_run.sh
	$(BUILD_BOOT_RUN_PSPLASH_END_SETUP)
	$(BUILD_BOOT_RUN_QT_START_SLEEP_SETUP)
	$(BUILD_BOOT_RUN_QT_TSLIB_EXPORT_SETUP)
	$(BUILD_BOOT_RUN_LOGO_PLAYER_SETUP)
	$(BUILD_BOOT_RUN_QT_DRIVER_TESTCASE_SETUP)
	$(BUILD_BOOT_RUN_QT_LS3_SYSTEM_TOOL_SETUP)
endef

define BOOT_RUN_INSTALL_STAGING_CMDS
	echo "nothing to do"
endef

ifeq ($(BR2_INIT_SYSTEMD),y)
define BOOT_RUN_INSTALL_TARGET_CMDS
	echo "install boot_run.service and boot_run.sh"
	mkdir -p $(TARGET_DIR)/usr/lib/systemd/system/multi-user.target.wants
	cd $(@D) && cp boot_run.service $(TARGET_DIR)/usr/lib/systemd/system/
	cd $(TARGET_DIR)/usr/lib/systemd/system/multi-user.target.wants && ln -b -s ../boot_run.service boot_run_service
	cd $(@D) && chmod a+x ./boot_run.sh && cp boot_run.sh $(TARGET_DIR)/root/
endef
else
define BOOT_RUN_INSTALL_TARGET_CMDS
	echo "install boot_run.sh"
	mkdir -p $(TARGET_DIR)/etc/init.d
	cd $(@D) && chmod a+x S90_boot_run && cp S90_boot_run $(TARGET_DIR)/etc/init.d/
	cd $(@D) && chmod a+x ./boot_run.sh && cp boot_run.sh $(TARGET_DIR)/root/
endef
endif

define BUILD_BOOT_RUN_ADD_TLS_LINK
	mkdir -p $(TARGET_DIR)/usr/lib64/tls; cd $(TARGET_DIR)/usr/lib64/tls; if ! test -L loongarch ; then ln -s ../../lib64/ loongarch; fi
endef

BOOT_RUN_TARGET_FINALIZE_HOOKS += BUILD_BOOT_RUN_PROFILE_ADD_QT_TSLIB_EXPORT
BOOT_RUN_TARGET_FINALIZE_HOOKS += BUILD_BOOT_RUN_ADD_TLS_LINK

$(eval $(generic-package))
