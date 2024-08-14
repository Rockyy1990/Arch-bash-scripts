#!/bin/bash

# Custom ISO creater for CachyOS
# Last Edit: 14.08.24

read - "If you wont a CachyOS iso with latest packages press any key to continue.."

sudo pacman -Syy

sudo pacman -S --needed --noconfirm archiso mkinitcpio-archiso git squashfs-tools 

clear

git clone https://github.com/cachyos/cachyos-live-iso.git cachyos-archiso

read -p "Now you can edit the configs for the cachyos iso like add more packages etc."

sudo nano ~/cachyos-archiso/archiso/bootstrap_packages.x86_64
sudo nano ~/cachyos-archiso/archiso/packages_desktop.x86_64
sudo nano ~/cachyos-archiso/archiso/profiledef.sh

read -p "Do you wont to build the iso now press any key to continue"

cd cachyos-archiso

# Default iso desktop is plasma. 
sudo ./buildiso.sh -p desktop -v

read -p "Press any key to remove the build directory (~/cachyos-archiso/build) "
sudo rm -vr ~/cachyos-archiso/build

echo ""
echo "All done. Have fun"
