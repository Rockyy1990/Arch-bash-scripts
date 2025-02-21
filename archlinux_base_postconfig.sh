#!/usr/bin/env bash

# Last edit: 21.02.2025 

echo ""
echo "----------------------------------------------"
echo "    ..Archlinux base config after install..   "
echo "                                              "
echo "----------------------------------------------"
sleep 2
echo ""
echo "      !!!You should read this script first!!!
"
echo "         (The default AUR Helper is yay)
            (rtorrent terminal tool for torrents)
                    (Flatpak support)
				  (Pipewire as default)
				  
	Optional:
	Archlinux wallpaper
	Linux Mint wallpaper
	Linux Mint Icons (mint-l-icons)
	
 rtorrent usage: rtorrent datei.torrents
                 rtorrent load datei.torrent

config: ~/.rtorrent.rc
"

echo ""
read -p "         ..Press any key to continue.."
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
sudo pacman -S --needed --noconfirm dbus-broker dkms kmod amd-ucode pacman-contrib mono nano-syntax-highlighting git ufw yay samba bind ethtool 
sudo pacman -S --needed --noconfirm rsync mtools dosfstools xfsdump jfsutils btrfs-progs f2fs-tools quota-tools gnome-disk-utility 
sudo pacman -S --needed --noconfirm lrzip zstd lz4 laszip unrar unzip fuse2 fuseiso rtorrent 

# Installing fastfetch
sudo pacman -S --noconfirm fastfetch

# Using zsh as default
sudo pacman -S --noconfirm zsh zsh-autosuggestions zsh-syntax-highlighting 
touch ~/.zshrc
echo "exec zsh" | tee -a ~/.bashrc
# sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# chsh -s $(which zsh)

echo "fastfetch" | tee -a ~/.bashrc
echo "fastfetch" | tee -a ~/.zshrc


# Complet x11 support
sudo pacman -S --needed --noconfirm xorg-server-xvfb xorg-xkill xorg-xinput xorg-xrandr libxv libxcomposite libxinerama 
sudo pacman -S --needed --noconfirm lib32-libxcomposite lib32-libxrandr lib32-libxfixes

# Additional System tools and libraries
sudo pacman -S --needed --noconfirm hdparm sdparm hwdetect hwdata sof-firmware cpupower openssl fwupd libelf nss micro
sudo pacman -S --needed --noconfirm xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs
    
# Full python support
sudo pacman -S --needed --noconfirm python python-extras python-fuse python-reportlab python-glfw python-pyxdg python-pywayland python-cachy tcl tk
	
# System tweaks
sudo pacman -S --needed --noconfirm irqbalance nohang ananicy-cpp
 
 # Installing make-tools
sudo pacman -S --needed --noconfirm base-devel binutils fakeroot clang llvm bc meson ninja cmake automake autoconf ccache

# needed packages for various variables (sysctl variables etc)
sudo pacman -S --needed --noconfirm procps-ng iproute2 nmon lm_sensors pciutils libpciaccess


#----------------------------------------------------------------------------------------------------------------------

# Installing amd-gpu-driver
sudo pacman -S --noconfirm mesa lib32-mesa mesa-utils libva libdrm lib32-libdrm 
sudo pacman -S --needed --noconfirm xf86-video-amdgpu mesa lib32-mesa glu lib32-glu libvdpau-va-gl 
sudo pacman -S --needed --noconfirm opencl-icd-loader ocl-icd lib32-ocl-icd rocm-opencl-runtime
    
# Install Vulkan drivers
sudo pacman -S --needed --noconfirm vulkan-radeon lib32-vulkan-radeon vulkan-swrast vulkan-icd-loader lib32-vulkan-icd-loader 
sudo pacman -S --needed --noconfirm vulkan-validation-layers vulkan-mesa-layers lib32-vulkan-mesa-layers vulkan-headers

echo "
AMD_VULKAN_ICD=RADV
RADV_PERFTEST=aco,sam,nggc
RADV_DEBUG=novrsflatshading
" | sudo tee -a /etc/environment
    
# Disable GPU polling
echo -e "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf


# Iinstall intel gpu driver
# sudo pacman -S --needed xf86-video-intel intel-media-driver mesa mesa-utils vulkan-intel vulkan-swrast
# sudo pacman -S --needed intel-gmmlib intel-compute-runtime libva-intel-driver libva-utils
# sudo pacman -S --needed vulkan-validation-layers vulkan-mesa-layers vulkan-icd-loader lib32-vulkan-icd-loader


# Install nvidia driver
# sudo pacman -S --needed --noconfirm nvidia nvidia-settings nvidia-utils lib32-nvidia-utils opencl-nvidia lib32-opencl-nvidia
# sudo pacman -S --needed --noconfirm libxnvctrl libvdpau lib32-libvdpau vulkan-icd-loader lib32-vulkan-icd-loader
#-------------------------------------------------------------------------------------------------------------------------


# Fonts
sudo pacman -S --needed --noconfirm ttf-dejavu ttf-freefont ttf-liberation ttf-droid terminus-font 
sudo pacman -S --needed --noconfirm noto-fonts ttf-ubuntu-font-family ttf-roboto  


# Installing flatpak
sudo pacman -S --needed --noconfirm flatpak 
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Install base programs
sudo pacman -S --needed --noconfirm firefox thunderbird celluloid libreoffice-fresh xed yt-dlp gthumb 
sudo pacman -S --needed --noconfirm firefox-i18n-de thunderbird-i18n-de libreoffice-fresh-de
clear

echo "Do you wont to install archlinux or mint wallpapers? If not needed press n"
sudo pacman -S --needed archlinux-wallpaper
yay -S mint-backgrounds-tina mint-backgrounds-victoria
clear
echo "Do you wont to install mint icons? If not needed press n"
sudo pacman -S --needed mint-l-icons
clear
    
   
# Installing pipewire
sudo pacman -S --needed --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-zeroconf pipewire-v4l2 wireplumber 
sudo pacman -S --needed --noconfirm pavucontrol gst-plugin-pipewire rtkit alsa-firmware alsa-plugins alsa-lib lib32-alsa-lib
    

# Multimeda Codecs
sudo pacman -S --needed --noconfirm lame flac opus ffmpeg a52dec x264 x265 libvpx libvorbis libogg speex libfdk-aac
sudo pacman -S --needed --noconfirm gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gstreamer-vaapi gst-libav
sudo pacman -S --needed --noconfirm twolame libmad libtheora libmpeg2 faac faad2 libavif libheif xvidcore openal lib32-openal


# Other values for ~/.alsoftrc
# default-sample-rate = 48000
# default-channels = 2
# latency = 24ms

echo "
hrtf = true
" | tee -a  ~/.alsoftrc
    

     
# Installs some needed packages with yay 
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
# This should increase performance in some situations
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



# Enable fstrim for ssd/nvme
sudo systemctl enable fstrim.timer
sudo fstrim -av
clear

# Package cleaning
sudo pacman -Scc --noconfirm
yay -Yc --noconfirm
sudo paccache -rk 0
sudo pacman -Sy
    
# Clearing temporary files
sudo rm -rf /tmp/*
sudo rm -rf ~/.cache/*


# Update the dynamic library cache
sudo ldconfig

# Update grub bootloader
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
