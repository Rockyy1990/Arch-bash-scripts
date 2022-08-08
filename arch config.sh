#!/usr/bin/env bash

echo "#############  Einrichtung nach dem System install ##########################"
echo "Archlinux update, config and install various programs"
echo "#############################################################################"
sleep 4
set +o history
sudo pacman-key --init
sudo pacman-key --populate archlinux
sudo pacman -Sy
sudo pacman -Syyu
sleep 3
clear
sleep 2

echo "Multimedia Support installieren"
sleep 3
sudo pacman -S gstreamer-vaapi gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-plugins-espeak gst-plugins-av lame x264 a52dec jasper flac pipewire-zeroconf pipewire-pulse gst-plugin-pipewire pavucontrol 
clear

echo "Systemtools und yay für AUR.."
sleep 3
sudo pacman -S --needed xdg-user-dirs wget git hdparm nano-syntax-highlighting gufw gnome-disk-utility bash-completion shellharden f2fs-tools ntfs-3g xfsdump jfsutils mtools gsmartcontrol neofetch dkms --noconfirm
git clone https://aur.archlinux.org/yay.git


cd yay
echo "yay Paketmanager kompilieren..."
sleep 3
makepkg -si 
cd
sudo bash -c "echo neofetch >> ~/.bashrc"

clear
echo ""
echo "Timeshift ArchLinux Sicherung mit BTRFS"
echo ""
yay -S btrfsmaintenance-git grub-btrfs os-prober-btrfs mkinitcpio-btrfs timeshift timeshift-autosnap autoupgrade 


echo "Installation von Programmen"
sudo pacman -S firefox firefox-i18n-de vlc libreoffice-fresh libreoffice-fresh-de strawberry soundconverter transmission-gtk discord audacity 
echo ""
echo "Falls Gnome Desktop installiert ist, werden rhythmbox und epiphany entfernt."
echo ""
sudo pacman -Rs rhythmbox epiphany

echo "weitere Schriftarten"
sudo pacman -S ttf-liberation ttf-linux-libertine ttf-ubuntu-font-family --noconfirm

echo "Flatpak installation .."
sudo pacman -S flatpak --noconfirm

clear
echo "Drucker Support einrichten"
sleep 3
sudo pacman -S cups cups-filters cups-pdf gutenprint ghostscript foomatic-db-gutenprint-ppds foomatic-db-nonfree-ppds foomatic-db-ppds foomatic-db-engine system-config-printer
sudo systemctl enable cups.service

clear
echo "Nvidia Graphics Driver"
sleep 2
sudo pacman -S --needed  nvidia-dkms nvidia-utils opencl-nvidia nvidia-settings lib32-nvidia-utils lib32-opencl-nvidia

clear
echo "Gaming support"
sleep 3
sudo pacman -S --needed steam wine-staging libgdiplus faudio lib32-faudio vkd3d lib32-vkd3d
echo "hrtf = true" >> ~/.alsoftrc
yay -S gamemode lib32-gamemode bottles protonup-qt

clear
echo "Installation von AUR Paketen"
sleep 2
yay -S grub-hook update-grub nohang-git systemd-zram ttf-ms-fonts yt-dlp ventoy-bin
sudo systemctl enable systemd-zram
yay -S mint-y-icons mint-themes mint-backgrounds

echo "SSD optimieren"
sleep 2
sudo fstrim -av 

echo "Grub Update und Multiboot konfiguration"
sleep 3
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

clear
echo "System aufräumen.."
sleep 2
sudo yay -c
sudo paccache -r
history -c
clear

echo "Installation ist erfolgreich abgeschlossen"
sleep 8

sudo reboot


