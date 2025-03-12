#! /bin/bash

systemctl disable loongson_timesyncd_config
rm /usr/lib/systemd/system/multi-user.target.wants/loongson_timesyncd_config.service
rm /usr/lib/systemd/system/loongson_timesyncd_config.service
timedatectl set-ntp 0
rm /usr/local/loongson_timesyncd_config.sh

