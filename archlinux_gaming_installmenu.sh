#!/usr/bin/env bash

# Function to display the menu
show_menu() {
    clear
    echo "----------------------------------------------"
    echo "    ..Archlinux config after install..        "
    echo "              .. Gaming ..                    "
    echo "----------------------------------------------"
    echo ""
    echo "      !!You should read this script first!!"
    echo ""
    echo "Please choose an option:"
    echo "1) Install Wine"
    echo "2) Install Wine-tkg-staging"
    echo "3) Install Steam"
    echo "4) Install Protonup-qt"
    echo "5) Install Bottles"
    echo "6) Install Heroic Games Launcher"
    echo "7) Install Umu Launcher"
    echo "8) Set /etc/environment variables"
    echo "9) Exit"
}

# Function to install packages
install_packages() {
    sudo pacman -S --needed --noconfirm "$@"
}

# Function to install AUR packages using yay
install_aur_packages() {
    yay -S --needed --noconfirm "$@"
}

# Function to set environment variables
set_environment_variables() {
    # Check if the environment variables are already set
    if grep -q "STEAM_RUNTIME_HEAVY" /etc/environment; then
        echo "Environment variables are already set."
        return
    fi

    echo "
STEAM_RUNTIME_HEAVY=1
STEAM_FRAME_FORCE_CLOSE=0
GAMEMODE=1
vblank_mode=1
PROTON_LOG=0
PROTON_USE_WINED3D=0
PROTON_FORCE_LARGE_ADDRESS_AWARE=1
PROTON_USE_FSYNC=1
DXVK_ASYNC=1
WINE_FSR_OVERRIDE=1
WINE_FULLSCREEN_FSR=1
WINE_VK_USE_FSR=1
WINEFSYNC_SPINCOUNT=24
MESA_BACK_BUFFER=ximage
MESA_NO_DITHER=1
MESA_SHADER_CACHE_DISABLE=false
mesa_glthread=true
MESA_DEBUG=0
MESA_VK_ENABLE_SUBMIT_THREAD=1
STAGING_SHARED_MEMORY=1
ANV_ENABLE_PIPELINE_CACHE=1
LIBGL_DEBUG=0
LIBGL_THROTTLE_REFRESH=1
LIBC_FORCE_NOCHECK=1
__GLX_VENDOR_LIBRARY_NAME=mesa
__GLVND_DISALLOW_PATCHING=0
__GL_THREADED_OPTIMIZATIONS=1
__GL_SHADER_DISK_CACHE=0
__GL_MaxFramesAllowed=1
__GL_VRR_ALLOWED=0
" | sudo tee -a /etc/environment > /dev/null

    echo "Environment variables set."
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice [1-9]: " choice

    case $choice in
        1)
            install_packages wine
            echo "Wine installed."
            ;;
        2)
            install_aur_packages wine-tkg-staging-bin
            echo "Wine-tkg-staging installed."
            ;;
        3)
            install_packages steam steam-native-runtime protontricks-git gamemode lib32-gamemode lib32-fontconfig libldap lib32-libldap \
            mpg123 lib32-mpg123 v4l-utils lib32-v4l-utils lib32-libpulse lib32-alsa-plugins sqlite lib32-sqlite \
            gnutls lib32-gnutls libgpg-error lib32-libgpg-error libjpeg-turbo lib32-libjpeg-turbo \
            lib32-libgcrypt libgcrypt ncurses lib32-ncurses lib32-opencl-icd-loader \
            libxslt lib32-libxslt lib32-libva gtk3 lib32-gtk3 lib32-gst-plugins-base-libs \
            lib32-sdl2 lib32-alsa-lib lib32-giflib lib32-gnutls lib32-libglvnd \
            lib32-libxcursor lib32-gnutls
            echo "Steam installed."
            ;;
        4)
            install_packages protonup-qt
            echo "Protonup-qt installed."
            ;;
        5)
            install_packages bottles
            echo "Bottles installed."
            ;;
        6)
            install_aur_packages heroic-games-launcher-bin
            echo "Heroic Games Launcher installed."
            ;;
        7)
            install_aur_packages umu-launcher
            echo "Umu Launcher installed."
            ;;
        8)
            set_environment_variables
            ;;
        9)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac

    read -p "Press any key to continue..."
done
