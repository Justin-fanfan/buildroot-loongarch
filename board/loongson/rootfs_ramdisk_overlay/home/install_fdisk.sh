#! /bin/sh

disk_size=0
disk_size_root=0
disk_size_data=0
disk_size_swap=2
disk_size_backup=4
disk_size_ex_swap=0
disk_size_root_and_data=0
#是disk_size_root_and_data的备份
disk_size_root_and_data_bak=0

swap_exist=1
backup_exist=1

fdisk_part_total=0

install_disk_blk="/dev/sda"

part_1_size_unit="G"
part_2_size_unit="G"

check_cmdline_ins_target()
{
	install_target_type=0
	# install_target_type=$(cat /proc/cmdline | grep ins_target="scsi") #default is scsi
	install_target_type=$(cat /proc/cmdline | grep ins_target=mmc)
	if [ ! -z "$install_target_type" ]; then
		install_disk_blk="/dev/mmcblk0"
		return 0
	fi

	install_disk_blk="/dev/sda"
}

#读取SSD的大小
read_disk_size()
{
	disk_size=$(fdisk -l | grep "Disk $install_disk_blk" | head -n1 | cut -d ' ' -f3);
	fdisk -l | grep "Disk" | head -n1 | grep GB >/dev/null
	# if just MB size
	if [ $? -eq 1 ]; then
		disk_size=$(($disk_size/1024))
	fi
	disk_size_ex_swap=$(($disk_size-$disk_size_swap));
}

#$1 是第一个的比例
#$2 是第二个的比例
#$3 瓜分总数
buffer_num1=0;
buffer_num2=0;
spilt_num_to_buffer()
{
	buffer_num1=0
	buffer_num2=0
	count=$(($1+$2))
	total_num=$3

	if [ $1 -le 0 ]; then
		buffer_num2=$3
		return 0
	elif [ $2 -le 0 ]; then
		buffer_num1=$3
		return 0
	fi

	while [ $total_num -ge $count ]
	do
		buffer_num1=$(($buffer_num1+$1))
		buffer_num2=$(($buffer_num2+$2))
		total_num=$(($total_num-$count))
	done
	if [ $1 -lt $2 ]; then
		buffer_num2=$(($buffer_num2+$total_num))
	else
		buffer_num1=$(($buffer_num1+$total_num))
	fi
}

split_rootdata_and_backup()
{
	spilt_num_to_buffer $1 $2 $3
	disk_size_root_and_data=$buffer_num1
	disk_size_backup=$buffer_num2

}

split_root_and_data()
{
	spilt_num_to_buffer $1 $2 $3
	disk_size_root=$buffer_num1
	disk_size_data=$buffer_num2
}

#这是开始格式化分区的函数
#注意分区的数字需要参数传入，否则不能识别
fdisk_run_four_part()
{
	fdisk $install_disk_blk >/dev/null << !
d
1
d
2
d
3
d
4

n
p
1

+$1$part_1_size_unit

n
p
2

+$2$part_2_size_unit

n
p
3

+$3G

n
p
4



t
3
82

p

w
!
}

#这是开始格式化分区的函数
#注意分区的数字需要参数传入，否则不能识别
fdisk_run_three_part_without_data()
{
	fdisk $install_disk_blk >/dev/null << !
d
1
d
2
d
3
d
4

n
p
1

+$1$part_1_size_unit

n
p
3

+$2G

n
p
4



t
3
82

p

w
!
}

temp_fdisk_name=temp_fdisk
fdisk_run_delete_all_part()
{
	echo d >> $temp_fdisk_name
	echo 1 >> $temp_fdisk_name
	echo d >> $temp_fdisk_name
	echo 2 >> $temp_fdisk_name
	echo d >> $temp_fdisk_name
	echo 3 >> $temp_fdisk_name
	echo d >> $temp_fdisk_name
	echo 4 >> $temp_fdisk_name
	echo "" >> $temp_fdisk_name
	echo "" >> $temp_fdisk_name
}

fdisk_run_set_swap_flag()
{
	echo t >> $temp_fdisk_name
	echo 82 >> $temp_fdisk_name
	echo "" >> $temp_fdisk_name
	echo "" >> $temp_fdisk_name
}

cur_part_num=1
fdisk_run_set_part_write_file()
{
	echo n >> $temp_fdisk_name
	echo p >> $temp_fdisk_name
	echo $1 >> $temp_fdisk_name
	echo "" >> $temp_fdisk_name
	echo $2 >> $temp_fdisk_name
	echo "" >> $temp_fdisk_name
	echo "" >> $temp_fdisk_name
}

fdisk_run_set_part()
{
	if [ $cur_part_num -ne 4 ]; then
		if [ $cur_part_num -eq $fdisk_part_total ]; then
			fdisk_run_set_part_write_file $1 ""
		else
			fdisk_run_set_part_write_file $1 "+$2G"
		fi
	else
		fdisk_run_set_part_write_file "" ""
	fi
	cur_part_num=$(($cur_part_num+1))
}

fdisk_run_end_file()
{
	echo w >> $temp_fdisk_name
}

