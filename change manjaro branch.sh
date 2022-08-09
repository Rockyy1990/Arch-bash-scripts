#!/usr/bin/env bash

echo "Change Manjaro Branch"
echo "stable unstable & testing"
sudo pacman-mirrors --api --set-branch unstable

sudo pacman-mirrors --country Germany
sudo pacman -Syyu

echo "Done.. reboot after 6 seconds"
sleep 6
reboot



