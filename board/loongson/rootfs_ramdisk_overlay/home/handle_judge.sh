#! /bin/sh

# 0 install 1 recover
handle_type=0

check_cmdline_ins_target()
{
	install_target_type=0
	# install_target_type=$(cat /proc/cmdline | grep ins_target="scsi") #default is scsi
	install_target_type=$(cat /proc/cmdline | grep ins_target=mmc)
	if [ ! -z "$install_target_type" ]; then
		old_path=$PWD
		cd /home/fstab
		./update_device_name.sh "/dev/mmcblk0p"
		cd $old_path
		return 0
	fi
	install_target_type=$(cat /proc/cmdline | grep rec_target=mmc)
	if [ ! -z "$install_target_type" ]; then
		old_path=$PWD
		cd /home/fstab
		./update_device_name.sh "/dev/mmcblk0p"
		cd $old_path
		return 0
	fi
}

judge_cmdline()
{
	temp_str=$(cat /proc/cmdline | grep ins_way)
	if [ ! -z "$temp_str" ]; then
		handle_type=0;
		return 0;
	fi
	temp_str=$(cat /proc/cmdline | grep "rec_sys=1")
	if [ ! -z "$temp_str" ]; then
		handle_type=1;
		return 0;
	fi
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo "your uboot version maybe not a laster version!"
	echo "so this ramdisk.gz will handle install action!"
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	return 1
}

start()
{
	check_cmdline_ins_target
	judge_cmdline
	res=$?
	if [ $res -eq 1 ]; then
		/home/install_usb.sh
	else
		if [ $handle_type -eq 0 ]; then
			echo "Install System..."
			/home/install_usb.sh
		elif [ $handle_type -eq 1 ]; then
			echo "Recover System..."
			/home/recover_backup.sh
		else
			echo "handle_judge.sh unexpected handle_type: $handle_type"
			echo "ramdisk failed! exit!"
			return 1
		fi
	fi
	return 0
}

start
