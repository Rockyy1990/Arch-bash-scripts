#!/bin/bash

# Update the package repositories
sudo pacman -Sy

# Install the cronie package
sudo pacman -S --needed --noconfirm cronie

# Enable and start the cronie service
sudo systemctl enable cronie.service
sudo systemctl start cronie.service

# Configure system to update every 8 days
sudo echo "0 0 */8 * * sudo pacman -Syu" >> /etc/crontab

read -p "System configured to update every 8 days"
