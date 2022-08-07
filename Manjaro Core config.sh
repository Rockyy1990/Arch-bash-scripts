#!/usr/bin/env bash

echo "----------------------------------------------"
echo "..Manjaro-Minimal XFCE4 config after install.."
echo "   with Dracut, Timeshift & Paru Aur Helper   "
echo "----------------------------------------------"
sleep 4

sudo pacman-mirrors --country Germany
sudo pacman -Sy
sudo pacman -Rs midori parole gparted pamac-gtk libpamac-flatpak-plugin manjaro-application-utility manjaro-hello --noconfirm
sudo pacman -S dkms timeshift timeshift-autosnap 
clear

echo "Install Paru AUR Helper"
sudo pacman -S --needed base-devel
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si
cd
clear

echo "Pipewire statt pulseaudio"
sleep 3
sudo pacman -Rs pulseaudio-zeroconf manjaro-pulse
sudo pacman -S pipewire pipewire-alsa pipewire-pulse gst-plugin-pipewire wireplumber
clear

echo "Dracut for building initramfs images"
sleep 2
paru -S dracut dracut-hook-uefi rebuild-initramfs-dracut rebuild-initramfs-dracut-hook
clear

echo "System upgrade"
sleep 3 
sudo pacman -Syyu
clear

echo "Fonts"
sudo pacman -S ttf-dejavu ttf-droid  ttf-liberation ttf-ubuntu-font-family
clear

echo "Firefox"
sudo pacman -S firefox firefox-i18n-de firefox-adblock-plus
clear

echo "Multimedia"
sudo pacman -S --needed vlc strawberry lame flac libsoxr manjaro-gstreamer gstreamer-vaapi gst-plugins-espeak
clear

echo "Nützliche Programme & System tools"
sleep 2
sudo pacman -S --needed fakeroot base-devel jre-openjdk-headless neofetch gsmartcontrol gnome-text-editor ocl-icd lib32-libldap vkd3d lib32-vkd3d vulkan-tools ntp gufw ufw-extras nss gnome-disk-utility file-roller libreoffice-fresh-de libreoffice-fresh shotwell udftools xfsdump f2fs-tools jfsutils mtools aria2 cabextract wimlib chntpw cdrtools transmission-gtk libva mono yt-dlp

sudo systemctl enable ufw.service 
echo "neofetch" >> ~/.bashrc
clear

echo "ZSH"
sleep 2
sudo paru -S zsh zsh-autosuggestions zsh-syntax-highlighting zsh-completions zsh-fish
chsh -s /usr/bin/zsh

clear
echo "Installation von AUR Paketen"
sleep 3
paru -S grub-hook nohang-git auto-cpufreq ttf-ms-fonts mcmojave-circle-icon-theme  systemd-zram 
sudo systemctl condrestart systemd-zram  
clear

echo "Linux Mint Icons & Themes"
sleep 2
paru -S mint-themes mint-x-icons mint-backgrounds-vanessa
clear

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
sleep 2
sudo pacman -S avahi
sudo systemctl enable --now avahi-daemon.service

clear

echo "Windows Support"
sleep 3
sudo pacman -S --needed faudio openal lib32-openal libgdiplus wine-staging wine-gecko wine-mvulkan-icd-loader lib32-vulkan-icd-loader 
clear

echo "Steam Gaming Plattform installation"
sleep 3
paru -S --needed steam protontricks steam-tweaks libxcomposite lib32-libxcomposite libxinerama lib32-libgcrypt libgcrypt lib32-libxinerama ncurses lib32-ncurses opencl-icd-loader lib32-opencl-icd-loader libxslt lib32-libxslt libva lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs 
	
echo "hrtf = true" >> ~/.alsoftrc

echo "IPTV"
sleep 2
paru -S hypnotix

echo "Bluray wiedergabe"
sleep 2
paru -S aacskeys makemkv-libaacs libbluray

echo "SSD optimieren"
sleep 2
sudo systemctl enable fstrim.timer      


echo "swap optimieren"
echo "vm.swappiness=10" >> /etc/sysctl.d/100-manjaro.conf
echo ""
echo "System Bereinigung.."
echo 
sleep 3
paru -c
sudo paccache -r
sudo fstrim -av
clear
history -c
echo ""

echo "..Sytem erfolgreich eingerichtet.. Neustart in 10 sekunden!"
sleep 10
reboot
