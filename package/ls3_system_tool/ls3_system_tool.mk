################################################################################
#
# ls3_system_tool
#
################################################################################

LS3_SYSTEM_TOOL_VERSION = origin/master
LS3_SYSTEM_TOOL_SITE = http://192.168.1.5/ls3_system_tool
LS3_SYSTEM_TOOL_SITE_METHOD = git
LS3_SYSTEM_TOOL_GIT_SUBMODULES = YES
LS3_SYSTEM_TOOL_CFLAGS = $(TARGET_CFLAGS)

ifeq ($(BR2_PACKAGE_LS3_SYSTEM_TOOL_QT),y)
LS3_SYSTEM_TOOL_DEPENDENCIES = qt5base
endif

#define LS3_SYSTEM_TOOL_EXTRACT_CMDS

#endef

#$(TARGET_MAKE_ENV) $(MAKE) CC=$(TARGET_CC) AR=$(TARGET_AR) -C $(@D)

define LS3_SYSTEM_TOOL_BUILD_SINGLE_TEST_CASE
	cd $(@D)/test_case_single && ./build_single_test.sh $(TARGET_CC) $(TARGET_CXX)
endef

ifeq ($(BR2_PACKAGE_LS3_SYSTEM_TOOL_QT),y)
define LS3_SYSTEM_TOOL_BUILD_QT_VER_CMDS
	mkdir -p $(@D)/Qtver/build && cd $(@D)/Qtver/build && $(HOST_DIR)/bin/qmake ../ls_system_tool/ls_system_tool.pro && $(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/Qtver/build
endef
define LS3_SYSTEM_TOOL_INSTALL_QT_VER_CMDS
	echo "install Qt version sofeware" && cd $(@D)/Qtver/build/ && cp ls_system_tool $(TARGET_DIR)/usr/bin/ls_system_tool_qt
endef
else
define LS3_SYSTEM_TOOL_BUILD_QT_VER_CMDS
	echo "not build Qt version"
endef
define LS3_SYSTEM_TOOL_INSTALL_QT_VER_CMDS
	echo "not install Qt version"
endef
endif

define LS3_SYSTEM_TOOL_INSTALL_SINGLE_TEST_CASE
	cd $(TARGET_DIR)/ && mkdir -p ./root/loongson_test_case && cd $(@D)/test_case_single/out/loongson_test_case && cp -r * $(TARGET_DIR)/root/loongson_test_case/
endef

ifeq ($(BR2_PACKAGE_LS3_SYSTEM_TOOL_QT_AUTO_START),y)

ifeq ($(BR2_PACKAGE_BOOT_RUN),y)
define LS3_SYSTEM_TOOL_INSTALL_AUTO_EXEC_AFTER_BOOT_CMDS
	echo "auto run in boot in /root/boot_run.sh"
endef
else
define LS3_SYSTEM_TOOL_INSTALL_AUTO_EXEC_AFTER_BOOT_CMDS
	echo "install auto boot Qt version sofeware service" && cd $(TOPDIR)/package/ls3_system_tool/ && cp ls3_system_tool.service $(TARGET_DIR)/usr/lib/systemd/system/ && cd $(TARGET_DIR)/usr/lib/systemd/system/ && mkdir -p multi-user.target.wants && cd $(TARGET_DIR)/usr/lib/systemd/system/multi-user.target.wants && ln -s -f ../ls3_system_tool.service ls3_system_tool.service
endef
endif

else
define LS3_SYSTEM_TOOL_INSTALL_AUTO_EXEC_AFTER_BOOT_CMDS
	echo "nothing to do"
endef
endif

# echo "first cmake all single test case"
# cd $(@D) && mkdir -p build && cd ./build && cmake -D CMAKE_C_COMPILER=$(TARGET_CC) ../
# $(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/build/
# cd $(@D) && export CC=$(TARGET_CC); export $(TARGET_MAKE_ENV); export ARCH=$(BR2_ARCH); export CROSS_COMPILE=$(BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX)-; ./compile_ob_cp.sh && ./install_single_test.sh

define LS3_SYSTEM_TOOL_BUILD_CMDS
	$(LS3_SYSTEM_TOOL_BUILD_SINGLE_TEST_CASE)
	echo "build cmd version sofeware"
	cd $(@D) && export $(TARGET_MAKE_ENV); export CC=$(TARGET_CC); export ARCH=$(BR2_ARCH); export CROSS_COMPILE=$(BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX)-; ./build.sh rebuild
	$(LS3_SYSTEM_TOOL_BUILD_QT_VER_CMDS)
endef

define LS3_SYSTEM_TOOL_INSTALL_STAGING_CMDS
	echo "nothing to do"
endef

# echo "install all single test case"
# cd $(TARGET_DIR)/ && mkdir -p ./root/loongson_test_case
# cd $(@D) && cd out/loongson_test_case/ && cp -r * $(TARGET_DIR)/root/loongson_test_case/
# echo "install test-server(all test case test tool)"
# mkdir -p $(TARGET_DIR)/root/loongson-test-server
# cd $(@D)/test-server-project && cp test-server $(TARGET_DIR)/root/loongson-test-server
# #cd $(@D)/test-server-project && cp can_client $(TARGET_DIR)/root/loongson-test-server

define LS3_SYSTEM_TOOL_INSTALL_TARGET_CMDS
	$(LS3_SYSTEM_TOOL_INSTALL_SINGLE_TEST_CASE)
	cd $(@D) && ./package_output.sh
	cd $(@D)/ls_system_tool_install && cp ls_system_tool $(TARGET_DIR)/usr/bin/
	mkdir -p $(TARGET_DIR)/opt/ls_system_config
	cd $(@D)/ls_system_tool_install && cp -a shell $(TARGET_DIR)/opt/ls_system_config/
	$(LS3_SYSTEM_TOOL_INSTALL_QT_VER_CMDS)
	$(LS3_SYSTEM_TOOL_INSTALL_AUTO_EXEC_AFTER_BOOT_CMDS)
endef

$(eval $(generic-package))
