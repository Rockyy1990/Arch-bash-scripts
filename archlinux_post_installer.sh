#!/bin/bash

# Last edit: 22.10.2024 

echo ""
read -p "Its recommend to install the chaotic aur repo for some packges.
                  Press any key to continue."
echo ""


# Function to display the menu
display_menu() {
    clear
    echo "------------------------------------------"
    echo "      Archlinux Post-Installer            "
    echo "------------------------------------------"
    echo "1)  Install Chaotic-Repo (Compiled AUR)"
    echo "2)  Install Needed-packages"
    echo "3)  Install bashrc-tweaks"
    echo "4)  Install Make-tools"
    echo "5)  Install Programs"
    echo "6)  Install Pipewire-full"
    echo "7)  Install AMD GPU Driver"
    echo "8)  Install Nvidia GPU Driver "
    echo "9)  Install Print Support"
    echo "10) Install Flatpak Support"
    echo "11) Install Wine (Windows support)"
    echo "12) Install Steam Gaming Platform"
    echo "13) Install AUR Helper "
    echo "14) Install Chromium Browser"
    echo "15) Install Firefox Browser"
    echo "16) Final steps "
    echo "-----------------------------------------"
    echo "17) Archlinux to CachyOS Converter"
    echo "18) Install and config nfs (server)"
    echo "19) Install and config nfs (client)"
    echo "20) Install and config samba (share)"
    echo "21) Install virt-manager (Virtualisation)"
    echo "22) Install Libreoffice (fresh)"
    echo "23) Install Ventoy (USB Multiboot)"
    echo "0) EXIT"
    echo "-----------------------------------------"
}


# Function to install a package
install_chaotic-aur() {
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
    echo "Installing Needed-packages..."
    sudo pacman -S --needed --noconfirm dbus-broker dkms pacman-contrib bash-completion ntp rsync timeshift timeshift-autosnap 
    sudo pacman -S --needed --noconfirm  lrzip zstd unrar unzip unace nss fuse2 fuseiso samba bind
    sudo pacman -S --needed --noconfirm xorg-xkill xorg-xinput xorg-xrandr libwnck3 libxcomposite lib32-libxcomposite libxinerama lib32-libxrandr lib32-libxfixes
    sudo pacman -S --needed --noconfirm hdparm sdparm gvfs gvfs-smb gvfs-nfs mtools xfsdump f2fs-tools udftools hwdetect sof-firmware fwupd cpupower mintstick
    sudo pacman -S --needed --noconfirm xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs
    
    # Fonts
    sudo pacman -S --needed --noconfirm ttf-dejavu ttf-freefont ttf-liberation ttf-droid terminus-font
    sudo pacman -S --needed --noconfirm noto-fonts noto-fonts-emoji ttf-ubuntu-font-family ttf-roboto ttf-roboto-mono
    
    #Themes
    sudo pacman -S --needed --noconfirm mint-l-icons mint-y-icons mint-l-theme
    sudo pacman -S --needed --noconfirm mcmojave-circle-icon-theme-git

    
    sudo systemctl enable --now cpupower.service
    sudo cpupower frequency-set -g performance
    sudo systemctl enable --now dbus-broker.service
    sudo timedatectl set-ntp true
    

    echo "Needed packages installed successfully!"
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
    echo "alias gup='sudo grub-mkconfig -o /boot/grub/grub.cfg' " | sudo tee -a ~/.bashrc
    echo "alias trim='sudo fstrim -av' " | sudo tee -a ~/.bashrc
    echo "alias pclean='sudo pacman -Scc --noconfirm' " | sudo tee -a ~/.bashrc
    echo "alias kver='uname -r' " | sudo tee -a ~/.bashrc
    echo "alias disks='sudo gnome-disk-utility' " | sudo tee -a ~/.bashrc
    echo "bashrc-tweaks installed successfully!"
    read -p "Press [Enter] to continue..."
}



# Function to install a package
install_make-tools() {
    echo "Installing make-tools..."
    sudo pacman -S --needed --noconfirm base-devel fakeroot gcc clang llvm bc automake autoconf git ccache
    echo "make-tools installed successfully!"
    read -p "Press [Enter] to continue..."
}



