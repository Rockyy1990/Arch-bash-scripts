#!/usr/bin/env bash

# Last edit: 20.02.2025 

echo ""
echo "---------------------------------------------------"
echo "        ..Archlinux config after install..         "
echo "                Virt-Manager (Qemu)                "
echo "---------------------------------------------------"
sleep 3
echo ""
echo "         !!You should read this script first!!
"

read -p "
    Enable IOMMU: Make sure IOMMU is enabled in your BIOS/UEFI settings.

Kernel Parameters: Add the following to your kernel parameters in /etc/default/grub:

    For Intel: intel_iommu=on
    For AMD: amd_iommu=on

Then run sudo grub-mkconfig -o /boot/grub/grub.cfg and reboot.

    If the parameters already set than press any key to continue.
"

sudo pacman -S --needed --noconfirm virt-manager libvirt qemu qemu-tools libguestfs vulkan-virtio spice-vdagent dnsmasq vde2 bridge-utils openbsd-netcat

echo " The tpm packages are needed for an win11 vm"
sudo pacman -S --needed tpm2-tools tpm2-tss swtpm python-tpm2-pytss

sudo systemctl enable --now libvirtd

# Add current user to the libvirt group
USER=$(whoami)

echo "Adding user $USER to the libvirt group..."
sudo usermod -aG libvirt $USER

# Configure default network for libvirt
echo "Configuring default network..."

sudo virsh net-start default
sudo virsh net-autostart default

# Check if IOMMU is enabled (optional)
if grep -q "intel_iommu=on" /proc/cmdline || grep -q "amd_iommu=on" /proc/cmdline; then

    echo "IOMMU is enabled."
else
    echo "IOMMU is not enabled. Please enable it in your BIOS/UEFI settings and add the appropriate kernel parameters."

fi


echo "Virt-Manager installed successfully!"



