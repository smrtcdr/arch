#!/usr/bin/bash
#
# curl  -LO https://github.com/smrtcdr/arch/raw/master/strap.sh
#

# break on errors
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

function msg ()
{
  echo -e "${Green}[+] $*${Reset}"
}

msg "configuring pacman mirrors"
echo -e 'Server = http://ftp.eenet.ee/pub/archlinux/$repo/os/$arch' > /etc/pacman.d/mirrorlist
sed -i 's/#Color/Color/' /etc/pacman.conf

msg "clearing partition table on ${DISK}"
wipefs --all --force ${DISK}
sgdisk --zap-all --clear --mbrtogpt ${DISK}

msg "creating /boot and /root partitions on ${DISK}"
sgdisk -n 0:0:+100M -t 0:ef00 -c 0:"efi_boot" ${DISK}
sgdisk -n 0:0: -t 0:8300 -c 0:"linux" ${DISK}
partprobe /dev/sda
sgdisk -p /dev/sda

msg "creating filesystems"
mkfs.fat -F32 ${BOOT_PARTITION}
mkfs.ext4 -F ${ROOT_PARTITION}

msg "mounting partitions"
mount ${ROOT_PARTITION} ${TARGET_DIR}
mkdir ${TARGET_DIR}/boot
mount ${BOOT_PARTITION} ${TARGET_DIR}/boot

msg "bootstrapping base installation"
pacstrap ${TARGET_DIR} base sudo mc htop tmux

msg "configuring EFI boot"
arch-chroot ${TARGET_DIR} /usr/bin/bootctl --path=/boot install
partuuid=$(blkid -s PARTUUID -o value ${ROOT_PARTITION})
cat <<-EOF > ${TARGET_DIR}/boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /initramfs-linux.img
options root=PARTUUID=${partuuid} rw ipv6.disable=1
EOF

msg "configuring locales"
echo 'LANG=en_US.UTF-8' > ${TARGET_DIR}/etc/locale.conf
echo 'KEYMAP=us' > ${TARGET_DIR}/etc/vconsole.conf
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' ${TARGET_DIR}/etc/locale.gen
arch-chroot ${TARGET_DIR} /usr/bin/locale-gen

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
arch-chroot ${TARGET_DIR} /usr/bin/systemctl enable systemd-networkd

msg "configuring system settings"
genfstab -pU ${TARGET_DIR} >> ${TARGET_DIR}/etc/fstab
cp -rT ${TARGET_DIR}/etc/skel ${TARGET_DIR}/root
cat <<-EOF >> ${TARGET_DIR}/root/.bashrc
# my stuff
export PS1='\[\033[1;36m\]\u\[\033[1;31m\]@\[\033[1;32m\]\h:\[\033[1;35m\]\w\[\033[1;31m\]\$\[\033[0m\] '
EOF
sed -i 's/#Color/Color/' ${TARGET_DIR}/etc/pacman.conf
sed -i 's/include unknown.syntax/include sh.syntax/' ${TARGET_DIR}/usr/share/mc/syntax/Syntax
arch-chroot ${TARGET_DIR} ln -sf /usr/share/zoneinfo/Europe/Tallinn /etc/localtime
echo "a64vm" > ${TARGET_DIR}/etc/hostname

msg "installing extra packages"
arch-chroot ${TARGET_DIR} pacman -S --noconfirm openssh net-tools wget vim bash-completion pacman-contrib arch-install-scripts

msg "installing linux kernel"
arch-chroot ${TARGET_DIR} /usr/bin/pacman -S --noconfirm linux virtualbox-guest-modules-arch virtualbox-guest-utils-nox

msg "system cleanup"
arch-chroot ${TARGET_DIR} /usr/bin/pacman -Rdd --noconfirm --dbonly licenses pacman-mirrorlist
sed -i 's|#IgnorePkg   =|IgnorePkg   = licenses, pacman-mirrorlist|' ${TARGET_DIR}/etc/pacman.conf
sed -i 's|#NoExtract   =|NoExtract   = usr/share/doc/* \
NoExtract   = usr/share/licenses/* \
NoExtract   = usr/share/locale/* !usr/share/locale/locale.alias \
NoExtract   = usr/share/man/* !usr/share/man/man*|' ${TARGET_DIR}/etc/pacman.conf
# remove with exclusions
pushd ${TARGET_DIR}/usr/share/locale >/null
[ -n "$(find . -mindepth 1 ! -name "locale.alias" -delete 2>/dev/null)" ] && echo "error!"
cd ${TARGET_DIR}/usr/share/man
[ -n "$(find . -mindepth 1 -type d ! -name "man*" -delete 2>/dev/null)" ] && echo "error!"
popd >/dev/null
# remove everything
rm -rf ${TARGET_DIR}/usr/share/doc/*
rm -rf ${TARGET_DIR}/usr/share/licenses/*
rm -rf ${TARGET_DIR}/var/cache/pacman/pkg/ 
rm -rf ${TARGET_DIR}/var/lib/pacman/sync/ 

msg "backup script"
mkdir -p ${TARGET_DIR}/root/arch
cp `basename "$0"` ${TARGET_DIR}/root/arch

msg "finalizing..."
sync
du -hsx ${TARGET_DIR}
msg "installation complete!"
sleep 3
