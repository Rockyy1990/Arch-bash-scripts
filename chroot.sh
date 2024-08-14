#!/usr/bin/env bash

echo "be careful. read this script befor execute!!"
read -p "Press any key to continue.."

#Chroot (Arch rescue or modify)

mount /dev/sdXY /mnt
#mount /dev/sdXY /mnt/boot      # needed bei extern /boot
mount -t proc proc /mnt/proc
mount -t sysfs sys /mnt/sys
mount -o bind /dev /mnt/dev
mount -t devpts /dev/pts /mnt/dev/pts/
mount -o bind /sys/firmware/efi/efivars /mnt/sys/firmware/efi/efivars

chroot /mount /bin/bash   #chroot into the system


#exit
#umount /mnt/dev/pts
#umount /mnt/dev
#umount /mnt/sys
#umount /mnt/proc
#umount /mnt/Verzeichnis        (optional: extern partiton (z.B.: /boot).
#umount /mnt


# arch-chroot (part of arch-install-scripts)
#sudo pacman -S arch-install-scripts

#mount /dev/sda1 /mnt
#arch-chroot /mnt

#exit
#umount /mnt
