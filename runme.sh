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
#UEFI_RELEASE=DEBUG
#BOOT_LOADER=uefi
#DDR_SPEED=2400
#BOARD_CONFIG -
# 0-clearfog_cn COM express
# 1-napa
# 2-clearfog-base (cn9130 SOM)
# 3-clearfog-pro (cn9130 SOM)

###############################################################################
# Misc
###############################################################################

RELEASE=${RELEASE:-v5.12}
SHALLOW=${SHALLOW:true}
	if [ "x$SHALLOW" == "xtrue" ]; then
		SHALLOW_FLAG="--depth 1"
	fi
BOOT_LOADER=${BOOT_LOADER:-u-boot}
BOARD_CONFIG=${BOARD_CONFIG:-0}
CP_NUM=${CP_NUM:-1}
mkdir -p build images
ROOTDIR=`pwd`
PARALLEL=$(getconf _NPROCESSORS_ONLN) # Amount of parallel jobs for the builds
TOOLS="wget tar git make 7z unsquashfs dd vim mkfs.ext4 parted mkdosfs mcopy dtc iasl mkimage e2cp truncate qemu-system-aarch64 cpio rsync bc bison flex python unzip"

export PATH=$ROOTDIR/build/toolchain/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin:$PATH
export CROSS_COMPILE=aarch64-linux-gnu-
export ARCH=arm64

case "${BOARD_CONFIG}" in
	0)
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
	2)
		CP_NUM=1
		DTB_UBOOT=cn9130-cf-base
		DTB_KERNEL=cn9130-cf-base
	;;
	3)
		CP_NUM=1
		DTB_UBOOT=cn9130-cf-pro
		DTB_KERNEL=cn9130-cf-pro
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
                echo "sudo apt install build-essential git dosfstools e2fsprogs parted sudo mtools p7zip p7zip-full device-tree-compiler acpica-tools u-boot-tools e2tools qemu-system-arm libssl-dev cpio rsync bc bison flex python unzip"
                exit -1
        fi
done
set -e

