#!/usr/bin/env bash

sudo pacman -Scc --noconfirm

sudo pacman -Rns manjaro-keyring archlinux-keyring
sudo rm -r /etc/pacman.d/gnupg
sudo pacman -S manjaro-keyring archlinux-keyring
sudo pacman-key --init
sudo pacman-key --populate manjaro archlinux
sudo pacman-mirrors -c Global

pamac update

clear
read -p "Repair compltete. Press any key to reboot the system."
sudo reboot
