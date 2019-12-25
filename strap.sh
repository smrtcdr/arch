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
pacstrap ${TARGET_DIR} base mc htop sudo
sync;

msg "configuring EFI boot"
arch-chroot ${TARGET_DIR} \
  bootctl --path=/boot install
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
arch-chroot ${TARGET_DIR} \
  systemctl enable systemd-networkd

msg "installing linux kernel"
arch-chroot ${TARGET_DIR} \
  pacman -S --noconfirm linux

msg "installing extra packages"
arch-chroot ${TARGET_DIR} \
  pacman -S --noconfirm virtualbox-guest-modules-arch virtualbox-guest-utils-nox \
            openssh net-tools vim bash-completion \
            arch-install-scripts pacman-contrib
sync;

msg "configuring user settings"
echo 'LANG=en_US.UTF-8' > ${TARGET_DIR}/etc/locale.conf
echo 'KEYMAP=us' > ${TARGET_DIR}/etc/vconsole.conf
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' ${TARGET_DIR}/etc/locale.gen
sed -i 's/#Color/Color/' ${TARGET_DIR}/etc/pacman.conf
sed -i 's/include unknown.syntax/include sh.syntax/' ${TARGET_DIR}/usr/share/mc/syntax/Syntax
arch-chroot ${TARGET_DIR} \
  cp -rT /etc/skel /root; \
  ln -sf /usr/share/zoneinfo/Europe/Tallinn /etc/localtime; \
  locale-gen && hostnamectl set-hostname arch64
sync;

msg "system cleanup"
arch-chroot ${TARGET_DIR} \
  pacman -Rdd --noconfirm licenses pacman-mirrorlist; sync;
if [[ -f ${TARGET_DIR}/etc/pacman.d/mirrorlist.pacsave ]]
    then mv ${TARGET_DIR}/etc/pacman.d/mirrorlist.pacsave ${TARGET_DIR}/etc/pacman.d/mirrorlist
fi
sed -i 's%#NoExtract\s=%NoExtract    = usr/share/doc/*\
NoExtract    = usr/share/licenses/*\
NoExtract    = usr/share/locale/* !usr/share/locale/locale.alias\
NoExtract    = usr/share/man/* !usr/share/man/man*%' ${TARGET_DIR}/etc/pacman.conf
rm -rf ${TARGET_DIR}/usr/share/doc/*
rm -rf ${TARGET_DIR}/usr/share/licenses/*
cd ${TARGET_DIR}/usr/share/locale && find . ! -name "locale.alias" -exec rm -r {} \; 2>/dev/null
cd ${TARGET_DIR}/usr/share/man && find . -type d ! -name "man*" -exec rm -r {} \; 2>/dev/null
rm -rf ${TARGET_DIR}/var/cache/pacman/pkg/ 
rm -rf ${TARGET_DIR}/var/lib/pacman/sync/ 
arch-chroot ${TARGET_DIR} \
  sync; du -hsx

msg "installation complete!"
pause 'Press [Enter] key to continue...'
