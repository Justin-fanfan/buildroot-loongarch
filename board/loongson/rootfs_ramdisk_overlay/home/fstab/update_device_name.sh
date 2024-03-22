#! /bin/bash

new_device_name=$1

sed -i 's|/dev/sda|'"$new_device_name"'|g' ./*
