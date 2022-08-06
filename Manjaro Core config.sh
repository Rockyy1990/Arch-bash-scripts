#! /bin/bash

echo "----------------------------------------------"
echo "..Manjaro-Minimal XFCE4 config after install.."
echo " ..ext4 und seperate Home Partition..         "
echo "----------------------------------------------"
sleep 4
sudo pacman-mirrors --country Germany
sudo pacman -Sy
sudo pacman -Rs midori parole
sudo pacman -S timeshift timeshift-autosnap 
clear

echo "Pipewire statt pulseaudio"
sleep 3
sudo pacman -Rs pulseaudio-zeroconf manjaro-pulse
sudo pacman -S pipewire pipewire-alsa pipewire-pulse gst-plugin-pipewire wireplumber
clear

echo "System upgrade"
sleep 3 
sudo pacman -Syyu
clear
echo "Firefox"
sudo pacman -S firefox firefox-i18n-de firefox-adblock-plus
clear
echo "Multimedia"
sudo pacman -S --needed vlc strawberry lame flac libsoxr manjaro-gstreamer gstreamer-vaapi gst-plugins-espeak
clear
echo "Nützliche Programme & System tools"
sudo pacman -S fakeroot gcc make neofetch yay gsmartcontrol gnome-text-editor ocl-icd lib32-libldap vkd3d lib32-vkd3d vulkan-tools ntp gufw ufw-extras nss gnome-disk-utility file-roller libreoffice-fresh-de libreoffice-fresh  shotwell udftools xfsdump f2fs-tools mtools transmission-gtk libva mono ttf-dejavu ttf-liberation ttf-ubuntu-font-family yt-dlp

sudo systemctl enable ufw.service 
echo "neofetch" >> ~/.bashrc

clear
echo "Installation von AUR Paketen"
sleep 3
yay -S grub-hook nohang-git auto-cpufreq ttf-ms-fonts mcmojave-circle-icon-theme elementary-xfce-icons-git systemd-zram 
sudo systemctl condrestart systemd-zram  


echo "Flatpak"
sleep 3
sudo pacman -S --needed flatpak flatpak-xdg-utils libpamac-flatpak-plugin
flatpak install flathub org.freac.freac               
flatpak install flathub com.usebottles.bottles        
flatpak install flathub com.discordapp.Discord        
clear

echo "Drucker Support"
sleep 3
sudo pacman -S --needed cups cups-filters ghostscript gutenprint system-config-printer
sudo systemctl enable --now cups.service
sudo systemctl enable --now cups.socket
sudo systemctl enable --now cups.path
clear

echo "Netzwerk Drucker Support"
sudo pacman -S avahi
sudo systemctl enable --now avahi-daemon.service

clear

echo "Windows Support"
sleep 3
sudo pacman -S --needed faudio openal lib32-openal libgdiplus wine-staging 
clear

echo "Steam Gaming Plattform installation"
sleep 3
yay -S --needed steam protontricks steam-tweaks
echo "hrtf = true" >> ~/.alsoftrc

echo "IPTV"
sleep 2
yay -S hypnotix

echo "Bluray wiedergabe"
sleep 2
yay -S aacskeys makemkv-libaacs libbluray

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

echo "Sytem erfolgreich eingerichtet.. Neustart in 10 sekunden"
sleep 10
reboot
