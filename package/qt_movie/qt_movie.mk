################################################################################
#
# qt_movie
#
################################################################################

QT_MOVIE_SITE = $(TOPDIR)/package/qt_movie/qt_movie.tar.gz
QT_MOVIE_SITE_METHOD = file
QT_MOVIE_CFLAGS = $(TARGET_CFLAGS)

QT_MOVIE_DEPENDENCIES = qt5base

define QT_MOVIE_EXTRACT_CMDS
	echo $(QT_MOVIE_SITE)
	tar -zxf $(QT_MOVIE_SITE) -C $(@D)/
endef

ifeq ($(BR2_PACKAGE_QT_MOVIE_AUTOBOOT),y)

ifeq ($(BR2_PACKAGE_BOOT_RUN),y)
define QT_MOVIE_INSTALL_AUTO_EXEC_AFTER_BOOT_CMDS
	echo "auto run in boot in /root/boot_run.sh"
endef
else
define QT_MOVIE_INSTALL_AUTO_EXEC_AFTER_BOOT_CMDS
	echo "install auto boot logo_player sofeware service" && cd $(TOPDIR)/package/qt_movie/ && cp logo_player.service $(TARGET_DIR)/usr/lib/systemd/system/ && cd $(TARGET_DIR)/usr/lib/systemd/system/ && mkdir -p multi-user.target.wants && cd $(TARGET_DIR)/usr/lib/systemd/system/multi-user.target.wants && ln -s -f ../logo_player.service logo_player.service
endef
endif

else
define QT_MOVIE_INSTALL_AUTO_EXEC_AFTER_BOOT_CMDS
	echo "nothing to do"
endef
endif

#$(TARGET_MAKE_ENV) $(MAKE) CC=$(TARGET_CC) AR=$(TARGET_AR) -C $(@D)

define QT_MOVIE_BUILD_CMDS
	cd $(@D) && $(HOST_DIR)/bin/qmake movie.pro && $(TARGET_MAKE_ENV) $(MAKE) -C $(@D)
endef

define QT_MOVIE_INSTALL_STAGING_CMDS
	echo "nothing to do"
endef

define QT_MOVIE_INSTALL_TARGET_CMDS
	mkdir -p $(TARGET_DIR)/root/logo_player/
	cd $(@D) && cp movie $(TARGET_DIR)/root/logo_player/logo_player
	cd $(@D) && cp logo.gif $(TARGET_DIR)/root/logo_player/
endef

$(eval $(generic-package))