# Function to install a package
install_programs() {
    echo "Installing programs..."
    sudo pacman -S --needed --noconfirm  thunderbird thunderbird-i18n-de vlc lollypop discord transmission-gtk file-roller yt-dlp
    sudo pacman -S --needed --noconfirm gufw gsmartcontrol gnome-disk-utility
    sudo ufw enable

# Name des Pakets, das überprüft werden soll
PACKAGE="soundconverter"

# Überprüfen, ob das Paket installiert ist
if pacman -Qs "^$PACKAGE" > /dev/null; then
    echo "$PACKAGE already installed."
else
    read -p "$PACKAGE is not installed. Soundconverter (mp3, flac etc converter)? (ja/nein): " antwort

    case $antwort in
        [Jj]|[Jj][Aa])
            # Paket installieren
            sudo pacman -S --noconfirm "$PACKAGE"
            echo "$PACKAGE now installed."
            ;;
        [Nn]|[Nn][Ee])
            echo "Install from $PACKAGE cancelled."
            ;;
        *)
            echo "Wrong input. Write 'ja' oder 'nein'."
            ;;
    esac
fi

    
    echo "programs installed successfully!"
    read -p "Press [Enter] to continue..."
}



# Function to install a package
install_pipewire-full() {
    echo "Installing pipewire..."
    sudo pacman -S --needed --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-zeroconf pipewire-v4l2 gst-plugin-pipewire wireplumber pavucontrol alsa-firmware
    sudo systemctl enable --now wireplumber
    
    sudo pacman -S --needed --noconfirm lame flac opus ffmpeg a52dec x264 x265 
    sudo pacman -S --needed --noconfirm gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gstreamer-vaapi gst-libav
    sudo pacman -S --needed --noconfirm twolame libmad libxv libvorbis libogg libtheora libmpeg2 faac faad2
    sudo pacman -S --needed --noconfirm openal lib32-openal
    echo "hrtf = true" | sudo tee -a  ~/.alsoftrc
    
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
    sudo pacman -S --needed --noconfirm xf86-video-amdgpu mesa lib32-mesa  mesa-vdpau lib32-mesa-vdpau libva-mesa-driver lib32-libva-mesa-driver
    sudo pacman -S --needed --noconfirm adriconf opencl-icd-loader ocl-icd lib32-ocl-icd rocm-opencl-runtime
    
    # Install Vulkan drivers
    sudo pacman -S --needed --noconfirm vulkan-radeon lib32-vulkan-radeon vulkan-swrast vulkan-icd-loader lib32-vulkan-icd-loader
    sudo pacman -S --needed --noconfirm vulkan-validation-layers vulkan-mesa-layers vulkan-headers
    echo "amd-gpu-driver installed successfully!"
    read -p "Press [Enter] to continue..."
}


# Function to install a package
install_nvidia-gpu-driver() {
    echo "Installing nvidia-gpu-driver..."
    sudo pacman -S --needed --noconfirm nvidia nvidia-utils opencl-nvidia libxnvctrl libvdpau nvidia-settings
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
   
# Name des Pakets, das überprüft werden soll
PACKAGE="bottles"

# Überprüfen, ob das Paket installiert ist
if pacman -Qs "^$PACKAGE" > /dev/null; then
    echo "$PACKAGE is already installed."
else
    read -p "$PACKAGE not installed. bottles (gui for wine) installieren? (ja/nein): " antwort

    case $antwort in
        [Jj]|[Jj][Aa])
            # Paket installieren
            sudo pacman -S --noconfirm "$PACKAGE"
            echo "$PACKAGE is now installed."
            ;;
        [Nn]|[Nn][Ee])
            echo "Install from $PACKAGE canceled."
            ;;
        *)
            echo "Wrong input. Type 'ja' oder 'nein'."
            ;;
    esac
fi

    echo "wine installed successfully!"
    read -p "Press [Enter] to continue..."
}



