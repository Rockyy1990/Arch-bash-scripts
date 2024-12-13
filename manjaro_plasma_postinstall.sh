#!/usr/bin/env bash

# Last Edit: 13.12.2024


# Function to check for root privileges

check_root() {

    if [ "$EUID" -ne 0 ]; then
          echo "This script requires root privileges. Please enter your password."
          sudo "$0" "$@"
        exit

    fi

}

# Call the function to check for root privileges
check_root "$@"

# Your script logic goes here
echo "You are running this script as root."
clear



echo "              !!Read this script before execute !!"
read -p " Manjaro Postinstall for Plasma Desktop. Press any key to continue.."
clear

sudo pacman -Sy

# Remove not needed packages
# sudo pacman -R elisa
clear

echo " Needed Base Packages"
sleep 2
sudo pacman -S --needed --noconfirm manjaro-tools git base-devel fakeroot fwupd gsmartcontrol gnome-disk-utility mtools f2fs-tools xfsdump fuse2 fuseiso samba bind yay
clear

echo "Install Complete Python support for gui scripts"
sleep 2 
sudo pacman -S --needed --noconfirm python python-extras python-autocommand python-reportlab tcl tk
clear

echo " Install various programs.."
sleep 2
sudo pacman -S --needed --noconfirm libreoffice-fresh libreoffice-fresh-de thunderbird discord ventoy ktorrent adriconf 
clear

echo " Multimedia"
sleep 2
sudo pacman -S --needed lollypop yt-dlp flac lame
yay -S --needed ffaudioconverter 
clear

echo  " Steam Gaming Platform"
sleep 2
sudo pacman -S --needed steam steam-native-runtime protontricks protonup-qt
yay -S --needed faudio
clear


 

