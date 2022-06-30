#!/bin/bash

export TEMPMOUNT=/target

export SCRIPTDIR="/root/debian-custom-iso"

export HOSTNAME=unconfigured-host

export DOMAIN=managenet.lan

export DEBIAN_FRONTEND=noninteractive

export LANG=en_US.UTF-8

export TIMEZONE=America/Los_Angeles

TIMEOUT=30

for x in $(cat /proc/cmdline); do
        case $x in
        release=*)
                RELEASE=${x#release=} # bullseye, bookworm or sid
                ;;
        disklayout=*)
                DISKLAYOUT=${x#disklayout=} #ext4_single, zfs_single, zfs_mirror
                ;;
        bootmode=*)
                BOOTMODE=${x#bootmode=} #bios/legacy or efi/uefi
                ;;
        rootpass=*)
                ROOTPASS=${x#rootpass=}
                ;;
        user=*)
                USER=${x#user=}
                ;;
        userpass=*)
                USERPASS=${x#userpass=}
                ;;           
        esac
done

###################################################################################################

zfsSingleDiskSetup(){
    DISK=$(lsblk -dno NAME | grep -v sr0 | grep -v loop | sed -n 1p)

    for i in /dev/disk/by-id/*; do
        if [ "$(readlink -f $i)" = "/dev/$DISK" ] 
            then 
            export FIRSTDISK=$i 
        fi
    done
            
    sgdisk --zap-all $FIRSTDISK
    sgdisk --clear $FIRSTDISK

    sgdisk     -n1:1M:+512M   -t1:EF00 $FIRSTDISK
    sgdisk     -n2:0:0        -t2:BE00 $FIRSTDISK

    sleep 3

    zpool create -f -o ashift=12 -o autotrim=on -O acltype=posixacl -O compression=lz4 -O dnodesize=auto -O relatime=on -O xattr=sa -O normalization=formD -O canmount=off -O mountpoint=/ -R $TEMPMOUNT zroot $FIRSTDISK-part2
            
    zfs create -o canmount=off -o mountpoint=none -o org.zfsbootmenu:rootprefix="root=zfs:" -o org.zfsbootmenu:commandline="ro" zroot/ROOT

    zfs create -o canmount=noauto -o mountpoint=/ zroot/ROOT/default
    zfs mount zroot/ROOT/default
    zpool set bootfs=zroot/ROOT/default zroot
            
    zfs create -o canmount=off -o mountpoint=none zroot/DATA
    zfs create -o canmount=off -o mountpoint=none zroot/DATA/var
    zfs create -o canmount=off -o mountpoint=none zroot/DATA/var/lib
    zfs create -o canmount=on -o mountpoint=/var/log zroot/DATA/var/log
    zfs create -o canmount=off -o mountpoint=/home zroot/DATA/home
    zfs create -o canmount=on -o mountpoint=/home/$USER zroot/DATA/home/$USER

    mkfs.vfat -n EFI $FIRSTDISK-part1

    zpool export zroot

    zpool import -N -R $TEMPMOUNT zroot

    zfs mount zroot/ROOT/default

    zfs mount -a 

    mkdir -p $TEMPMOUNT/boot/efi

    mkdir -p $TEMPMOUNT/etc

    mount $FIRSTDISK-part1 $TEMPMOUNT/boot/efi

cat << EOF > $TEMPMOUNT/etc/fstab
/dev/disk/by-uuid/$(blkid -s UUID -o value $FIRSTDISK-part1) /boot/efi vfat defaults,noauto 0 0
EOF
}

zfsMirrorDiskSetup(){
    DISK1=$(lsblk -dno NAME | grep -v sr0 | grep -v loop | sed -n 1p)

    DISK2=$(lsblk -dno NAME | grep -v sr0 | grep -v loop | sed -n 2p)

    for i in /dev/disk/by-id/*; do
        if [ "$(readlink -f $i)" = "/dev/$DISK1" ] 
            then 
            export FIRSTDISK=$i 
        fi
    done

    for j in /dev/disk/by-id/*; do
        if [ "$(readlink -f $j)" = "/dev/$DISK2" ] 
            then 
            export SECONDDISK=$j 
        fi
    done
            
    sgdisk --zap-all $FIRSTDISK
    sgdisk --clear $FIRSTDISK

    sgdisk     -n1:1M:+512M   -t1:EF00 $FIRSTDISK
    sgdisk     -n2:0:0        -t2:BE00 $FIRSTDISK

    sgdisk --zap-all $SECONDDISK
    sgdisk --clear $SECONDDISK

    sgdisk     -n1:1M:+512M   -t1:EF00 $SECONDDISK
    sgdisk     -n2:0:0        -t2:BE00 $SECONDDISK

    sleep 3    

    zpool create -f -o ashift=12 -o autotrim=on -O acltype=posixacl -O compression=lz4 -O dnodesize=auto -O relatime=on -O xattr=sa -O normalization=formD -O canmount=off -O mountpoint=/ -R $TEMPMOUNT zroot mirror $FIRSTDISK-part2 $SECONDDISK-part2
            
    zfs create -o canmount=off -o mountpoint=none -o org.zfsbootmenu:rootprefix="root=zfs:" -o org.zfsbootmenu:commandline="ro" zroot/ROOT

    zfs create -o canmount=noauto -o mountpoint=/ zroot/ROOT/default
    zfs mount zroot/ROOT/default
    zpool set bootfs=zroot/ROOT/default zroot
            
    zfs create -o canmount=off -o mountpoint=none zroot/DATA
    zfs create -o canmount=off -o mountpoint=none zroot/DATA/var
    zfs create -o canmount=off -o mountpoint=none zroot/DATA/var/lib
    zfs create -o canmount=on -o mountpoint=/var/log zroot/DATA/var/log
    zfs create -o canmount=off -o mountpoint=/home zroot/DATA/home
    zfs create -o canmount=on -o mountpoint=/home/$USER zroot/DATA/home/$USER

    mkfs.vfat -n EFI $FIRSTDISK-part1

    mkfs.vfat -n EFI2 $SECONDDISK-part1

    zpool export zroot

    zpool import -N -R $TEMPMOUNT zroot

    zfs mount zroot/ROOT/default

    zfs mount -a 

    mkdir -p $TEMPMOUNT/boot/efi

    mkdir -p $TEMPMOUNT/boot/efi2

    mkdir -p $TEMPMOUNT/etc

    mount $FIRSTDISK-part1 $TEMPMOUNT/boot/efi

    mount $SECONDDISK-part1 $TEMPMOUNT/boot/efi2

cat << EOF > $TEMPMOUNT/etc/fstab
/dev/disk/by-uuid/$(blkid -s UUID -o value $FIRSTDISK-part1) /boot/efi vfat defaults,noauto 0 0
/dev/disk/by-uuid/$(blkid -s UUID -o value $SECONDDISK-part1) /boot/efi2 vfat defaults,noauto 0 0
EOF
}

ext4SingleDiskSetup(){
    DISK=$(lsblk -dno NAME | grep -v sr0 | grep -v loop | sed -n 1p)

    for i in /dev/disk/by-id/*; do
        if [ "$(readlink -f $i)" = "/dev/$DISK" ] 
            then 
            export FIRSTDISK=$i 
        fi
    done
            
    sgdisk --zap-all $FIRSTDISK
    sgdisk --clear $FIRSTDISK

    sgdisk     -n1:1M:+512M   -t1:EF00 $FIRSTDISK
    sgdisk     -n2:0:0        -t2:8300 $FIRSTDISK
      
    sleep 3

    mkfs.vfat -n EFI $FIRSTDISK-part1

    mkfs.ext4 $FIRSTDISK-part2

    mount $FIRSTDISK-part2 $TEMPMOUNT

    mkdir -p $TEMPMOUNT/boot/efi

    mkdir -p $TEMPMOUNT/etc

    mount $FIRSTDISK-part1 $TEMPMOUNT/boot/efi

    for j in /dev/disk/by-partuuid/*; do
        if [ "$(readlink -f $j)" = "/dev/$DISK"2 ] 
            then 
            export ROOT_PARTUUID=$(echo $j | cut -d '/' -f 5)
        fi
    done

cat << EOF > $TEMPMOUNT/etc/fstab
UUID=$(blkid -s UUID -o value $FIRSTDISK-part2) / ext4 errors=remount-ro 0 1
UUID=$(blkid -s UUID -o value $FIRSTDISK-part1) /boot/efi vfat defaults,noauto 0 0
EOF
}

bootstrap(){
    debootstrap $RELEASE $TEMPMOUNT

    mkdir -p $TEMPMOUNT/etc/network/interfaces.d

    for NETDEVICE in $(ip -br l | grep -v lo | cut -d ' ' -f1); do 

cat << EOF > $TEMPMOUNT/etc/network/interfaces.d/$NETDEVICE
auto $NETDEVICE
iface $NETDEVICE inet dhcp
EOF

    done

    mkdir -p $TEMPMOUNT/etc/systemd/system/networking.service.d

cat << EOF > $TEMPMOUNT/etc/systemd/system/networking.service.d/override.conf
[Service]
TimeoutStartSec=
TimeoutStartSec=1min
EOF

    cp /etc/hostid $TEMPMOUNT/etc/hostid

cat << EOF > $TEMPMOUNT/etc/apt/sources.list
deb http://deb.debian.org/debian $RELEASE main contrib non-free
deb-src http://deb.debian.org/debian $RELEASE main contrib non-free
deb http://security.debian.org/debian-security $RELEASE-security main contrib non-free
deb-src http://security.debian.org/debian-security $RELEASE-security main contrib non-free
deb http://deb.debian.org/debian $RELEASE-updates main contrib non-free
deb-src http://deb.debian.org/debian $RELEASE-updates main contrib non-free
EOF


    mkdir -p $TEMPMOUNT/dev

    mkdir -p $TEMPMOUNT/proc

    mkdir -p $TEMPMOUNT/sys

    mount --rbind /dev $TEMPMOUNT/dev

    mount --rbind /proc $TEMPMOUNT/proc

    mount --rbind /sys $TEMPMOUNT/sys
}

baseChrootConfig(){
    chroot $TEMPMOUNT /bin/bash -c "ln -s /proc/self/mounts /etc/mtab"
    
    chroot $TEMPMOUNT /bin/bash -c "apt -y update"
    
    chroot $TEMPMOUNT /bin/bash -c "apt install -y locales"

    chroot $TEMPMOUNT /bin/bash -c "ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime"
    chroot $TEMPMOUNT /bin/bash -c "hwclock --systohc"

    echo "$LANG UTF-8" >> $TEMPMOUNT/etc/locale.gen

    chroot $TEMPMOUNT /bin/bash -c "locale-gen"
    
    echo "LANG=$LANG" >> $TEMPMOUNT/etc/locale.conf
    
    echo "$HOSTNAME" > $TEMPMOUNT/etc/hostname
    
    echo "127.0.1.1 $HOSTNAME.$DOMAIN $HOSTNAME" >> $TEMPMOUNT/etc/hosts
}

packageInstallBase(){
    chroot $TEMPMOUNT /bin/bash -c "apt install -y dpkg-dev linux-headers-amd64 linux-image-amd64 systemd-sysv firmware-linux fwupd intel-microcode amd64-microcode dconf-cli console-setup wget git openssh-server sudo sed python3 dosfstools apt-transport-https rsync apt-file man unattended-upgrades"
    export CURRENT_KERNEL=$(chroot $TEMPMOUNT /bin/bash -c "realpath /vmlinuz")
}

packageInstallZfs(){
    chroot $TEMPMOUNT /bin/bash -c "apt install -y zfs-initramfs"
    chroot $TEMPMOUNT /bin/bash -c "apt install -y sanoid"
}

postInstallConfig(){
    sed -i '/PermitRootLogin/c\PermitRootLogin\ no' $TEMPMOUNT/etc/ssh/sshd_config
    sed -i '/PermitEmptyPasswords/c\PermitEmptyPasswords\ no' $TEMPMOUNT/etc/ssh/sshd_config
    sed -i '/PasswordAuthentication/c\PasswordAuthentication\ no' $TEMPMOUNT/etc/ssh/sshd_config
    
    chroot $TEMPMOUNT /bin/bash -c "apt-file update"

cat << 'EOF' >> $TEMPMOUNT/etc/apt/apt.conf.d/50unattended-upgrades

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::InstallOnShutdown "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::SyslogFacility "daemon";
Unattended-Upgrade::Verbose "true";

EOF
}

postInstallConfigZfs(){
    cp $SCRIPTDIR/zfs-recursive-restore.sh $TEMPMOUNT/usr/bin

    chroot $TEMPMOUNT /bin/bash -c "chmod +x /usr/bin/zfs-recursive-restore.sh"

    for file in $TEMPMOUNT/etc/logrotate.d/* ; do
        if grep -Eq "(^|[^#y])compress" "$file" ; then
            sed -i -r "s/(^|[^#y])(compress)/\1#\2/" "$file"
        fi
    done

    chroot $TEMPMOUNT /bin/bash -c "mkdir -p /etc/dkms"

    chroot $TEMPMOUNT /bin/bash -c "echo REMAKE_INITRD=yes > /etc/dkms/zfs.conf"

    chroot $TEMPMOUNT /bin/bash -c "zpool set cachefile=/etc/zfs/zpool.cache zroot"

    chroot $TEMPMOUNT /bin/bash -c "systemctl enable zfs.target"
    chroot $TEMPMOUNT /bin/bash -c "systemctl enable zfs-import-cache"
    chroot $TEMPMOUNT /bin/bash -c "systemctl enable zfs-mount"
    chroot $TEMPMOUNT /bin/bash -c "systemctl enable zfs-import.target"

    chroot $TEMPMOUNT /bin/bash -c "cp /usr/share/systemd/tmp.mount /etc/systemd/system/"
    chroot $TEMPMOUNT /bin/bash -c "systemctl enable tmp.mount"

cat << 'EOF' > $TEMPMOUNT/etc/sanoid/sanoid.conf
[zroot]
        use_template = production
        recursive = yes

#############################
# templates below this line #
#############################

[template_production]
        frequently = 0
        hourly = 36
        daily = 30
        monthly = 6
        yearly = 0
        autosnap = yes
        autoprune = yes
EOF
}
    
userSetup(){
    chroot $TEMPMOUNT /bin/bash -c "mkdir -p /home/$USER"

    chroot $TEMPMOUNT /bin/bash -c "useradd -M -G sudo -s /bin/bash -d /home/$USER $USER"

    chroot $TEMPMOUNT /bin/bash -c "mkdir /home/$USER/.ssh"

    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKzYpvYaW10iIkmNXls5v+XbdNBXBzZMYtWBZBzXcdO ansible-ssh-key' > $TEMPMOUNT/home/$USER/.ssh/authorized_keys

    chroot $TEMPMOUNT /bin/bash -c "chown -R $USER:$USER /home/$USER"

cat << EOF > $TEMPMOUNT/root/root-pass
root:$ROOTPASS
EOF

cat << EOF > $TEMPMOUNT/root/user-pass
$USER:$USERPASS
EOF

    chroot $TEMPMOUNT /bin/bash -c "cat /root/root-pass | chpasswd"

    chroot $TEMPMOUNT /bin/bash -c "cat /root/user-pass | chpasswd"

    rm $TEMPMOUNT/root/root-pass

    rm $TEMPMOUNT/root/user-pass
}

bootSetup(){

    chroot $TEMPMOUNT /bin/bash -c "apt -y install refind efibootmgr"
    
    chroot $TEMPMOUNT /bin/bash -c "mkdir -p /boot/efi/EFI/debian"
    
    chroot $TEMPMOUNT /bin/bash -c "cp /boot/vmlinuz-* /boot/efi/EFI/debian"

    chroot $TEMPMOUNT /bin/bash -c "cp /boot/initrd.img-* /boot/efi/EFI/debian"
  
    cp $SCRIPTDIR/refind.conf $TEMPMOUNT/boot/efi/EFI/refind

cat << 'EOF' >> $TEMPMOUNT/etc/kernel/postinst.d/initramfs-tools

echo "Mounting efi system partition at /boot/efi"
mount /boot/efi    
sleep 1

update-initramfs -c -k "${version}" -b /boot/efi/EFI/debian >&2

sleep 1

full_kernel="/boot/vmlinuz-$version"

echo "Copy full kernel from /boot to /boot/efi/EFI/debian/vmlinuz-$version"
cp "$full_kernel" /boot/efi/EFI/debian

echo "Setting linux-image-$version and linux-headers-$version to manually installed to avoid autoremoval"
apt-mark manual "linux-image-$version"
apt-mark manual "linux-headers-$version"

echo "Adding $version to list of kernels to keep in /boot/current-kernels"
echo "$version" >> /boot/current-kernels 

echo "Keeping list of kernels to keep in /boot/current-kernels to a maximum of three"
if [ "$(wc -l /boot/current-kernels | cut -d ' ' -f 1)" == "4" ]; then
    
    echo "Finding the oldest kernel in the list to be kept (first line entry)"
    old_version="$(sed -n 1p /boot/current-kernels)"

    echo "Found oldest kernel to no longer keep: $old_version\nSetting linux-image-$old_version and linux-headers-$old_version to auto installed for autoremoval"
    apt-mark auto "linux-image-$old_version"
    apt-mark auto "linux-headers-$old_version"

    echo "Removing $old_version from list of kernels to keep"
    sed -i 1d /boot/current-kernels

fi
EOF

if [ "$DISKLAYOUT" = "zfs_single" -o "$DISKLAYOUT" = "zfs_mirror" ]; then

cat << EOF >> $TEMPMOUNT/etc/kernel/postinst.d/initramfs-tools

sed -i "s/BOOT_IMAGE=\/boot\/\([^ ]*\) /BOOT_IMAGE=$full_kernel /g" /boot/efi/EFI/debian/refind_linux.conf
EOF
else
    
cat << 'EOF' >> $TEMPMOUNT/etc/kernel/postinst.d/initramfs-tools

sed -i "s/BOOT_IMAGE=\/boot\/\([^ ]*\) /BOOT_IMAGE=$full_kernel /g" /boot/efi/EFI/debian/refind_linux.conf
EOF

fi

cat << EOF >> $TEMPMOUNT/etc/kernel/postinst.d/initramfs-tools

sleep 1
echo "Unmounting efi system partition from /boot/efi"
umount /boot/efi

sleep 1

if [ -f "/boot/efi.img-bak" ]; then
    echo "Found existing /boot/efi.img-bak, removing"
    rm "/boot/efi.img-bak"
fi

if [ -f "/boot/efi.img" ]; then
    echo "Found existing /boot/efi.img, renaming to /boot/efi.img-bak"
    mv "/boot/efi.img" "/boot/efi.img-bak"
fi

echo "Creating image of current efi system partition at /boot/efi.img"
dd "if=$FIRSTDISK-part1" "of=/boot/efi.img" bs=4096 status=progress
EOF

cat << 'EOF' >> $TEMPMOUNT/etc/kernel/postrm.d/initramfs-tools

echo "Mounting efi system partition at /boot/efi"
mount /boot/efi    
sleep 1

update-initramfs -d -k "${version}" -b /boot/efi/EFI/debian >&2

sleep 1

full_kernel="vmlinuz-$version"

echo "Removing full kernel at /boot/efi/EFI/debian/vmlinuz-$version"
rm "/boot/efi/EFI/debian/$full_kernel"

sleep 1
echo "Unmounting efi system partition from /boot/efi"
umount /boot/efi

sleep 1

if [ -f "/boot/efi.img-bak" ]; then
    echo "Found existing /boot/efi.img-bak, removing"
    rm "/boot/efi.img-bak"
fi

if [ -f "/boot/efi.img" ]; then
    echo "Found existing /boot/efi.img, renaming to /boot/efi.img-bak"
    mv "/boot/efi.img" "/boot/efi.img-bak"
fi
EOF

cat << EOF >> $TEMPMOUNT/etc/kernel/postrm.d/initramfs-tools

echo "Creating image of current efi system partition at /boot/efi.img"
dd "if=$FIRSTDISK-part1" "of=/boot/efi.img" bs=4096 status=progress
EOF
}

bootSetupZfs(){
    chroot $TEMPMOUNT /bin/bash -c "mkdir -p /boot/efi/EFI/zbm"
    
cat << EOF > $TEMPMOUNT/boot/efi/EFI/zbm/refind_linux.conf
"Boot default"  "zfsbootmenu:POOL=zroot zbm.import_policy=hostid zbm.set_hostid zbm.timeout=30 ro quiet loglevel=4"
"Boot to menu"  "zfsbootmenu:POOL=zroot zbm.import_policy=hostid zbm.set_hostid zbm.show ro quiet loglevel=4"
EOF

cat << EOF > $TEMPMOUNT/boot/efi/EFI/debian/refind_linux.conf    
"Standard boot"   "BOOT_IMAGE=$CURRENT_KERNEL dozfs=force root=ZFS=zroot/ROOT/default rw" 
EOF

    cd $TEMPMOUNT/boot/efi/EFI/zbm && wget https://github.com/zbm-dev/zfsbootmenu/releases/download/v1.12.0/zfsbootmenu-release-vmlinuz-x86_64-v1.12.0.EFI

    if [ "$DISKLAYOUT" == "zfs_mirror" ]
    then

cat << 'EOF' >> $TEMPMOUNT/etc/kernel/postinst.d/initramfs-tools

echo "Mounting second efi system partition at /boot/efi2"
mount /boot/efi2
sleep 1

update-initramfs -c -k "${version}" -b /boot/efi2/EFI/debian >&2 

sleep 1

echo "Copy full kernel from /boot to /boot/efi2/EFI/debian/vmlinuz-$version"
cp "$full_kernel" /boot/efi2/EFI/debian
EOF

if [ "$DISKLAYOUT" = "zfs_single" -o "$DISKLAYOUT" = "zfs_mirror" ]; then

cat << EOF >> $TEMPMOUNT/etc/kernel/postinst.d/initramfs-tools

sed -i "s/BOOT_IMAGE=\/boot\/\([^ ]*\) /BOOT_IMAGE=$full_kernel /g" /boot/efi2/EFI/debian/refind_linux.conf

sleep 1
echo "Unmounting second efi system partition from /boot/efi2"
umount /boot/efi2
EOF
else
    
cat << 'EOF' >> $TEMPMOUNT/etc/kernel/postinst.d/initramfs-tools

sed -i "s/BOOT_IMAGE=\/boot\/\([^ ]*\) /BOOT_IMAGE=$full_kernel /g" /boot/efi2/EFI/debian/refind_linux.conf

sleep 1
echo "Unmounting second efi system partition from /boot/efi2"
umount /boot/efi2
EOF

fi

cat << 'EOF' >> $TEMPMOUNT/etc/kernel/postrm.d/initramfs-tools

echo "Mounting second efi system partition at /boot/efi2"
mount /boot/efi2    
sleep 1

update-initramfs -d -k "${version}" -b /boot/efi2/EFI/debian >&2

sleep 1

echo "Removing full kernel at /boot/efi2/EFI/debian/vmlinuz-$version"
rm "/boot/efi2/EFI/debian/$full_kernel"

sleep 1
echo "Unmounting second efi system partition from /boot/efi2"
umount /boot/efi2

EOF

        chroot $TEMPMOUNT /bin/bash -c "/usr/bin/rsync -a /boot/efi/EFI /boot/efi2"
    fi
}
bootSetupExt4(){
cat << EOF > $TEMPMOUNT/boot/efi/EFI/debian/refind_linux.conf 
"Standard boot"     "BOOT_IMAGE=$CURRENT_KERNEL root=PARTUUID=$ROOT_PARTUUID rw add_efi_memmap"
EOF
}

###################################################################################################

echo "Debian $RELEASE will be installed with a $DISKLAYOUT root"
echo "Installation will begin automatically in $TIMEOUT seconds"
echo ""
echo "Please select one of the following options:"
echo ""
echo "  1)Press [Return] to start the installation now"
echo "  2)Abort the installation, the install script can be manually started with:\n      $SCRIPTDIR/debian-auto-install.sh" 
echo "  3)Open Shell to live environment, delaying the installation until done"


read -rt $TIMEOUT n
if [ -z "$n" ]
then
    n=1
fi
case $n in
  1) echo "Starting automatic install of Debian $RELEASE with $DISKLAYOUT root" ;;
  2) exit 1 ;;
  3) /bin/bash ;;
esac

mkdir -p $TEMPMOUNT

if [ "$DISKLAYOUT" = "zfs_single"  ]; then

    zfsSingleDiskSetup

elif [ "$DISKLAYOUT" = "zfs_mirror" ]; then
    
    zfsMirrorDiskSetup

elif [ "$DISKLAYOUT" = "ext4_single" ]; then

    ext4SingleDiskSetup

else
    
    echo "Not a supported disk configuration"

    sleep 500

    exit 1

fi

bootstrap

baseChrootConfig

packageInstallBase

if [ "$DISKLAYOUT" = "zfs_single" -o "$DISKLAYOUT" = "zfs_mirror" ]; then

    packageInstallZfs

    postInstallConfigZfs

else
    
    echo "Skipping zfs packages"

fi

postInstallConfig

userSetup

bootSetup

if [ "$DISKLAYOUT" = "zfs_single" -o "$DISKLAYOUT" = "zfs_mirror" ]; then

    bootSetupZfs

    umount -Rl $TEMPMOUNT

    zpool export zroot

elif [ "$DISKLAYOUT" = "ext4_single" ]; then

    bootSetupExt4

    umount -Rl $TEMPMOUNT

else 
    
    echo "Not a supported disk configuration, how did you get here?"

    sleep 500

    exit 1
fi
    
reboot



