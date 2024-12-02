# SolidRun's CN913x products build scripts

## Introduction
The main intention of this repository is to provide build scripts that are easy to handle than Marvell's build environment.

They are used in SolidRun to quickly build images for development where those images can be used to boot from SD card, SPI, eMMC, network TFTP (kernel) or used for root NFS

The sources are pulled from:
1. arm-trusted firmware: https://github.com/SolidRun/atf-marvell/tree/atf-v2.8-marvell-sdk-v12
2. mv-ddr: https://github.com/SolidRun/mv-ddr-marvell/tree/mv-ddr-marvell-sdk-v12
3. u-boot: https://github.com/SolidRun/u-boot/tree/u-boot-v2023.01-marvell-sdk-v12
4. armada-firmware: https://github.com/SolidRun/armada-firmware/tree/marvell-sdk-v12
5. linux: https://github.com/SolidRun/linux-marvell/tree/linux-6.1.y-marvell-sdk-v12
6. patches are provided by Solid-Run in the `patches/` directory

The build script builds the u-boot, atf and linux components, integrate it with either Debian or Ubuntu bootstrapped rootfs.

## Build

### Build Full Image from Source with Docker

A docker image providing a consistent build environment can be used as below:

1. build container image (first time only)

       docker build --build-arg user=$(whoami) --build-arg userid=$(id -u) -t cn913x_build docker

2. invoke build script in working directory

       docker run --rm -i -t -v "$PWD":/cn913x_build_dir cn913x_build bash -c "<ARGUMENTS> ./runme.sh"

#### rootless Podman

Due to the way podman performs user-id mapping, the root user inside the container (uid=0, gid=0) will be mapped to the user running podman (e.g. 1000:100).
Therefore in order for the build directory to be owned by current user, `-build-arg user=root --build-arg userid=0` have to be passed to *docker build*.

### Build Full Image from Source with Host Tools

Simply running ./runme.sh will check for required tools, clone and build images and place results in images/ directory.

### Configure Build Options

By default the script will create an image bootable from SD (ready to use .img file) suitable for Clearfog Pro.

Build options can be customised by passing environment variables to the runme script, For example:

- `BOARD_CONFIG=0 ./runme.sh` **or**
- `docker run --rm -i -t -v "$PWD":/cn913x_build_dir cn913x_build bash -c "BOARD_CONFIG=0 ./runme.sh"`

#### Available Options:

- `BOARD_CONFIG`: select target board
  - `0`: CN9132 CEX-7 Evaluation Board
  - `1`: CN9130 Clearfog Base
  - `2`: CN9130 Clearfog Pro (default)
  - `3`: CN9131 SolidWAN
- `BOOT_LOADER`: select boot -loader type
  - `u-boot` (default)
- `UBOOT_ENVIRONMENT`: U-Boot Environment Variabel Storage (recommended to match boot media)
  - `spi`: SPI Flash
  - `mmc:0:0`: MMC0 (SoM eMMC), data Partition
  - `mmc:0:1`: MMC0 (SoM eMMC), boot0 Partition
  - `mmc:0:2`: MMC0 (SoM eMMC), boot1 Partition
  - `mmc:1:0`: MMC1 (Carrier Board SD), data Partition (default)
  - `mmc:1:1`: MMC1 (Carrier Board SD), boot0 Partition (only valid if carrier board has eMMC instead of microSD)
  - `mmc:1:2`: MMC1 (Carrier Board SD), boot1 Partition (only valid if carrier board has eMMC instead of microSD)
- `BUILD_ROOTFS`: DDR speed in MHz increments
  - `yes`: build full bootable image with kernel & rootfs (default)
  - `no`: build bootloader only
- `DISTRO`: Platform clock in MHz
  - `debian`: Generate Debian based rootfs
  - `ubuntu`: Generate Ubuntu based rootfs (default)
- `DEBIAN_VERSION`: Debian Version
  - bookworm (12, default)
- `DEBIAN_ROOTFS_SIZE`: rootfs / partition size
  - `1472M` (default)
  - arbitrary sizes supported in unit `M`, 1472M recommended minimum
- `UBUNTU_VERSION`: Ubuntu Version
  - bionic (18.04)
  - focal (20.04, default)
  - jammy (22.04)
- `UBUNTU_ROOTFS_SIZE`: rootfs / partition size
  - `500M` (default)
  - arbitrary sizes supported in unit `M`, 500M recommended minimum
- `DPDK_RELEASE`: select soc revision
  - `v22.11`
  - `v23.11`
  - `v24.07` (default)
- `SHALLOW`: enable shallow git clone to save space and bandwidth
  - `true` (default)
  - `false`

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

## DPDK

> DPDK has been tested only on ClearFog-Base CN9130 based product.

> Please notice that the support is for ethernet ports that are directly connected to the SoC (i.e. no L2 DSA switch support).

### Compiling DPDK
The default DPDK version is v22.07, and the supported versions are v22.07 and v20.11.<br>
Technically, any DPDK version can be used, but the DPDK patches should be ported to the wanted version.<br>
Usually the porting is quite easy and takes a few minutes.<br>
The closes supported version should be used as reference (usually, the only differences are the location of the changed lines).<br><br>
The runme script will clone the version specified by the <b>DPDK_RELEASE</b> argument (or the default one), and will look for patches in patches/dpdk-{version} directory, so this directory should be created and the patches should be placed there.<br>

> Please note that dpdk compilation is highly dependent on the build environment, Docker is greatly recommended.

> Please note that once DPDK is cloned, it won't be cloned again, even if the DPDK_RELEASE argument is different. Please delete the build/dpdk directory in order to invoke a new clone.

### Running DPDK
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
dpdk-testpmd --vdev=eth_mvpp2,iface=eth0,iface=eth1,iface=eth2 -- --txd=1024 --txpkts=1500 --tx-first --auto-start --forward-mode=txonly --nb-cores=1 --stats-period=1
```

The output image will have the following DPDK applications:
* dpdk-testpmd
* dpdk-l2fwd
* dpdk-l3fwd

More applications can be copied from ```build/dpdk/build/examples``` or ```build/dpdk/build/app```

## VPP

VPP is supported for all native interfaces of CN9130, CN9131, CN9132.
However interfaces connected to managed ethernet switches (e.g. Clearfog Pro) are not supported.

Please see [vpp.md](vpp.md) for details.