# Environment variables
    echo -e "
    CPU_LIMIT=0
    CPU_GOVERNOR=performance
    GPU_USE_SYNC_OBJECTS=1
    SHARED_MEMORY=1
    ELEVATOR=deadline
    TRANSPARENT_HUGEPAGES=always
    NET_CORE_WMEM_MAX=1048576
    NET_CORE_RMEM_MAX=1048576
    NET_IPV4_TCP_WMEM=1048576
    NET_IPV4_TCP_RMEM=1048576
    MALLOC_CONF=background_thread:true
    MALLOC_CHECK=0
    MALLOC_TRACE=0
    LD_DEBUG_OUTPUT=0
    MESA_DEBUG=0
    LIBGL_DEBUG=0
    LIBGL_NO_DRAWARRAYS=0
    LIBGL_THROTTLE_REFRESH=1
    LIBC_FORCE_NOCHECK=1
    LIBGL_DRI3_DISABLE=1
    VK_LOG_LEVEL=error
    VK_LOG_FILE=/dev/null
    HISTCONTROL=ignoreboth:eraseboth
    HISTSIZE=5
    LESSHISTFILE=-
    LESSHISTSIZE=0
    LESSSECURE=1
    PAGER=less
    EDITOR=nano
    VISUAL=nano
	" | sudo tee -a /etc/environment
	
	echo -e "Enable write cache"
    echo -e "write back" | sudo tee /sys/block/*/queue/write_cache
    sudo tune2fs -o journal_data_writeback $(df / | grep / | awk '{print $1}')
    sudo tune2fs -O ^has_journal $(df / | grep / | awk '{print $1}')
    sudo tune2fs -o journal_data_writeback $(df /home | grep /home | awk '{print $1}')
    sudo tune2fs -O ^has_journal $(df /home | grep /home | awk '{print $1}')
    echo -e "Enable fast commit"
    sudo tune2fs -O fast_commit $(df / | grep / | awk '{print $1}')
    sudo tune2fs -O fast_commit $(df /home | grep /home | awk '{print $1}')

    
    ## Improve NVME
    if $(find /sys/block/nvme[0-9]* | grep -q nvme); then
    echo -e "options nvme_core default_ps_max_latency_us=0" | sudo tee /etc/modprobe.d/nvme.conf
    fi

    ## Improve PCI latency
    sudo setpci -v -d *:* latency_timer=48 >/dev/null 2>&1
	
	echo ""
	echo -e "Settings for AMD GPU"
	echo ""
	echo -e "AMD_VULKAN_ICD=RADV" | sudo tee -a /etc/environment &&
    echo -e "RADV_PERFTEST=aco,sam,nggc" | sudo tee -a /etc/environment &&
    echo -e "RADV_DEBUG=novrsflatshading" | sudo tee -a /etc/environment &&
    echo -e "WINEPREFIX=~/.wine" | sudo tee -a /etc/environment &&
    echo -e "MOZ_ENABLE_WAYLAND=0" | sudo tee -a /etc/environment &&
    echo -e "WINE_LARGE_ADDRESS_AWARE=1" | sudo tee -a /etc/environment &&
    echo -e "WINEFSYNC_SPINCOUNT=24" | sudo tee -a /etc/environment &&
    echo -e "WINEFSYNC=1" | sudo tee -a /etc/environment &&
    echo -e "WINEFSYNC_FUTEX2=0" | sudo tee -a /etc/environment &&
    echo -e "STAGING_WRITECOPY=0" | sudo tee -a /etc/environment &&
    echo -e "STAGING_SHARED_MEMORY=0" | sudo tee -a /etc/environment &&
    echo -e "STAGING_RT_PRIORITY_SERVER=4" | sudo tee -a /etc/environment &&
    echo -e "STAGING_RT_PRIORITY_BASE=2" | sudo tee -a /etc/environment &&
    echo -e "STAGING_AUDIO_PERIOD=13333" | sudo tee -a /etc/environment &&
    echo -e "WINE_FSR_OVERRIDE=1" | sudo tee -a /etc/environment &&
    echo -e "WINE_FULLSCREEN_FSR=1" | sudo tee -a /etc/environment &&
    echo -e "WINE_VK_USE_FSR=1" | sudo tee -a /etc/environment &&
    echo -e "PROTON_LOG=0" | sudo tee -a /etc/environment &&
    echo -e "PROTON_USE_WINED3D=0" | sudo tee -a /etc/environment &&
    echo -e "PROTON_FORCE_LARGE_ADDRESS_AWARE=1" | sudo tee -a /etc/environment &&
    echo -e "PROTON_NO_ESYNC=1" | sudo tee -a /etc/environment &&
    echo -e "ENABLE_VKBASALT=0" | sudo tee -a /etc/environment &&
    echo -e "DXVK_ASYNC=1" | sudo tee -a /etc/environment &&
    echo -e "DXVK_HUD=compile" | sudo tee -a /etc/environment &&
    echo -e "MESA_BACK_BUFFER=ximage" | sudo tee -a /etc/environment &&
    echo -e "MESA_NO_DITHER=1" | sudo tee -a /etc/environment &&
    echo -e "MESA_NO_ERROR=1" | sudo tee -a /etc/environment && 
    echo -e "MESA_SHADER_CACHE_DISABLE=false" | sudo tee -a /etc/environment &&
    echo -e "mesa_glthread=true" | sudo tee -a /etc/environment &&
    echo -e "ANV_ENABLE_PIPELINE_CACHE=1" | sudo tee -a /etc/environment &&
    echo -e "__GLX_VENDOR_LIBRARY_NAME=mesa" | sudo tee -a /etc/environment &&
    echo -e "__GLVND_DISALLOW_PATCHING=1" | sudo tee -a /etc/environment &&
    echo -e "__GL_THREADED_OPTIMIZATIONS=1" | sudo tee -a /etc/environment &&
    echo -e "__GL_SYNC_TO_VBLANK=1" | sudo tee -a /etc/environment &&
    echo -e "__GL_MaxFramesAllowed=1" | sudo tee -a /etc/environment &&
    echo -e "__GL_SHADER_DISK_CACHE=0" | sudo tee -a /etc/environment &&
    echo -e "__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1" | sudo tee -a /etc/environment &&
    echo -e "__GL_YIELD=NOTHING" | sudo tee -a /etc/environment &&
    echo -e "__GL_VRR_ALLOWED=0" | sudo tee -a /etc/environment &&
    echo -e "VKD3D_CONFIG=upload_hvv" | sudo tee -a /etc/environment &&
    echo -e "LP_PERF=no_mipmap,no_linear,no_mip_linear,no_tex,no_blend,no_depth,no_alphatest" | sudo tee -a /etc/environment &&
    echo -e "STEAM_FRAME_FORCE_CLOSE=0" | sudo tee -a /etc/environment &&
    echo -e "STEAM_RUNTIME_HEAVY=1" | sudo tee -a /etc/environment &&
    echo -e "GAMEMODE=1" | sudo tee -a /etc/environment &&
    echo -e "vblank_mode=1" | sudo tee -a /etc/environment
    
    echo -e "Disable GPU polling"
    echo -e "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf
	
	# Enable trim for ssd/nvme
	sudo systemctl enable fstrim.timer
	sudo fstrim -av
	
	# Reload libraries
	sudo ldconfig
	
	# Create backup with timeshift
	sudo timeshift --create
	
	clear
	read -p "Postinstall complete. Press any key to reboot the system."
	sudo reboot
	
