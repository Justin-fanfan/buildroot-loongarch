echo " ";
echo "*************************************************************************"
echo "*********************************STARG 3*********************************"
echo "*******************this stage for check log and reboot*******************"
echo "*************************************************************************"
echo " ";

# sda1 / 	usb1
# sda2 data usb2
# sda3 swap usb3
# sda4 backup usb4

boot_device_type=0
boot_device_num=1

install_target_type=0
root_partition=""
root_mount_point="/mnt/usb1"

resize_ext4_dir="./usr/local/ls_resize"
resize_ext4_flag="$resize_ext4_dir/resizerootfs"

check_cmdline_ins_target()
{
	install_target_type=0
	# install_target_type=$(cat /proc/cmdline | grep ins_target="scsi") #default is scsi
	install_target_type=$(cat /proc/cmdline | grep rec_target=mmc)
	if [ ! -z "$install_target_type" ]; then
		boot_device_type=1
		install_target_type=1
		root_partition="/dev/mmcblk0p1"
		return 0
	fi
	root_partition="/dev/sda1"
	install_target_type=0
}

#防止前面的脚本出现错误，导致没有解除挂载一些已经挂载的分区。
check_and_umount_for_safe()
{
	for i in /mnt/usb*; do
	{
		if mountpoint -q i; then
		{
			sync;
			umount i;
		}
		fi
	}
	done
}

check_resize_ext4()
{
	mount $root_partition $root_mount_point;
	sync;

	old_path=$PWD
	cd $root_mount_point
	if [ -d $resize_ext4_dir ]; then
		echo 2 > $resize_ext4_flag
	fi
	cd $old_path
	umount $root_partition
	sync
}

#防止前面的脚本出现错误，导致没有解除挂载一些已经挂载的分区。
check_cmdline_ins_target
check_and_umount_for_safe;
check_resize_ext4
/home/sys_config_tool $boot_device_type 0 $boot_device_num

echo "-------------> stage3 reboot system <-------------"
#检查是否有错误记录文件，则之前的脚本执行时出错
reboot -f
echo "-------------> stage3 end <-------------"
