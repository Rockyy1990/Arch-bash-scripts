#!/bin/bash

## Last edit: 09.08.2024

#
# Archlinux Postinstall script
#

echo ""
echo "Archlinux Postinstall Script"
echo " Can use for Desktop like gnome, plasma or cinnamon"
echo ""
read -p "Read this script before execute !! Some lines need to edit if you wont to use it"
clear


# First steps...

echo ""
echo "Chaotic AUR Repo setting up.."
sleep 2
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 
sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

echo "" | sudo tee -a /etc/pacman.conf
echo "## Chaotic AUR Repo ##" | sudo tee -a /etc/pacman.conf
echo "[chaotic-aur]" | sudo tee -a /etc/pacman.conf 
echo "Include = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
clear

echo "Ranking Mirrors.."
sleep 2
sudo pacman -S --needed --noconfirm reflector rsync curl
sudo reflector --verbose --country 'Germany' -l 14 --sort rate --save /etc/pacman.d/mirrorlist


read -p "Press any key to customize the pacman.conf"
sudo nano -w /etc/pacman.conf
sudo pacman -Sy


read -p "Press any key to customize fstab"
sudo nano -w /etc/fstab
clear
echo ""

# packages from chaotic aur
sudo pacman -S --needed --noconfirm bauh update-grub mintstick
sudo pacman -S --needed --noconfirm timeshift timeshift-autosnap 

# Make Tools
sudo pacman -S --needed --noconfirm base-devel gcc clang llvm bc automake autoconf git ccache


# Macos Themes
# sudo pacman -S --needed --noconfirm mcmojave-icon-theme-git
# sudo pacmam -S --needed --noconfirm whitesur-cursor-theme-git

# Linux Mint Themes
# sudo pacman -S mint-themes mint-y-icons mint-x-icons mint-l-icons mint-l-theme 


# Cinnamon Desktop needs...
# sudo pacman -S nemo-image-converter nemo-share cinnamon-translations



# Other Kernel...

# Xanmod kernel. Compiled with clang.
# sudo pacman -S --needed --noconfirm linux-xanmod-clang-v3 linux-xanmod-clang-v3-headers

# Latest Mainline Kernel
# sudo pacman -S --needed --noconfirm linux-mainline-v3 linux-mainline-v3-headers


# Compiling Xanmod Kernel with clang
# cd -
# git clone https://aur.archlinux.org/linux-xanmod.git  
# cd linux-xanmod                                       

# microarchitecture=x86_64 for generell x86 architecture or znver3 , znver4 vor amd..
# export _microarchitecture=native use_numa=n use_tracers=n _compiler=clang

# makepkg -sric 



# needed
sudo pacman -S --needed --noconfirm pacman-contrib lrzip unrar unzip unace p7zip dbus-broker
sudo pacman -S --needed --noconfirm ttf-dejavu ttf-opensans freetype2 ttf-droid ttf-liberation ubuntu-font-family
sudo pacman -S --needed --noconfirm xorg-xkill xorg-xinput xorg-xrandr libwnck3 libxcomposite lib32-libxcomposite libxinerama lib32-libxrandr lib32-libxfixes
sudo pacman -S --needed --noconfirm hdparm sdparm hwdetect sof-firmware fwupd cpupower fastfetch bash-completion

# Wayland
sudo pacman -S --needed --noconfirm wayland wayland-protocols xorg-xwayland wayland-utils

sudo systemctl enable --now cpupower.service
sudo cpupower frequency-set -g performance
sudo systemctl enable --now dbus-broker.service

echo "fastfetch" | sudo tee -a ~/.bashrc


# programs
sudo pacman -S --needed --noconfirm firefox firefox-i18n-de thunderbird thunderbird-i18n-de vlc lollypop discord transmission-gtk file-roller yt-dlp 
sudo pacman -S --needed --noconfirm base-devel fakeroot git gufw gsmartcontrol gnome-disk-utility xfsdump f2fs-tools mtools gvfs
sudo pacman -S --needed --noconfirm zstd nss fuse2 fuseiso samba


# If you use Gnome Desktop. Replace Nautilus Filemanager with Nemo File Manager.
# sudo pacman -R nautilus && sudo pacman -S nemo nemo-image-converter nemo-share cinnamon-translations 



# Install printing support
sudo pacman -S --needed --noconfirm cups cups-filters cups-pdf gutenprint ghostscript avahi system-config-printer
#sudo pacman -S --needed --noconfirm foomatic-db foomatic-db-engine foomatic-db-gutenprint-ppds foomatic-db-nonfree foomatic-db-nonfree-ppds foomatic-db-ppds
sudo systemctl enable --now cups.service

# Install Flatpak
sudo pacman -S --needed --noconfirm flatpak xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak update

sudo ufw enable




# Configure Audio...

# Install Pipewire and related packages
sudo pacman -S --needed --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-zeroconf pipewire-v4l2 gst-plugin-pipewire wireplumber pavucontrol alsa-firmware


# Enable and start the Pipewire services
sudo systemctl enable --now wireplumber

# Bluetooth support
# sudo pacman -S --needed --noconfirm bluez bluez-utils bluez-plugins bluez-hid2hci bluez-cups bluez-libs bluez-tools
# sudo systemctl enable --now bluetooth.service

# Blueman (GTK+ Bluetooth Manager)
# sudo pacman -S --needed --noconfirm blueman

# EasyEffects 
# sudo pacman -S easyeffects


