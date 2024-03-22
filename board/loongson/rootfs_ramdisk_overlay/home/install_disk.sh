echo " ";
echo "*************************************************************************"
echo "*********************************STARG 2*********************************"
echo "*******************uzip system and setup it with fstab*******************"
echo "*************************************************************************"
echo " ";
sleep 2;

usb_partition="/dev/sdb1"
usb_partition_bak="/dev/sdb"
root_partition="/dev/sda1"
data_partition="/dev/sda2"
swap_partition="/dev/sda3"
backup_partition="/dev/sda4"

usb_mount_point="/mnt/usb0"
root_mount_point="/mnt/usb1"
data_mount_point="/mnt/usb2"
swap_mount_point="/mnt/usb3"
backup_mount_point="/mnt/usb4"

install_target_type=0

check_cmdline_ins_target()
{
	install_target_type=0
	# install_target_type=$(cat /proc/cmdline | grep ins_target="scsi") #default is scsi
	install_target_type=$(cat /proc/cmdline | grep ins_target=mmc)
	if [ ! -z "$install_target_type" ]; then
		install_target_type=1

		usb_partition="/dev/sda1"
		usb_partition_bak="/dev/sda"
		root_partition="/dev/mmcblk0p1"
		data_partition="/dev/mmcblk0p2"
		swap_partition="/dev/mmcblk0p3"
		backup_partition="/dev/mmcblk0p4"
		return 0
	fi

	usb_partition="/dev/sdb1"
	usb_partition_bak="/dev/sdb"
	root_partition="/dev/sda1"
	data_partition="/dev/sda2"
	swap_partition="/dev/sda3"
	backup_partition="/dev/sda4"
	install_target_type=0
}

#错误信息输出到usb的install文件夹里的error.log
#注意安装系统时install文件夹不要存放error.log
#否则会先改名error.log.bak,多次执行后，这样可能会造成数据丢失
error_inf_write_usb()
{
	if mountpoint -q $usb_mount_point; then
		echo $1 >> $usb_mount_point"/install/error.log";
	else
		mount $usb_partition $usb_mount_point;
		if mountpoint -q $usb_mount_point; then
			echo $1 >> $usb_mount_point"/install/error.log";
			sync;
			umount $usb_mount_point;
		else
			echo "-------------> log error: couldn't mount usb("$usb_partition") <-------------"
		fi
	fi
}

error_inf_print()
{
	echo "";
	echo "*************************************************************************"
	echo "********************************Error Log********************************"
	echo "*************************************************************************"
	echo $1
	error_inf_write_usb $1
	check_and_umount_for_safe;
	exit 1;
}

# sda1 / 	usb1
# sda2 data usb2
# sda3 swap usb3
# sda4 backup usb4

#uzip_rootfs 解压文件系统到根文件分区 必要
#copy_uimage_to_boot 复制内核到/boot目录（没做boot分区）必要
#copy_file_to_data 复制home opt var到data分区 不一定，根据fstab而定

uzip_rootfs()
{
	echo "-------------> stage2.1 unzip system <-------------"

	if [ -e "/dev/fb0" ]; then
		show_process_dev="/dev/tty0"
	else
		if [ -e "/dev/console" ]; then
			show_process_dev="/dev/console"
		else
			show_process_dev="/dev/tty0"
		fi
	fi

	if [ -e $backup_partition ]; then
		mount $backup_partition $backup_mount_point
		sync;
		mount $root_partition $root_mount_point
		sync;
		echo "can observe process in screen"
		pv $backup_mount_point/rootfs.tar.gz 2>$show_process_dev | tar -xzf - -C $root_mount_point;
		if [ $? -ne 0 ]; then
			error_inf_print "Error! unzip system failed! Please check rootfs.tar.gz and try again";
		fi
	else
		mount $root_partition $root_mount_point
		sync;
		echo "can observe process in screen"
		pv $root_mount_point/rootfs.tar.gz 2>$show_process_dev | tar -xzf - -C $root_mount_point;
		if [ $? -ne 0 ]; then
			error_inf_print "Error! unzip system failed! Please check rootfs.tar.gz and try again";
		fi
		rm -r $root_mount_point/rootfs.tar.gz
	fi
	check_and_umount_for_safe;
	return 0;
}

