#!/usr/bin/env bash

read -p "Fix for: libGL: Can't open configuration file /etc/drirc: No such file or directory.
                        Read this script before execute!!
                            Press any key to continue.."

# "create a basic drirc file to avoid this error."
sudo touch /etc/drirc


# User -Specific Configuration: If you want to create a user-specific configuration.
# You can create a .drirc file in your home directory:
# touch ~/.drirc

# Reinstalling the drivers
sudo pacman -Syu
sudo pacman -S mesa lib32-mesa
sudo pacman -S mesa-utils
sudo pacman -S libdrm lib32-libdrm

sudo pacman -S vulkan-radeon


# If you notice that symlinks for libdrm_amdgpu are pointing to the wrong library, you can correct them.
sudo ln -sf /usr/lib/libdrm_amdgpu.so.1.0.0 /usr/lib/libdrm_amdgpu.so.1

export LD_LIBRARY_PATH=/usr/lib:$LD_LIBRARY_PATH

source ~/.bashrc


# Kernel Mode Setting (KMS): If you continue to experience issues, 
# consider adding amdgpu to the modules line in /etc/mkinitcpio.conf, regenerating the initramfs, and rebooting:

# sudo nano /etc/mkinitcpio.conf

# Add amdgpu to the MODULES line, then run:

# sudo mkinitcpio -P