# Function to install a package
install_steam-gaming-platform() {
    echo "Installing steam..."
    sudo pacman -S --needed --noconfirm steam steam-native-runtime protontricks-git gamemode lib32-gamemode lib32-fontconfig giflib lib32-giflib libpng lib32-libpng libldap lib32-libldap gnutls lib32-gnutls

    sudo pacman -S --needed --noconfirm mpg123 lib32-mpg123 v4l-utils lib32-v4l-utils lib32-libpulse lib32-alsa-plugins alsa-lib lib32-alsa-lib
    sudo pacman -S --needed --noconfirm libgpg-error lib32-libgpg-error  libjpeg-turbo lib32-libjpeg-turbo sqlite lib32-sqlite 
    sudo pacman -S --needed --noconfirm lib32-libgcrypt libgcrypt lib32-libxinerama ncurses lib32-ncurses lib32-opencl-icd-loader
    sudo pacman -S --needed --noconfirm libxslt lib32-libxslt lib32-libva gtk3 lib32-gtk3 lib32-gst-plugins-base-libs  

    sudo pacman -S --needed --noconfirm lib32-sdl2 lib32-alsa-lib lib32-giflib lib32-gnutls lib32-libglvnd lib32-libldap      
    sudo pacman -S --needed --noconfirm lib32-libxinerama lib32-libxcursor lib32-gnutls lib32-libva lib32-libvdpau libvdpau
    
# Name des Pakets, das überprüft werden soll
PACKAGE="protonup-qt"

# Überprüfen, ob das Paket installiert ist
if pacman -Qs "^$PACKAGE" > /dev/null; then
    echo "$PACKAGE is already installed."
else
    read -p "$PACKAGE not installed. Protonup-qt (proton-ge install manager) install now ? (ja/nein): " antwort

    case $antwort in
        [Jj]|[Jj][Aa])
            # Paket installieren
            sudo pacman -S --noconfirm "$PACKAGE"
            echo "$PACKAGE is installed."
            ;;
        [Nn]|[Nn][Ee])
            echo "Installation of $PACKAGE cancelled."
            ;;
        *)
            echo "Wrong input. Write 'ja' or 'nein'."
            ;;
    esac
fi
    

    
    echo "steam installed successfully!"
    read -p "Press [Enter] to continue..."
}



# Function to install AUR Helper
install_aur-helper() {
    echo "Installing yay AUR helper..."
    sudo pacman -S --needed --noconfirm git base-devel
    git clone https://aur.archlinux.org/yay.git
    cd yay || exit
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
    
    
# Name des Pakets, das überprüft werden soll
PACKAGE="pamac-aur"

# Überprüfen, ob das Paket installiert ist
if pacman -Qs "^$PACKAGE" > /dev/null; then
    echo "$PACKAGE is already installed."
else
    read -p "$PACKAGE not installed. Pamac-aur (gui for pacman) install now? (ja/nein): " antwort

    case $antwort in
        [Jj]|[Jj][Aa])
            # Paket installieren
            sudo pacman -S --noconfirm "$PACKAGE"
            echo "$PACKAGE wurde installiert."
            ;;
        [Nn]|[Nn][Ee])
            echo "Install of $PACKAGE cancelled."
            ;;
        *)
            echo "Wrong input. Write 'ja' or 'nein'."
            ;;
    esac
fi



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
install_final-steps() {
    
    echo "Starting final steps..."
    # System cleaning
    sudo pacman -Scc --noconfirm

    sudo systemctl enable fstrim.timer
    sudo fstrim -av 
    
   
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
            read -p "Press any key to costumize grub config. For enabling os-prober etc.."
            sudo nano -w /etc/default/grub
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
install_virt-manager() {
   echo "Installing virt-manager..."
   sudo pacman -Sy
   sudo pacman -S --needed --noconfirm virt-manager qemu libvirt dnsmasq bridge-utils
   sudo systemctl enable libvirtd.service
   sudo systemctl start libvirtd.service
   sudo virsh net-autostart default
   sudo virsh net-start default
   sudo usermod -aG libvirt $(whoami)
   echo "virt-manager installed successfully!"
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
install_ventoy() {
    
    echo "Starting install ventoy..."
   sudo pacman -S --needed --noconfirm ventoy-bin
 
    echo "ventoy installed successfully!"
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
        4) install_make-tools ;;
        5) install_programs ;;
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
       16) install_final-steps ;;
       17) install_arch_to_cachyos_converter ;;
       18) install_nfs_server ;;  
       19) install_nfs_client ;;  
       20) install_samba ;;
       21) install_virt-manager ;; 
       22) install_libreoffice ;;  
       23) install_ventoy ;;  
         0) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option! Please try again." ;;
    esac
done
