#!/usr/bin/env bash

echo "----------------------------------------------"
echo "   ..Manjaro XFCE4 config after install..     "
echo "      with Timeshift & yay Aur Helper         "
echo "----------------------------------------------"
sleep 4

sudo pacman-mirrors --country Germany
sudo pacman -Sy
sudo pacman -Rs mousepad parole gparted audacious hexchat pidgin gimp onlyoffice-desktopeditors
sudo pacman -S yay dkms booster 
clear

echo "Pipewire statt pulseaudio"
sleep 3
sudo pacman -Rs pulseaudio-zeroconf manjaro-pulse
sudo pacman -S pipewire pipewire-alsa pipewire-pulse gst-plugin-pipewire wireplumber
clear

echo "System upgrade"
sleep 2
sudo pacman -Syyu
clear

echo "Nützliche Programme & System tools"
sleep 2
sudo pacman -S fakeroot base-devel jre-openjdk-headless neofetch gnome-text-editor ocl-icd lib32-libldap vkd3d lib32-vkd3d vulkan-tools ntp nss gnome-disk-utility libreoffice-fresh-de libreoffice-fresh shotwell udftools xfsdump f2fs-tools jfsutils mtools fatresize schroot aria2 cabextract wimlib chntpw cdrtools transmission-gtk libva mono yt-dlp

sudo systemctl enable ufw.service

echo "Windows Support"
sleep 3
sudo pacman -S faudio openal lib32-openal libgdiplus wine-staging wine-mono wine-gecko wine-mvulkan-icd-loader lib32-vulkan-icd-loader 
clear

echo "Drucker Support"
sleep 3
sudo pacman -S system-config-printer
sudo systemctl enable --now cups.service
sudo systemctl enable --now cups.socket
sudo systemctl enable --now cups.path
clear

echo "Netzwerk Drucker Support"
sleep 2
sudo pacman -S avahi
sudo systemctl enable --now avahi-daemon.service

clear

echo "Windows Support"
sleep 3
sudo pacman -S faudio openal lib32-openal libgdiplus wine-staging wine-gecko wine-mvulkan-icd-loader lib32-vulkan-icd-loader 
clear

echo "Fonts"
sudo pacman -S ttf-liberation ttf-ubuntu-font-family ttf-opensans gnu-free-fonts
clear

echo "Multimedia"
sudo pacman -S strawberry soundconverter audacity libsoxr manjaro-gstreamer gstreamer-vaapi gst-plugins-espeak
clear

echo "Installation von AUR Paketen"
sleep 3
yay -S grub-hook nohang-git auto-cpufreq ttf-ms-fonts mcmojave-circle-icon-theme  systemd-zram 
sudo systemctl condrestart systemd-zram  
clear

echo "SSD optimieren"
sleep 2
sudo systemctl enable fstrim.timer      

echo "swap optimieren"
echo "vm.swappiness=10" >> /etc/sysctl.d/100-manjaro.conf
echo ""
echo "System Bereinigung.."
echo 
sleep 3
yay -c
sudo paccache -r
sudo fstrim -av
clear
history -c
echo ""

echo "..Sytem erfolgreich eingerichtet.. Neustart in 10 sekunden!"
sleep 10
reboot
