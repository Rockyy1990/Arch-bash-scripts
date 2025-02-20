#!/usr/bin/env bash

# Last edit: 20.02.2025 

echo ""
echo "----------------------------------------------"
echo "    ..Archlinux config after install..        "
echo "              .. Gaming ..                    "
echo "----------------------------------------------"
sleep 3
echo ""
echo "      !!You should read this script first!!
"

echo "
 Installs:
 Wine ..optional..
 Wine-tkg-staging  ..optional..
 Steam Gaming Platform
 Protonup-qt (Steam Proton downloader) ..optional..
 Bottles (Wine management GUI tool) ..optional..
 Heroic-games-launcher  ..optional..
 Umu-launcher ..optional..
 Set /etc/environment variable
"

read -p "Press any key to continue.."


# Installing wine (Windows support)
sudo pacman -S --needed wine 
   
# wine with TkG-Staging patches and multilib support
yay -S --needed wine-tkg-staging-bin 

# Additional packages for Wine
sudo pacman -S --needed winetricks libgdiplus vkd3d lib32-vkd3d cabextract zenity


# Installing steam with some extra packages
sudo pacman -S --needed --noconfirm steam steam-native-runtime protontricks-git gamemode lib32-gamemode lib32-fontconfig libldap lib32-libldap 

sudo pacman -S --needed --noconfirm mpg123 lib32-mpg123 v4l-utils lib32-v4l-utils lib32-libpulse lib32-alsa-plugins sqlite lib32-sqlite 
sudo pacman -S --needed --noconfirm gnutls lib32-gnutls libgpg-error lib32-libgpg-error  libjpeg-turbo lib32-libjpeg-turbo 
sudo pacman -S --needed --noconfirm lib32-libgcrypt libgcrypt ncurses lib32-ncurses lib32-opencl-icd-loader
sudo pacman -S --needed --noconfirm libxslt lib32-libxslt lib32-libva gtk3 lib32-gtk3 lib32-gst-plugins-base-libs  

sudo pacman -S --needed --noconfirm lib32-sdl2 lib32-alsa-lib lib32-giflib lib32-gnutls lib32-libglvnd     
sudo pacman -S --needed --noconfirm lib32-libxcursor lib32-gnutls
 
# Proton-GE downloader
sudo pacman -S --needed protonup-qt


# Wine managing gui tool
sudo pacman -S --needed bottles

# Open source Launcher for Epic, Amazon and GOG Games
yay -S --needed heroic-games-launcher-bin

# Unified Launcher for Windows Games on Linux, to run Proton with fixes outside of Steam
yay -S --needed umu-launcher


# System optimizazions for /etc/environment
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
" | sudo tee -a /etc/environment


clear
echo ""
echo -e "
----------------------------------
Postconfig (Gaming) is complete.
System reboot after 6 seconds..
----------------------------------
"
sleep 6
sudo reboot
