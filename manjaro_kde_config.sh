#!/usr/bin/env bash

echo ""
echo "Manjaro KDE Minimal config"
read -p "Press any key to continue.."
clear

sudo pamac remove -y firefox micro timeshift vlc
clear

sudo pamac upgrade -a
clear


sudo pamac install -y base-devel binutils fakeroot ccache irqbalance ventoy smb4k yay flatpak flatpak-xdg-utils libpamac-flatpak-plugin
sudo pamac install -y gnome-disk-utility mtools f2fs-tools xfsdump irqbalance 

sudo pamac install -y opencl-mesa vulkan-mesa-layers vulkan-extra-layers vulkan-validation-layers vulkan-dzn vulkan-swrast

sudo pamac install -y vivaldi vivaldi-ffmpeg-codecs gstreamer-vaapi gst-plugin-va discord celluloid soundconverter handbrake strawberry yt-dlp pavucontrol pipewire-v4l2 pipewire-zeroconf

sudo pamac install -y wine wine-mono wine-gecko winetricks
sudo pamac install -y steam steam-native-runtime python-steam protontricks protonup-qt vkd3d libgdiplus openal gamemode lib32-gamemode
clear

yay -S --noconfirm faudio ttf-ms-fonts nomachine


read -p "If you wont you can now install makemkv and libdvdcss.."
yay -S jre-openjdk makemkv makemkv-libaacs libdvdcss
clear

read -p "If you wont you can now istall the Linux Mint Icons and Themes.."
sudo pamac install mint-l-icons mint-l-theme
yay -S mint-backgrounds-tina mint-backgrounds-victoria
clear


echo "hrtf = true" | sudo tee -a  ~/.alsoftrc
sudo systemctl enable irqbalance


# Environment variables
echo "
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

# Reload libraries
sudo ldconfig

sudo systemctl enable fstrim.timer
sudo fstrim -av

sudo pamac clean

clear
echo "Config is now complete."
read -p "Press any key to reboot Manjaro"
sudo reboot
