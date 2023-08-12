#!/usr/bin/env bash

echo ""
echo "Endeveour OS config"
echo "Unneeded Software or driver can be skip by press n"
sleep 3
echo "Nvidia Treiber mit Vulkan"
sudo pacman -S  nvidia-dkms nvidia-settings nvidia-utils lib32-nvidia-utils lib32-opencl-nvidia opencl-nvidia libvdpau libxnvctrl vulkan-icd-loader lib32-vulkan-icd-loader
clear

echo "AMD Treiber"
sudo pacman -S mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon vulkan-icd-loader lib32-vulkan-icd-loader
clear

echo "Intel Treiber"
sudo pacman -S vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver lib32-libva-intel-driver intel-gmmlib intel-compute-runtime throttled libmfx intel-opencl-clang vulkan-mesa-layers libva-mesa-driver glu glew mesa-vdpau ocl-icd
clear

echo "Snapper (Snapshots)"
yay -S btrfsmaintenance-git snapper snap-pac snapper-support btrfs-assistent-git
clear

echo "Gaming"
yay -S ttf-ms-fonts wine-staging faudio gamemode lib32-gamemode opencl-icd-loader lib32-openal lib32-libldap vkd3d lib32-vkd3d libgdiplus bottles steam protonup-qt
clear

echo "Programme"
yay -S discord strawberry vlc transmission-gtk ufw
sudo ufw enable
clear

echo "Optimierung"
yay -S grub-hook update-grub nohang-git systemd-zram 
sudo systemctl enable systemd-zram 
clear

echo "System erfolgreich eingerichtet"
echo "Neustart in 10 sekunden"
sleep 10
sudo reboot
