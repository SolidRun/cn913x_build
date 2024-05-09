#!/bin/bash
set -e
#set -x

# BOOT_LOADER=u-boot
# CPU_SPEED=1600,2000,2200
# SERDES=0
# CP_NUM=1,2,3
###############################################################################
# General configurations
###############################################################################
#RELEASE=cn9130-early-access-bsp_rev1.0 # Supports both rev1.0 and rev1.1
BUILDROOT_VERSION=2020.02.1
: ${BR2_PRIMARY_SITE:=} # custom buildroot mirror
#UEFI_RELEASE=DEBUG
#BOOT_LOADER=uefi
#DDR_SPEED=2400
#BOARD_CONFIG -
# 0-clearfog_cn COM express
# 1-clearfog-base (cn9130 SOM)
# 2-clearfog-pro (cn9130 SOM)
# 3-SolidWAN (cn9130 SOM)
# 4-BlDN MBV-A/B (cn9130 SOM)


#UBOOT_ENVIRONMENT -
# - spi (SPI FLash)
# - mmc:0:0 (MMC 0 Partition 0)
# - mmc:0:1 (MMC 0 Partition boot0)
# - mmc:0:2 (MMC 0 Partition boot1)
# - mmc:1:0 (MMC 1 Partition 0) <-- default, microSD on Clearfog
# - mmc:1:1 (MMC 1 Partition boot0)
# - mmc:1:2 (MMC 1 Partition boot1)
: ${UBOOT_ENVIRONMENT:=mmc:1:0}
: ${BUILD_ROOTFS:=yes} # set to no for bootloader-only build

: ${DISTRO:=ubuntu}
# Debian Version
# - bookworm (12)
: ${DEBIAN_VERSION:=bookworm}
: ${DEBIAN_ROOTFS_SIZE:=1472M}
# Ubuntu Version
# - bionic (18.04)
# - focal (20.04)
# - jammy (22.04)
: ${UBUNTU_VERSION:=focal}
: ${UBUNTU_ROOTFS_SIZE:=500M}

# Check if git user name and git email are configured
if [ -z "`git config user.name`" ] || [ -z "`git config user.email`" ]; then
			echo "git is not configured, please run:"
			echo "git config --global user.email \"you@example.com\""
			echo "git config --global user.name \"Your Name\""
			exit -1
fi

###############################################################################
# Misc
###############################################################################

RELEASE=${RELEASE:-linux-4.14.207-marvell-sdk-v10.23.01}
DPDK_RELEASE=${DPDK_RELEASE:-v22.07}

SHALLOW=${SHALLOW:true}
	if [ "x$SHALLOW" == "xtrue" ]; then
		SHALLOW_FLAG="--depth 1"
	fi
BOOT_LOADER=${BOOT_LOADER:-u-boot}
BOARD_CONFIG=${BOARD_CONFIG:-2}
CP_NUM=${CP_NUM:-1}
mkdir -p build images
ROOTDIR=`pwd`
PARALLEL=$(getconf _NPROCESSORS_ONLN) # Amount of parallel jobs for the builds
TOOLS="wget tar git make 7z unsquashfs dd vim mkfs.ext4 parted mkdosfs mcopy dtc iasl mkimage e2cp truncate qemu-system-aarch64 cpio rsync bc bison flex python unzip depmod debootstrap"

export PATH=$ROOTDIR/build/toolchain/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin:$PATH
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

