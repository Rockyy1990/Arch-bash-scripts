#!/usr/bin/env bash

# Last Edit: 18.02.2025


echo ""
echo "----------------------------------------------"
echo "    ..Manjaro Plasma config after install..   "
echo "              Minimal Install                 "
echo "----------------------------------------------"
sleep 2
echo ""

read -p "   Read this script before execute!!
               Press any key to continue..
"

echo ""
echo "If screen fliggering under wayland: Display Settings -> disable adaptive sync"
sleep 3
clear

echo ""
echo " Installing chaotic-aur for compiled AUR packages."
echo ""
sleep 2
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 
sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    
echo "" | sudo tee -a /etc/pacman.conf
echo "## Chaotic AUR Repo ##" | sudo tee -a /etc/pacman.conf
echo "[chaotic-aur]" | sudo tee -a /etc/pacman.conf 
echo "Include = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
echo ""
clear

echo ""
sudo pamac remove --no-confirm vlc
clear

echo ""
echo "Package database update and system upgrade."
sleep 2
sudo pamac update
sudo pamac upgrade -a
clear

echo ""
echo "Needed base Packages"
sleep 2
sudo pamac install --no-confirm manjaro-tools git fwupd gsmartcontrol fuseiso fuse2 yay plasma-firewall
sudo pamac install --no-confirm gnome-disk-utility plasma-disks mtools f2fs-tools xfsdump irqbalance ananicy-cpp
sudo pamac install --no-confirm base-devel binutils fakeroot gcc clang llvm bc automake autoconf ccache
sudo systemctl enable irqbalance
sudo systemctl enable ananicy-cpp
clear


echo ""
echo "Install complete Wayland Support"
sleep 2
sudo pamac install --no-confirm wayland-protocols plasma-wayland-protocols egl-wayland waylandpp xwaylandvideobridge
clear


echo ""
echo "Install Complete Python support for gui scripts"
sleep 2
sudo pamac install --no-confirm python python-extras python-reportlab tcl tk
clear


echo ""
echo "Install Virt-Manager (Qemu)"
sleep 2
sudo pamac install --no-confirm virt-manager libvirt-glib ovmf vte3 vde2 bridge-utils dnsmasq spice-gtk 
sudo pamac install --no-confirm libguestfs qemu-guest-agent openbsd-netcat
sudo systemctl enable libvirtd.service
sudo usermod -a -G libvirt $(whoami)
sudo virsh net-start default
sudo virsh net-autostart default
clear



echo ""
echo "Install various programs.."
sleep 2
sudo pamac install --no-confirm libreoffice-fresh thunderbird discord ventoy ktorrent
clear


echo ""
echo "Multimedia"
sleep 2
sudo pamac install --no-confirm lollypop celluloid yt-dlp flac lame gstreamer-vaapi openal
sudo pamac install soundconverter
echo "hrtf = true" | sudo tee -a  ~/.alsoftrc
clear


echo ""
echo  "Steam Gaming Platform. Can be skipped if not needed"
sleep 2
sudo pamac install steam steam-native-runtime python-steam libgdiplus protontricks protonup-qt
yay -S --needed faudio
clear


echo ""
echo "Install Wine (Windows Support). Can be skipt if not needed.."
sleep 2
sudo pamac install wine wine-mono wine-gecko winetricks
clear


echo ""
echo "Install Mint Icons and other stuff (Can be skipped if not needed)"
sleep 2
sudo pamac install mint-l-icons
sudo pamac install mint-l-theme
sudo pamac install mintstick
yay -S mint-backgrounds-tina mint-backgrounds-victoria
clear


echo ""
echo "Install needed language packages.."
sleep 2
sudo pamac install --no-confirm libreoffice-fresh-de thunderbird-i18n-de firefox-i18n-de
clear



# Environment variables
echo -e "
CPU_LIMIT=0
CPU_GOVERNOR=performance
GPU_USE_SYNC_OBJECTS=1
SHARED_MEMORY=1
ELEVATOR=deadline
TRANSPARENT_HUGEPAGES=always
MALLOC_CONF=background_thread:true
MALLOC_CHECK=0
MALLOC_TRACE=0
LD_DEBUG_OUTPUT=0
MESA_DEBUG=0
mesa_glthread=true
AMD_VULKAN_ICD=RADV
RADV_PERFTEST=aco,sam,nggc
RADV_DEBUG=novrsflatshading
GAMEMODE=1
LIBGL_DEBUG=0
LIBGL_NO_DRAWARRAYS=1
LIBGL_THROTTLE_REFRESH=1
LIBGL_DRI3_DISABLE=1
__GL_MaxFramesAllowed=1
__GL_VRR_ALLOWED=0
WINE_FSR_OVERRIDE=1
WINE_FULLSCREEN_FSR=1
WINE_VK_USE_FSR=1
PROTON_FORCE_LARGE_ADDRESS_AWARE=1
PROTON_USE_FSYNC=1
DXVK_ASYNC=1
LP_PERF=no_mipmap,no_linear,no_mip_linear,no_tex,no_blend,no_depth,no_alphatest
LIBC_FORCE_NOCHECK=1
EDITOR=nano
VISUAL=nano
" | sudo tee -a /etc/environment


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



## Improve PCI latency
sudo setpci -v -d *:* latency_timer=48 >/dev/null 2>&1

# Reload libraries
sudo ldconfig

# System cleaning..
sudo pamac clean
sudo rm -rf /tmp/*
sudo rm -rf ~/.cache/*

# Enable trim for ssd/nvme
sudo systemctl enable fstrim.timer
sudo fstrim -av


clear
echo ""
read -p "
-------------------------------------
       Postinstall complete. 
 Press any key to reboot the system.
-------------------------------------
"
sudo reboot
