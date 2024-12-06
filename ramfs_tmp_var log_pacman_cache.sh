#!/usr/bin/env bash

read -p "Creating an ramfs for tmp, var/log and pacman cache. Ptess any key to continue.."

echo "tmpfs   /tmp                tmpfs   defaults,noatime,nosuid,size=2G   0  0" | sudo tee -a /etc/fstab
echo "tmpfs   /var/log            tmpfs   defaults,noatime,nosuid,size=1G   0  0" | sudo tee -a /etc/fstab
echo "tmpfs   /var/cache/pacman/pkg tmpfs   defaults,noatime,nosuid,size=1G   0  0" | sudo tee -a /etc/fstab     

sudo nano /etc/fstab

sudo mkdir -p /var/log
sudo mkdir -p /var/cache/pacman/pkg

read -p "check pacman.conf the right cache dir.. Press any key to continue."
sudo nano /etc/pacman.conf

sudo mount -a

sudo reboot