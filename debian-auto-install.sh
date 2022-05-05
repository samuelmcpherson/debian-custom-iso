#!/bin/bash

export TEMPMOUNT=/target

export HOSTNAME=pxe-configured-host

export DOMAIN=managenet.lan

export SCRIPTDIR="/root/debian-custom-iso"

export USER=ansible

export USERPASS=changeme

export ROOTPASS=changeme

export DEBIAN_FRONTEND=noninteractive

export NETDEVICE=$(ip -br l | grep -v lo | sed -n 1p | cut -d ' ' -f1)

export RELEASE=

export LANG=en_US.UTF-8

export TIMEZONE=America/Los_Angeles

for x in $(cat /proc/cmdline); do
        case $x in
        release=*)
                RELEASE=${x#release=} # bullseye, bookworm or sid
                ;;
        disklayout=*)
                DISKLAYOUT=${x#disklayout=} #ext4_single, zfs_single, zfs_mirror
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

    sleep

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
    zfs create -V 16G -b 4096 -o logbias=throughput -o sync=always -o primarycache=metadata -o com.sun:auto-snapshot=false zroot/swap
    mkswap -f /dev/zvol/zroot/swap

    mkfs.vfat -n EFI $FIRSTDISK-part1

    zpool export zroot

    zpool import -N -R $TEMPMOUNT zroot

    zfs mount zroot/ROOT/default

    zfs mount -a 

    mkdir -p $TEMPMOUNT/boot/efi

    mkdir -p $TEMPMOUNT/etc

    mount $FIRSTDISK-part1 $TEMPMOUNT/boot/efi

cat << EOF > $TEMPMOUNT/etc/fstab
/dev/zvol/zroot/swap none swap defaults 0 0
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
    zfs create -V 16G -b 4096 -o logbias=throughput -o sync=always -o primarycache=metadata -o com.sun:auto-snapshot=false zroot/swap
    mkswap -f /dev/zvol/zroot/swap

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
/dev/zvol/zroot/swap none swap defaults 0 0
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

    mkfs.ext4 -n root $FIRSTDISK-part2

    mount $FIRSTDISK-part2 $TEMPMOUNT

    mkdir -p $TEMPMOUNT/boot/efi

    mkdir -p $TEMPMOUNT/etc

    mount $FIRSTDISK-part1 $TEMPMOUNT/boot/efi

cat << EOF > $TEMPMOUNT/etc/fstab
/dev/disk/by-uuid/$(blkid -s UUID -o value $FIRSTDISK-part1) /boot/efi vfat defaults,noauto 0 0
EOF
}

bootstrap(){
    debootstrap $RELEASE $TEMPMOUNT

    #mkdir -p $TEMPMOUNT/etc/network/interfaces.d

#cat << EOF > $TEMPMOUNT/etc/network/interfaces.d/$NETDEVICE
#auto $NETDEVICE
#iface $NETDEVICE inet dhcp
#EOF


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
    chroot $TEMPMOUNT /bin/bash -c "apt install -y dpkg-dev linux-headers-amd64 linux-image-amd64 systemd-sysv firmware-linux fwupd intel-microcode amd64-microcode dconf-cli console-setup wget git openssh-server sudo sed python3 dosfstools apt-transport-https rsync apt-file"
}

packageInstallZfs(){
    chroot $TEMPMOUNT /bin/bash -c "apt install -y zfs-initramfs"
}

postInstallConfig(){
    sed -i '/PermitRootLogin/c\PermitRootLogin\ no' $TEMPMOUNT/etc/ssh/sshd_config
    sed -i '/PermitEmptyPasswords/c\PermitEmptyPasswords\ no' $TEMPMOUNT/etc/ssh/sshd_config
    sed -i '/PasswordAuthentication/c\PasswordAuthentication\ no' $TEMPMOUNT/etc/ssh/sshd_config
    
    chroot $TEMPMOUNT /bin/bash -c "apt-file update"
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
}
    
