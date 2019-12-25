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
sgdisk -Z ${DISK}
wipefs -a ${DISK}

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
pacstrap ${TARGET_DIR} base mc htop sudo --ignore pacman-mirrorlist

msg "configuring EFI boot"
arch-chroot ${TARGET_DIR} bootctl --path=/boot install
partuuid=$(blkid -s PARTUUID -o value $root_device)
tee ${TARGET_DIR}/boot/loader/entries/arch.conf <<EOF
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=${partuuid} rw ipv6.disable=1
EOF

msg "generating fstab"
genfstab -pU ${TARGET_DIR} >> ${TARGET_DIR}/etc/fstab

msg "configure network"
tee ${TARGET_DIR}/etc/systemd/network/enp0s3.network <<EOF
[Match]
name=enp0s3
[Network]
DHCP=ipv4
LinkLocalAddresing=no
IPv6AcceptRA=no
EOF
echo 'nameserver 192.168.1.1' >> ${TARGET_DIR}/etc/resolv.conf
arch-chroot ${TARGET_DIR} systemctl enable systemd-networkd

msg "installing linux kernel"
arch-chroot ${TARGET_DIR} pacman -S --noconfirm linux

msg "installing extra packages"
arch-chroot ${TARGET_DIR} \
pacman -S --noconfirm virtualbox-guest-modules-arch virtualbox-guest-utils-nox \
            openssh net-tools vim bash-completion \
            arch-install-scripts pacman-contrib

msg "configuring user settings"
echo 'LANG=en_US.UTF-8' > ${TARGET_DIR}/etc/locale.conf
echo 'KEYMAP=us' > ${TARGET_DIR}/etc/vconsole.conf
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' ${TARGET_DIR}/etc/locale.gen
arch-chroot ${TARGET_DIR} locale-gen
arch-chroot ${TARGET_DIR} cp -rT /etc/skel /root
arch-chroot ${TARGET_DIR} ln -sf /usr/share/zoneinfo/Europe/Tallinn /etc/localtime
arch-chroot ${TARGET_DIR} sed -i 's/#Color/Color/' /etc/pacman.conf
arch-chroot ${TARGET_DIR} sed -i 's/include unknown.syntax/include sh.syntax/' /usr/share/mc/syntax/Syntax
arch-chroot ${TARGET_DIR} hostnamectl set-hostname arch64

msg "system cleanup"
arch-chroot ${TARGET_DIR} sed -i 's%#NoExtract\s=%NoExtract    = usr/share/doc/*\
NoExtract    = usr/share/licenses/*\
NoExtract    = usr/share/locale/* !usr/share/locale/locale.alias\
NoExtract    = usr/share/man/* !usr/share/man/man*%' /etc/pacman.conf
arch-chroot ${TARGET_DIR} rm -rf /usr/share/doc/*
arch-chroot ${TARGET_DIR} rm -rf /usr/share/licenses/*
arch-chroot ${TARGET_DIR} cd /usr/share/locale && find . ! -name "locale.alias" -exec rm -r {} \;
arch-chroot ${TARGET_DIR} cd /usr/share/man && find . -type d ! -name "man*" -exec rm -r {} \;
arch-chroot ${TARGET_DIR} rm -rf /var/cache/pacman/pkg/ 
arch-chroot ${TARGET_DIR} rm -rf /var/lib/pacman/sync/ 
arch-chroot ${TARGET_DIR} du -hsx /

msg "installation complete!"
pause 'Press [Enter] key to continue...'
