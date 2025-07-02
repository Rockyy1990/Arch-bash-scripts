#!/usr/bin/env bash

# Last Edit: 01.07.25

echo ""
echo " ---------------------------"
echo "       Archlinux config     "
echo "         (EndeveourOS)      "
echo "----------------------------"
echo ""
echo " These environments are recommended:
        XFCE4
        Gnome
        Cinnamon
"		
echo ""
read -p "Press any key to start the config."
echo ""


# Update the system
sudo pacman -Syu --noconfirm

# Install necessary packages
sudo pacman -S --needed --noconfirm base-devel fakeroot pacman-contrib dkms gsmartcontrol gvfs gvfs-smb gufw samba git curl 
sudo pacman -S --needed --noconfirm mesa mesa-utils opencl-mesa vulkan-mesa-layers vulkan-tools
sudo pacman -S --needed --noconfirm firefox firefox-i18n-de thunderbird mousepad 
sudo pacman -S --needed --noconfirm linux-zen linux-zen-headers

# Multimedia
sudo pacman -S --needed --noconfirm ffmpeg fdkaac flac libmad0 flac lame twolame libtheora libmatroska x264 x265 a52dec libsoxr gst-libav rtkit
sudo pacman -S --needed --noconfirm celluloid handbrake soundconverter yt-dlp pavucontrol


# Gaming
sudo pacman -S --needed steam libgdiplus gamemode lib32-gamemode
yay -S --needed protonup-qt-bin protontricks bottles faudio ttf-ms-fonts

yay -S --needed nomachine ventoy-bin update-grub
yay -S --needed pamac-aur

# performance optimized firefox browser
# yay -S --needed zen-browser-bin 


# Install fish shell as default
sudo pacman -S --needed fish
chsh -s /usr/bin/fish
echo "/usr/bin/fish" | sudo tee -a /etc/shells
sudo chsh -s /usr/bin/fish root
sudo chsh -s /usr/bin/fish lxadmin

# SSD Trim
sudo systemctl enable fstrim
sudo fstrim -av

clear
echo ""
echo "Archlinux configuration completed successfully."
echo ""
echo ""
sleep 2
read -p "Press any key to reboot.."
sudo reboot