copy_uImage_to_boot()
{
	echo "-------------> stage2.2 copy uImage to /boot <-------------"
	if [ -e $backup_partition ]; then
		mount $backup_partition $backup_mount_point
		sync;
		mount $root_partition $root_mount_point
		sync;

		#保证boot文件存在
		if [ ! -d $root_mount_point/boot ]; then
			mkdir $root_mount_point/boot
		fi

		cp -a $backup_mount_point/uImage $root_mount_point/boot/
		if [ $? -ne 0 ]; then
			error_inf_print "Error! copy uImage failed! Please try again";
		fi
	else
		mount $root_partition $root_mount_point
		sync;

		#保证boot文件存在
		if [ ! -d $root_mount_point/boot ]; then
			mkdir $root_mount_point/boot
		fi

		mv $root_mount_point/uImage $root_mount_point/boot/
		if [ $? -ne 0 ]; then
			error_inf_print "Error! copy uImage failed! Please try again";
		fi
	fi
	check_and_umount_for_safe;
	return 0;
}

copy_fstab()
{
	echo "-------------> stage2.3 copy fstab to /etc/fstab <-------------"
	sda1_partition_target=0
	sda2_partition_target=0
	sda3_partition_target=0
	sda4_partition_target=0
	if [ -e $root_partition ]; then
		sda1_partition_target=1;
	fi
	if [ -e $data_partition ]; then
		sda2_partition_target=1;
	fi
	if [ -e $swap_partition ]; then
		sda3_partition_target=1;
	fi
	if [ -e $backup_partition ]; then
		sda4_partition_target=1;
	fi

	mount $root_partition $root_mount_point;
	sync;

	if [ -f $root_mount_point/etc/fstab ]; then
		cp $root_mount_point/etc/fstab $root_mount_point/etc/fstab_ori;
		cp "/home/fstab/"$sda4_partition_target$sda3_partition_target$sda2_partition_target$sda1_partition_target"part_fstab" $root_mount_point/etc/fstab;

		echo "" >> $root_mount_point/etc/fstab
		cat $root_mount_point/etc/fstab_ori | grep proc >> $root_mount_point/etc/fstab;
		cat $root_mount_point/etc/fstab_ori | grep sysfs >> $root_mount_point/etc/fstab;
		cat $root_mount_point/etc/fstab_ori | grep tmpfs >> $root_mount_point/etc/fstab;
		cat $root_mount_point/etc/fstab_ori | grep devpts >> $root_mount_point/etc/fstab;
	else
		cp "/home/fstab/"$sda4_partition_target$sda3_partition_target$sda2_partition_target$sda1_partition_target"part_fstab" $root_mount_point/etc/fstab;
	fi

	check_and_umount_for_safe;
	return 0;
}

copy_file_to_data()
{
	echo "-------------> stage2.4 copy file to data partition <-------------"
	mount $data_partition $data_mount_point;
	sync;
	mount $root_partition $root_mount_point;
	sync;

	cp -a $root_mount_point/root/ $data_mount_point;
	cp -a $root_mount_point/home/ $data_mount_point;
	cp -a $root_mount_point/opt/ $data_mount_point;
	cp -a $root_mount_point/var/ $data_mount_point;
	sync;

	rm -r $root_mount_point/root/
	rm -r $root_mount_point/home/
	rm -r $root_mount_point/opt/
	rm -r $root_mount_point/var/

	mkdir -p $root_mount_point/root/
	mkdir -p $root_mount_point/home/
	mkdir -p $root_mount_point/opt/
	mkdir -p $root_mount_point/var/
	mkdir -p $root_mount_point/data/
	sync;

	check_and_umount_for_safe;
	return 0;
}

#防止前面的脚本出现错误，导致没有解除挂载一些已经挂载的分区。
check_and_umount_for_safe()
{
	for i in /mnt/usb*; do
	{
		if mountpoint -q $i; then
			sync;
			umount $i;
		fi
	}
	done
}

#相关分区
#backup分区
start_stage2()
{
	uzip_rootfs
	echo ""
	copy_uImage_to_boot
	echo ""
	copy_fstab;
	echo ""
	if [ -e $data_partition ]; then
		copy_file_to_data
	fi
}

check_usb_name()
{
	if [ ! -e $usb_partition ]; then
		usb_partition=$usb_partition_bak
	fi
}

###################start##########################
###################start##########################
###################start##########################

check_cmdline_ins_target
#防止第一个阶段因未知原因而导致没有解除挂载
if [ $# -eq 1 ]; then
	usb_partition=$1
fi
check_and_umount_for_safe;
check_usb_name; #如果前面有参数 那么 这里的判断等于白做事
start_stage2;
check_and_umount_for_safe;

echo "-------------> stage2 end <-------------"

/home/install_reboot.sh
