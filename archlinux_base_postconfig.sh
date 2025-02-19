#!/usr/bin/env bash

# Last edit: 19.02.2025 

echo ""
echo "----------------------------------------------"
echo "    ..Archlinux base config after install..   "
echo "                                              "
echo "----------------------------------------------"
sleep 3
echo ""
echo "      !!!You should read this script first!!!
"
echo "          (The default AUR Helper is yay)
                       (Flatpak support) 
"
read -p "        ..Press any key to continue.."
clear

# Config the pacman.conf
    
# Colorful progress bar
grep -q "^Color" /etc/pacman.conf || sudo sed -i -e "s/^#Color$/Color/" /etc/pacman.conf
grep -q "ILoveCandy" /etc/pacman.conf || sudo sed -i -e "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sudo sed -i -e s"/\#VerbosePkgLists/VerbosePkgLists/"g /etc/pacman.conf
sudo sed -i -e s"/\#ParallelDownloads.*/ParallelDownloads = 2/"g /etc/pacman.conf
    

    # Installing chaotic-aur for compiled AUR packages.
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 
sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    
echo "" | sudo tee -a /etc/pacman.conf
echo "## Chaotic AUR Repo ##" | sudo tee -a /etc/pacman.conf
echo "[chaotic-aur]" | sudo tee -a /etc/pacman.conf 
echo "Include = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
echo ""
	
sudo pacman -Sy
clear


# Install system packages
sudo pacman -S --needed --noconfirm dbus-broker dkms kmod amd-ucode pacman-contrib bash-completion git ufw yay samba bind ethtool libelf nss
sudo pacman -S --needed --noconfirm rsync mtools dosfstools xfsdump jfsutils btrfs-progs f2fs-tools quota-tools gnome-disk-utility 
sudo pacman -S --needed --noconfirm lrzip zstd lz4 laszip unrar unzip fuse2 fuseiso

# Installing fastfetch
sudo pacman -S --noconfirm fastfetch

# Using zsh as default
sudo pacman -S --noconfirm zsh zsh-autosuggestions zsh-syntax-highlighting
touch ~/.zshrc
echo "exec zsh" >> ~/.bashrc
# sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# chsh -s $(which zsh)

echo "fastfetch" | sudo tee -a ~/.bashrc
echo "fastfetch" | sudo tee -a ~/.zshrc


# Complet x11 support
sudo pacman -S --needed --noconfirm xorg-server-xvfb xorg-xkill xorg-xinput xorg-xrandr libxv libxcomposite lib32-libxcomposite libxinerama lib32-libxrandr lib32-libxfixes
    

# Additional System tools and libraries
sudo pacman -S --needed --noconfirm hdparm sdparm hwdetect hwdata sof-firmware cpupower
sudo pacman -S --needed --noconfirm xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs
    
# Full python support
sudo pacman -S --needed --noconfirm python python-extras python-fuse python-reportlab python-glfw python-pyxdg python-pywayland python-cachy tcl tk
	
# System tweaks
sudo pacman -S --needed --noconfirm irqbalance nohang ananicy-cpp
 
 # Installing make-tools
sudo pacman -S --needed --noconfirm base-devel binutils fakeroot gcc clang llvm bc meson ninja automake autoconf ccache

# needed packages for various variables (sysctl variables etc)
sudo pacman -S --needed --noconfirm procps-ng iproute2 iotop nmon lm_sensors pciutils libpciaccess

# Fonts
sudo pacman -S --needed --noconfirm ttf-dejavu ttf-freefont ttf-liberation ttf-droid terminus-font 
sudo pacman -S --needed --noconfirm noto-fonts ttf-ubuntu-font-family ttf-roboto  


# Installing flatpak
sudo pacman -S --needed --noconfirm flatpak 
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Install base programs
sudo pacman -S --needed --noconfirm firefox firefox-i18n-de thunderbird-i18n-de thunderbird celluloid transmission-gtk mousepad
    
   
# Installing pipewire
sudo pacman -S --needed --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-zeroconf pipewire-v4l2 gst-plugin-pipewire wireplumber 
sudo pacman -S --needed --noconfirm pavucontrol rtkit alsa-firmware alsa-plugins alsa-lib lib32-alsa-lib
    

# Multimeda Codecs
sudo pacman -S --needed --noconfirm lame flac opus ffmpeg a52dec x264 x265 libvpx libvorbis libogg speex libdca libfdk-aac
sudo pacman -S --needed --noconfirm gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gstreamer-vaapi gst-libav
sudo pacman -S --needed --noconfirm twolame libmad libtheora libmpeg2 faac faad2 libavif libheif xvidcore

