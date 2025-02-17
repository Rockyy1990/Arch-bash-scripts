#!/usr/bin/env bash

# Last edit: 17.02.2025 

echo ""
echo "----------------------------------------------"
echo "    ..Archlinux config after install..        "
echo "                Gaming                        "
echo "----------------------------------------------"
sleep 3
echo ""
echo "      !!You should read this script first!!
"

echo "
  Installs:
 AMD or NVIDIA gpu driver
 Vulkan api
 Wine
 Steam Gaming Platform
 Protonup-qt (Steam Proton downloader)
 Set /etc/environment variable
"

read -p "Press any key to continue.."

# Installing amd-gpu-driver
sudo pacman -S --noconfirm mesa lib32-mesa mesa-utils libva libdrm lib32-libdrm 
sudo pacman -S --needed --noconfirm xf86-video-amdgpu mesa lib32-mesa glu lib32-glu libvdpau-va-gl 
sudo pacman -S --needed --noconfirm opencl-icd-loader ocl-icd lib32-ocl-icd rocm-opencl-runtime
    
# Install Vulkan drivers
sudo pacman -S --needed --noconfirm vulkan-radeon lib32-vulkan-radeon vulkan-swrast vulkan-icd-loader lib32-vulkan-icd-loader 
sudo pacman -S --needed --noconfirm vulkan-validation-layers vulkan-mesa-layers lib32-vulkan-mesa-layers vulkan-headers
    

# Disable GPU polling
echo -e "options drm_kms_helper poll=0" | sudo tee /etc/modprobe.d/disable-gpu-polling.conf



# Installing nvidia-gpu-driver
# sudo pacman -S --needed --noconfirm nvidia nvidia-utils lib32-nvidia-utils opencl-nvidia lib32-opencl-nvidia 
# sudo pacman -S --needed --noconfirm libxnvctrl libvdpau vulkan-icd-loader lib32-vulkan-icd-loader nvidia-settings


# Installing wine
sudo pacman -S --needed --noconfirm wine wine-mono wine-gecko winetricks libgdiplus vkd3d lib32-vkd3d cabextract zenity
   
   
# Installing steam
sudo pacman -S --needed --noconfirm steam steam-native-runtime protontricks-git gamemode lib32-gamemode openal lib32-openal lib32-fontconfig libldap lib32-libldap 

sudo pacman -S --needed --noconfirm mpg123 lib32-mpg123 v4l-utils lib32-v4l-utils lib32-libpulse lib32-alsa-plugins sqlite lib32-sqlite 
sudo pacman -S --needed --noconfirm gnutls lib32-gnutls libgpg-error lib32-libgpg-error  libjpeg-turbo lib32-libjpeg-turbo 
sudo pacman -S --needed --noconfirm lib32-libgcrypt libgcrypt ncurses lib32-ncurses lib32-opencl-icd-loader
sudo pacman -S --needed --noconfirm libxslt lib32-libxslt lib32-libva gtk3 lib32-gtk3 lib32-gst-plugins-base-libs  

sudo pacman -S --needed --noconfirm lib32-sdl2 lib32-alsa-lib lib32-giflib lib32-gnutls lib32-libglvnd lib32-libldap      
sudo pacman -S --needed --noconfirm lib32-libxcursor lib32-gnutls lib32-libvdpau libvdpau
 
sudo pacman -S protonup-qt

echo "
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
PROTON_USE_FSYNC=1
DXVK_ASYNC=1
WINE_FSR_OVERRIDE=1
WINE_FULLSCREEN_FSR=1
WINE_VK_USE_FSR=1
WINEFSYNC_FUTEX2=1
WINEFSYNC_SPINCOUNT=24
MESA_BACK_BUFFER=ximage
MESA_NO_DITHER=0
MESA_SHADER_CACHE_DISABLE=false
mesa_glthread=true
MESA_DEBUG=0
MESA_VK_ENABLE_SUBMIT_THREAD=1
STAGING_SHARED_MEMORY=1
STAGING_AUDIO_PERIOD=13333
STAGING_RT_PRIORITY_BASE=2
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
echo -e "Postconfig (Gaming) is complete."
sleep 3
exit