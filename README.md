# debian-custom-iso

These scripts are built to generate customized Debian iso files that run a fully automatic and customized installation of Debian with the debootstrap tool. 

These scripts were originally created to build root on zfs systems and are optimized for creating a minimal install to build on.  

The debian-build.sh script will bootstrap a minimal system with zfs support with the repo included in /root. 

The automated installation is accomplished by having the resulting system automatically login as root on tty1 at boot; on a non ssh root login, the debian-auto-install.sh script will be launched inside of a tmux session that will automatically be attached on login over ssh.