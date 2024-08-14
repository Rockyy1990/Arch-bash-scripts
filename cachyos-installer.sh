#!/bin/bash

# Last Edit: 12.08.24

# Cachyos Installer on Archlinux

read -p "Archlinux to Cachyos (Optimized Packages etc) Press any key to start"


curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz

tar xvf cachyos-repo.tar.xz && cd cachyos-repo

sudo ./cachyos-repo.sh

sudo grub-mkconfig -o /boot/grub/grub.cfg

echo ""
echo "check pacman.conf"
sleep 2
sudo nano /etc/pacman.conf


sudo pacman -S --needed --noconfirm cachyos-kernel-manager
sudo pacman -S --needed --noconfirm cachyos-sysctl-manager


read -p "All done. Press any key to reboot the system"
sudo reboot
