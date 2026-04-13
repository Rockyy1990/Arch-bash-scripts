#!/bin/bash

echo ""
read -p "This script makes an reset of Plasma Desktop if its crashs sometimes..
                    Press any key to continue..
"
clear

rm -rf ~/.cache/plasmashell/
rm -rf ~/.config/plasma*
rm -rf ~/.config/kdedefaults
sudo pacman -S --noconfirm plasma-workspace-wallpapers
sudo pacman -S --noconfirm plasma-desktop
sudo pacman -Syu

echo ""
echo "Now the system will do an reboot after 10 seconds..."
echo "After this all should work without crashs."
sleep 10
sudo reboot
