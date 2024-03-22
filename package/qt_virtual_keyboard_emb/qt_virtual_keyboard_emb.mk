################################################################################
#
# qt_virtual_keyboard_emb
#
################################################################################

QT_VIRTUAL_KEYBOARD_EMB_VERSION = origin/master
QT_VIRTUAL_KEYBOARD_EMB_SITE = https://gitee.com/yynestt/QVirtualKeyboard
QT_VIRTUAL_KEYBOARD_EMB_SITE_METHOD = git
QT_VIRTUAL_KEYBOARD_EMB_CFLAGS = $(TARGET_CFLAGS)

QT_VIRTUAL_KEYBOARD_EMB_DEPENDENCIES = qt5base qt5virtualkeyboard

#$(TARGET_MAKE_ENV) $(MAKE) CC=$(TARGET_CC) AR=$(TARGET_AR) -C $(@D)

define QT_VIRTUAL_KEYBOARD_EMB_BUILD_CMDS
	cd $(@D) && mkdir -p build && cd ./build && $(HOST_DIR)/bin/qmake ../VirtualKeyboard.pro && $(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/build
endef

define QT_VIRTUAL_KEYBOARD_EMB_INSTALL_STAGING_CMDS
	echo "nothing to do"
endef

define QT_VIRTUAL_KEYBOARD_EMB_INSTALL_TARGET_CMDS
	cd $(@D) && cp ./bin/plugins/platforminputcontexts/libQt5SoftKeyboard.so $(TARGET_DIR)/usr/lib/qt/plugins/platforminputcontexts
endef

$(eval $(generic-package))
