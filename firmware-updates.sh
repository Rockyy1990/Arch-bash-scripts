#!/bin/bash

echo ""
sudo pacman -S --needed --noconfirm fwupd fwupd-efi
clear

echo ""
read -p "Firmware updates. Press any key to continue.."
clear

echo ""
sudo fwupdmgr get-devices
sudo fwupdmgr refresh --force
sleep 3

echo ""
echo "Hole Firmware updates..."
sudo fwupdmgr get-updates -y

echo ""
echo "Führe firmware updates aus..."
sudo fwupdmgr update -y

echo ""
echo "Fertig. Das System wird nun neu gestartet.."
sleep 4
sudo reboot
