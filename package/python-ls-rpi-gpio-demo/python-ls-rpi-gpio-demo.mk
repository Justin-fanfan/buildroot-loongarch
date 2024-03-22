################################################################################
#
# python-ls-rpi-gpio-demo
#
################################################################################

PYTHON_LS_RPI_GPIO_DEMO_DEPENDENCIES = python-RPi-GPIO-LS

define PYTHON_LS_RPI_GPIO_DEMO_INSTALL_TARGET_CMDS
	echo "install python demo"
	mkdir -p $(TARGET_DIR)/usr/local/python_demo
	cp $(@D)/../python-RPi-GPIO-LS*/python-demo/* $(TARGET_DIR)/usr/local/python_demo/ -a -d
	cd $(TARGET_DIR)/root/ && ln -sf /usr/local/python_demo python_demo
endef

$(eval $(generic-package))

