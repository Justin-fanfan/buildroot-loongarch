#!/bin/bash

#set -ex

conf=""
PS3="Please enter your choice:"

function get_conf()
{
	plat=loongarch64_${1}
	options=(`cd configs && ls ${plat}*`)
	select opt in "${options[@]}"
	do
		conf=$opt
	#	echo $opt
		break
	done
	
	echo 
	echo "Your select is :$conf"
	echo 
}

function get_all_conf()
{
	get_conf 2k1000la
	get_conf 2k500
	get_conf 2k300
	get_conf 2p500
}

function usage()
{
	echo "./buildenv.sh <2k300/2k500/2k1000la/2p500/all>"
}


function main()
{
	if [ $# -eq 1 ] ;then
		param=${1}
		if [ $param = "all" ]; then
			get_conf 
		else
			plat=${1}_
			get_conf $plat
		fi
		make $conf
	else
		usage	
	fi
}

main $@

