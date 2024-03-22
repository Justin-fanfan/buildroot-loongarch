#! /bin/sh

install_disk_blk="/dev/sda"
install_target_type=0

check_cmdline_ins_target()
{
	install_target_type=0
	# install_target_type=$(cat /proc/cmdline | grep ins_target="scsi") #default is scsi
	install_target_type=$(cat /proc/cmdline | grep ins_target=mmc)
	if [ ! -z "$install_target_type" ]; then
		install_target_type=1
		install_disk_blk="/dev/mmcblk0"
		return 0
	fi

	install_target_type=0
	install_disk_blk="/dev/sda"
}

check_num()
{
	result=$(echo $num1 | grep '^-*[1-9][0-9]*$')
	if [ -z $result ]; then
		return 1
	fi
	return 0
}

check_dev_part_num_list()
{
	if [ $# -eq 4 ]; then
		check_num $1
		if [ $? -ne 0 ]; then
			return 1
		fi
		check_num $2
		if [ $? -ne 0 ]; then
			return 1
		fi
		check_num $3
		if [ $? -ne 0 ]; then
			return 1
		fi
		check_num $4
		if [ $? -ne 0 ]; then
			return 1
		fi
	else
		return 1
	fi
	for i in $1 $2 $3 $4; do
		if [ $i -gt 5 ]; then
			echo "warning!!! $i > 5, this num is a ratio not a real size!!!"
			return 1
		fi
	done
	if [ $1 -le 0 ]; then
		echo "error!!! / part must define!!!"
		return 1
	fi
	if [ $2 -lt 0 ]; then
		echo "warning!!! data part not support default size"
		return 1
	fi
	if [ $3 -ne 0 -a $3 -ne -1 ]; then
		echo "warning!!! swap part not support set $3"
		echo "warning!!! swap part ratio == 0 stand for not set swap"
		echo "warning!!! swap part ratio == -1 stand for set default"
		return 1
	fi
	if [ $4 -lt -2 ]; then
		echo "warning!!! backup part not support set $4"
		echo "warning!!! backup part ratio > 0 stand for set backup part by this ratio"
		echo "warning!!! backup part ratio == 0 stand for not set backup part"
		echo "warning!!! backup part ratio == -1 stand for set 4G"
		echo "warning!!! backup part ratio == -2 stand for set 5G"
		return 1
	fi
	return 0;
}

fidsk_default_2_part()
{
	echo ""
	if [ $install_target_type -eq 1 ]; then
		echo "would split $install_disk_blk to 1 partition! rootfs part"
		sleep 1;
		fdisk $install_disk_blk < /home/fdisk_mmc.txt >/dev/null;
	else
		echo "would split $install_disk_blk to 2 partition! rootfs and swap part"
		sleep 1;
		fdisk $install_disk_blk < /home/fdisk.txt >/dev/null;
	fi
}

fdisk_config_analy()
{
	if [ "$1" == "4part" ]; then
		/home/install_fdisk.sh 0
	elif [ "$1" == "twosys" ]; then
		/home/install_fdisk.sh 1
	elif [ "$1" == "twosys_3" ]; then
		/home/install_fdisk.sh 2
	else
		num1=$(echo $1 | tr -s ' ' | cut -d ' ' -f1)
		num2=$(echo $1 | tr -s ' ' | cut -d ' ' -f2)
		num3=$(echo $1 | tr -s ' ' | cut -d ' ' -f3)
		num4=$(echo $1 | tr -s ' ' | cut -d ' ' -f4)

		if [ ! -z "$num4" ]; then
			check_dev_part_num_list $num1 $num2 $num3 $num4
			if [ $? -eq 0 ]; then
				/home/install_fdisk.sh 3 $num1 $num2 $num3 $num4
				return 0
			fi
		fi

		fidsk_default_2_part;
	fi
}

# arg1 file path
fdisk_file_analy()
{
	first_line="$(cat $1 | head -1)"

	if [ "$first_line" == "d" ]; then
		fdisk $install_disk_blk < $1 >/dev/null;
	else
		fdisk_config_analy "$first_line"
	fi
}

analy_start()
{
	if [ $# -eq 2 ]; then
		if [ $1 -eq 1 ]; then
			fdisk_file_analy $2
		elif [ $1 -eq 2 ]; then
			fdisk_config_analy $2
		else
			fidsk_default_2_part
		fi
	else
		fidsk_default_2_part
	fi
}

check_cmdline_ins_target
if [ $# -eq 2 ]; then
	analy_start $1 $2
else
	analy_start
fi