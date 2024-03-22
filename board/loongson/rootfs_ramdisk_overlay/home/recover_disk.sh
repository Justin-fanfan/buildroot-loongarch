echo " ";
echo "*************************************************************************"
echo "*********************************STARG 2*********************************"
echo "*******************uzip system and setup it with fstab*******************"
echo "*************************************************************************"
echo " ";
sleep 2;

root_partition="/dev/sda1"
data_partition="/dev/sda2"
swap_partition="/dev/sda3"
backup_partition="/dev/sda4"

root_mount_point="/mnt/usb1"
data_mount_point="/mnt/usb2"
swap_mount_point="/mnt/usb3"
backup_mount_point="/mnt/usb4"

check_cmdline_ins_target()
{
	install_target_type=0
	# install_target_type=$(cat /proc/cmdline | grep ins_target="scsi") #default is scsi
	install_target_type=$(cat /proc/cmdline | grep rec_target=mmc)
	if [ ! -z "$install_target_type" ]; then
		root_partition="/dev/mmcblk0p1"
		data_partition="/dev/mmcblk0p2"
		swap_partition="/dev/mmcblk0p3"
		backup_partition="/dev/mmcblk0p4"
		return 0
	fi

	root_partition="/dev/sda1"
	data_partition="/dev/sda2"
	swap_partition="/dev/sda3"
	backup_partition="/dev/sda4"
}

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

#错误信息输出到backup分区里的error.log
#注意安装系统时backup分区不要存放error.log
#否则会先改名error.log.bak,多次执行后，这样可能会造成数据丢失
error_inf_write_backup()
{
	if mountpoint -q $backup_mount_point; then
		echo $1 >> $backup_mount_point"/error.log";
	else
		mount $backup_partition $backup_mount_point;
		if mountpoint -q $backup_mount_point; then
			echo $1 >> $backup_mount_point"/error.log";
			sync;
			umount $backup_mount_point;
		else
			echo "-------------> log error: couldn't mount backup partition("$backup_partition") <-------------"
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
	error_inf_write_backup $1
	check_and_umount_for_safe;
	echo "*************************************************************************"
	echo ""
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
	echo "-------------> stage2.1 uzip_rootfs <-------------";

	mount $root_partition $root_mount_point;
	sync;
	mount $backup_partition $backup_mount_point;
	sync;

	if [ -e "/dev/fb0" ]; then
		show_process_dev="/dev/tty0"
	else
		if [ -e "/dev/console" ]; then
			show_process_dev="/dev/console"
		else
			show_process_dev="/dev/tty0"
		fi
	fi

	echo "can observe process in screen"
	pv $backup_mount_point/rootfs.tar.gz 2>$show_process_dev | tar -xzf - -C $root_mount_point;
	if [ $? -ne 0 ]; then
		error_inf_print "Error! unzip rootfs.tar.gz failed!"
	fi

	check_and_umount_for_safe;
	return 0;
}

copy_uimage_to_boot()
{
	echo "-------------> stage2.2 copy_uimage_to_boot <-------------";

	mount $root_partition $root_mount_point;
	sync;
	mount $backup_partition $backup_mount_point;
	sync;

	mkdir -p $root_mount_point/boot/
	cp -a $backup_mount_point/uImage $root_mount_point/boot/;
	if [ $? -ne 0 ]; then
		error_inf_print "Error! copy uImage to /boot/ failed!"
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
	mv $root_mount_point/etc/fstab $root_mount_point/etc/fstab_ori;
	cp "/home/fstab/"$sda4_partition_target$sda3_partition_target$sda2_partition_target$sda1_partition_target"part_fstab" $root_mount_point/etc/fstab;

	check_and_umount_for_safe;
	return 0;
}


#相关分区
#data 分区
#/ 分区
#/分区里面的/home /opt /var复制到data分区，然后删除自身的/home /opt /var
copy_file_to_data()
{
	echo "-------------> stage2.4 update data partition <-------------";

	mount $root_partition $root_mount_point
	sync
	mount $data_partition $data_mount_point
	sync

	#必须重置dpkg的记录，否则就会提示什么包都装好了，但是程序提示找不到
	# if [ -d $2/var/lib/dpkg ]; then
	# {
	# 	echo "-------------> stage2.3 delete dpkg inf in data partition <-------------"
	# 	rm -r $2/var/lib/dpkg;
	# 	sync;
	# }
	# fi
	# echo "-------------> stage2.3 copy dpkg inf to data partition <-------------"
	# cp -a $4/var/lib/dpkg $2/var/lib
	# sync;
	# sleep 1;

	#先保留mysql的数据，然后删除var，复制var过来，然后再恢复mysql的数据
	if [ -d $data_mount_point/var ]; then
		if [ -d $data_mount_point/var/lib/mysql ]; then
			echo "-------------> stage2.3 backup mysql data to data partition <-------------";
			cp -a $data_mount_point/var/lib/mysql $data_mount_point/;
			sync;
		fi
		rm -r $data_mount_point/var
	fi
	cp -a $root_mount_point/var $data_mount_point/var
	if [ -d $data_mount_point/mysql ]; then
		rm -r $data_mount_point/var/lib/mysql 2>/dev/null
		cp -a $data_mount_point/mysql $data_mount_point/var/lib/mysql
	fi
	rm -r $root_mount_point/var;
	sync;

	rm -r $root_mount_point/home;
	sync;

	rm -r $root_mount_point/opt;
	sync;

	rm -r $root_mount_point/root;
	sync;

	mkdir -p $root_mount_point/var
	mkdir -p $root_mount_point/home
	mkdir -p $root_mount_point/opt
	mkdir -p $root_mount_point/root
	mkdir -p $root_mount_point/data

	check_and_umount_for_safe;
}

#相关分区
#backup分区
start_stage2()
{
	check_cmdline_ins_target
	#执行三个阶段的操作
	uzip_rootfs;
	copy_uimage_to_boot;
	copy_fstab;
	if [ -e $data_partition ]; then
		copy_file_to_data;
	fi
}

###################start##########################
###################start##########################
###################start##########################

#防止第一个阶段因未知原因而导致没有解除挂载
check_and_umount_for_safe;
start_stage2;
check_and_umount_for_safe;

echo "-------------> stage2 end <-------------"

/home/recover_reboot.sh
