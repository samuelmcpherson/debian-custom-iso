#!/bin/bash

export TEMPMOUNT=/target

export SCRIPTDIR="/root/debian-custom-iso"

export HOSTNAME=unconfigured-host

export DOMAIN=managenet.lan

export DEBIAN_FRONTEND=noninteractive

export LANG=en_US.UTF-8

export TIMEZONE=America/Los_Angeles

LIVEDISK="$(mount | grep '/run/live/medium' | cut -d ' ' -f1 | cut -d '/' -f3)"
export LIVEDISK

export KEY_PATH='/etc/zfs'

export KEY_FILE='zroot.key'

TIMEOUT=30

for x in $(cat /proc/cmdline); do
        case $x in
        release=*)
                RELEASE=${x#release=} # bullseye, bookworm or sid
                ;;
        disklayout=*)
                DISKLAYOUT=${x#disklayout=} #ext4_single, zfs_single, zfs_mirror
                ;;
        # legacy boot not currently supported
        # bootmode=*)
        #         BOOTMODE=${x#bootmode=} #bios/legacy or efi/uefi
        #         ;;
        encryptionpass=*)
                ENCRYPTIONPASS=${x#encryptionpass=}
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
    DISK=$(lsblk -dno NAME | grep -v sr0 | grep -v loop | grep -v "$LIVEDISK" | sed -n 1p)

    for i in /dev/disk/by-id/*; do
        if [[ "$(readlink -f "$i")" = "/dev/$DISK" ]]; then 
            export FIRSTDISK=$i 
        fi
    done
            
    sgdisk --zap-all "$FIRSTDISK"
    sgdisk --clear "$FIRSTDISK"

    sgdisk     -n1:1M:+512M   -t1:EF00 "$FIRSTDISK"
    sgdisk     -n2:0:0        -t2:BE00 "$FIRSTDISK"

    sleep 3

    if [[ -n "$ENCRYPTIONPASS" ]]; then
        mkdir -p $KEY_PATH
        echo "$ENCRYPTIONPASS" > $KEY_PATH/$KEY_FILE        
        chmod 000 "$KEY_PATH/$KEY_FILE"
        echo "$ENCRYPTIONPASS" | zpool create -f -o ashift=12 -o autotrim=on -O acltype=posixacl -O compression=lz4 -O dnodesize=auto -O relatime=on -O xattr=sa -O normalization=formD -O canmount=off -O mountpoint=/ -O encryption=aes-256-gcm -O keylocation="file://$KEY_PATH/$KEY_FILE" -O keyformat=passphrase -R $TEMPMOUNT zroot "$FIRSTDISK-part2"
    elif [[ -z "$ENCRYPTIONPASS" ]]; then
        zpool create -f -o ashift=12 -o autotrim=on -O acltype=posixacl -O compression=lz4 -O dnodesize=auto -O relatime=on -O xattr=sa -O normalization=formD -O canmount=off -O mountpoint=/ -R $TEMPMOUNT zroot "$FIRSTDISK-part2"
    else 
        echo "Not a supported encryption configuration, how did you get here?"
        sleep 500
        exit 1
    fi

    zfs create -o canmount=off -o mountpoint=none -o org.zfsbootmenu:rootprefix="root=zfs:" -o org.zfsbootmenu:commandline="ro" zroot/ROOT

    zfs create -o canmount=noauto -o mountpoint=/ zroot/ROOT/default
    zfs mount zroot/ROOT/default
    zpool set bootfs=zroot/ROOT/default zroot
            
    zfs create -o canmount=off -o mountpoint=none zroot/DATA
    zfs create -o canmount=off -o mountpoint=none zroot/DATA/var
    zfs create -o canmount=off -o mountpoint=none zroot/DATA/var/lib
    zfs create -o canmount=on -o mountpoint=/var/log zroot/DATA/var/log
    zfs create -o canmount=on -o mountpoint=/home zroot/DATA/home
    zfs create -o canmount=on -o mountpoint=/home/"$USER" zroot/DATA/home/"$USER"

    mkfs.vfat -n EFI "$FIRSTDISK-part1"

    zpool export zroot

    zpool import -N -R $TEMPMOUNT zroot
    
    if [[ -n "$ENCRYPTIONPASS" ]]; then
        zfs load-key zroot
    fi

    zfs mount zroot/ROOT/default

    zfs mount -a 

    mkdir -p $TEMPMOUNT/boot/efi

    mkdir -p $TEMPMOUNT/etc

    mount "$FIRSTDISK-part1" $TEMPMOUNT/boot/efi

cat << EOF > $TEMPMOUNT/etc/fstab
/dev/disk/by-uuid/$(blkid -s UUID -o value "$FIRSTDISK-part1") /boot/efi vfat defaults,noauto 0 0
EOF
}

zfsMirrorDiskSetup(){
    DISK1=$(lsblk -dno NAME | grep -v sr0 | grep -v loop | grep -v "$LIVEDISK" | sed -n 1p)

    DISK2=$(lsblk -dno NAME | grep -v sr0 | grep -v loop | grep -v "$LIVEDISK" | sed -n 2p)

    for i in /dev/disk/by-id/*; do
        if [[ "$(readlink -f "$i")" = "/dev/$DISK1" ]]; then 
            export FIRSTDISK=$i 
        fi
    done

    for j in /dev/disk/by-id/*; do
        if [[ "$(readlink -f "$j")" = "/dev/$DISK2" ]]; then 
            export SECONDDISK=$j 
        fi
    done
            
    sgdisk --zap-all "$FIRSTDISK"
    sgdisk --clear "$FIRSTDISK"

    sgdisk     -n1:1M:+512M   -t1:EF00 "$FIRSTDISK"
    sgdisk     -n2:0:0        -t2:BE00 "$FIRSTDISK"

    sgdisk --zap-all "$SECONDDISK"
    sgdisk --clear "$SECONDDISK"

    sgdisk     -n1:1M:+512M   -t1:EF00 "$SECONDDISK"
    sgdisk     -n2:0:0        -t2:BE00 "$SECONDDISK"

    sleep 3    

    if [[ -n "$ENCRYPTIONPASS" ]]; then
        mkdir -p $KEY_PATH
        echo "$ENCRYPTIONPASS" > $KEY_PATH/$KEY_FILE        
        chmod 000 "$KEY_PATH/$KEY_FILE"
        echo "$ENCRYPTIONPASS" | zpool create -f -o ashift=12 -o autotrim=on -O acltype=posixacl -O compression=lz4 -O dnodesize=auto -O relatime=on -O xattr=sa -O normalization=formD -O canmount=off -O mountpoint=/ -O encryption=aes-256-gcm -O keylocation="file://$KEY_PATH/$KEY_FILE" -O keyformat=passphrase -R $TEMPMOUNT zroot mirror "$FIRSTDISK-part2" "$SECONDDISK-part2"
    elif [[ -z "$ENCRYPTIONPASS" ]]; then
        zpool create -f -o ashift=12 -o autotrim=on -O acltype=posixacl -O compression=lz4 -O dnodesize=auto -O relatime=on -O xattr=sa -O normalization=formD -O canmount=off -O mountpoint=/ -R $TEMPMOUNT zroot mirror "$FIRSTDISK-part2" "$SECONDDISK-part2"
    else 
        echo "Not a supported encryption configuration, how did you get here?"
        sleep 500
        exit 1
    fi
            
    zfs create -o canmount=off -o mountpoint=none -o org.zfsbootmenu:rootprefix="root=zfs:" -o org.zfsbootmenu:commandline="ro" zroot/ROOT

    zfs create -o canmount=noauto -o mountpoint=/ zroot/ROOT/default
    zfs mount zroot/ROOT/default
    zpool set bootfs=zroot/ROOT/default zroot
            
    zfs create -o canmount=off -o mountpoint=none zroot/DATA
    zfs create -o canmount=off -o mountpoint=none zroot/DATA/var
    zfs create -o canmount=off -o mountpoint=none zroot/DATA/var/lib
    zfs create -o canmount=on -o mountpoint=/var/log zroot/DATA/var/log
    zfs create -o canmount=on -o mountpoint=/home zroot/DATA/home
    zfs create -o canmount=on -o mountpoint=/home/"$USER" zroot/DATA/home/"$USER"

    mkfs.vfat -n EFI "$FIRSTDISK-part1"

    mkfs.vfat -n EFI2 "$SECONDDISK-part1"

    zpool export zroot

    zpool import -N -R $TEMPMOUNT zroot

    if [[ -n "$ENCRYPTIONPASS" ]]; then
        zfs load-key zroot
    fi

    zfs mount zroot/ROOT/default

    zfs mount -a 

    mkdir -p $TEMPMOUNT/boot/efi

    mkdir -p $TEMPMOUNT/boot/efi2

    mkdir -p $TEMPMOUNT/etc

    mount "$FIRSTDISK-part1" $TEMPMOUNT/boot/efi

    mount "$SECONDDISK-part1" $TEMPMOUNT/boot/efi2

cat << EOF > $TEMPMOUNT/etc/fstab
/dev/disk/by-uuid/$(blkid -s UUID -o value "$FIRSTDISK-part1") /boot/efi vfat defaults,noauto 0 0
/dev/disk/by-uuid/$(blkid -s UUID -o value "$SECONDDISK-part1") /boot/efi2 vfat defaults,noauto 0 0
EOF
}

ext4SingleDiskSetup(){
    DISK=$(lsblk -dno NAME | grep -v sr0 | grep -v loop | grep -v "$LIVEDISK" | sed -n 1p)

    for i in /dev/disk/by-id/*; do
        if [[ "$(readlink -f "$i")" = "/dev/$DISK" ]] 
            then 
            export FIRSTDISK=$i 
        fi
    done
            
    sgdisk --zap-all "$FIRSTDISK"
    sgdisk --clear "$FIRSTDISK"

    sgdisk     -n1:1M:+512M   -t1:EF00 "$FIRSTDISK"
    sgdisk     -n2:0:0        -t2:8300 "$FIRSTDISK"
      
    sleep 3

    mkfs.vfat -n EFI "$FIRSTDISK-part1"

    mkfs.ext4 "$FIRSTDISK-part2"

    mount "$FIRSTDISK-part2" $TEMPMOUNT

    mkdir -p $TEMPMOUNT/boot/efi

    mkdir -p $TEMPMOUNT/etc

    mount "$FIRSTDISK-part1" $TEMPMOUNT/boot/efi

    for j in /dev/disk/by-partuuid/*; do
        if [[ "$(readlink -f "$j")" = "/dev/$DISK"2 ]]; then 
            ROOT_PARTUUID=$(echo "$j" | cut -d '/' -f 5)
            export ROOT_PARTUUID
        fi
    done

cat << EOF > $TEMPMOUNT/etc/fstab
UUID=$(blkid -s UUID -o value "$FIRSTDISK-part2") / ext4 errors=remount-ro 0 1
UUID=$(blkid -s UUID -o value "$FIRSTDISK-part1") /boot/efi vfat defaults,noauto 0 0
EOF
}

bootstrap(){
    debootstrap "$RELEASE" $TEMPMOUNT

    mkdir -p $TEMPMOUNT/etc/network/interfaces.d

    for NETDEVICE in $(ip -br l | grep -v lo | cut -d ' ' -f1); do 

cat << EOF > $TEMPMOUNT/etc/network/interfaces.d/"$NETDEVICE"
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
deb http://deb.debian.org/debian $RELEASE main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $RELEASE main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $RELEASE-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security $RELEASE-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $RELEASE-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian $RELEASE-updates main contrib non-free non-free-firmware
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

    chroot $TEMPMOUNT /bin/bash -c "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
    chroot $TEMPMOUNT /bin/bash -c "hwclock --systohc"

    echo "$LANG UTF-8" >> $TEMPMOUNT/etc/locale.gen

    chroot $TEMPMOUNT /bin/bash -c "locale-gen"
    
    echo "LANG=$LANG" >> $TEMPMOUNT/etc/locale.conf
    
    echo "$HOSTNAME" > $TEMPMOUNT/etc/hostname
    
    echo "127.0.1.1 $HOSTNAME.$DOMAIN $HOSTNAME" >> $TEMPMOUNT/etc/hosts

    if [[ -n "$ENCRYPTIONPASS" ]]; then
        mkdir -p $TEMPMOUNT/$KEY_PATH
        echo "$ENCRYPTIONPASS" > $TEMPMOUNT$KEY_PATH/$KEY_FILE        
        chmod 000 $TEMPMOUNT$KEY_PATH/$KEY_FILE
    elif [[ -z "$ENCRYPTIONPASS" ]]; then
        echo "No encryption"
    else 
        echo "Not a supported encryption configuration, how did you get here?"
        sleep 500
        exit 1
    fi
}

packageInstallBase(){
    chroot $TEMPMOUNT /bin/bash -c "apt install -y dpkg-dev linux-headers-amd64 linux-image-amd64 systemd-sysv firmware-linux fwupd intel-microcode amd64-microcode dconf-cli console-setup wget git openssh-server sudo sed python3 dosfstools apt-transport-https rsync apt-file man"

    if [[ -n "$WIFI_NEEDED" ]]; then
       chroot $TEMPMOUNT /bin/bash -c "apt install -y firmware-iwlwifi firmware-libertas network-manager"

       cp /etc/systemd/system/wifi-autoconnect.service $TEMPMOUNT/etc/systemd/system/wifi-autoconnect.service

        for NETDEVICE in $(ip -br l | grep -v lo | cut -d ' ' -f1); do 
            rm $TEMPMOUNT/etc/network/interfaces.d/"$NETDEVICE"
        done
    fi
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
}

postInstallConfigZfs(){
    cp $SCRIPTDIR/zfs-recursive-restore.sh $TEMPMOUNT/usr/bin

    chroot $TEMPMOUNT /bin/bash -c "chmod +x /usr/bin/zfs-recursive-restore.sh"

    for file in "$TEMPMOUNT"/etc/logrotate.d/* ; do
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

    chroot $TEMPMOUNT /bin/bash -c "mkdir -p /etc/sanoid"

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

    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB3LG8oXQJM7GzoLt50rN630vdVTeGSpYE7f6JBPSMXp ansible-ssh-key' > $TEMPMOUNT/home/"$USER"/.ssh/authorized_keys

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
  
    cp $SCRIPTDIR/refind.conf $TEMPMOUNT/boot/efi/EFI/refind
}

bootSetupZfs(){
    chroot $TEMPMOUNT /bin/bash -c "mkdir -p /boot/efi/EFI/zbm"
    
cat << EOF > $TEMPMOUNT/boot/efi/EFI/zbm/refind_linux.conf
"Boot default"  "zfsbootmenu:POOL=zroot zbm.import_policy=hostid zbm.set_hostid zbm.timeout=30 ro quiet loglevel=4"
"Boot to menu"  "zfsbootmenu:POOL=zroot zbm.import_policy=hostid zbm.set_hostid zbm.show ro quiet loglevel=4"
EOF

    cp /root/zbm/vmlinuz.EFI $TEMPMOUNT/boot/efi/EFI/zbm/vmlinuz.EFI 

    if [[ "$DISKLAYOUT" = "zfs_mirror" ]]; then
        chroot $TEMPMOUNT /bin/bash -c "/usr/bin/rsync -a /boot/efi/EFI /boot/efi2"
    fi
}
bootSetupExt4(){
cat << EOF > $TEMPMOUNT/boot/refind_linux.conf
"Boot default"  "root=PARTUUID=$ROOT_PARTUUID rw add_efi_memmap"
EOF
}

###################################################################################################

echo "Debian $RELEASE will be installed with a $DISKLAYOUT root"
echo "Installation will begin automatically in $TIMEOUT seconds"
echo ""
echo "Please select one of the following options:"
echo ""
echo "  1)Press [Return] to start the installation now"
echo "  2)Abort the installation, the install script can be manually started with:"
echo "    $SCRIPTDIR/debian-auto-install.sh" 
echo "  3)Open Shell to live environment, delaying the installation until done"


read -rt $TIMEOUT n
if [[ -z "$n" ]]
then
    n=1
fi
case $n in
  1) echo "Starting automatic install of Debian $RELEASE with $DISKLAYOUT root" ;;
  2) exit 1 ;;
  3) /bin/bash ;;
esac

mkdir -p $TEMPMOUNT

if [[ "$DISKLAYOUT" = "zfs_single"  ]]; then

    zfsSingleDiskSetup

elif [[ "$DISKLAYOUT" = "zfs_mirror" ]]; then
    
    zfsMirrorDiskSetup

elif [[ "$DISKLAYOUT" = "ext4_single" ]]; then

    ext4SingleDiskSetup

else
    
    echo "Not a supported disk configuration"

    sleep 500

    exit 1

fi

sleep 3

echo "Checking network connectivity..."
echo ''

ping -c 4 google.com || export WIFI_NEEDED=yes

echo ''

if [[ -n "$WIFI_NEEDED" ]]; then

    echo "No network connectivity, attempting to conect to wifi..."
    echo ''
    
    systemctl start wifi-autoconnect.service

fi

sleep 3

bootstrap

baseChrootConfig

packageInstallBase

if [[ "$DISKLAYOUT" = "zfs_single" || "$DISKLAYOUT" = "zfs_mirror" ]]; then

    packageInstallZfs

    postInstallConfigZfs

else
    
    echo "Skipping zfs packages"

fi

postInstallConfig

userSetup

bootSetup

if [[ "$DISKLAYOUT" = "zfs_single" || "$DISKLAYOUT" = "zfs_mirror" ]]; then

    bootSetupZfs

    umount -Rl $TEMPMOUNT

    zpool export zroot

elif [[ "$DISKLAYOUT" = "ext4_single" ]]; then

    bootSetupExt4

    umount -Rl $TEMPMOUNT

else 
    
    echo "Not a supported disk configuration, how did you get here?"

    sleep 500

    exit 1
fi
    
reboot



