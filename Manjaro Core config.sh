#! /bin/bash
echo "-------------------------------------------"
echo "Manjaro-Minimal XFCE4 config after install"
echo " ..ext4 und seperate Home Partition.."
echo "-------------------------------------------"
sleep 3
sudo pacman-mirrors --fasttrack
sudo pacman -Rs midori 
sudo pacman -S timeshift timeshift-autosnap 
clear

echo "Pipewire statt pulseaudio"
sleep 3
sudo pacman -Rs pulseaudio-zeroconf manjaro-pulse
sudo pacman -S pipewire pipewire-alsa pipewire-pulse gst-plugin-pipewire wireplumber
clear

echo "System upgrade und Installation von Programmen..."
sleep 3 
sudo pacman -Syyu
clear
sudo pacman -S fakeroot gcc make neofetch yay gsmartcontrol ocl-icd lib32-libldap vkd3d lib32-vkd3d vulkan-tools ntp ufw gufw ufw-extras nss gnome-disk-utility file-roller libreoffice-fresh-de libreoffice-fresh firefox firefox-i18n-de firefox-adblock-plus vlc strawberry gedit gedit-plugins shotwell udftools xfsdump mtools transmission-gtk libva gstreamer-vaapi sox lame manjaro-gstreamer mono ttf-dejavu ttf-liberation ttf-ubuntu-font-family yt-dlp

echo "neofetch" >> ~/.bashrc

echo "Installation von AUR Paketen"
sleep 3
yay -S grub-hook nohang-git auto-cpufreq ttf-ms-fonts mcmojave-circle-icon-theme elementary-xfce-icons-git systemd-zram 
sudo systemctl condrestart systemd-zram  
sudo systemctl enable ufw.service 

echo "Flatpak"
sleep 3
sudo pacman -S --needed flatpak flatpak-xdg-utils libpamac-flatpak-plugin
flatpak install flathub org.freac.freac               
flatpak install flathub com.usebottles.bottles        
flatpak install flathub com.discordapp.Discord        

echo "Drucker Support"
sleep 3
sudo pacman -S --needed cups cups-filters ghostscript gutenprint

echo "Windows Support"
sleep 3
sudo pacman -S --needed faudio openal lib32-openal libgdiplus wine-staging 

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
sudo fstrim -av

echo "swap optimieren"
echo "vm.swappiness=10" >> /etc/sysctl.d/100-manjaro.conf
echo ""
echo "System Bereinigung.."
echo 
sleep 3
yay -c
sudo paccache -r
clear
history -c
echo ""

echo "Sytem erfolgreich eingerichtet.. Neustart in 10 sekunden"
sleep 10
reboot
