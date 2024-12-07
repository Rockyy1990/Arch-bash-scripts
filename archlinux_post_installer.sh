#!/usr/bin/env bash

# Last edit: 05.12.2024 

echo ""
echo "         !!You should read this script first!!
"
echo "           (The default AUR Helper is yay)
"
echo ""
read -p "Its recommend to install the chaotic aur repo for some packeges.
                     Press any key to continue."
echo ""

# Function to display the menu
display_menu() {
    clear
    LIGHT_BLUE='\033[1;36m' # ANSI escape code for light blue color
    NC='\033[0m'            # No Color
    
    echo -e "${LIGHT_BLUE}-----------------------------------------------${NC}"
    echo -e "${LIGHT_BLUE}        Archlinux Post-Installer               ${NC}"
    echo -e "${LIGHT_BLUE}-----------------------------------------------${NC}"
    echo -e "${LIGHT_BLUE}1)  Install Chaotic-Repo (Compiled AUR)${NC}"
    echo -e "${LIGHT_BLUE}2)  Install Needed-packages and system tweaks${NC}"
    echo -e "${LIGHT_BLUE}3)  Install bashrc-tweaks${NC}"
    echo -e "${LIGHT_BLUE}4)  Install Programs${NC}"
    echo -e "${LIGHT_BLUE}5)  Install Docker${NC}"
    echo -e "${LIGHT_BLUE}6)  Install Pipewire-full (Sound)${NC}"
    echo -e "${LIGHT_BLUE}7)  Install AMD GPU Driver${NC}"
    echo -e "${LIGHT_BLUE}8)  Install Nvidia GPU Driver ${NC}"
    echo -e "${LIGHT_BLUE}9)  Install Print Support${NC}"
    echo -e "${LIGHT_BLUE}10) Install Flatpak Support${NC}"
    echo -e "${LIGHT_BLUE}11) Install Wine (Windows support)${NC}"
    echo -e "${LIGHT_BLUE}12) Install Steam Gaming Platform${NC}"
    echo -e "${LIGHT_BLUE}13) Install Pamac-AUR Helper (GUI for Pacman)${NC}"
    echo -e "${LIGHT_BLUE}14) Install Chromium Browser${NC}"
    echo -e "${LIGHT_BLUE}15) Install Firefox Browser${NC}"
    echo -e "${LIGHT_BLUE}---------------------------------------------${NC}"
    echo -e "${LIGHT_BLUE}16) Archlinux to CachyOS Converter${NC}"
    echo -e "${LIGHT_BLUE}17) Install and config nfs (server)${NC}"
    echo -e "${LIGHT_BLUE}18) Install and config nfs (client)${NC}"
    echo -e "${LIGHT_BLUE}19) Install and config samba (share)${NC}"
    echo -e "${LIGHT_BLUE}20) Install VMware Workstation (Virtualisation)${NC}"
    echo -e "${LIGHT_BLUE}21) Install Libreoffice (fresh)${NC}"
    echo -e "${LIGHT_BLUE}22) Final steps (System cleaning and Backup)${NC}"
    echo -e "${LIGHT_BLUE}0) EXIT installer and reboot${NC}"
    echo -e "${LIGHT_BLUE}---------------------------------------------${NC}"
}



# Function to install a package
install_chaotic-aur() {
    
    # Config the pacman.conf
    
    # Colorful progress bar
    grep -q "^Color" /etc/pacman.conf || sudo sed -i -e "s/^#Color$/Color/" /etc/pacman.conf
    grep -q "ILoveCandy" /etc/pacman.conf || sudo sed -i -e "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
    sudo sed -i -e s"/\#VerbosePkgLists/VerbosePkgLists/"g /etc/pacman.conf
    sudo sed -i -e s"/\#ParallelDownloads.*/ParallelDownloads = 2/"g /etc/pacman.conf
    
    # Disable pacman cache.
    sudo sed -i -e s"/\#CacheDir.*/CacheDir = /"g /etc/pacman.conf
    
    echo "Installing chaotic-aur..."
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 
    sudo pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    
    echo "" | sudo tee -a /etc/pacman.conf
    echo "## Chaotic AUR Repo ##" | sudo tee -a /etc/pacman.conf
    echo "[chaotic-aur]" | sudo tee -a /etc/pacman.conf 
    echo "Include = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
    echo ""
    
    
    read -p "Press any key to costumize pacman.conf."
    sudo nano -w /etc/pacman.conf

    sudo pacman -Sy

    echo "chaotic-aur installed successfully!"
    read -p "Press [Enter] to continue..."
}



