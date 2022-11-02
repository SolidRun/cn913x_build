# SolidRun's CN913x products build scripts

## Introduction
The main intention of this repository is to provide build scripts that are easy to handle than Marvell's build environment.

They are used in SolidRun to quickly build images for development where those images can be used to boot from SD card, SPI, eMMC, network TFTP (kernel) or used for root NFS

The sources are pulled from:
1. arm-trusted firmware: https://github.com/ARM-software/arm-trusted-firmware.git
2. mv-ddr-marvell:  https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git
3. u-boot: currently from marvell SDK
4. linux: https://github.com/torvalds/linux.git
5. patches are supplied by Solid-Run in the patches/ directory
6. binaries are supplied by Solid-Run in the binaries/ directory

The build script builds the u-boot, atf and linux components, integrate it with Ubuntu rootfs bootstrapped with multistrap. Buildroot is also built aside for future use.

## Build
### Docker build (recommended)

* Build the Docker image (<b>Just once</b>):

```
docker build --build-arg user=$(whoami) --build-arg userid=$(id -u) -t cn913x_build docker/
```

To check if the image exists in you machine, you can use the following command:

```
docker images | grep cn913x_build
```

* Run the build script:
```
docker run -i -t -v "$PWD":/cn913x_build_dir -v /etc/gitconfig:/etc/gitconfig cn913x_build bash -c "<ARGUMENTS> ./runme.sh"
```

> The git configuration file is mounted, if your gitconfig file is not located in /etc/gitconfig, change the command accordingly, or copy the file to /etc/gitconfig.

### Build with host tools
Simply running ./runme.sh will check for required tools, clone and build images and place results in images/ directory.

## Auto detection of boot device such as SD card, eMMC and SPI
Currently there no support of distro for auto detection of boot device, however it is under development.

## Configuration adn Customization
The board can be configured based on the amount of CP# devices and to which carrier board it will fit.
There are a few parameters that must be taken to account:

1. CP_NUM:
	1 - CN9130
	2 - CN9131
	3 - CN9132
2. BOARD_CONFIG - defines the device tree based on the platform
	0 - CN9132 CEx7 based on Clearfog Eval Board
	1 - CN9130 SOM based on Clearfog Base
	2 - CN9130 SOM based on Clearfog Pro


## Examples:
1. For CN9130 SOM base on Clearfog Base, run:
	`BOARD_CONFIG=1 CP_NUM=1 ./runme`
	generates *images/cn9130-cf-base_config_1_ubuntu.img*

2. For CN9132 CEx7 base on Clearfog EVAL board, run:
        `BOARD_CONFIG=0 CP_NUM=3 ./runme`
	generates *images/cn9132-cex7_config_0_ubuntu.img*

## U-Boot based on Marevll's SDK
The CN913x u-boot is not public yet, and is taken from Marvell's SDK10

In order to use the script with the SDK patches, create a directory in ROOTDIR:

`mkdir $ROOTDIR/patches-sdk-u-boot/`

The script will apply the u-boot patches onto the mainline u-boot. In order to do so:

Extract the git-u-boot-<version>-<release>.tar.bz2 under the destination folder git-u-boot-<version>-<release> and copy the patches to $ROOTDIR/patches-sdk-u-boot/


## DDR configuration and EEPROM
The atf dram_port.c supports both CN9132 CEx7 SO-DIMM with SPD and CN9130 SOM with DDRs soldered on board which might have various configurations and are set according to boot straps MPPs[11:10].
In order to differentiate, it checks the first 196 Bytes of the EEPROM. 
If programming data on the EEPROM (address 0x53) is requiered, and is not related to the DDR configuration, it must be after the first 196 Bytes. Otherwise, the boot sequence will be corrupted. 


## Deploying
For SD card bootable images:

Plug in a uSD into your machine and run the following, where sdX is the location of the SD card got probed into your machine -

`sudo dd if=images/<image_name>.img of=/dev/sdX`

In u-boot prompt, write the folloiwng command for loading ubuntu:

`get_images=load mmc 1:1 $kernel_addr_r boot/Image; load mmc 1:1 $fdt_addr_r boot/<device_tree>.dtb; setenv root 'root=/dev/mmcblk1p1' rw; boot`

To active the FAN on CEx7 platform, add to the command:
'mw 0xf2440144 0xffefffff; mw 0xf2440140 0x00100000;`

For burning u-boot image only on uSD card:
`sudo dd if=images/flash-image.bin of=/dev/sdX bs=512 seek=4096`


For SPI boot:

Burn the flash-image.bin onto a uSD to the system memory and flash it using the `sf probe` and `sf update` commands. 

An example below loads the image through TFTP prototocl, flashes and then verifies the image -

`sf probe; setenv ipaddr 192.168.15.223; setenv serverip 192.168.15.3; tftp 0xa0000000 cn9132-cex7_config_0_ubuntu.img ;sf update 0xa0000000 0 $filesize; sf read 0xa4000000 0 $filesize; cmp 0xa0000000 0xa4000000 $filesize`

and then set boot DIP switch SW2 on COM to off/on/on/off/on from numbers 1 to 5 (notice the marking 'ON' on the DIP switch)


For eMMC boot: 

Copy the image located at images/cn9132-cex7_config_0_ubuntu.img onto a SD card or a USB drive.

After booting the device from SD card, burn the image onto the eMMC:

`mount /dev/mmcblk1p1 /mnt`

`sudo dd if=/mnt/cn9132-cex7_config_0_ubuntu.img of=/dev/mmcblk0 bs=512 seek=1`

Then set the boot DIP switch and reset the system. 

`get_images=load mmc 0:1 $kernel_addr_r boot/Image; load mmc 0:1 $fdt_addr_r boot/cn9132-cex7.dtb; setenv root 'root=/dev/mmcblk0p1' rw; boot`

Afterwards run update the RTC and update the repository -

`dhclient -i eth2; ntpdate pool.ntp.org; apt update`

## Running DPDK

The default DPDK version is v22.07, and can be changed using the DPDK_RELEASE argument.
<br>
Allocate hugepages for DPDK, for example:

```
mkdir -p /mnt/huge
mount -t hugetlbfs nodev /mnt/huge
echo 512 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
```

Insert MUSDK kernel modules

```
insmod /root/musdk_modules/mv_pp_uio.ko
insmod /root/musdk_modules/musdk_cma.ko
```

Run test-pmd
In order to use all three interfaces, the next command can be used:

```
/root/dpdk/dpdk-testpmd --vdev=eth_mvpp2,iface=eth0,iface=eth1,iface=eth2 -- --txd=1024 --txpkts=1500 --tx-first --auto-start --forward-mode=txonly --nb-cores=1 --stats-period=1
```

> At the moment, switching back from DPDK to Linux kernel is not possible, so, once a DPDK applciation starts, the linux kernel won't be able to use the network interfaces.