case "${BOARD_CONFIG}" in
	0)
		echo "*** Board Configuration CEx7 CN9132 based on Clearfog CN9K ***"
		if [ "x$CP_NUM" == "x1" ]; then
			DTB_UBOOT=cn9130-cex7-A
			DTB_KERNEL=cn9130-cex7
		elif [ "x$CP_NUM" == "x2" ]; then
			DTB_UBOOT=cn9131-cex7-A
			DTB_KERNEL=cn9131-cex7
		elif [ "x$CP_NUM" == "x3" ]; then
                        DTB_UBOOT=cn9132-cex7-A
			DTB_KERNEL=cn9132-cex7
		else 
			 echo "Please define a correct number of CPs [1,2,3]"
			 exit -1
		fi
	;;
	1)
                echo "*** CN9130 SOM based on Clearfog Base ***"
		CP_NUM=1
		DTB_UBOOT=cn9130-cf-base
		DTB_KERNEL=cn9130-cf-base
	;;
	2)
		echo "*** CN9130 SOM based on Clearfog Pro ***"
		CP_NUM=1
		DTB_UBOOT=cn9130-cf-pro
                DTB_KERNEL=cn9130-cf-pro
	;;

	3)
		echo "*** CN9131 SOM based on SolidWAN ***"
		CP_NUM=2
		DTB_UBOOT=cn9131-cf-solidwan
		DTB_KERNEL=cn9131-cf-solidwan
	;;
	4) 	
		echo "*** CN9131 SOM based on Bldn MBV-A/B ***"
                CP_NUM=2
                DTB_UBOOT=cn9131-bldn-mbv
                DTB_KERNEL=cn9131-bldn-mbv
        ;;


	*)
		echo "Please define board configuration"
		exit -1
	;;
esac

#########################
# checking tools 
#########################

echo "Checking all required tools are installed"

set +e
for i in $TOOLS; do
        TOOL_PATH=`which $i`
        if [ "x$TOOL_PATH" == "x" ]; then
                echo "Tool $i is not installed"
                echo "If running under apt based package management you can run -"
                echo "sudo apt install build-essential git dosfstools e2fsprogs parted sudo mtools p7zip p7zip-full device-tree-compiler acpica-tools u-boot-tools e2tools qemu-system-arm libssl-dev cpio rsync bc bison flex python unzip kmod debootstrap"
                exit -1
        fi
done
set -e

if [[ ! -d $ROOTDIR/build/toolchain ]]; then
	mkdir -p $ROOTDIR/build/toolchain
	cd $ROOTDIR/build/toolchain
	wget http://releases.linaro.org/components/toolchain/binaries/7.5-2019.12/aarch64-linux-gnu/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz
	tar -xvf gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz 
fi

echo "Building boot loader"
cd $ROOTDIR

###############################################################################
# source code cloning and building 
###############################################################################
SDK_COMPONENTS="u-boot mv-ddr-marvell arm-trusted-firmware linux"

