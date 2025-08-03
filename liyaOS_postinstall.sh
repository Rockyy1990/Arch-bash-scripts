#!/usr/bin/env bash

echo ""
echo "LiyaOS Postinstall"
read -p "Press any key to continue..."
echo ""

sudo pacman -R --noconfirm brave-bin gnome-chess-classic gnuchess gnome-robots perl-www-robotrules timeshift timeshift-autosnap geary pinta bleachbit
sudo pacman -R proton-vpn-gtk-app python-proton-core python-proton-vpn-network-manager python-proton-vpn-local-agent

sudo pacman-key --init
sudo pacman-key --populate
sudo pacman -Syu
clear

sudo pacman -S --needed --noconfirm lib32-mesa lib32-mesa-utils opencl-mesa vulkan-radeon vulkan-swrast vulkan-mesa-layers vulkan-dzn vulkan-extra-layers

sudo pacman -S --needed --noconfirm yay xfsdump  vivaldi vivaldi-ffmpeg-codecs thunderbird
sudo pacman -S --needed soundconverter yt-dlp handbrake gstreamer-vaapi pipewire-v4l2 pipewire-zeroconf gst-plugin-pipewire 

sudo pacman -S --needed --noconfirm steam bottles protonup-qt protontricks winetricks wine wine-mono libgdiplus openal
yay -S faudio
clear

sudo pacman -Scc --noconfirm

sudo systemctl enable fstrim.timer
sudo fstrim -av 

clear
echo "Postinstall is now complete."
read -p "Press any key to reboot.."
sudo reboot

