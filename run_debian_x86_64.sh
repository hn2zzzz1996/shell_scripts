#!/bin/bash

LROOT=$PWD
JOBCOUNT=${JOBCOUNT=$(nproc)}
export ARCH=x86_64
export INSTALL_PATH=$LROOT/rootfs_debian_x86_64/boot/
export INSTALL_MOD_PATH=$LROOT/rootfs_debian_x86_64/
export INSTALL_HDR_PATH=$LROOT/rootfs_debian_x86_64/usr/

kernel_build=$PWD/rootfs_debian_x86_64/usr/src/linux/
rootfs_path=$PWD/rootfs_debian_x86_64
rootfs_image=$PWD/rootfs_debian_x86_64.ext4

rootfs_size=8192

SMP="-smp 2"

if [ $# -lt 1 ]; then
	echo "Usage: $0 [arg]"
	echo "build_kernel: build the kernel image."
	echo "build_rootfs: build the rootfs image."
	echo " run:  run debian system."
fi

if [ $# -eq 2 ] && [ $2 == "debug" ]; then
	echo "Enable qemu debug server"
	DBG="-s -S"
	# SMP=""
fi

make_kernel_image(){
		echo "start build kernel image..."
		make debian_defconfig
		make -j $JOBCOUNT
}

prepare_rootfs(){
		if [ ! -d $rootfs_path ]; then
			echo "decompressing rootfs..."
			tar -Jxf rootfs_debian_x86_64.tar.xz
		fi
}

build_kernel_devel(){
	kernver="$(make -s kernelrelease)"
	echo "kernel version: $kernver"

	mkdir -p $kernel_build
	rm rootfs_debian_x86_64/lib/modules/$kernver/build
	cp -a include $kernel_build
	cp Makefile .config Module.symvers System.map $kernel_build
	mkdir -p $kernel_build/arch/x86/
	mkdir -p $kernel_build/arch/x86/kernel/
	mkdir -p $kernel_build/scripts

	cp -a arch/x86/include $kernel_build/arch/x86/
	cp -a arch/x86/Makefile $kernel_build/arch/x86/
	cp scripts/gcc-goto.sh $kernel_build/scripts
	cp -a scripts/Makefile.*  $kernel_build/scripts
	#cp arch/x86/kernel/module.lds $kernel_build/arch/x86/kernel/

	ln -s /usr/src/linux rootfs_debian_x86_64/lib/modules/$kernver/build

}

check_root(){
		if [ "$(id -u)" != "0" ];then
			echo "superuser privileges are required to run"
			echo "sudo ./run_debian_x86_64.sh build_rootfs"
			exit 1
		fi
}

update_rootfs(){
		if [ ! -f $rootfs_image ]; then
			echo "rootfs image is not present..., pls run build_rootfs"
		else
			echo "update rootfs ..."

			mkdir -p $rootfs_path
			echo "mount ext4 image into rootfs_debian_x86_64"
			mount -t ext4 $rootfs_image $rootfs_path -o loop

			make install
			make modules_install -j $JOBCOUNT
			make headers_install

			build_kernel_devel

			umount $rootfs_path
			chmod 777 $rootfs_image

			rm -rf $rootfs_path
		fi

}

build_rootfs(){
		if [ ! -f $rootfs_image ]; then
			make install
			make modules_install -j $JOBCOUNT
			#make headers_install

			build_kernel_devel

			echo "making image..."
			dd if=/dev/zero of=rootfs_debian_x86_64.ext4 bs=1M count=$rootfs_size
			mkfs.ext4 rootfs_debian_x86_64.ext4
			mkdir -p tmpfs
			echo "copy data into rootfs..."
			mount -t ext4 rootfs_debian_x86_64.ext4 tmpfs/ -o loop
			cp -af rootfs_debian_x86_64/* tmpfs/
			umount tmpfs
			chmod 777 rootfs_debian_x86_64.ext4
		fi

}

update_kvm(){
		if [ ! -f $rootfs_image ]; then
			echo "rootfs image is not present..., pls run build_rootfs"
		else
			echo "update rootfs ..."

			mkdir -p $rootfs_path
			echo "mount ext4 image into rootfs_debian_x86_64"
			mount -t ext4 $rootfs_image $rootfs_path -o loop

			make -C . M=arch/x86/kvm modules_install 

			build_kernel_devel

			umount $rootfs_path
			chmod 777 $rootfs_image

			rm -rf $rootfs_path
		fi
}

# debug-alternative
		# gdb --directory ~/working/software/qemu-6.1.0/ --args \
			# --trace "kvm_set_user_memory" \
			# --trace "pci_cfg_write" \
			# --trace "kvm_vcpu_ioctl" \
			# -device intel-iommu,intremap=on \
			# -drive if=pflash,format=raw,readonly,file=./bios.bin \

# KERNEL=arch/x86/boot/bzImage
KERNEL=/home/hsq/bzImage

run_qemu_debian(){
		gdb --directory ~/working/software/qemu-6.1.0/ --args \
		qemu-system-x86_64 \
			-m 4G \
			-machine q35,kernel-irqchip=split \
			--enable-kvm \
			-cpu host \
			-nographic $SMP -kernel $KERNEL \
			-append "nokaslr noinitrd console=ttyS0 crashkernel=256M 
					root=/dev/vda rootfstype=ext4 rw loglevel=8" \
			-drive if=none,file=rootfs_debian_x86_64.ext4,id=hd0 \
			-device virtio-blk-pci,drive=hd0 \
			--fsdev local,id=kmod_dev,path=./sharefs,security_model=none \
			-device virtio-9p-pci,fsdev=kmod_dev,mount_tag=kmod_mount\
			-netdev user,id=mynet\
			-device virtio-net-pci,netdev=mynet\
			-device edu,dma_mask=0xffffffffffffffff\
			$DBG

}

case $1 in
	build_kernel)
		make_kernel_image
		#prepare_rootfs
		#build_rootfs
		;;
	
	build_rootfs)
		#make_kernel_image
		check_root
		prepare_rootfs
		build_rootfs
		;;
	update_rootfs)
		check_root
		update_rootfs
		;;
	update_kvm)
		check_root
		update_kvm
		;;
	run)

		if [ ! -f $LROOT/arch/x86/boot/bzImage ]; then
			echo "canot find kernel image, pls run build_kernel command firstly!!"
			echo "./run_debian_x86_64.sh build_kernel"
			exit 1
		fi

		if [ ! -f $rootfs_image ]; then
			echo "canot find rootfs image, pls run build_rootfs command firstly!!"
			echo "sudo ./run_debian_x86_64.sh build_rootfs"
			exit 1
		fi

		#prepare_rootfs
		#build_rootfs
		run_qemu_debian
		;;
esac

