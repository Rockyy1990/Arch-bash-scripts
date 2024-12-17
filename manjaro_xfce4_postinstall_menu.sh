#!/usr/bin/env bash

# Define color codes
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

# Function to display the menu
display_menu() {
    clear
    echo -e "${ORANGE}          Manjaro XFCE Postinstall${NC}"
    echo -e "${ORANGE}1) Install needed packages${NC}"
    echo -e "${ORANGE}2) Install Complete Python support for GUI scripts${NC}"
    echo -e "${ORANGE}3) Install graphics driver and libraries${NC}"
    echo -e "${ORANGE}4) Install various programs${NC}"
    echo -e "${ORANGE}5) Install printer support${NC}"
    echo -e "${ORANGE}6) Install Steam Gaming Platform${NC}"
    echo -e "${ORANGE}7) Set environment variables${NC}"
    echo -e "${ORANGE}8) Enable write cache and fast commit${NC}"
    echo -e "${ORANGE}9) Improve NVME and PCI latency${NC}"
    echo -e "${ORANGE}10) Disable GPU polling${NC}"
    echo -e "${ORANGE}11) Enable trim for SSD/NVMe${NC}"
    echo -e "${ORANGE}12) Create backup with Timeshift${NC}"
    echo -e "${ORANGE}0) Exit${NC}"
    echo -n "Choose an option: "
}

# Function to install packages
install_packages() {
    echo -e "${ORANGE}Installing needed packages...${NC}"
    sudo pamac install --no-confirm base-devel fakeroot git yay xfsdump f2fs-tools mtools fwupd lame flac
    sudo pamac install --no-confirm gnome-disk-utility gsmartcontrol ventoy pavucontrol gnome-firmware
    echo -e "${ORANGE}Installation complete! Press any key to continue...${NC}"
    read -n 1
}

# Function to install Python support
install_python_support() {
    echo -e "${ORANGE}Installing Complete Python support for GUI scripts...${NC}"
    sudo pamac install --no-confirm python python-extras python-autocommand python-reportlab tcl tk
    echo -e "${ORANGE}Installation complete! Press any key to continue...${NC}"
    read -n 1
}

# Function to install graphics drivers
install_graphics_drivers() {
    echo -e "${ORANGE}Installing graphics driver and libraries...${NC}"
    sudo pamac install --no-confirm xf86-video-fbdev xf86-video-amdgpu vulkan-radeon vulkan-swrast vulkan-mesa-layers
    echo -e "${ORANGE}Installation complete! Press any key to continue...${NC}"
    read -n 1
}

# Function to install various programs
install_various_programs() {
    echo -e "${ORANGE}Installing various programs...${NC}"
    sudo pamac install vlc thunderbird thunderbird-i18n-de transmission-gtk libreoffice-fresh libreoffice-fresh-de strawberry yt-dlp
    echo -e "${ORANGE}Installation complete! Press any key to continue...${NC}"
    read -n 1
}

# Function to install printer support
install_printer_support() {
    echo -e "${ORANGE}Installing printer support...${NC}"
    sudo pamac install --no-confirm cups cups-pdf ghostscript gutenprint system-config-printer
    sudo systemctl enable cups.service
    echo -e "${ORANGE}Installation complete! Press any key to continue...${NC}"
    read -n 1
}

# Function to install Steam
install_steam() {
    echo -e "${ORANGE}Installing Steam Gaming Platform...${NC}"
    sudo pamac install steam steam-native-runtime python-steam protonup-qt protontricks libgdiplus
    echo -e "${ORANGE}Installation complete! Press any key to continue...${NC}"
    read -n 1
}

