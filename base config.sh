#!/bin/bash

echo "----------------------------------------------------------"
echo "ALCI (Arch Linux Calamares Installer) config after install" 
echo "----------------------------------------------------------"
sleep 5
set +o history
sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman -Sy
sudo pacman -Syyu
clear

echo "LTS und Zen Kernel"
sleep 3
sudo pacman -S linux-lts linux-lts-headers
sudo pacman -S linux-zen linux-zen-headers
clear

echo "Timeshift für ext4"
sleep 2
sudo pacman -S --needed timeshift timeshift-autosnap
clear

echo "Snapper (Snapshots) btrfs"
sleep 2
sudo pacman -S snapper snap-pac snapper-support grub-btrfs btrfs-assistant snap-pac-grub
clear

echo "SSD optimierung"
sleep 3
sudo systemctl enable fstrim.timer 
sudo fstrim / -v 
clear

echo "System einrichten.."
sleep 2
sudo pacman -S yay gnome-disk-utility gsmartcontrol gvfs f2fs-tools xfsdump ntfs-3g mtools xdg-user-dirs nano-syntax-highlighting neofetch
echo "neofetch" >> ~/.bashrc
sleep 1
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
clear

echo "Programme installieren"
sleep 3
sudo pacman -S vlc libreoffice-fresh libreoffice-fresh-de strawberry soundconverter ventoy transmission-gtk yt-dlp gsmartcontrol gufw flatpak discord
clear

echo "Weitere Schriftarten"
sleep 2
sudo pacman -S ttf-liberation ttf-linux-libertine ttf-ms-fonts ttf-ubuntu-font-family
clear

echo "Drucker einrichten"
sleep 3
sudo pacman -S --needed cups cups-filters cups-pdf gutenprint ghostscript foomatic-db-gutenprint-ppds foomatic-db-nonfree-ppds foomatic-db-ppds foomatic-db-engine system-config-printer
sudo systemctl enable cups.service
clear

echo "Pipewire"
sleep 2
sudo pacman -S gstreamer-vaapi gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-plugins-espeak gst-plugin-av lame pipewire-zeroconf pipewire-pulse gst-plugin-pipewire wireplumber pavucontrol pipewire-support
clear

echo "Pulseaudio"
sleep 2
sudo pacman -S pulseaudio pulseaudio-alsa pulseaudio-zeroconf pulseaudio-rtp pavucontrol

clear

echo "Nvidia Graphics Driver"
sleep 3
sudo pacman -S --needed nvidia-dkms nvidia-utils opencl-nvidia nvidia-settings lib32-nvidia-utils lib32-opencl-nvidia
clear

echo "Intel Graphics Driver"
sleep 3
pacman -S --needed vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver lib32-libva-intel-driver intel-gmmlib intel-compute-runtime throttled libmfx intel-opencl-clang vulkan-mesa-layers libva-mesa-driver glu glew mesa-vdpau ocl-icd
clear

echo "Gaming setup..."
sleep 3
sudo pacman -S --needed arcolinux-meta-wine steam gamemode
yay -S bottles protonup-qt steam-tweaks
clear

echo "ZSH einrichten.."
sleep 2
sudo pacman -S zsh zsh-completions zsh-syntax-highlighting zsh-autosuggestions 
chsh -s /usr/bin/zsh
clear

echo "Linux Mint icons and Theme"
sleep 2
sudo pacman -S mint-y-icons mint-themes
clear

echo "System wird aufgeräumt..."
yay -c
sudo paccache -r
history -c 
clear

echo "System erfolgreich konfiguriert.. Neustart nach 10 sekunden"
sleep 10

reboot