# Install Codecs
sudo pacman -S --needed --noconfirm lame flac opus ffmpeg a52dec x264 x265 
sudo pacman -S --needed --noconfirm gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gstreamer-vaapi gst-libav
sudo pacman -S --needed --noconfirm twolame libmad libxv libvorbis libogg libtheora libmpeg2 faac faad2


# Reload the systemd manager configuration
sudo systemctl --system daemon-reload




# Configure Video Drivers...

# Nvidia Driver
# sudo pacman -S --needed --noconfirm nvidia nvidia-utils opencl-nvidia libxnvctrl libvdpau nvidia-settings 

# AMD Driver
sudo pacman -S --needed --noconfirm xf86-video-amdgpu mesa lib32-mesa rocm-opencl-runtime ocl-icd lib32-ocl-icd lib32-mesa-vdpau mesa-vdpau libva-mesa-driver lib32-mesa-vdpau opencl-icd-loader

# Install Vulkan drivers
sudo pacman -S --needed --noconfirm vulkan-radeon lib32-vulkan-radeon vulkan-mesa-layers vulkan-icd-loader lib32-vulkan-icd-loader





# Configure Gaming


# Chaotic Packages
sudo pacman -S --needed --noconfirm bottles protonup-qt
# sudo pacman -S --needed --noconfirm playonlinux


# Wine (Windows api support)
sudo pacman -S --needed --noconfirm wine wine-mono wine-gecko winetricks libgdiplus vkd3d lib32-vkd3d  openal lib32-openal cabextract zenity


# Install Steam and Proton
sudo pacman -S --needed --noconfirm steam steam-native-runtime protontricks-git gamemode lib32-gamemode lib32-fontconfig giflib lib32-giflib libpng lib32-libpng libldap lib32-libldap gnutls lib32-gnutls

sudo pacman -S --needed --noconfirm mpg123 lib32-mpg123 v4l-utils lib32-v4l-utils lib32-libpulse lib32-alsa-plugins alsa-lib lib32-alsa-lib
sudo pacman -S --needed --noconfirm libgpg-error lib32-libgpg-error  libjpeg-turbo lib32-libjpeg-turbo sqlite lib32-sqlite 
sudo pacman -S --needed --noconfirm lib32-libgcrypt libgcrypt lib32-libxinerama ncurses lib32-ncurses lib32-opencl-icd-loader
sudo pacman -S --needed --noconfirm libxslt lib32-libxslt lib32-libva gtk3 lib32-gtk3 lib32-gst-plugins-base-libs  

sudo pacman -S --needed --noconfirm lib32-sdl2 lib32-alsa-lib lib32-giflib lib32-gnutls lib32-libglvnd lib32-libldap 
sudo pacman -S --needed --noconfirm lib32-libxinerama lib32-libxcursor lib32-gnutls lib32-libva lib32-libvdpau libvdpau


# Mangohud  (A Vulkan and OpenGL overlay for monitoring FPS, temperatures, CPU/GPU load and more.)
# sudo pacman -S --needed --noconfirm mangohud lib32-mangohud


# Enable Steam Play (Proton) for all titles
echo "Enable Steam Play for all titles"
echo "Please restart Steam after running this script"
sed -i 's/\"enabled\".false/\"enabled\".true/' ~/.steam/root/config/config.vdf

# Increase the processor count
export PROTON_USE_WINED3D=1
export PROTON_NO_ESYNC=1




# Final settings...

# Install zsh shell
# sudo pacman -S --needed --noconfirm zsh zsh-completions zsh-syntax-highlighting oh-my-zsh-git

# Set up zsh as default shell
# chsh -s /usr/bin/zsh


# Regenerate the initramfs. Uncommend needed.
# sudo mkinitcpio -p linux
# sudo mkinitcpio -p linux-lts
# sudo mkinitcpio -p linux-zen
# sudo mkinitcpio -p linux-mainline-v3
# sudo mkinitcpio -p linux-xanmod-clang-v3


# System cleaning
sudo pacman -Scc --noconfirm

sudo systemctl enable fstrim.timer
sudo fstrim -av 
clear

sudo nano -w /etc/default/grub

read -p "Press any key to costumize grub config. For enabling os-prober etc.."
sudo pacman -S --needed --noconfirm os-prober
sudo os-prober

sudo grub-mkconfig -o /boot/grub/grub.cfg


# Add DNS servers to /etc/resolv.conf

echo "Cloudflare DNS" | sudo tee -a /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
echo "nameserver 1.0.0.1" | sudo tee -a /etc/resolv.conf

# Disable IPv6
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
clear



# Bash config (bashrc etc)

echo "export HISTSIZE=0" | sudo tee -a ~/.bashrc

# Set the default editor
export EDITOR=nano
export VISUAL=nano


# Alias config
echo "alias update='sudo pacman -Syu --noconfirm' " | sudo tee -a ~/.bashrc
echo "alias add='sudo pacman -S --noconfirm' " | sudo tee -a ~/.bashrc
echo "alias remove='sudo pacman -R --noconfirm' " | sudo tee -a ~/.bashrc
echo "alias gup='sudo grub-mkconfig -o /boot/grub/grub.cfg' " | sudo tee -a ~/.bashrc
echo "alias trim='sudo fstrim -av' " | sudo tee -a ~/.bashrc
echo "alias pclean='sudo pacman -Scc --noconfirm' " | sudo tee -a ~/.bashrc
echo "alias kver='uname -r' " | sudo tee -a ~/.bashrc
echo "alias disks='sudo gnome-disk-utility' " | sudo tee -a ~/.bashrc



clear
echo ""
echo "Postinstall is complete"
read -p "Please save your work. If you are finish press a key. The System will be reboot."
sudo reboot


