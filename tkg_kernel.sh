#!/usr/bin/env bash

# Last edit: 21.02.2025 

echo ""
echo "----------------------------------------------"
echo "           Installing TKG Kernel              "
echo "                                              "
echo "----------------------------------------------"
echo "
# For general desktop use, 
# the TKG kernel can provide a more responsive and efficient experience as the stock kernel.
"
sleep 2
echo ""
echo " IMPORTENT!! Read this script before execute !"
echo ""
echo "
# Keep in mind building recent linux kernels with GCC will require ~20-25GB of disk space. 
# Using llvm/clang, LTO, ccache and/or enabling more drivers in the defconfig will push that requirement higher, 
# so make sure you have enough free space on the volume you're using to build.

# Nvidia's proprietary drivers might need to be patched if they don't support your chosen kernel OOTB: 
# Frogging-Family nvidia-all can do that automatically for you.

# Note regarding kernels older than 5.9 on Arch Linux: since the switch to zstd compressed initramfs by default, 
# you will face an invalid magic at start of compress error by default. 
# You can workaround the issue by editing /etc/mkinitcpio.conf to uncomment the COMPRESSION="lz4" (for example, 
# since that's the best option after zstd) line and regenerating initramfs for all kernels with sudo mkinitpcio -P

# The script will use a slightly modified Arch config from the linux-tkg-config folder, 
# it can be changed through the _configfile variable in customization.cfg. 
# The options selected at build-time are installed to /usr/share/doc/$pkgbase/customization.cfg, where $pkgbase is the package name.

# Note: the base-devel package group is expected to be installed, see here for more information.
# Optional: edit the  customization.cfg  file
"
echo ""
read -p "Press any key to continue.."
clear

echo ""
echo " Installing the tkg linux kernel..."
sleep 1
git clone https://github.com/Frogging-Family/linux-tkg.git
cd linux-tkg
makepkg -si
sudo mkinitpcio -P
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo ""
read -p "All done. Press any key to reboot the system."
sudo reboot