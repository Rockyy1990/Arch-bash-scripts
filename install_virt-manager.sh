#!/bin/bash

echo "Check this scipt before execute !!"
read -p "This script installs virt-manager. Press any key to continue."

sudo pacman -Syy
sudo pacman -S archlinux-keyring
sudo pacman -S qemu virt-manager virt-viewer dnsmasq vde2 bridge-utils openbsd-netcat dmidecode

sudo pacman -S ebtables iptables

sudo pacman -S libguestfs

sudo systemctl enable libvirtd.service
sudo systemctl start libvirtd.service

# set  unix_sock_group = "libvirt"  around line 85 and unix_sock_rw_perms = "0770" around line 102 -> etc/libvirt/libvirtd.conf 
sudo nano -w /etc/libvirt/libvirtd.conf

sudo usermod -a -G libvirt $(whoami)
newgrp libvirt

sudo systemctl restart libvirtd.service




