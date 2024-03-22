loongson LA64 ls2k300

Intro
=====

This default configuration will allow you to start experimenting with the
buildroot environment for the ls2k300. With the current configuration
it will bring-up the board, and allow access through the serial console.

How to build it
===============

Configure Buildroot:

    $ make loongson2k300_mini_dp_defconfig (this will use rootfs_overlay)

Compile everything and build the system:

    $ make
    or
    $ make -j4 (run in 4 core PC)

How to install the system
========================

you can use
{buildroot_path}/output/images/rootfs.tar.gz
or
{buildroot_path}/output/images/rootfs.ubi
to install to SSD or nand by uboot function
remember rootfs.ext4.gz rename to rootfs.img
