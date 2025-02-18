#!/usr/bin/env bash

echo "
Installing refind bootloader for manjaro. 
Read this script before execute !!
"
sleep 2
echo ""

read -p "Press any key to continue.."


# Troubleshooting Blank Screen: 
# If you encounter a blank screen, ensure that the dont_scan_volumes option in refind.conf is set correctly to avoid scanning unnecessary partitions.

# Secure Boot Considerations: 
# If you are using Secure Boot, additional steps may be required to sign rEFInd and its drivers.

# You don't necessarily need to remove GRUB when installing rEFInd as the default bootloader on Manjaro Linux. 
# However, if rEFInd works well for your setup, you can safely remove GRUB to avoid conflicts, 
# but ensure you have a backup and that rEFInd is properly configured first.


sudo pacman -S --needed --noconfirm refind

sudo pacman -S --needed --noconfirm os-prober ntfs-3g efibootmgr

sudo refind-install

sudo refind-mkdefault


#Copy Necessary Files (if needed)
#Ensure that the necessary files are in the correct directories:

# sudo mkdir -pv /boot/efi/EFI/refind/drivers_x64 /boot/efi/EFI/BOOT/drivers_x64
# sudo cp -v /usr/share/refind/refind_x64.efi /boot/efi/EFI/refind/
# sudo cp -v /usr/share/refind/drivers_x64/* /boot/efi/EFI/refind/drivers_x64/

sleep 3
sudo reboot




