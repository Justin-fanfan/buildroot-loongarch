echo " ";
echo "*************************************************************************"
echo "*********************************STARG 1*********************************"
echo "************************this stage for format SSD************************"
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

create_all_mount_point()
{
	if [ ! -d $root_mount_point ]; then
		mkdir $root_mount_point
	fi
	if [ ! -d $data_mount_point ]; then
		mkdir $data_mount_point
	fi
	if [ ! -d $swap_mount_point ]; then
		mkdir $swap_mount_point
	fi
	if [ ! -d $backup_mount_point ]; then
		mkdir $backup_mount_point
	fi
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

create_all_mount_point()
{
	if [ ! -d $root_mount_point ]; then
		mkdir $root_mount_point
	fi
	if [ ! -d $data_mount_point ]; then
		mkdir $data_mount_point
	fi
	if [ ! -d $swap_mount_point ]; then
		mkdir $swap_mount_point
	fi
	if [ ! -d $backup_mount_point ]; then
		mkdir $backup_mount_point
	fi
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

#format_all_partition 格式化所有分区 必要

#检查文件是否齐全
check_file_for_safe()
{
	echo "-------------> stage1 check_file_for_safe <-------------"
	#检查是不是缺少部分文件，不然格式化了才说没文件系统，那么原来的系统就会丢失。
	#能来这里执行，就代表本来就有uImage
	if [ ! -f $backup_mount_point"/uImage" ]; then
		error_inf_print "Error! not found uImage in backup partition!"
	fi
	if [ ! -f $backup_mount_point"/rootfs.tar.gz" ]; then
		error_inf_print "Error! not found rootfs.tar.gz in backup partition!"
	fi
}

#相关分区
#所有分区，这是格式化分区的函数
format_all_partition()
{
	#分区格式化
	if [ -e $root_partition ]; then
		echo "-------------> stage1.1 format / partition --- start <-------------"
		mke2fs -t ext4 -L rootfs -F $root_partition -O ^metadata_csum >/dev/null;
		if [ $? -eq 0 ]; then
			echo "-------------> stage1.1 format / partition --- success <-------------"
		else
			error_inf_print "Error! format / partition failed! Please try again"
		fi
		sync
	fi

	if [ -e $swap_partition ]; then
		echo "-------------> stage1.1 format swap partition --- start <-------------"
		mkswap $swap_partition >/dev/null;
		if [ $? -eq 0 ]; then
			echo "-------------> stage1.1 format swap partition --- success <-------------"
		else
			error_inf_print "Error! format swap partition failed! Please try again"
		fi
		sync
	fi
	return 0;
}

start_stage1()
{
	sleep 1;
	sync;
	check_cmdline_ins_target
	create_all_mount_point;
	mount $backup_partition $backup_mount_point;
	if mountpoint -q $backup_mount_point; then
		if [ -f $backup_mount_point"/error.log" ]; then
			echo "-------------> stage1 warning: found error.log <-------------"
			echo "-------------> stage1 warning: rename error.log as error.log.bak <-------------"
			mv $backup_mount_point/error.log $backup_mount_point/error.log.bak
		fi

		check_file_for_safe;
		if [ $? -eq 1 ]; then
			exit 1;
		fi
		umount $backup_mount_point;
	fi
	format_all_partition;
}

###################start##########################
###################start##########################
###################start##########################

check_and_umount_for_safe;
start_stage1;
check_and_umount_for_safe;

echo "-------------> stage1 end <-------------"

/home/recover_disk.sh
