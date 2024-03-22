#! /bin/sh

###1 dont delete
tftp_ip=$1
rootfs_name=rootfs.tar.gz
md5_name=md5.txt
uImage_name=uImage
recover_name=ramdisk.gz
recover_local_name=ramdisk.gz

download_mount_point=$2

download_rootfs_path="$download_mount_point/$rootfs_name"
download_md5_path="$download_mount_point/$md5_name"
download_uImage_path="$download_mount_point/$uImage_name"
download_recover_path="$download_mount_point/$recover_local_name"

root_partition="/dev/sda1"
data_partition="/dev/sda2"
swap_partition="/dev/sda3"
backup_partition="/dev/sda4"

###2 dont delete

install_target_type=0

check_cmdline_ins_target()
{
	install_target_type=0
	# install_target_type=$(cat /proc/cmdline | grep ins_target="scsi") #default is scsi
	install_target_type=$(cat /proc/cmdline | grep ins_target=mmc)
	if [ ! -z "$install_target_type" ]; then
		install_target_type=1
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
	install_target_type=0
}

error_inf_print()
{
	echo "";
	echo "*************************************************************************"
	echo "********************************Error Log********************************"
	echo "*************************************************************************"
	echo $1
	sleep 2
	echo "*************************************************************************"
	echo ""
	exit 1;
}

#检查文件是否齐全
check_file_for_safe()
{
	#检查是不是缺少部分文件，不然分了区才说没文件系统，那么原来的系统就会丢失。
	#能来这里执行，就代表本来就有uImage
	echo "-------------> stage1 check_file_for_safe <-------------"
	if [ ! -f "$download_rootfs_path" ]; then
		error_inf_print "Error! not found "$rootfs_name" download failed!"
		exit 1;
	fi
	if [ ! -f "$download_uImage_path" ]; then
		error_inf_print "Error! not found "$uImage_name" download failed!"
		exit 1;
	fi
}

download_system()
{
	echo "$rootfs_name downloading...."
	tftp -l "$download_rootfs_path" -r $rootfs_name -g $tftp_ip -b 65535
	echo "$uImage_name downloading...."
	tftp -l "$download_uImage_path" -r $uImage_name -g $tftp_ip -b 4096

	if [ ! -z $md5_name ]; then
		tftp -l "$download_md5_path" -r $md5_name -g $tftp_ip 2>/dev/null

		if [ -f "$download_md5_path" ]; then
			if [ -f "$download_rootfs_path" ]; then
				ori_md5=$(cat "$download_md5_path" | cut -d ' ' -f1);
				local_md5=$(md5sum "$download_rootfs_path" | cut -d ' ' -f1);

				if [ "$ori_md5" == "$local_md5" ]; then
					echo "md5 check success!!!";
				else
					error_inf_print "md5 check failed!!! remove $rootfs_name";
					rm "$download_rootfs_path"
				fi

				rm "$download_md5_path"
			fi
		fi
	fi

	if [ -e $backup_partition ]; then
		tftp -l "$download_recover_path" -r $recover_name -g $tftp_ip -b 4096 2>/dev/null
	fi
	check_file_for_safe;
	return $?
}

check_cmdline_ins_target
download_system
exit $?
