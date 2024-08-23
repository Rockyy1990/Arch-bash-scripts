#!/bin/bash

# Function to display the menu
display_menu() {
    clear
    echo "------------------------------------------------------"
    echo "      Archlinux Post-Installer               "
    echo "----------------------------------------------------- "
    echo "1)  Install Chaotic-AUR"
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
    echo "0) EXIT"
    echo "--------------------------------------"
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
    
    echo "Ranking Mirrors.."
    sleep 2
    sudo pacman -S --needed --noconfirm reflector rsync curl
    sudo reflector --verbose --country 'Germany' -l 14 --sort rate --save /etc/pacman.d/mirrorlist
    sudo nano /etc/pacman.d/mirrorlist
    
    read -p "Press any key to costumize pacman.conf."
    sudo nano -w /etc/pacman.conf

    sudo pacman -Sy

    echo "chaotic-aur installed successfully!"
    read -p "Press [Enter] to continue..."
}


# Function to install a package
install_needed-packages() {
    echo "Installing Needed-packages..."
    sudo pacman -S --needed --noconfirm  update-grub mintstick
    sudo pacman -S --needed --noconfirm timeshift timeshift-autosnap 
    sudo pacman -S --needed --noconfirm pacman-contrib lrzip unrar unzip unace p7zip dbus-broker zstd nss fuse2 fuseiso samba
    sudo pacman -S --needed --noconfirm ttf-dejavu ttf-opensans freetype2 ttf-droid ttf-liberation ubuntu-font-family
    sudo pacman -S --needed --noconfirm xorg-xkill xorg-xinput xorg-xrandr libwnck3 libxcomposite lib32-libxcomposite libxinerama lib32-libxrandr lib32-libxfixes
    sudo pacman -S --needed --noconfirm hdparm sdparm gvfs mtools f2fs-tools hwdetect sof-firmware fwupd cpupower bash-completion
    sudo pacman -S --needed --noconfirm xdg-utils xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs
    
    sudo systemctl enable --now cpupower.service
    sudo cpupower frequency-set -g performance
    sudo systemctl enable --now dbus-broker.service

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
    echo "$PACKAGE ist bereits installiert."
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
    
    # Name des Pakets, das überprüft werden soll
    PACKAGE="blueman"

    # Überprüfen, ob das Paket installiert ist
    if pacman -Qs "^$PACKAGE" > /dev/null; then
    echo "$PACKAGE is already installed."
    else
    read -p "$PACKAGE is not installed. blueman (Gui for bluetooth) install now? (ja/nein): " antwort

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

  # Name des Pakets, das überprüft werden soll
   PACKAGE="easyeffects"

  # Überprüfen, ob das Paket installiert ist
  if pacman -Qs "^$PACKAGE" > /dev/null; then
    echo "$PACKAGE is already installed."
  else
    read -p "$PACKAGE not installed. Easyeffects install now? (ja/nein): " antwort

    case $antwort in
        [Jj]|[Jj][Aa])
            # Paket installieren
            sudo pacman -S --noconfirm "$PACKAGE"
            echo "$PACKAGE installed."
            ;;
        [Nn]|[Nn][Ee])
            echo "Install of $PACKAGE cancelled."
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
    sudo pacman -S --needed --noconfirm xf86-video-amdgpu mesa lib32-mesa rocm-opencl-runtime ocl-icd lib32-ocl-icd lib32-mesa-vdpau mesa-vdpau libva-mesa-driver lib32-mesa-vdpau opencl-icd-loader

    # Install Vulkan drivers
    sudo pacman -S --needed --noconfirm vulkan-radeon lib32-vulkan-radeon vulkan-mesa-layers vulkan-icd-loader lib32-vulkan-icd-loader
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
    sudo pacman -S --needed --noconfirm wine wine-mono wine-gecko winetricks libgdiplus vkd3d lib32-vkd3d  openal lib32-openal cabextract zenity
    #!/bin/bash

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
    
    # Enable Steam Play (Proton) for all titles
    echo "Enable Steam Play for all titles"
    echo "Please restart Steam after running this script"
    sed -i 's/\"enabled\".false/\"enabled\".true/' ~/.steam/root/config/config.vdf

    # Increase the processor count
    export PROTON_USE_WINED3D=1
    export PROTON_NO_ESYNC=1
    
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
    
    echo "Starting install chromium browser..."
   sudo pacman -S --needed --noconfirm firefox firefox-i18n-de
 
    echo "firefox  installed successfully!"
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
    
    echo "The final steps are done! Please reboot archlinux now"
    read -p "Press [Enter] to continue..."
}




# Main script loop
while true; do
    display_menu
    read -p "Select an option [0-16]: " option

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
        0) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option! Please try again." ;;
    esac
done
