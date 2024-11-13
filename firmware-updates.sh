#!/bin/bash

sudo pacman -S --needed --noconfirm fwupd fwupd-efi

read -p "Firmware updates. Press any key to continue.."

sudo fwupdmgr get-devices
sudo fwupdmgr refresh --force
sudo fwupdmgr get-updates -y
sudo fwupdmgr update -y