echo "hrtf = true" | sudo tee -a  ~/.alsoftrc
    

     
# Installs some needed packages with the yay aur-helper
yay -S --needed --noconfirm grub-hook update-grub faudio 
    
   
# Enable the services
sudo systemctl enable --now cpupower.service
sudo cpupower frequency-set -g performance
sudo systemctl enable --now dbus-broker.service
sudo systemctl --global enable dbus-broker.service
    
#sudo systemctl disable systemd-oomd
sudo systemctl enable irqbalance
sudo systemctl enable nohang
sudo systemctl enable ananicy-cpp

# Enable ufw firewall and set default config
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable

# Update the library cache
sudo ldconfig



## Improve NVME
# if $(find /sys/block/nvme[0-9]* | grep -q nvme); then
# echo -e "options nvme_core default_ps_max_latency_us=0" | sudo tee /etc/modprobe.d/nvme.conf
# fi

## Improve PCI latency
# sudo setpci -v -d *:* latency_timer=48 >/dev/null 2>&1


# Enable tmpfs ramdisk
sudo sed -i -e '/^\/\/tmpfs/d' /etc/fstab
echo -e "
tmpfs /var/tmp tmpfs nodiratime,nodev,nosuid,mode=1777 0 0
tmpfs /var/log tmpfs nodiratime,nodev,nosuid,mode=1777 0 0
tmpfs /var/run tmpfs nodiratime,nodev,nosuid,mode=1777 0 0
tmpfs /var/lock tmpfs nodiratime,nodev,nosuid,mode=1777 0 0
tmpfs /var/volatile tmpfs nodiratime,nodev,nosuid,mode=1777 0 0
tmpfs /var/spool tmpfs nodiratime,nodev,nosuid,mode=1777 0 0
tmpfs /dev/shm tmpfs nodiratime,nodev,nosuid,mode=1777 0 0
" | sudo tee -a /etc/fstab
clear


## Set some ulimits to unlimited
echo -e "
* soft nofile 524288
* hard nofile 524288
root soft nofile 524288
root hard nofile 524288
* soft as unlimited
* hard as unlimited
root soft as unlimited
root hard as unlimited
* soft memlock unlimited
* hard memlock unlimited
root soft memlock unlimited
root hard memlock unlimited
* soft core unlimited
* hard core unlimited
root soft core unlimited
root hard core unlimited
* soft nproc unlimited
* hard nproc unlimited
root soft nproc unlimited
root hard nproc unlimited
* soft sigpending unlimited
* hard sigpending unlimited
root soft sigpending unlimited
root hard sigpending unlimited
* soft stack unlimited
* hard stack unlimited
root soft stack unlimited
root hard stack unlimited
* soft data unlimited
* hard data unlimited
root soft data unlimited
root hard data unlimited
" | sudo tee /etc/security/limits.conf

## Set realtime to unlimited
echo -e "
@realtime - rtprio 99
@realtime - memlock unlimited
" | sudo tee -a /etc/security/limits.conf
clear


# Set base /etc/environment variables
echo -e "
CPU_LIMIT=0
CPU_GOVERNOR=performance
GPU_USE_SYNC_OBJECTS=1
PYTHONOPTIMIZE=1
ELEVATOR=deadline
TRANSPARENT_HUGEPAGES=always
MALLOC_CONF=background_thread:true
MALLOC_CHECK=0
MALLOC_TRACE=0
LD_DEBUG_OUTPUT=0
LP_PERF=no_mipmap,no_linear,no_mip_linear,no_tex,no_blend,no_depth,no_alphatest
LESSSECURE=1
PAGER=less
EDITOR=nano
VISUAL=nano
" | sudo tee -a /etc/environment



sudo systemctl enable fstrim.timer
sudo fstrim -av
clear

sudo pacman -Scc --noconfirm
yay -Yc --noconfirm
sudo paccache -rk 0
sudo pacman -Sy
    
# Clearing temporary files
sudo rm -rf /tmp/*
sudo rm -rf ~/.cache/*


sudo grub-mkconfig -o /boot/grub/grub.cfg
clear

echo ""
echo "----------------------------------------------"
echo "       Postconfig is now complete.            "
echo "                 Have fun !!                  "
echo "----------------------------------------------"
echo ""
read -p "..Press any key to reboot the System.."
clear
echo ""
echo "Reboot.."
sleep 2
sudo reboot