fdisk_run_func()
{
	fdisk_run_delete_all_part
	if [ $swap_exist -eq 1 ]; then
		fdisk_run_set_part 3 $disk_size_swap
		fdisk_run_set_swap_flag;
	fi
	if [ $backup_exist -eq 2 ]; then
		fdisk_run_set_part 4 $disk_size_backup
	fi

	fdisk_run_set_part 1 $disk_size_root

	if [ $1 -ne 0 ]; then
		fdisk_run_set_part 2 $disk_size_data
	fi

	if [ $backup_exist -eq 1 ]; then
		fdisk_run_set_part 4 $disk_size_backup
	fi
	fdisk_run_end_file;
	fdisk $install_disk_blk < $temp_fdisk_name >/dev/null
}

#分析4分区, 不包括乒乓系统
analy_four_part()
{
	#16G的特别对待，保证root能装满系统
	if [ $disk_size -le 8 ]; then
		disk_size_root=2
		disk_size_data=3
		disk_size_swap=1
		disk_size_root_and_data=5
		disk_size_root_and_data_bak=5
	elif [ $disk_size -le 16 ]; then
		disk_size_root=3
		disk_size_data=7
		disk_size_root_and_data=10
		disk_size_root_and_data_bak=10
	else
		disk_size_root_and_data=$(($disk_size_ex_swap-$disk_size_backup))
		disk_size_root_and_data_bak=$disk_size_root_and_data
		split_root_and_data 1 2 $disk_size_root_and_data;
	fi
}

#分析4分区，包括乒乓系统
analy_pingpang()
{
	if [ $disk_size -le 8 ]; then
		disk_size_root=1536
		disk_size_data=3072
		disk_size_swap=1
		disk_size_root_and_data=4608
		disk_size_root_and_data_bak=4608
		part_1_size_unit="M"
		part_2_size_unit="M"
	elif [ $disk_size -le 16 ]; then
		disk_size_root=3
		disk_size_data=6
		disk_size_root_and_data=9
		disk_size_root_and_data_bak=9
	else
		# /2会向下取整，也就是bakcup的大小 >= root+data
		disk_size_root_and_data=$((3*$disk_size_ex_swap/4))
		# 预留多1G给backup分区，用来存镜像
		disk_size_root_and_data=$(($disk_size_root_and_data - 1))
		disk_size_root_and_data_bak=$disk_size_root_and_data
		split_root_and_data 1 2 $disk_size_root_and_data;
	fi
}

#fdisk_four_part 不包括4分区
#fidks_pingpang 包括4分区
#这两个函数都是接口。

fdisk_four_part()
{
	read_disk_size;
	analy_four_part;
	fdisk_run_four_part $disk_size_root $disk_size_data $disk_size_swap;
}

fdisk_pingpang()
{
	read_disk_size;
	analy_pingpang;
	fdisk_run_four_part $disk_size_root $disk_size_data $disk_size_swap;
}

fdisk_three_pingpang()
{
	read_disk_size;
	analy_pingpang;
	echo $disk_size_root_and_data_bak $disk_size_swap
	fdisk_run_three_part_without_data $disk_size_root_and_data_bak $disk_size_swap;
}

fdisk_by_ratio_swap_size()
{
	if [ $1 -eq 0 ]; then
		swap_exist=0;
		disk_size_swap=0;
	else
		swap_exist=1
		if [ $disk_size -le 16 ]; then
			disk_size_swap=1
		else
			disk_size_swap=2
		fi
	fi
	disk_size_ex_swap=$(($disk_size-$disk_size_swap))
}

fdisk_by_ratio_backup_size()
{
	backup_exist=1
	if [ $1 -eq 0 ]; then
		backup_exist=0;
		disk_size_backup=0;
	elif [ $1 -eq -1 ]; then
		backup_exist=2
		disk_size_backup=4
	elif [ $1 -eq -2 ]; then
		backup_exist=2
		disk_size_backup=5
	fi
}

fdisk_by_ratio_other_part()
{
	fdisk_part_total=1;
	if [ $2 -gt 0 ]; then
		fdisk_part_total=$(($fdisk_part_total+1));
	fi
	if [ $swap_exist -eq 1 ]; then
		fdisk_part_total=$(($fdisk_part_total+1));
	fi
	if [ $backup_exist -ne 0 ]; then
		fdisk_part_total=$(($fdisk_part_total+1));
	fi

	if [ $backup_exist -eq 0 ]; then
		split_root_and_data $1 $2 $disk_size_ex_swap
	else
		rootdata_ratio=$(($1+$2))
		if [ $backup_exist -eq 2 ]; then
			disk_size_root_and_data=$(($disk_size_ex_swap-$disk_size_backup))
		else
			split_rootdata_and_backup $rootdata_ratio $3 $disk_size_ex_swap
		fi
		split_root_and_data $1 $2 $disk_size_root_and_data
	fi

	fdisk_run_func $2
}

fidks_by_ratio()
{
	read_disk_size;
	fdisk_by_ratio_swap_size $3
	fdisk_by_ratio_backup_size $4
	fdisk_by_ratio_other_part $1 $2 $4
}

check_cmdline_ins_target

if [ $1 -eq 0 ]; then
	fdisk_four_part;
elif [ $1 -eq 1 ]; then
	fdisk_pingpang;
elif [ $1 -eq 2 ]; then
	fdisk_three_pingpang;
elif [ $1 -eq 3 ]; then
	fidks_by_ratio $2 $3 $4 $5
fi