# Function to set environment variables
set_environment_variables() {
    echo -e "${ORANGE}Setting environment variables...${NC}"
   echo -e "
   CPU_LIMIT=0
   CPU_GOVERNOR=performance
   GPU_USE_SYNC_OBJECTS=1
   SHARED_MEMORY=1
   LC_ALL=de_DE.UTF-8
   TIMEZONE=Europe/Berlin
   PYTHONOPTIMIZE=1
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
   AMD_VULKAN_ICD=RADV
   RADV_PERFTEST=aco,sam,nggc
   RADV_DEBUG=novrsflatshading
   STEAM_RUNTIME_HEAVY=1
   STEAM_FRAME_FORCE_CLOSE=0
   GAMEMODE=1
   vblank_mode=1
   PROTON_LOG=0
   PROTON_USE_WINED3D=0
   PROTON_FORCE_LARGE_ADDRESS_AWARE=1
   PROTON_NO_ESYNC=1
   DXVK_ASYNC=1
   WINE_FULLSCREEN_FSR=1
   WINE_VK_USE_FSR=1
   MESA_BACK_BUFFER=ximage
   MESA_NO_DITHER=1
   MESA_SHADER_CACHE_DISABLE=false
   mesa_glthread=true
   MESA_DEBUG=0
   LIBGL_DEBUG=0
   LIBGL_NO_DRAWARRAYS=0
   LIBGL_THROTTLE_REFRESH=1
   LIBC_FORCE_NOCHECK=1
   LIBGL_DRI3_DISABLE=1
   __GLVND_DISALLOW_PATCHING=1
   __GL_THREADED_OPTIMIZATIONS=1
   __GL_SYNC_TO_VBLANK=1
   __GL_SHADER_DISK_CACHE=0
   __GL_YIELD=NOTHING
   VK_LOG_LEVEL=error
   VK_LOG_FILE=/dev/null
   ANV_ENABLE_PIPELINE_CACHE=1
   HISTCONTROL=ignoreboth:eraseboth
   HISTSIZE=5
   LESSHISTFILE=-
   LESSHISTSIZE=0
   LESSSECURE=1
   PAGER=less
   EDITOR=nano
   VISUAL=nano
" | sudo tee -a /etc/environment
	
    echo -e "${ORANGE}Environment variables set! Press any key to continue...${NC}"
    read -n 1
}

# Function to enable write cache and fast commit
enable_write_cache() {
    echo -e "${ORANGE}Enabling write cache and fast commit...${NC}"
    echo -e "write back" | sudo tee /sys/block/*/queue/write_cache
    sudo tune2fs -o journal_data_writeback $(df / | grep / | awk '{print $1}')
    sudo tune2fs -O ^has_journal $(df / | grep / | awk '{print $1}')
    sudo tune2fs -o journal_data_writeback $(df /home | grep /home | awk '{print $1}')
    sudo tune2fs -O ^has_journal $(df /home | grep /home | awk '{print $1}')
    sudo tune2fs -O fast_commit $(df / | grep / | awk '{print $1}')
    sudo tune2fs -O fast_commit $(df /home | grep /home | awk '{print $1}')
    echo -e "${ORANGE}Write cache and fast commit enabled! Press any key to continue...${NC}"
    read -n 1
}

# Function to improve NVME and PCI latency
improve_nvme_pci() {
    echo -e "${ORANGE}Improving NVME and PCI latency...${NC}"
    if find /sys/block/nvme[0-9]* | grep -q nvme; then
        echo -e "options nvme_core default_ps_max_latency_us=0" | sudo tee /etc/modprobe.d/nvme.conf
    fi
    sudo setpci -v -d *:* latency_timer=48 >/dev/null 2>&1
    echo -e "${ORANGE}NVME and PCI latency improved! Press any key to continue...${NC}"
    read -n 1
}

# Function to disable GPU polling
disable_gpu_polling() {
    echo -e "${ORANGE}Disabling GPU polling...${NC}"
    echo -e "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf
    echo -e "${ORANGE}GPU polling disabled! Press any key to continue...${NC}"
    read -n 1
}

# Function to enable trim for SSD/NVMe
enable_trim() {
    echo -e "${ORANGE}Enabling trim for SSD/NVMe...${NC}"
    sudo systemctl enable fstrim.timer
    sudo fstrim -av
    echo -e "${ORANGE}Trim enabled! Press any key to continue...${NC}"
    read -n 1
}

# Function to create backup with Timeshift
create_backup() {
    echo -e "${ORANGE}Creating backup with Timeshift...${NC}"
    sudo pamac install timeshift timeshift-autosnap-manjaro
    sudo timeshift --create
    echo -e "${ORANGE}Backup created! Press any key to continue...${NC}"
    read -n 1
}

# Main loop
while true; do
    display_menu
    read -r option
    case $option in
        1) install_packages ;;
        2) install_python_support ;;
        3) install_graphics_drivers ;;
        4) install_various_programs ;;
        5) install_printer_support ;;
        6) install_steam ;;
        7) set_environment_variables ;;
        8) enable_write_cache ;;
        9) improve_nvme_pci ;;
        10) disable_gpu_polling ;;
        11) enable_trim ;;
        12) create_backup ;;
        0) echo -e "${ORANGE}Exiting...${NC}"; break ;;
        *) echo -e "${ORANGE}Invalid option! Press any key to try again...${NC}"; read -n 1 ;;
    esac
done

