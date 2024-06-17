#!/usr/bin/env bash

# Exit when an error happens
set -e

# Function to prompt the user with a yes or no question
function yesno() {
	local prompt="$1"

	while true; do
		read -rp "$prompt [y/n] " yn
		case $yn in
			[Yy]* ) echo "y"; return;;
			[Nn]* ) echo "n"; return;;
			* ) echo "Please answer yes or no.";;
		esac
	done
}

if ! [[ -b "/dev/vda" ]]; then
	echo "Checking UEFI bitness."
	if "$(cat /sys/firmware/efi/fw_platform_size)" -eq 64; then
		echo "UEFI bitness is 64."
	else 
		echo "UEFI bitness is not 64, please reboot into UEFI and try again."
		exit
	fi
fi

echo "Checking internet connection."
if ping -c 1 "archlinux.org" > /dev/null 2>&1; then
	echo "Internet connection established."
else
	echo "Unable to connect to the internet. Please connect and then try again."
	exit
fi


cat << Introduction
This script will format the entire disk with a 1GB boot partition
16GB of swap, and then allocate the rest to EXT4.
Introduction

# If in a VM
if [[ -b "/dev/vda" ]]; then
DISK="/dev/vda"

BOOTDISK="${DISK}3"
SWAPDISK="${DISK}2"
ROOTDISK="${DISK}1"

# Normal disk
else
cat << FormatWarning
Please enter the disk by ID to be formatted without the part number.
(e.g nvme-eui.0123456789). Your devices are shown below:

FormatWarning

ls -al /dev/disk/by-id

echo ""

read -r DISKINPUT
DISK="/dev/disk/by-id/${DISKINPUT}"

BOOTDISK="${DISK}-part3"
SWAPDISK="${DISK}-part2"
ROOTDISK="${DISK}-part1"
fi

echo "Boot Partition: $BOOTDISK"
echo "SWAP Partition: $SWAPDISK"
echo "Root Partition: $ROOTDISK"

do_format=$(yesno "This irreversibly formats the entire disk. Are you sure?")

if [[ $do_format == "n" ]]; then
	exit
fi

echo "Removing all previous partitions."
blkdiscard -f "$DISK" >> ~/install.log 2>&1

echo "Creating boot partition."
# -n3 is the 3rd partition, 1M is starting sector, +1G ends sector in 1 GiB. -t3 is type of 3rd partition. EF00 is EFI.
sgdisk -n3:1M:+1G -t3:EF00 "$DISK" >> ~/install.log 2>&1

echo "Creating swap partition."
# 8200 is Linux swap
sgdisk -n2:0:+16G -t2:8200 "$DISK" >> ~/install.log 2>&1

echo "Creating root partition."
# Second 0 creates partition using all available free space. 8300 is Linux Filesystem.
sgdisk -n1:0:0 -t1:8300 "$DISK" >> ~/install.log 2>&1

echo "Notifying kernel of partition changes."
sgdisk -p "$DISK" > /dev/null
sleep 5

echo "Formatting boot partition."
mkfs.fat -F 32 "$BOOTDISK" -n ARCHBOOT >> ~/install.log 2>&1

echo "Formatting swap partition."
mkswap "$SWAPDISK" --label "swap" >> ~/install.log 2>&1

echo "Formatting root partition."
mkfs.ext4 "$ROOTDISK" -L "root" >> ~/install.log 2>&1

echo "Mounting root partition at /mnt."
mount "$ROOTDISK" /mnt >> ~/install.log 2>&1

echo "Mounting boot partiton at /mnt/boot."
mount --mkdir "$BOOTDISK" /mnt/boot >> ~/install.log 2>&1

echo "Mounting swap partition."
swapon "$SWAPDISK" >> ~/install.log 2>&1

echo "Installing base packages."
pacstrap -K /mnt base base-devel linux linux-firmware nano networkmanager dhcpcd >> ~/install.log 2>&1

echo "Generating /etc/fstab."
genfstab -U /mnt >> /mnt/etc/fstab

function archchroot() {
	echo "What timezone would you like the system to be set to? (e.g. America/Chicago)"
	read -r TIMEZONE 

	echo "Setting timezone to ${TIMEZONE}"
	ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime >> ~/install.log 2>&1

	echo "Syncing hardware clock"
	hwclock --systohc >> ~/install.log 2>&1

	echo "Setting locale to en_US.UTF-8"
	sed -i '/en_US.UTF-8 UTF-8/s/^#//g' /etc/locale.gen >> ~/install.log 2>&1

	echo "Generating locale."
	locale-gen >> ~/install.log 2>&1

	echo "Creating /etc/locale.conf."
	echo LANG=en_US.UTF-8 > /etc/locale.conf

	echo "What hostname would you like the system to be set to? (e.g. arch)"
	read -r HOSTNAME

	echo "Setting hostname to ${HOSTNAME}"
	echo ${HOSTNAME} > /etc/hostname

	echo "Please set the root user's password."
	passwd

	echo "Installing systemd-boot."
	bootctl install >> ~/install.log 2>&1

	echo "Configuring loader.conf."
	echo default arch.conf >> /boot/loader/loader.conf
	echo timeout 0 >> /boot/loader/loader.conf
	echo editor no >> /boot/loader/loader.conf

	echo "Generating arch boot entry."
	echo title Arch Linux >> /boot/loader/entries/arch.conf
	echo linux /vmlinuz-linux >> /boot/loader/entries/arch.conf
	echo initrd /initramfs-linux.img >> /boot/loader/entries/arch.conf
	echo ${DISK}
	echo "$(blkid -s PARTUUID -o value ${DISK}1)"
	if [[ -b "/dev/vda" ]]; then
		echo "options root=PARTUUID=$(blkid -s PARTUUID -o value ${DISK}1) rw" >> /boot/loader/entries/arch.conf
	else
		echo "options root=PARTUUID=$(blkid -s PARTUUID -o value /dev/${DISKINPUT}1) rw" >> /boot/loader/entries/arch.conf
	fi
}

export -f archchroot

if [[ -b "/dev/vda" ]]; then
	export DISK=/dev/vda
else
	export DISKINPUT=${DISKINPUT}
fi

echo "Changing root into new system."
arch-chroot /mnt /bin/bash -c "archchroot"

echo "Unmounting system."
umount -R ${DISK}1 >> ~/install.log 2>&1

echo "Installation finished. You can now reboot."