# Check if git is configured:
#GIT_CONF=`git config user.name`
#if [ "x$GIT_CONF" == "x" ]; then
#	echo "git is not configured. please configure git username and email first"
#	exit -1
#fi

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
			echo "Cloing https://www.github.com/torvalds/$i release $RELEASE"
			cd $ROOTDIR/build
			git clone $SHALLOW_FLAG git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git linux -b v5.12
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
                        mkdir $ROOTDIR/build/$i
			echo "dpdk not supported yet"
		fi
		
		echo "Checking patches for $i"
		cd $ROOTDIR/build/$i
		if [ "x$i" == "xu-boot" ] && [[ -d $ROOTDIR/patches-sdk-u-boot/ ]]; then
			git am $ROOTDIR/patches-sdk-u-boot/*.patch
			git am $ROOTDIR/patches/$i/*.patch
		fi
		if [ "x$i" != "xu-boot" ] && [[ -d $ROOTDIR/patches/$i/ ]]; then
			git am $ROOTDIR/patches/$i/*.patch
		fi
	fi
done
##############################################################################
# File System
###############################################################################

if [[ ! -f $ROOTDIR/build/ubuntu-core.ext4 ]]; then
        echo "Building File System"
	cd $ROOTDIR/build
        mkdir -p ubuntu
        cd ubuntu
	if [ ! -d buildroot ]; then
                git clone $SHALLOW_FLAG https://github.com/buildroot/buildroot -b $BUILDROOT_VERSION
        fi
	cd buildroot	
	cp $ROOTDIR/configs/buildroot/buildroot_defconfig configs/
	make buildroot_defconfig 
	mkdir -p overlay/etc/init.d/
	cat > overlay/etc/init.d/S99bootstrap-ubuntu.sh << EOF
#!/bin/sh

case "\$1" in
        start)
		resize
                mkfs.ext4 -F /dev/vda -b 4096
                mount /dev/vda /mnt
                cd /mnt/
                udhcpc -i eth0
                wget -c -P /tmp/ http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.1-base-arm64.tar.gz
                tar zxf /tmp/ubuntu-base-20.04.1-base-arm64.tar.gz -C /mnt
                mount -o bind /proc /mnt/proc/
                mount -o bind /sys/ /mnt/sys/
                mount -o bind /dev/ /mnt/dev/
                mount -o bind /dev/pts /mnt/dev/pts
                mount -t tmpfs tmpfs /mnt/var/lib/apt/
                mount -t tmpfs tmpfs /mnt/var/cache/apt/
                echo "nameserver 8.8.8.8" > /mnt/etc/resolv.conf
                echo "localhost" > /mnt/etc/hostname
                echo "127.0.0.1 localhost" > /mnt/etc/hosts
                export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C
                chroot /mnt apt update
                chroot /mnt apt install --no-install-recommends -y systemd-sysv apt locales less wget procps openssh-server ifupdown net-tools isc-dhcp-client ntpdate lm-sensors i2c-tools psmisc less sudo htop iproute2 iputils-ping kmod network-manager iptables rng-tools apt-utils
                echo -e "root\nroot" | chroot /mnt passwd
                umount /mnt/var/lib/apt/
                umount /mnt/var/cache/apt
                chroot /mnt apt clean
                chroot /mnt apt autoclean
                reboot
                ;;

esac
EOF

	chmod +x overlay/etc/init.d/S99bootstrap-ubuntu.sh
	make
	IMG=ubuntu-core.ext4.tmp
	truncate -s 350M $IMG
	qemu-system-aarch64 -m 1G -M virt -cpu cortex-a57 -nographic -smp 1 -kernel output/images/Image -append "console=ttyAMA0" -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 -initrd output/images/rootfs.cpio.gz -drive file=$IMG,if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 -no-reboot
        mv $IMG $ROOTDIR/build/ubuntu-core.ext4

fi


###############################################################################
# Building sources u-boot / atf / mv-ddr / kernel
###############################################################################

# if patches from the sdk exist, then compile u-boot, otherwise, the atf will take the u-boot.bin from the binaries  
if [ "x$BOOT_LOADER" == "xu-boot" ] && [[ -d $ROOTDIR/patches-sdk-u-boot/ ]]; then
	echo "Building u-boot"
	cd $ROOTDIR/build/u-boot/
	make sr_cn913x_cex7_defconfig
	make -j${PARALLEL} DEVICE_TREE=$DTB_UBOOT
	cp $ROOTDIR/build/u-boot/u-boot.bin $ROOTDIR/binaries/u-boot/u-boot.bin
fi 

export BL33=$ROOTDIR/binaries/u-boot/u-boot.bin

if [ "x$BOOT_LOADER" == "xuefi" ]; then
	echo "no support for uefi yet"
fi

echo "Building arm-trusted-firmware"
cd $ROOTDIR/build/arm-trusted-firmware
export SCP_BL2=$ROOTDIR/binaries/atf/mrvl_scp_bl2.img
make -j${PARALLEL} USE_COHERENT_MEM=0 LOG_LEVEL=20 PLAT=t9130 MV_DDR_PATH=$ROOTDIR/build/mv-ddr-marvell CP_NUM=$CP_NUM all fip


echo "Building the kernel"
cd $ROOTDIR/build/linux
#make defconfig
./scripts/kconfig/merge_config.sh arch/arm64/configs/defconfig $ROOTDIR/configs/linux/cn913x_additions.config
make -j${PARALLEL} all #Image dtbs modules

\rm -rf $ROOTDIR/images/tmp
mkdir -p $ROOTDIR/images/tmp/
mkdir -p $ROOTDIR/images/tmp/boot
make INSTALL_MOD_PATH=$ROOTDIR/images/tmp/ INSTALL_MOD_STRIP=1 modules_install
cp $ROOTDIR/build/linux/arch/arm64/boot/Image $ROOTDIR/images/tmp/boot
cp $ROOTDIR/build/linux/arch/arm64/boot/dts/marvell/cn913*.dtb $ROOTDIR/images/tmp/boot


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
    FDT /boot/cn9132-cex7.dtb
    APPEND console=ttyS0,115200 root=PARTUUID=30303030-01 rw rootwait
EOF

# blkid images/tmp/ubuntu-core.img | cut -f2 -d'"'
cp $ROOTDIR/build/ubuntu-core.ext4 $ROOTDIR/images/tmp/
e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/ubuntu-core.ext4:extlinux
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/extlinux/extlinux.conf $ROOTDIR/images/tmp/ubuntu-core.ext4:extlinux/
e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/ubuntu-core.ext4:boot
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/boot/Image $ROOTDIR/images/tmp/ubuntu-core.ext4:boot/
e2cp -G 0 -O 0 $ROOTDIR/images/tmp/boot/cn9132-cex7.dtb $ROOTDIR/images/tmp/ubuntu-core.ext4:boot/

# Copy over kernel image
echo "Copying kernel modules"
cd $ROOTDIR/images/tmp/
for i in `find lib`; do
        if [ -d $i ]; then
                e2mkdir -G 0 -O 0 $ROOTDIR/images/tmp/ubuntu-core.ext4:usr/$i
        fi
        if [ -f $i ]; then
                DIR=`dirname $i`
                e2cp -G 0 -O 0 -p $ROOTDIR/images/tmp/$i $ROOTDIR/images/tmp/ubuntu-core.ext4:usr/$DIR
        fi
done
cd -




# ext4 ubuntu partition is ready
cp $ROOTDIR/build/arm-trusted-firmware/build/t9130/release/flash-image.bin $ROOTDIR/images
cp $ROOTDIR/build/linux/arch/arm64/boot/Image $ROOTDIR/images
cd $ROOTDIR/
truncate -s 420M $ROOTDIR/images/tmp/ubuntu-core.img
parted --script $ROOTDIR/images/tmp/ubuntu-core.img mklabel msdos mkpart primary 64MiB 417MiB
# Generate the above partuuid 3030303030 which is the 4 characters of '0' in ascii
echo "0000" | dd of=$ROOTDIR/images/tmp/ubuntu-core.img bs=1 seek=440 conv=notrunc
dd if=$ROOTDIR/images/tmp/ubuntu-core.ext4 of=$ROOTDIR/images/tmp/ubuntu-core.img bs=1M seek=64 conv=notrunc

dd if=$ROOTDIR/images/flash-image.bin of=$ROOTDIR/images/tmp/ubuntu-core.img bs=512 seek=4096 conv=notrunc
mv $ROOTDIR/images/tmp/ubuntu-core.img $ROOTDIR/images/${DTB_KERNEL}_config_${BOARD_CONFIG}_ubuntu.img

echo "Images are ready at $ROOTDIR/image/"