# Function to install a package
install_needed-packages() {
    echo -e "Installing Needed-packages and make system tweaks.."
    echo ""
    sudo pacman -S --needed --noconfirm dbus-broker dkms kmod amd-ucode pacman-contrib bash-completion yay samba bind ethtool rsync timeshift timeshift-autosnap
    sudo pacman -S --needed --noconfirm gufw mtools dosfstools xfsdump btrfs-progs f2fs-tools udftools gnome-disk-utility lrzip zstd unrar unzip unace nss fuse2 fuseiso libelf upx
    
    # Complet x11 support
    sudo pacman -S --needed --noconfirm xorg-server-xvfb xorg-xkill xorg-xinput xorg-xrandr libwnck3 libxcomposite lib32-libxcomposite libxinerama lib32-libxrandr lib32-libxfixes
    
    # Additional System tools and libraries
    sudo pacman -S --needed --noconfirm hdparm sdparm gvfs gvfs-smb gvfs-nfs hwdetect sof-firmware cpupower 
    sudo pacman -S --needed --noconfirm xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs
    
    # Full python support
    sudo pacman -S --needed --noconfirm python python-extras python-reportlab python-opengl python-glfw python-pyxdg python-pywayland python-cachy tcl tk 
	
    # System tweaks
    sudo pacman -S --needed --noconfirm irqbalance memavaild nohang ananicy-cpp
    
    # needed packages for various variables (sysctl variables etc)
    sudo pacman -S --needed --noconfirm procps-ng iproute2 iotop nmon quota-tools lm_sensors lz4 pciutils libpciaccess
	
    # Fonts
    sudo pacman -S --needed --noconfirm ttf-dejavu ttf-freefont ttf-liberation ttf-droid terminus-font 
    sudo pacman -S --needed --noconfirm noto-fonts ttf-ubuntu-font-family ttf-roboto ttf-roboto-mono 
    
    # Mint Icons and theme
    sudo pacman -S --needed --noconfirm mint-l-icons mint-y-icons mint-l-theme
    

    echo -e "Set the theme and icon theme for XFCE4 with tweaks"
    xfconf-query -c xsettings -p /Net/ThemeName -n -s "Mint-L-Darker"
    xfconf-query -c xsettings -p /Net/IconThemeName -n -s "Mint-L"
    xfconf-query -c xfwm4 -p /general/enable_workarounds -s true --create --type bool
    xfconf-query -c xfwm4 -p /general/use_shadows -s false --create --type bool
    #xfconf-query -c xfce4-desktop -v --create -p /desktop-icons/style -t int -s 0
    
    xfconf-query -c xscreensaver -p /timeout -s 0 --create -t int
    xfconf-query -c xscreensaver -p /cycle -s 0 --create -t int
    xfconf-query -c xfce4-session -p /shutdown/LockScreen -s false
    xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/lock-screen-suspend-hibernate -s false
    xfconf-query -c xfce4-session -p /startup/ssh-agent/enabled -n -t bool -s false



    echo -e "Installing make-tools..."
    sudo pacman -S --needed --noconfirm base-devel binutils git fakeroot gcc clang llvm bc meson ninja rust automake autoconf ccache
     
    yay -S --needed --noconfirm grub-hook update-grub faudio ffaudioconverter ttf-ms-win10-auto 
    
   

   
    # Enable the services
    sudo systemctl enable --now cpupower.service
    sudo cpupower frequency-set -g performance
    sudo systemctl enable --now dbus-broker.service
    sudo systemctl --global enable dbus-broker.service
    
    #sudo systemctl disable systemd-oomd
    sudo systemctl enable irqbalance
    sudo systemctl enable memavaild
    sudo systemctl enable nohang
    sudo systemctl enable ananicy-cpp

    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo systemctl enable ufw

    # Update the library cache
    sudo ldconfig
   
    

# Environment variables
    echo -e "
    CPU_LIMIT=0
    GPU_USE_SYNC_OBJECTS=1
    SHARED_MEMORY=1
    MALLOC_CONF=background_thread:true
    MALLOC_CHECK=0
    MALLOC_TRACE=0
    LD_DEBUG_OUTPUT=0
    MESA_DEBUG=0
    LIBGL_DEBUG=0
    LIBGL_NO_DRAWARRAYS=1
    LIBGL_THROTTLE_REFRESH=1
    LIBC_FORCE_NOCHECK=1
    HISTCONTROL=ignoreboth:eraseboth
    HISTSIZE=5
    LESSHISTFILE=-
    LESSHISTSIZE=0
    LESSSECURE=1
    PAGER=less
	" | sudo tee -a /etc/environment
    
    
    # BFQ scheduler
    echo -e "Enable BFQ scheduler"
    echo -e "bfq" | sudo tee /etc/modules-load.d/bfq.conf
    echo -e 'ACTION=="add|change", ATTR{queue/scheduler}=="*bfq*", KERNEL=="sd*[!0-9]|sr*|mmcblk[0-9]*|nvme[0-9]*", ATTR{queue/scheduler}="bfq"' | sudo tee /etc/udev/rules.d/60-scheduler.rules
    echo -e 'ACTION=="add|change", KERNEL=="sd*[!0-9]|sr*|mmcblk[0-9]*|nvme[0-9]*", ATTR{queue/iosched/slice_idle}="0", ATTR{queue/iosched/low_latency}="1"' | sudo tee /etc/udev/rules.d/90-low-latency.rules
    
    
   
    # Optimize sysctl
    sudo touch /etc/sysctl.d/99-custom.conf
    echo -e "
    vm.swappiness = 1
    vm.vfs_cache_pressure = 50
    vm.overcommit_memory = 1
    vm.overcommit_ratio = 50
    vm.dirty_background_ratio = 5
    vm.dirty_ratio = 10
    vm.stat_interval = 60
    vm.page-cluster = 0
    vm.dirty_expire_centisecs = 500
    vm.oom_dump_tasks = 1
    vm.oom_kill_allocating_task = 1
    vm.extfrag_threshold = 500
    vm.block_dump = 0
    vm.reap_mem_on_sigkill = 1
    vm.panic_on_oom = 0
    vm.zone_reclaim_mode = 0
    vm.scan_unevictable_pages = 0
    vm.compact_unevictable_allowed = 1
    vm.compaction_proactiveness = 0
    vm.page_lock_unfairness = 1
    vm.percpu_pagelist_high_fraction = 0
    vm.pagecache = 1
    vm.watermark_scale_factor = 1
    vm.memory_failure_recovery = 0
    vm.max_map_count = 262144
    min_perf_pct = 100
    kernel.io_delay_type = 3
    kernel.task_delayacct = 0
    kernel.sysrq = 0
    kernel.watchdog_thresh = 10
    kernel.nmi_watchdog = 0
    kernel.seccomp = 0
    kernel.timer_migration = 0
    kernel.core_pipe_limit = 0
    kernel.core_uses_pid = 1
    kernel.hung_task_timeout_secs = 0
    kernel.sched_rr_timeslice_ms = -1
    kernel.sched_rt_runtime_us = -1
    kernel.sched_rt_period_us = 1
    kernel.sched_child_runs_first = 1
    kernel.sched_tunable_scaling = 1
    kernel.sched_schedstats = 0
    kernel.sched_energy_aware = 0
    kernel.sched_autogroup_enabled = 0
    kernel.sched_compat_yield = 0
    kernel.sched_min_task_util_for_colocation = 0
    kernel.sched_nr_migrate = 4
    kernel.sched_migration_cost_ns = 100000
    kernel.sched_latency_ns = 100000
    kernel.sched_min_granularity_ns = 100000
    kernel.sched_wakeup_granularity_ns = 1000
    kernel.sched_scaling_enable = 1
    kernel.sched_itmt_enabled = 1
    kernel.numa_balancing = 1
    kernel.panic = 0
    kernel.panic_on_oops = 0
    kernel.perf_cpu_time_max_percent = 1
    kernel.printk_devkmsg = off
    kernel.compat-log = 0
    kernel.yama.ptrace_scope = 1
    kernel.stack_tracer_enabled = 0
    kernel.random.urandom_min_reseed_secs = 120
    kernel.perf_event_paranoid = -1
    kernel.perf_event_max_contexts_per_stack = 2
    kernel.perf_event_max_sample_rate = 1
    kernel.kptr_restrict = 0
    kernel.randomize_va_space = 0
    kernel.exec-shield = 0
    kernel.kexec_load_disabled = 1
    kernel.acpi_video_flags = 0
    kernel.unknown_nmi_panic = 0
    kernel.panic_on_unrecovered_nmi = 0
    dev.i915.perf_stream_paranoid = 0
    dev.scsi.logging_level = 0
    debug.exception-trace = 0
    debug.kprobes-optimization = 1
    fs.inotify.max_user_watches = 1048576
    fs.inotify.max_user_instances = 1048576
    fs.inotify.max_queued_events = 1048576
    fs.quota.allocated_dquots = 0
    fs.quota.cache_hits = 0
    fs.quota.drops = 0
    fs.quota.free_dquots = 0
    fs.quota.lookups = 0
    fs.quota.reads = 0
    fs.quota.syncs = 0
    fs.quota.warnings = 0
    fs.quota.writes = 0
    fs.leases-enable = 1
    fs.lease-break-time = 5
    fs.dir-notify-enable = 0 
    force_latency = 1
    net.ipv4.tcp_frto=1
    net.ipv4.tcp_frto_response=2
    net.ipv4.tcp_low_latency=1
    net.ipv4.tcp_slow_start_after_idle=0
    net.ipv4.tcp_window_scaling=1
    net.ipv4.tcp_keepalive_time=300
    net.ipv4.tcp_keepalive_probes=5
    net.ipv4.tcp_keepalive_intvl=15
    net.ipv4.tcp_ecn=1
    net.ipv4.tcp_fastopen=3
    net.ipv4.tcp_early_retrans=2
    net.ipv4.tcp_thin_dupack=1
    net.ipv4.tcp_autocorking=0
    net.ipv4.tcp_reordering=3
    net.ipv4.tcp_timestamps=0
    net.core.bpf_jit_enable=1
    net.core.bpf_jit_harden=0
    net.core.bpf_jit_kallsyms=0
    " | sudo tee /etc/sysctl.d/99-custom.conf
    echo -e "Drop caches"
    sudo sysctl -w vm.compact_memory=1 
    sudo sysctl -w vm.drop_caches=2 
    sudo sysctl -w vm.drop_caches=3
    sudo sysctl --system
    
    
    
    echo -e "Enable write cache"
    echo -e "write back" | sudo tee /sys/block/*/queue/write_cache
    sudo tune2fs -o journal_data_writeback $(df / | grep / | awk '{print $1}')
    sudo tune2fs -O ^has_journal $(df / | grep / | awk '{print $1}')
    sudo tune2fs -o journal_data_writeback $(df /home | grep /home | awk '{print $1}')
    sudo tune2fs -O ^has_journal $(df /home | grep /home | awk '{print $1}')
    echo -e "Enable fast commit"
    sudo tune2fs -O fast_commit $(df / | grep / | awk '{print $1}')
    sudo tune2fs -O fast_commit $(df /home | grep /home | awk '{print $1}')

    
    echo -e "Enable compose cache on disk"
    sudo mkdir -p /var/cache/libx11/compose
    mkdir -p /home/$USER/.compose-cache
    touch /home/$USER/.XCompose

    ## Improve NVME
    if $(find /sys/block/nvme[0-9]* | grep -q nvme); then
    echo -e "options nvme_core default_ps_max_latency_us=0" | sudo tee /etc/modprobe.d/nvme.conf
    fi

    ## Improve PCI latency
    sudo setpci -v -d *:* latency_timer=48 >/dev/null 2>&1
    
    
    
    echo "Needed packages and System tweaks installed successfully!"
    read -p "Press [Enter] to continue..."
}




# Function to install a package
install_bashrc-tweaks() {
    
    echo "Installing bashrc-tweaks..."
    sudo pacman -S --noconfirm fastfetch
    
    echo "fastfetch" | sudo tee -a ~/.bashrc
    
    echo "export HISTSIZE=0" | sudo tee -a ~/.bashrc

    # Set the default editor
    export EDITOR=nano
    export VISUAL=nano


    # Alias config
    echo "alias update='sudo pacman -Syu --noconfirm' " | sudo tee -a ~/.bashrc
    echo "alias add='sudo pacman -S --noconfirm' " | sudo tee -a ~/.bashrc
    echo "alias remove='sudo pacman -R --noconfirm' " | sudo tee -a ~/.bashrc
    #echo "alias update-grub='sudo grub-mkconfig -o /boot/grub/grub.cfg' " | sudo tee -a ~/.bashrc
    echo "alias trim='sudo fstrim -av' " | sudo tee -a ~/.bashrc
    echo "alias pclean='sudo pacman -Scc --noconfirm' " | sudo tee -a ~/.bashrc
    echo "alias kver='uname -r' " | sudo tee -a ~/.bashrc
    echo "alias disks='sudo gnome-disk-utility' " | sudo tee -a ~/.bashrc
    echo "bashrc-tweaks installed successfully!"
    read -p "Press [Enter] to continue..."
}




# Function to install a package
install_docker() {
    echo "Installing Docker..."
    sudo pacman -S --needed --noconfirm docker
    sudo systemctl start docker.service
    sudo systemctl enable docker.service
    sudo usermod -aG docker $USER
    newgrp docker
    docker run hello-world
   
    read -p "Press [Enter] to continue..."
}




# Function to install a package
install_programs() {

#!/bin/bash

available_packages=(
    "discord"
    "thunderbird"
    "vlc"
    "soundconverter"
    "lollypop"
    "strawberry"
    "yt-dlp"
    "gparted"
    "heroic-games-launcher-bin"
    "bottles"
    "obs-studio"
    "waterfox-bin"
    "hypnotix"
    "grub-customizer"
    "whatsapp-for-linux"
    "mintstick"
    "apple-fonts"
    "mcmojave-circle-icon-theme-git"
    "gsmartcontrol"
    "fwupd"
)

# Temporary file for storing the selection
tempfile=$(mktemp)
trap 'rm -f "$tempfile"' EXIT  # Ensure tempfile is removed on exit

# Create dialog options
dialog_options=()
for package in "${available_packages[@]}"; do
    case $package in
        "discord") desc="Discord" ;;
        "thunderbird") desc="Thunderbird Email" ;;
        "vlc") desc="VLC Videoplayer" ;;
        "soundconverter") desc="Soundconverter" ;;
        "lollypop") desc="Musikplayer Lollypop" ;;
        "strawberry") desc="Musikplayer Strawberry" ;;
        "yt-dlp") desc="Youtube-Downloader" ;;
        "gparted") desc="Gparted Partitionierungstool" ;;
        "heroic-games-launcher-bin") desc="Heroic Gamelauncher" ;;
        "bottles") desc="Wine Bottle Manager" ;;
        "obs-studio") desc="OBS-Studio" ;;
        "waterfox-bin") desc="Waterfox Web Browser" ;;
        "hypnotix") desc="Hypnotix IPTV" ;;
        "grub-customizer") desc="Grub-Customizer" ;;
        "whatsapp-for-linux") desc="Whatsapp Messenger" ;;
        "mintstick") desc="Mintstick USB-Tool" ;;
        "apple-fonts") desc="Apple-fonts" ;;
        "mcmojave-circle-icon-theme-git") desc="Mcmojave-Circle-Icons" ;;
        "gsmartcontrol") desc="SMART Control GUI" ;;
        "fwupd") desc="Firmware Updater" ;;
    esac
    dialog_options+=("$package" "$desc" off)
done

# Dialog for package selection
dialog --title "Arch Linux Paketinstallation" --checklist "Wählen Sie die zu installierenden Pakete aus.:" 28 0 0 "${dialog_options[@]}" 2> "$tempfile"

# Check if the user canceled
if [ $? -ne 0 ]; then
    echo "Installation abgebrochen."
    exit 1  # Return better exit status
fi

# Read selected packages from the temporary file
selected_packages=($(<"$tempfile"))

# Install packages
if [[ ${#selected_packages[@]} -gt 0 ]]; then
    echo "Installiere die folgenden Pakete: ${selected_packages[*]}"
    sudo pacman -S --needed --noconfirm "${selected_packages[@]}"
else
    echo "Keine Pakete ausgewählt."
fi

    echo "programs installed successfully!"
    read -p "Press [Enter] to continue..."
}



# Function to install a package
install_pipewire-full() {
    echo "Installing pipewire..."
    sudo pacman -S --needed --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-zeroconf pipewire-v4l2 gst-plugin-pipewire wireplumber 
    sudo pacman -S --needed --noconfirm pavucontrol rtkit alsa-firmware alsa-plugins alsa-card-profiles alsa-lib lib32-alsa-lib
    
    # Multimeda Codecs
    sudo pacman -S --needed --noconfirm lame flac opus ffmpeg a52dec x264 x265 libvpx libvorbis libogg speex libdca libfdk-aac
    sudo pacman -S --needed --noconfirm gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gstreamer-vaapi gst-libav
    sudo pacman -S --needed --noconfirm twolame libmad libxv libtheora libmpeg2 faac faad2 libdca libdv libavif libheif xvidcore
    echo "hrtf = true" | sudo tee -a  ~/.alsoftrc
    
    sudo touch /etc/pulse/daemon.conf
    
    echo "
    # Config for better sound quality
    daemonize = no
    cpu-limit = no
    high-priority = yes
    nice-level = -11
    realtime-scheduling = yes
    realtime-priority = 5
    resample-method = speex-float-10
    avoid-resampling = false
    enable-remixing = no
    rlimit-rtprio = 9
    default-sample-format = float32le
    default-sample-rate = 96000
    alternate-sample-rate = 48000
    default-sample-channels = 2
    default-channel-map = front-left,front-right
    default-fragments = 2
    default-fragment-size-msec = 125
    " | sudo tee /etc/pulse/daemon.conf

    
    
    # Name des Pakets, das überprüft werden soll
    PACKAGE="blueman"

    # Überprüfen, ob das Paket installiert ist
    if pacman -Qs "^$PACKAGE" > /dev/null; then
    echo "$PACKAGE is already installed."
    else
    read -p "$PACKAGE is not installed. Blueman (Gui for bluetooth) install now? (ja/nein): " antwort

    case $antwort in
        [Jj]|[Jj][Aa])
            # Paket installieren
            sudo pacman -S --noconfirm "$PACKAGE"
            echo "$PACKAGE installed now."
            ;;
        [Nn]|[Nn][Ee])
            echo "Install from $PACKAGE cancelled."
            ;;
        *)
            echo "Wrong input. Write 'ja' oder 'nein'."
            ;;
     esac
    fi

  

    echo "pipewire installed successfully!"
    read -p "Press [Enter] to continue..."
}




# Function to install a package
install_amd-gpu-driver() {
    echo "Installing amd-gpu-driver..."
    sudo pacman -S --needed --noconfirm xf86-video-amdgpu mesa lib32-mesa glu lib32-glu libvdpau-va-gl adriconf
    sudo pacman -S --needed --noconfirm opencl-icd-loader ocl-icd lib32-ocl-icd rocm-opencl-runtime
    
    # Install Vulkan drivers
    sudo pacman -S --needed --noconfirm vulkan-radeon lib32-vulkan-radeon vulkan-swrast vulkan-icd-loader lib32-vulkan-icd-loader 
    sudo pacman -S --needed --noconfirm vulkan-validation-layers vulkan-mesa-layers lib32-vulkan-mesa-layers vulkan-headers
    
    echo "
    KERNEL=="card0", SUBSYSTEM=="drm", DRIVERS=="amdgpu", ATTR{device/power_dpm_state}="performance"
    " | sudo tee -a /usr/lib/udev/rules.d/30-amdgpu-pm.rules
    
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
    echo -e "LIBGL_DRI3_DISABLE=1" | sudo tee -a /etc/environment &&
    echo -e "VKD3D_CONFIG=upload_hvv" | sudo tee -a /etc/environment &&
    echo -e "LP_PERF=no_mipmap,no_linear,no_mip_linear,no_tex,no_blend,no_depth,no_alphatest" | sudo tee -a /etc/environment &&
    echo -e "STEAM_FRAME_FORCE_CLOSE=0" | sudo tee -a /etc/environment &&
    echo -e "STEAM_RUNTIME_HEAVY=1" | sudo tee -a /etc/environment &&
    echo -e "GAMEMODE=1" | sudo tee -a /etc/environment &&
    echo -e "vblank_mode=1" | sudo tee -a /etc/environment
    
    echo -e "Disable GPU polling"
    echo -e "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf

    
    echo "amd-gpu-driver installed successfully!"
    read -p "Press [Enter] to continue..."
}




# Function to install a package
install_nvidia-gpu-driver() {
    echo "Installing nvidia-gpu-driver..."
    sudo pacman -S --needed --noconfirm nvidia nvidia-utils lib32-nvidia-utils opencl-nvidia lib32-opencl-nvidia 
    sudo pacman -S --needed --noconfirm libxnvctrl libvdpau vulkan-icd-loader lib32-vulkan-icd-loader nvidia-settings
    
            echo -e "WINEPREFIX=~/.wine" | sudo tee -a /etc/environment &&
            echo -e "WINE_LARGE_ADDRESS_AWARE=1" | sudo tee -a /etc/environment &&
            echo -e "WINEFSYNC_SPINCOUNT=24" | sudo tee -a /etc/environment &&
            echo -e "WINEFSYNC=1" | sudo tee -a /etc/environment &&
            echo -e "WINEFSYNC_FUTEX2=1" | sudo tee -a /etc/environment &&
            echo -e "WINE_SKIP_GECKO_INSTALLATION=1" | sudo tee -a /etc/environment &&
            echo -e "WINE_SKIP_MONO_INSTALLATION=1" | sudo tee -a /etc/environment &&
            echo -e "STAGING_WRITECOPY=1" | sudo tee -a /etc/environment &&
            echo -e "STAGING_SHARED_MEMORY=1" | sudo tee -a /etc/environment &&
            echo -e "STAGING_RT_PRIORITY_SERVER=4" | sudo tee -a /etc/environment &&
            echo -e "STAGING_RT_PRIORITY_BASE=2" | sudo tee -a /etc/environment &&
            echo -e "STAGING_AUDIO_PERIOD=13333" | sudo tee -a /etc/environment &&
            echo -e "PROTON_LOG=0" | sudo tee -a /etc/environment &&
            echo -e "PROTON_USE_WINED3D=1" | sudo tee -a /etc/environment &&
            echo -e "PROTON_FORCE_LARGE_ADDRESS_AWARE=1" | sudo tee -a /etc/environment &&
            echo -e "PROTON_NO_ESYNC=1" | sudo tee -a /etc/environment &&
            echo -e "ENABLE_VKBASALT=1" | sudo tee -a /etc/environment &&
            echo -e "DXVK_ASYNC=1" | sudo tee -a /etc/environment &&
            echo -e "DXVK_HUD=compile" | sudo tee -a /etc/environment &&
            echo -e "MESA_BACK_BUFFER=ximage" | sudo tee -a /etc/environment &&
            echo -e "MESA_NO_DITHER=1" | sudo tee -a /etc/environment &&
            echo -e "MESA_NO_ERROR=1" | sudo tee -a /etc/environment &&
            echo -e "MESA_GLSL_CACHE_DISABLE=false" | sudo tee -a /etc/environment &&
            echo -e "mesa_glthread=true" | sudo tee -a /etc/environment &&
            echo -e "ANV_ENABLE_PIPELINE_CACHE=1" | sudo tee -a /etc/environment &&
            echo -e "__NV_PRIME_RENDER_OFFLOAD=1" | sudo tee -a /etc/environment &&
            echo -e "__GLX_VENDOR_LIBRARY_NAME=mesa" | sudo tee -a /etc/environment &&
            echo -e "__GLVND_DISALLOW_PATCHING=1" | sudo tee -a /etc/environment &&
            echo -e "__GL_THREADED_OPTIMIZATIONS=1" | sudo tee -a /etc/environment &&
            echo -e "__GL_SYNC_TO_VBLANK=1" | sudo tee -a /etc/environment &&
            echo -e "__GL_MaxFramesAllowed=1" | sudo tee -a /etc/environment &&
            echo -e "__GL_SHADER_DISK_CACHE=1" | sudo tee -a /etc/environment &&
            echo -e "__GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1" | sudo tee -a /etc/environment &&
            echo -e "__GL_YIELD=NOTHING" | sudo tee -a /etc/environment &&
            echo -e "__GL_VRR_ALLOWED=0" | sudo tee -a /etc/environment &&
            echo -e "LIBGL_DRI3_DISABLE=1" | sudo tee -a /etc/environment &&
            echo -e "VKD3D_CONFIG=upload_hvv" | sudo tee -a /etc/environment &&
            echo -e "LP_PERF=no_mipmap,no_linear,no_mip_linear,no_tex,no_blend,no_depth,no_alphatest" | sudo tee -a /etc/environment &&
            echo -e "STEAM_FRAME_FORCE_CLOSE=0" | sudo tee -a /etc/environment &&
            echo -e "STEAM_RUNTIME_HEAVY=1" | sudo tee -a /etc/environment &&
            echo -e "GAMEMODE=1" | sudo tee -a /etc/environment &&
            echo -e "vblank_mode=1" | sudo tee -a /etc/environment


    echo -e "Disable GPU polling"
    echo -e "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf

    echo "nvidia-gpu-driver installed successfully!"
    read -p "Press [Enter] to continue..."
}




# Function to install a package
install_printer-support() {
    echo "Installing printer-support..."
    sudo pacman -S --needed --noconfirm cups cups-filters cups-pdf gutenprint ghostscript avahi system-config-printer
    sudo pacman -S --needed --noconfirm foomatic-db foomatic-db-engine foomatic-db-gutenprint-ppds foomatic-db-nonfree foomatic-db-nonfree-ppds foomatic-db-ppds
    sudo systemctl enable --now cups.service
    echo "printer-support installed successfully!"
    read -p "Press [Enter] to continue..."
}




# Function to install a package
install_flatpak-support() {
   echo "Installing flatpak..."
   sudo pacman -S --needed --noconfirm flatpak 
   flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
   flatpak update
   echo "flatpak installed successfully!"
   read -p "Press [Enter] to continue..."
}




# Function to install a package
install_wine() {
    echo "Installing wine..."
    sudo pacman -S --needed --noconfirm wine wine-mono wine-gecko winetricks libgdiplus vkd3d lib32-vkd3d cabextract zenity
   
    echo "wine installed successfully!"
    read -p "Press [Enter] to continue..."
}




# Function to install a package
install_steam-gaming-platform() {
    echo "Installing steam..."
    sudo pacman -S --needed --noconfirm steam steam-native-runtime protontricks-git gamemode lib32-gamemode openal lib32-openal lib32-fontconfig libldap lib32-libldap 

    sudo pacman -S --needed --noconfirm mpg123 lib32-mpg123 v4l-utils lib32-v4l-utils lib32-libpulse lib32-alsa-plugins sqlite lib32-sqlite 
    sudo pacman -S --needed --noconfirm gnutls lib32-gnutls libgpg-error lib32-libgpg-error  libjpeg-turbo lib32-libjpeg-turbo 
    sudo pacman -S --needed --noconfirm lib32-libgcrypt libgcrypt lib32-libxinerama ncurses lib32-ncurses lib32-opencl-icd-loader
    sudo pacman -S --needed --noconfirm libxslt lib32-libxslt lib32-libva gtk3 lib32-gtk3 lib32-gst-plugins-base-libs  

    sudo pacman -S --needed --noconfirm lib32-sdl2 lib32-alsa-lib lib32-giflib lib32-gnutls lib32-libglvnd lib32-libldap      
    sudo pacman -S --needed --noconfirm lib32-libxinerama lib32-libxcursor lib32-gnutls lib32-libva lib32-libvdpau libvdpau
 
    echo ""
    echo "Do you wont to install the Proton Manager Protonup-Qt ?"
    sudo pacman -S protonup-qt
    
    echo "steam installed successfully!"
    read -p "Press [Enter] to continue..."
}




# Function to install AUR Helper
install_aur-helper() {
    echo "Installing Pamac AUR helper..."
    sudo pacman -S --needed --noconfirm pamac-aur
    
    echo "aur-helper installed successfully!"
    read -p "Press [Enter] to continue..."
}




# Function to install a package
install_chromium_browser() {
    
    echo "Starting install chromium browser..."
   sudo pacman -S --needed --noconfirm chromium chromium-widevine
 
    echo "chromium browser installed successfully!"
    read -p "Press [Enter] to continue..."

}



# Function to install a package
install_firefox_browser() {
    
    echo "Starting install firefox browser..."
   sudo pacman -S --needed --noconfirm firefox firefox-i18n-de
 
    echo "firefox installed successfully!"
    read -p "Press [Enter] to continue..."

}



# Function to install a package
install_arch_to_cachyos_converter() {
    
   echo "Starting CachyOS installer...."
  
   curl https://mirror.cachyos.org/cachyos-repo.tar.xz -o cachyos-repo.tar.xz

   tar xvf cachyos-repo.tar.xz && cd cachyos-repo

   sudo ./cachyos-repo.sh

   sudo grub-mkconfig -o /boot/grub/grub.cfg

  echo ""
  echo "check pacman.conf"
  sleep 2
  sudo nano /etc/pacman.conf

  sudo pacman -S --needed --noconfirm cachyos-kernel-manager
  sudo pacman -S --needed --noconfirm cachyos-sysctl-manager

  echo "All done. You should reboot the system"
  
 
    echo "Arch to CachyOS successfully!"
    read -p "Press [Enter] to continue..."

}




# Function to install a package
install_nfs_server() {
    
    echo "Starting install  nfs (server)..."
  

# Exit on error
set -e

# Function to display usage
usage() {
    echo "Usage: $0 [-h | --help] [-p <path_to_export>]"
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo "  -p, --path        Path to export. This is required."
}



# Parse command line arguments
EXPORT_PATH=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -p|--path)
            shift
            EXPORT_PATH="$1"
            shift
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

# Check if the export path is provided
if [ -z "$EXPORT_PATH" ]; then
    echo "Error: Export path is required."
    usage
    exit 1
fi

# Ensure the export path exists
if [ ! -d "$EXPORT_PATH" ]; then
    echo "Error: Export path '$EXPORT_PATH' does not exist."
    exit 1
fi

# Update system and install NFS packages
echo "Updating system and installing NFS packages..."
sudo pacman -Syu --noconfirm nfs-utils

# Enable and start the NFS server
echo "Enabling and starting NFS server..."
sudo systemctl enable nfs-server
sudo systemctl start nfs-server

# Set the NFS exports
echo "Configuring NFS exports..."
echo "$EXPORT_PATH *(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports

# Restart NFS services to apply changes
echo "Restarting NFS services..."
sudo exportfs -a
sudo systemctl restart nfs-server

# Show the export list
echo "NFS server setup complete. Current exports:"
sudo exportfs -v

echo "Don't forget to configure your firewall to allow NFS traffic!"
echo "sudo ufw allow from <client_ip> to any port nfs"
 
    echo "nfs-server installed successfully!"
    read -p "Press [Enter] to continue..."

}



# Function to install a package
install_nfs_client() {
read -p "You need to set the mount_point and other parameters first in this script before execute!"
    
    echo "Starting installing a nfs client..."
   
# Exit immediately if any command fails
set -e

# Update the package database
echo "Updating package database..."
sudo pacman -Syu --noconfirm

# Install the required packages for NFS client
echo "Installing NFS client package..."
sudo pacman -S --needed --noconfirm nfs-utils

# Enable and start the necessary services
echo "Starting and enabling the nfs-client.target..."
sudo systemctl enable --now nfs-client.target

# Create a mount point for the NFS share
read -p "Enter the directory where you want to mount the NFS share (e.g., /mnt/nfs): " mount_point
sudo mkdir -p "$mount_point"

# Get the NFS server IP address and export path from the user
read -p "Enter the NFS server IP address: " nfs_server
read -p "Enter the export path on the NFS server (e.g., /exported/path): " export_path

# Mount the NFS share
echo "Mounting NFS share..."
sudo mount "$nfs_server:$export_path" "$mount_point"

# Add the NFS mount to /etc/fstab for persistent mounting on boot
echo "Adding to /etc/fstab for automatic mounting on boot..."
echo "$nfs_server:$export_path $mount_point nfs rw,sync,no_subtree_check,no_root_squash 0 0" | sudo tee -a /etc/fstab

echo "NFS client installation and configuration completed successfully."
echo "You can now access the NFS share at $mount_point."
 
    echo "nfs (client) installed successfully!"
    read -p "Press [Enter] to continue..."

}




# Function to install a package
install_samba() {
    
    echo "Starting install and config samba (share)..."
   
set -e

# Update the system
echo "Updating the system..."
sudo pacman -Syu --noconfirm

# Install Samba
echo "Installing Samba..."
sudo pacman -S --needed --noconfirm samba

# Create a directory to share
SHARE_DIR="/srv/samba/share"
sudo mkdir -p "$SHARE_DIR"
sudo chmod 777 "$SHARE_DIR"  # Change permissions as needed; this allows full access.

# Backup the original Samba configuration file
echo "Backing up original Samba configuration..."
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup

# Configure Samba
echo "Configuring Samba..."
cat <<EOF | sudo tee /etc/samba/smb.conf
[global]
    workgroup = WORKGROUP
    server string = Samba Server %v
    netbios name = archlinux
    security = user
    map to guest = bad user
    dns proxy = no

[Share]
    path = $SHARE_DIR
    valid users = guest
    read only = no
    browsable = yes
    public = yes
    writable = yes
EOF

# Add a Samba user (This example uses 'nobody' as a guest user)
echo "Adding Samba user..."
sudo smbpasswd -a nobody

# Start and enable Samba services
echo "Starting and enabling Samba services..."
sudo systemctl start smb.service
sudo systemctl enable smb.service
sudo systemctl start nmb.service
sudo systemctl enable nmb.service

echo "Samba installation and configuration complete!"
echo "You can access the share at: //your-server-ip/Share"

# Optionally, allow Samba through the firewall if using iptables or ufw.
# Make sure to customize according to your firewall configuration.

 
    echo "samba installed successfully!"
    read -p "Press [Enter] to continue..."

}



# Function to install a package
install_vmware_workstation() {
   echo "Installing vmware..."
   sudo pacman -Sy
   read -p "The chaotic repo need to be installed. Press any key to continue.."

sudo pacman -S --needed --noconfirm fuse2 gtkmm linux-headers pcsclite libcanberra 

sudo pacman -S --needed --noconfirm vmware-workstation

sudo systemctl enable vmware-networks.service

sudo systemctl enable vmware-usbarbitrator.service


# Enabling networking
cat <<EOF | sudo tee /etc/systemd/system/vmware-networks-server.service
[Unit]
Description=VMware Networks
Wants=vmware-networks-configuration.service
After=vmware-networks-configuration.service

[Service]
Type=forking
ExecStartPre=-/sbin/modprobe vmnet
ExecStart=/usr/bin/vmware-networks --start
ExecStop=/usr/bin/vmware-networks --stop

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable vmware-networks-server.service


# Create and enable the vmware.service
cat <<EOF | sudo tee /etc/systemd/system/vmware.service
[Unit]
Description=VMware daemon
Requires=vmware-usbarbitrator.service
Before=vmware-usbarbitrator.service
After=network.target

[Service]
ExecStart=/etc/init.d/vmware start
ExecStop=/etc/init.d/vmware stop
PIDFile=/var/lock/subsys/vmware
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable vmware.service

# Reload services and start vmware.service and usbarbitrator.service
sudo systemctl daemon-reload
sudo systemctl start vmware.service vmware-usbarbitrator.service 

# Recompiling VMware kernel modules
sudo  vmware-modconfig --console --install-all

# Load the VMware modules
sudo modprobe -a vmw_vmci vmmon

   
   echo "VMware installed successfully!"
   read -p "Press [Enter] to continue..."
}

# Function to install a package
install_libreoffice() {
   echo "Installing libreoffice..."
   sudo pacman -S --needed --noconfirm libreoffice-fresh libreoffice-fresh-de
   echo "libreoffice installed successfully!"
   read -p "Press [Enter] to continue..."
}




# Function to install a package
install_final-steps() {
    
    echo "Starting final steps..."
    
    sudo pacman -Scc --noconfirm
    yay -Yc --noconfirm
    sudo paccache -rk 0
    sudo pacman -Dk
    sudo pacman -Sy
    
    echo -e "Clearing temporary files..."
    sudo rm -rf /tmp/*
    sudo rm -rf ~/.cache/*
    sudo rm -rf ~/.config/saved-session/*
    

    ## Optimize font cache
    fc-cache -rfv
    ## Optimize icon cache
    gtk-update-icon-cache
    
    
    echo -e "Enable and run trim.."
    sudo systemctl enable fstrim.service
    sudo systemctl enable fstrim.timer
    sudo systemctl start fstrim.service
    sudo systemctl start fstrim.timer
    sudo fstrim -Av
    
   
# Name des Pakets, das überprüft werden soll
PACKAGE="os-prober"

# Überprüfen, ob das Paket installiert ist
if pacman -Qs "^$PACKAGE" > /dev/null; then
    echo "$PACKAGE is already installed."
else
    read -p "$PACKAGE is not installed. os-prober (multiboot with windows etc) install now? (ja/nein): " antwort

    case $antwort in
        [Jj]|[Jj][Aa])
            # Paket installieren
            sudo pacman -S --noconfirm "$PACKAGE"
            echo "GRUB_DISABLE_OS_PROBER=false" | sudo tee -a /etc/default/grub
            sudo os-prober
            echo "$PACKAGE installed now."
            ;;
        [Nn]|[Nn][Ee])
            echo "Install from $PACKAGE canceled."
            ;;
        *)
            echo "Wrong input. Write 'ja' oder 'nein'."
            ;;
    esac
fi


    sudo grub-mkconfig -o /boot/grub/grub.cfg
    
    sudo timeshift --create
    
    echo "The final steps are done! Please reboot archlinux now"
    read -p "Press [Enter] to continue..."
}




# Main script loop
while true; do
    display_menu
    read -p "Select an option [0-22]: " option

    case $option in
        1) install_chaotic-aur ;;
        2) install_needed-packages ;;
        3) install_bashrc-tweaks ;;  
        4) install_programs ;;
        5) install_docker ;;
        6) install_pipewire-full ;;
        7) install_amd-gpu-driver ;;
        8) install_nvidia-gpu-driver ;;
        9) install_printer-support ;;       
       10) install_flatpak-support ;;
       11) install_wine ;;
       12) install_steam-gaming-platform ;;
       13) install_aur-helper ;;
       14) install_chromium_browser ;;
       15) install_firefox_browser ;;
       16) install_arch_to_cachyos_converter ;;
       17) install_nfs_server ;;  
       18) install_nfs_client ;;  
       19) install_samba ;;
       20) install_vmware_workstation ;; 
       21) install_libreoffice ;;  
       22) install_final-steps ;;  
         0) echo "Exiting..."; sudo reboot ;;
        *) echo "Invalid option! Please try again." ;;
    esac
done