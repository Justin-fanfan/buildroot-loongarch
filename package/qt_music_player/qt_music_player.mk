################################################################################
#
# qt_music_player
#
################################################################################

QT_MUSIC_PLAYER_SITE = $(TOPDIR)/package/qt_music_player/qt_music_player.tar.gz
QT_MUSIC_PLAYER_SITE_METHOD = file
QT_MUSIC_PLAYER_CFLAGS = $(TARGET_CFLAGS)

QT_MUSIC_PLAYER_DEPENDENCIES = qt5base

define QT_MUSIC_PLAYER_EXTRACT_CMDS
	echo $(QT_MUSIC_PLAYER_SITE)
	tar -zxf $(QT_MUSIC_PLAYER_SITE) -C $(@D)/ --strip=1
endef

define QT_MUSIC_PLAYER_BUILD_CMDS
	cd $(@D) && $(HOST_DIR)/bin/qmake mplayer.pro && $(TARGET_MAKE_ENV) $(MAKE) -C $(@D)
endef

define QT_MUSIC_PLAYER_INSTALL_TARGET_CMDS
	cd $(@D) && cp mplayer $(TARGET_DIR)/root/
endef

$(eval $(generic-package))
