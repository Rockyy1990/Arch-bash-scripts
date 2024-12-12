#!/usr/bin/env bash

echo "                      Read this script before execute!!"
read -p " This script installs the Plasma Desktop. Press any key to continue.."

# Update the system
echo "Updating the system..."
sudo pacman -Syyu --noconfirm


# Install Plasma Desktop
echo "Installing Plasma Desktop..."
sudo pacman -S --needed plasma-desktop plasma-nm plasma-pa plasma-workspace plasma-integration plasma-firewall kpipewire plasma-widgets-addons plasma-thunderbolt plasma-vault 
sudo pacman -S --needed wayland xorg-xwayland wayland-protocols plasma-wayland-protocols wlroots plasma-wayland-session
sudo pacman -S --needed plasma-disks
sudo pacman -S sddm
sudo pacman -S --needed --noconfirm xdg-utils xdg-desktop-portal

# Install additional packages for performance
echo "Installing additional packages for performance..."
sudo pacman -S --needed kdegraphics-thumbnailers kdeplasma-addons kio-extras kio-gdrive kio-zeroconf kdeconnect kde-gtk-config 


# Install fonts for better rendering
echo "Installing fonts for better rendering..."
sudo pacman -S --needed noto-fonts ttf-dejavu ttf-hack ttf-liberation ttf-ubuntu-font-family 


# Configure Plasma Desktop for performance
echo "Configuring Plasma Desktop for performance..."
sudo sed -i 's/CompositingType = OpenGL 3.1/CompositingType = OpenGL 2.0/g' /etc/xdg/kdeglobals
sudo sed -i 's/OpenGLIsUnsafe = false/OpenGLIsUnsafe = true/g' /etc/xdg/kdeglobals


# Disable animations for better performance
echo "Disabling animations for better performance..."
sudo sed -i 's/AnimationDurationFactor = 1/AnimationDurationFactor = 0/g' /etc/xdg/kdeglobals


# Set the default desktop layout
echo "Setting the default desktop layout..."
sudo sed -i 's/LayoutName = Default/LayoutName = Netbook/g' /etc/xdg/kdeglobals


# Enable SDDM as the display manager
# echo "Enabling SDDM as the display manager..."
# sudo systemctl enable sddm


read -p "Plasma Desktop is now installed. Press any key to reboot"

# Reboot the system
echo "Rebooting the system..."
sudo reboot