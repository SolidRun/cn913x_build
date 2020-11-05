# SolidRun's CN913x COM express type 7 build scripts

## Introduction
The main intention of this repository is to provide build scripts that are easy to handle than Marvell's build environment.

They are used in SolidRun to quickly build images for development where those images can be SD or SPI booted or network TFTP (kernel) or used for root NFS

The sources are pulled from:
1. arm-trusted firmware: https://github.com/ARM-software/arm-trusted-firmware.git
2. mv-ddr-marvell:  https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git
3. u-boot: currently from marvell SDK10
4. linux: https://github.com/torvalds/linux.git
5. patches are supplied by Solid-Run in the patches/ directory
6. binaries are supplied by Solid-Run in the binaries/ directory

The build script builds the u-boot, atf and linux components, integrate it with Ubuntu rootfs bootstrapped with multistrap. Buildroot is also built aside for future use.

## Build with host tools
Simply running ./runme.sh will check for required tools, clone and build images and place results in images/ directory.

#Auto detection of boot device such as SD card, eMMC and SPI
Currently there no support of distro for auto detection of boot device, however it is under development.

## Configuration adn Customization
The board can be configured based on the amount of CP# devices and to which carrier board it will fit. the default is CN9132 and Clearfog Eval Board

1. CP_NUM:
	1 - CN9130
	2 - CN9131
	3 - CN9132
2. BOARD_CONFIG - defines the device tree based on the platform
	0 - CN9132 CEx7 based on Clearfog Eval Board
	1 - CN9130 SOM based on Clearfog Pro
	2 - CN9130 SOM based on Clearfog Base
	3 - CN9132 CEx7 based on NAPA
3. boot loader - *BOOT_LOADER=u-boot*


## U-Boot based on SDK10
The CN913x u-boot is not public yet, and is taken from Marvell's SDK10

In order to use use the script with the SDK patches, create a directory in ROOTDIR:

`mkdir $ROOTDIR/patches-sdk-u-boot/`

The script will apply the u-boot patches onto the mainline u-boot. In order to do so:

Extract the git-u-boot-<version>-<release>.tar.bz2 under the destination folder git-u-boot-<version>-<release> and copy the patches to $ROOTDIR/patches-sdk-u-boot/

## Examples:
- `./runme.sh` **or**

generates *images/cn9132-cex7_config_0_ubuntu.img* which is an image ready to be deployed on micro SD card and *images/flash-image.bin* which is an image ready to be deployed on the COM SPI flash.


## Deploying
For SD card bootable images:

Plug in a micro SD into your machine and run the following, where sdX is the location of the SD card got probed into your machine -

`sudo dd if=images/cn9132-cex7_config_0_ubuntu.img of=/dev/sdX bs=512 seek=1`

In u-boot prompt, write the folloiwng command for loading ubuntu:

`get_images=load mmc 0:1 $kernel_addr_r boot/Image; load mmc 0:1 $fdt_addr_r boot/cn9132-cex7.dtb; setenv root 'root=/dev/mmcblk0p1' rw; mw 0xf2440144 0xffefffff; mw 0xf2440140 0x00100000; boot`



For SPI boot:

Burn the flash-image.bin onto an SDto the system memory and flash it using the `sf probe` and `sf update` commands. 

An example below loads the image through TFTP prototocl, flashes and then verifies the image -

`sf probe; setenv ipaddr 192.168.15.223; setenv serverip 192.168.15.3; tftp 0xa0000000 cn9132-cex7_config_0_ubuntu.img ;sf update 0xa0000000 0 $filesize; sf read 0xa4000000 0 $filesize; cmp 0xa0000000 0xa4000000 $filesize`

and then set boot DIP switch SW2 on COM to off/on/on/off/on from numbers 1 to 5 (notice the marking 'ON' on the DIP switch)


For eMMC boot: 

`load mmc 0:1 0xa4000000 ubuntu-core.img`

`setenv mmc dev 1`

`mmc write 0xa4000000 0 0xd2000`

And then set boot DIP switch on COM to on/off/on/off/on from numbers 1 to 5 (notice the marking 'ON' on the DIP switch)

After booting Ubuntu you must resize the boot partition; for instance if booted under eMMC then login as root/root; then:

`fdisk /dev/mmcblk1`

Delete first partition and then recreate it starting from 131072 (64MByte) to the end of the volume.
Do not remove the signaute since it indicates for the kernel which partition ID to use.

After resizing the partition; resize the ext4 boot volume by running 'resize2fs /dev/mmcblk1p1'

Afterwards run update the RTC and update the repository -

`dhclient -i eth1; ntpdate pool.ntp.org; apt update`