userSetup(){
    chroot $TEMPMOUNT /bin/bash -c "mkdir -p /home/$USER"

    chroot $TEMPMOUNT /bin/bash -c "useradd -M -G sudo -s /bin/bash -d /home/$USER $USER"

    chroot $TEMPMOUNT /bin/bash -c "/home/$USER/.ssh"

    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICKzYpvYaW10iIkmNXls5v+XbdNBXBzZMYtWBZBzXcdO ansible-ssh-key' > $TEMPMOUNT/home/$USER/.ssh/authorized_keys

    chroot $TEMPMOUNT /bin/bash -c "chown -R $USER:users /home/$USER"

    chroot $TEMPMOUNT /bin/bash -c "echo root:$ROOTPASS | chpasswd"

    chroot $TEMPMOUNT /bin/bash -c "echo $USER:$USERPASS | chpasswd"
}

bootSetup(){

    chroot $TEMPMOUNT /bin/bash -c "apt -y install refind efibootmgr"
    
    chroot $TEMPMOUNT /bin/bash -c "mkdir -p /boot/efi/EFI/debian"
    
    chroot $TEMPMOUNT /bin/bash -c "cp /boot/vmlinuz-* /boot/efi/EFI/debian"

    chroot $TEMPMOUNT /bin/bash -c "cp /boot/initrd.img-* /boot/efi/EFI/debian"
  
    cp $SCRIPTDIR/refind.conf $TEMPMOUNT/boot/efi/EFI/refind

    chroot $TEMPMOUNT /bin/bash -c "mkdir -p /etc/initramfs/post-update.d"

cat << EOF > $TEMPMOUNT/etc/initramfs/post-update.d/10-copytoefi
#!/usr/bin/env bash

mount /boot/efi && cp -fv $(realpath /{vmlinuz,initrd.img}) /boot/efi/EFI/debian && umount /boot/efi
EOF
tmux new-session -d -s my_session
    chroot $TEMPMOUNT /bin/bash -c "chmod +x /etc/initramfs/post-update.d/10-copytoefi"
}

bootSetupZfs(){
    chroot $TEMPMOUNT /bin/bash -c "mkdir -p /boot/efi/EFI/zbm"
    
cat << EOF > $TEMPMOUNT/boot/efi/EFI/zbm/refind_linux.conf
"Boot default"  "zfsbootmenu:POOL=zroot zbm.import_policy=hostid zbm.set_hostid zbm.timeout=30 ro quiet loglevel=0"
"Boot to menu"  "zfsbootmenu:POOL=zroot zbm.import_policy=hostid zbm.set_hostid zbm.show ro quiet loglevel=0"
EOF

cat << EOF > $TEMPMOUNT/boot/efi/EFI/debian/refind_linux.conf    
"Standard boot"   "dozfs=force root=ZFS=zroot/ROOT/default rw" 
EOF
    cd $TEMPMOUNT/boot/efi/EFI/zbm && wget https://github.com/zbm-dev/zfsbootmenu/releases/download/v1.11.0/zfsbootmenu-x86_64-v1.11.0.EFI

    if [ "$DISKLAYOUT" == "zfs_mirror" ]
    then

        echo "mount /boot/efi2 && cp -fv $(realpath /{vmlinuz,initrd.img}) /boot/efi2/EFI/debian && umount /boot/efi2" >> $TEMPMOUNT/etc/initramfs/post-update.d/10-copytoefi
        
        chroot $TEMPMOUNT /bin/bash -c "/usr/bin/rsync -a /boot/efi /boot/efi2"
    fi
}

###################################################################################################

mkdir -p $TEMPMOUNT

if [ "$DISKLAYOUT" = "zfs_single"  ]; then

    zfsSingleDiskSetup

elif [ "$DISKLAYOUT" = "zfs_mirror" ]; then
    
    zfsMirrorDiskSetup

elif [ "$DISKLAYOUT" = "ext4_single" ]; then

    ext4SingleDiskSetup

else
    
    echo "Not a supported disk configuration"

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

else

    umount -Rl $TEMPMOUNT

fi
    
reboot