for i in $SDK_COMPONENTS; do
	if [[ ! -d $ROOTDIR/build/$i ]]; then
		if [ "x$i" == "xlinux" ]; then
			echo "Cloing https://github.com/SolidRun/linux-marvell release $RELEASE"
			cd $ROOTDIR/build
			git clone $SHALLOW_FLAG https://github.com/SolidRun/linux-marvell.git linux -b $RELEASE
		elif [ "x$i" == "xarm-trusted-firmware" ]; then
			echo "Cloning atf from mainline"
			cd $ROOTDIR/build
			git clone https://github.com/ARM-software/arm-trusted-firmware.git arm-trusted-firmware
			cd arm-trusted-firmware
			# Temporary commit waiting for a release
			git checkout 00ad74c7afe67b2ffaf08300710f18d3dafebb45
		elif [ "x$i" == "xmv-ddr-marvell" ]; then
			echo "Cloning mv-ddr-marvell from mainline"
			echo "Cloing https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git"
			cd $ROOTDIR/build
			git clone https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git mv-ddr-marvell
			cd mv-ddr-marvell
			git checkout mv-ddr-devel
		elif [ "x$i" == "xu-boot" ]; then
			echo "Cloning u-boot from git://git.denx.de/u-boot.git"
			cd $ROOTDIR/build
			git clone git://git.denx.de/u-boot.git u-boot
			cd u-boot
			git checkout v2019.10 -b marvell
		elif [ "x$i" == "xdpdk" ]; then
                        echo "Cloning DPDK from https://github.com/DPDK/dpdk.git"
                        cd $ROOTDIR/build
                        git clone $SHALLOW_FLAG https://github.com/DPDK/dpdk.git dpdk -b $DPDK_RELEASE
			# Apply release specific DPDK patches
			if [ -d $ROOTDIR/patches/dpdk-$DPDK_RELEASE ]; then
				cd dpdk
				git am $ROOTDIR/patches/dpdk-${DPDK_RELEASE}/*.patch
			fi
		fi

		echo "Checking patches for $i"
		cd $ROOTDIR/build/$i
		if [ -d $ROOTDIR/patches/$i ]; then
			git am $ROOTDIR/patches/$i/*.patch
		fi
	fi
done

###############################################################################
# Clean old image artifacts
###############################################################################

rm -rf $ROOTDIR/images/tmp
mkdir -p $ROOTDIR/images/tmp

###############################################################################
# Building sources u-boot / atf / mv-ddr / kernel
###############################################################################

echo "Building u-boot"
cd $ROOTDIR/build/u-boot/
./scripts/kconfig/merge_config.sh configs/sr_cn913x_cex7_defconfig $ROOTDIR/configs/u-boot/cn913x_additions.config
[[ "${UBOOT_ENVIRONMENT}" =~ (.*):(.*):(.*) ]] || [[ "${UBOOT_ENVIRONMENT}" =~ (.*) ]]
if [ "x${BASH_REMATCH[1]}" = "xspi" ]; then
cat >> .config << EOF
CONFIG_ENV_IS_IN_MMC=n
CONFIG_ENV_IS_IN_SPI_FLASH=y
CONFIG_ENV_SIZE=0x10000
CONFIG_ENV_OFFSET=0x3f0000
CONFIG_ENV_SECT_SIZE=0x10000
EOF
elif [ "x${BASH_REMATCH[1]}" = "xmmc" ]; then
cat >> .config << EOF
CONFIG_ENV_IS_IN_MMC=y
CONFIG_SYS_MMC_ENV_DEV=${BASH_REMATCH[2]}
CONFIG_SYS_MMC_ENV_PART=${BASH_REMATCH[3]}
CONFIG_ENV_IS_IN_SPI_FLASH=n
EOF
else
	echo "ERROR: \$UBOOT_ENVIRONMENT setting invalid"
	exit 1
fi
make olddefconfig
make -j${PARALLEL} DEVICE_TREE=$DTB_UBOOT
install -m644 -D $ROOTDIR/build/u-boot/u-boot.bin $ROOTDIR/binaries/u-boot/u-boot.bin
export BL33=$ROOTDIR/binaries/u-boot/u-boot.bin

if [ "x$BOOT_LOADER" == "xuefi" ]; then
	echo "no support for uefi yet"
fi

echo "Building arm-trusted-firmware"
cd $ROOTDIR/build/arm-trusted-firmware
export SCP_BL2=$ROOTDIR/binaries/atf/mrvl_scp_bl2.img

echo "Compiling U-BOOT and ATF"
echo "CP_NUM=$CP_NUM"
echo "DTB=$DTB_UBOOT"

make PLAT=t9130 clean
make -j${PARALLEL} USE_COHERENT_MEM=0 LOG_LEVEL=20 PLAT=t9130 MV_DDR_PATH=$ROOTDIR/build/mv-ddr-marvell CP_NUM=$CP_NUM all fip

echo "Copying flash-image.bin to /Images folder"
cp $ROOTDIR/build/arm-trusted-firmware/build/t9130/release/flash-image.bin $ROOTDIR/images/u-boot-${DTB_UBOOT}-${UBOOT_ENVIRONMENT}.bin

if [ "x${BUILD_ROOTFS}" != "xyes" ]; then
	echo "U-Boot Ready, Skipping RootFS"
	exit 0
fi

echo "Building the kernel"
cd $ROOTDIR/build/linux
#make defconfig
./scripts/kconfig/merge_config.sh -m arch/arm64/configs/marvell_v8_sdk_defconfig $ROOTDIR/configs/linux/cn913x_additions.config
make olddefconfig
make savedefconfig
make -j${PARALLEL} all #Image dtbs modules

mkdir -p $ROOTDIR/images/tmp/boot
make INSTALL_MOD_PATH=$ROOTDIR/images/tmp/ INSTALL_MOD_STRIP=1 modules_install
cp $ROOTDIR/build/linux/arch/arm64/boot/Image $ROOTDIR/images/tmp/boot
cp $ROOTDIR/build/linux/arch/arm64/boot/dts/marvell/cn913*.dtb $ROOTDIR/images/tmp/boot
cp $ROOTDIR/build/linux/arch/arm64/boot/dts/marvell/armada-8040-mcbin.dtb $ROOTDIR/images/tmp/boot

###############################################################################
# File System
###############################################################################

do_build_ubuntu() {
	case "${UBUNTU_VERSION}" in
		bionic)
			UBUNTU_BASE_URL=http://cdimage.ubuntu.com/ubuntu-base/releases/18.04/release/ubuntu-base-18.04.5-base-arm64.tar.gz
		;;
		focal)
			UBUNTU_BASE_URL=http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.5-base-arm64.tar.gz
		;;
		jammy)
			UBUNTU_BASE_URL=http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.4-base-arm64.tar.gz
		;;
		*)
			echo "Error: Unsupported Ubuntu Version \"\${UBUNTU_VERSION}\"! To proceed please add support to runme.sh."
			exit 1
		;;
	esac

	if [[ ! -f $ROOTDIR/build/ubuntu/${UBUNTU_VERSION}.ext4 ]]; then
		mkdir -p $ROOTDIR/build/ubuntu
		cd $ROOTDIR/build/ubuntu
		echo "Building Ubuntu ${UBUNTU_VERSION} File System"

		rm -f ubuntu-base.dl
		wget -c -O ubuntu-base.dl "${UBUNTU_BASE_URL}"

		rm -rf rootfs
		mkdir rootfs
		fakeroot -- tar -C rootfs -xpf ubuntu-base.dl

cat > rootfs/stage2.sh << EOF
#!/bin/sh

# mount pseudo-filesystems
mount -vt proc proc /proc
mount -vt sysfs sysfs /sys
mkdir -p -m 755 /dev/pts
mount -vt devpts devpts /dev/pts

# mount tmpfs for apt caches
mount -t tmpfs tmpfs /var/lib/apt/
mount -t tmpfs tmpfs /var/cache/apt/

# configure dns
cat /proc/net/pnp > /etc/resolv.conf

# configure hostname
echo "localhost" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts

# configure apt proxy
test -n "$APTPROXY" && printf 'Acquire::http { Proxy "%s"; }\n' $APTPROXY | tee -a /etc/apt/apt.conf.d/proxy || true

# fix path to stop dpkg complaints
test "$UBUNTU_VERSION" = "bionic" && export PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/bin:/bin

apt-get update
env DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C \
	apt-get install --no-install-recommends -y apt apt-utils ethtool htop i2c-tools ifupdown iproute2 iptables iputils-ping isc-dhcp-client kmod less lm-sensors locales memtester net-tools ntpdate openssh-server pciutils procps psmisc rfkill rng-tools sudo systemd-sysv usbutils wget
apt-get clean

# fix modules location for split lib,usr/lib
test "$UBUNTU_VERSION" = "bionic" && test -d /lib && ln -sv /usr/lib/modules /lib/modules

# set root password
echo "root\nroot" | passwd

# populate fstab
printf "/dev/root / ext4 defaults 0 1\\n" > /etc/fstab

# enable watchdog service
sed -i "s;[# ]*RuntimeWatchdogSec=.*\$;RuntimeWatchdogSec=30;g" /etc/systemd/system.conf

# wipe machine-id (regenerates during first boot)
echo uninitialized > /etc/machine-id

# remove apt proxy
rm -f /etc/apt/apt.conf.d/proxy

# delete self
rm -f /stage2.sh

# flush disk
sync

# power-off
reboot -f
EOF
		chmod +x rootfs/stage2.sh

		rm -f rootfs.ext4
		truncate -s $UBUNTU_ROOTFS_SIZE rootfs.ext4
		fakeroot mkfs.ext4 -L rootfs -d rootfs rootfs.ext4

		qemu-system-aarch64 \
			-m 1G \
			-M virt \
			-cpu max \
			-smp 4 \
			-netdev user,id=eth0 \
			-device virtio-net-device,netdev=eth0 \
			-drive file=rootfs.ext4,if=none,format=raw,cache=unsafe,id=hd0,discard=unmap \
			-device virtio-blk-device,drive=hd0 \
			-device virtio-rng-device \
			-nographic \
			-no-reboot \
			-kernel "${ROOTDIR}/images/tmp/boot/Image" \
			-append "console=ttyAMA0 root=/dev/vda rootfstype=ext4 ip=dhcp rw init=/stage2.sh"

		# fix errors
		s=0
		e2fsck -fy rootfs.ext4 || s=$?
		if [ $s -ge 4 ]; then
			echo "Error: Couldn't repair generated rootfs."
			exit 1
		fi

		mv rootfs.ext4 $UBUNTU_VERSION.ext4
	fi

	cp -v --sparse=always $ROOTDIR/build/ubuntu/$UBUNTU_VERSION.ext4 $ROOTDIR/images/tmp/rootfs.ext4
}

do_build_debian() {
	mkdir -p $ROOTDIR/build/debian
	cd $ROOTDIR/build/debian

	# (re-)generate only if rootfs doesn't exist
	if [ ! -f ${DEBIAN_VERSION}.ext4 ]; then
		rm -f rootfs.ext4

		local PKGS=apt-transport-https,busybox,ca-certificates,can-utils,command-not-found,curl,e2fsprogs,ethtool,fdisk,gpiod,haveged,i2c-tools,ifupdown,iputils-ping,isc-dhcp-client,initramfs-tools,lm-sensors,locales,nano,net-tools,ntpdate,openssh-server,psmisc,rfkill,sudo,systemd-sysv,usbutils,wget,xterm,xz-utils

		# bootstrap a first-stage rootfs
		rm -rf stage1
		fakeroot debootstrap --variant=minbase \
			--arch=arm64 --components=main,contrib,non-free,non-free-firmware \
			--foreign \
			--include=$PKGS \
			${DEBIAN_VERSION} \
			stage1 \
			https://deb.debian.org/debian

		# prepare init-script for second stage inside VM
		cat > stage1/stage2.sh << EOF
#!/bin/sh

# run second-stage bootstrap
/debootstrap/debootstrap --second-stage

# mount pseudo-filesystems
mount -vt proc proc /proc
mount -vt sysfs sysfs /sys

# configure dns
cat /proc/net/pnp > /etc/resolv.conf

# set empty root password
passwd -d root

# update command-not-found db
apt-file update
update-command-not-found

# enable optional system services
# none yet ...

# populate fstab
printf "/dev/root / ext4 defaults 0 1\\n" > /etc/fstab

# delete self
rm -f /stage2.sh

# flush disk
sync

# power-off
reboot -f
EOF
		chmod +x stage1/stage2.sh

		# create empty partition image
		dd if=/dev/zero of=rootfs.ext4 bs=1 count=0 seek=${DEBIAN_ROOTFS_SIZE}

		# create filesystem from first stage
		mkfs.ext2 -L rootfs -E root_owner=0:0 -d stage1 rootfs.ext4

		# bootstrap second stage within qemu
		qemu-system-aarch64 \
			-m 1G \
			-M virt \
			-cpu max \
			-smp 4 \
			-device virtio-rng-device \
			-netdev user,id=eth0 \
			-device virtio-net-device,netdev=eth0 \
			-drive file=rootfs.ext4,if=none,format=raw,cache=unsafe,id=hd0,discard=unmap \
			-device virtio-blk-device,drive=hd0 \
			-nographic \
			-no-reboot \
			-kernel "${ROOTDIR}/images/tmp/boot/Image" \
			-append "earlycon console=ttyAMA0 root=/dev/vda rootfstype=ext2 ip=dhcp rw init=/stage2.sh" \


		:

		# convert to ext4
		tune2fs -O extents,uninit_bg,dir_index,has_journal rootfs.ext4

		mv rootfs.ext4 $DEBIAN_VERSION.ext4
	fi;

	# export final rootfs for next steps
	cp -v --sparse=always $DEBIAN_VERSION.ext4 $ROOTDIR/images/tmp/rootfs.ext4
}

do_build_${DISTRO}

###############################################################################
# assembling images
###############################################################################
echo "Assembling kernel image"
cd $ROOTDIR
mkdir -p $ROOTDIR/images/tmp/extlinux/
cat > $ROOTDIR/images/tmp/extlinux/extlinux.conf << EOF
  TIMEOUT 30
  DEFAULT linux
  MENU TITLE linux-cn913x boot options
  LABEL primary
    MENU LABEL primary kernel
    LINUX /boot/Image
    FDTDIR /boot
    APPEND console=ttyS0,115200 root=PARTUUID=30303030-01 rw rootwait cma=256M
EOF

# blkid images/tmp/ubuntu-core.img | cut -f2 -d'"'
e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/rootfs.ext4:extlinux
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/extlinux/extlinux.conf $ROOTDIR/images/tmp/rootfs.ext4:extlinux/
e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/rootfs.ext4:boot
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/boot/Image $ROOTDIR/images/tmp/rootfs.ext4:boot/
e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/rootfs.ext4:boot/marvell
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/boot/*.dtb $ROOTDIR/images/tmp/rootfs.ext4:boot/marvell/

# Copy over kernel image
echo "Copying kernel modules"
cd $ROOTDIR/images/tmp/
for i in `find lib`; do
        if [ -d $i ]; then
                e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/rootfs.ext4:usr/$i
        fi
        if [ -f $i ]; then
                DIR=`dirname $i`
                e2cp -G 0 -O 0 -p $ROOTDIR/images/tmp/$i $ROOTDIR/images/tmp/rootfs.ext4:usr/$DIR
        fi
done
cd -

# ext4 ubuntu partition is ready
cp $ROOTDIR/build/arm-trusted-firmware/build/t9130/release/flash-image.bin $ROOTDIR/images
cp $ROOTDIR/build/linux/arch/arm64/boot/Image $ROOTDIR/images
cd $ROOTDIR/
ROOTFS_SIZE=$(stat -c "%s" $ROOTDIR/images/tmp/rootfs.ext4)
truncate -s 64M $ROOTDIR/images/tmp/ubuntu-core.img
truncate -s +$ROOTFS_SIZE $ROOTDIR/images/tmp/ubuntu-core.img
parted --script $ROOTDIR/images/tmp/ubuntu-core.img mklabel msdos mkpart primary 64MiB $((64*1024*1024+ROOTFS_SIZE-1))B
# Generate the above partuuid 3030303030 which is the 4 characters of '0' in ascii
echo "0000" | dd of=$ROOTDIR/images/tmp/ubuntu-core.img bs=1 seek=440 conv=notrunc
dd if=$ROOTDIR/images/tmp/rootfs.ext4 of=$ROOTDIR/images/tmp/ubuntu-core.img bs=1M seek=64 conv=notrunc,sparse
dd if=$ROOTDIR/build/arm-trusted-firmware/build/t9130/release/flash-image.bin of=$ROOTDIR/images/tmp/ubuntu-core.img bs=512 seek=4096 conv=notrunc,sparse
mv $ROOTDIR/images/tmp/ubuntu-core.img $ROOTDIR/images/ubuntu-${DTB_KERNEL}-${UBOOT_ENVIRONMENT}.img

echo "Images are ready at $ROOTDIR/image/"
