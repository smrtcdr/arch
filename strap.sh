#!/usr/bin/env bash

set -e

DISK='/dev/sda'
KEYMAP='us'
LANGUAGE='en_US.UTF-8'
TARGET_DIR='/mnt'
BOOT_PARTITION="${DISK}1"
ROOT_PARTITION="${DISK}2"

# colorize messages
Green='\e[0;32m'
Reset='\e[0m'

function pause ()
{
    read -p "$*"
}

function msg ()
{
    echo -e "${Green}[+] $*${Reset}"
}

msg "clearing partition table on ${DISK}"
wipefs -a ${DISK}
sgdisk -Z ${DISK}

msg "creating /boot and /root partitions on ${DISK}"
sgdisk -n 0:0:+100M -t 0:ef00 -c 0:"efi_boot" ${DISK}
sgdisk -n 0:0: -t 0:8300 -c 0:"linux" ${DISK}
partprobe /dev/sda
sgdisk -p /dev/sda

msg "creating filesystems"
mkfs.fat -F32 ${BOOT_PARTITION}
mkfs.ext4 -m 0 -F ${ROOT_PARTITION}

msg "mounting partitions"
mount ${ROOT_PARTITION} ${TARGET_DIR}
mkdir ${TARGET_DIR}/boot
mount ${BOOT_PARTITION} ${TARGET_DIR}/boot

msg "configure pacman mirrors"
echo -e 'Server = http://ftp.eenet.ee/pub/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist
sed -i 's/#Color/Color/' /etc/pacman.conf

msg "bootstrapping base installation"
pacstrap ${TARGET_DIR} base mc htop sudo

msg "configure EFI boot"
arch-chroot ${TARGET_DIR} bootctl --path=/boot install
cat <<-EOF > ${TARGET_DIR}/boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=$( blkid -s PARTUUID -o value ${ROOT_PARTITION} ) rw ipv6.disable=1
EOF

msg "generate fstab"
genfstab -pU ${TARGET_DIR} >> ${TARGET_DIR}/etc/fstab

msg "configure network"
cat <<-EOF > ${TARGET_DIR}/etc/systemd/network/enp0s3.network
[Match]
name=enp0s3
[Network]
DHCP=ipv4
LinkLocalAddresing=no
IPv6AcceptRA=no
EOF
echo 'nameserver 192.168.1.1' >> ${TARGET_DIR}/etc/resolv.conf
arch-chroot ${TARGET_DIR} systemctl enable systemd-networkd

msg "install linux kernel"
arch-chroot ${TARGET_DIR} pacman -S --noconfirm linux

msg "install extra packages"
arch-chroot ${TARGET_DIR} pacman -S --noconfirm virtualbox-guest-modules-arch virtualbox-guest-utils-nox
arch-chroot ${TARGET_DIR} pacman -S --noconfirm openssh net-tools vim arch-install-scripts

msg "configure user settings"
echo 'LANG=en_US.UTF-8' > ${TARGET_DIR}/etc/locale.conf
echo 'KEYMAP=us' > ${TARGET_DIR}/etc/vconsole.conf
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' ${TARGET_DIR}/etc/locale.gen
arch-chroot ${TARGET_DIR} locale-gen
arch-chroot ${TARGET_DIR} cp -rT /etc/skel /root
arch-chroot ${TARGET_DIR} ln -sf /usr/share/zoneinfo/Europe/Tallinn /etc/localtime
arch-chroot ${TARGET_DIR} sed -i 's/#Color/Color/' /etc/pacman.conf
arch-chroot ${TARGET_DIR} sed -i 's/include unknown.syntax/include sh.syntax/' /usr/share/mc/syntax/Syntax
arch-chroot ${TARGET_DIR} hostnamectl set-hostname arch64
arch-chroot ${TARGET_DIR} yes | pacman -Scc
arch-chroot ${TARGET_DIR} du -hsx /

msg "installation complete!"
pause 'Press [Enter] key to continue...'
