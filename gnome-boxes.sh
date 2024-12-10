#!/usr/bin/env bash

read -p "This installs Gnome-Boxes. Press any key to continue.."

sudo pacman -S --needed gnome-boxes qemu libvirt virt-manager

sudo systemctl enable libvirtd

sudo systemctl start libvirtd









