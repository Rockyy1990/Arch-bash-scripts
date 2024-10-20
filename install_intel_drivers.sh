#!/bin/bash

read -p "Press [Enter] to install the intel graphics driver"

# Configure Video Drivers...

# Intel Driver
sudo pacman -S --needed --noconfirm xf86-video-intel intel-media-driver intel-gmmlib intel-gpu-tools ocl-icd lib32-ocl-icd lib32-mesa-vdpau mesa-vdpau libva-mesa-driver lib32-mesa-vdpau opencl-icd-loader

# Install Vulkan drivers
sudo pacman -S --needed --noconfirm vulkan-intel vulkan-mesa-layers vulkan-icd-loader lib32-vulkan-icd-loader

echo ""
echo " Install complete"
sleep 3
exit

