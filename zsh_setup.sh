#!/bin/bash

# Update the package database
echo "Updating the package database..."
sudo pacman -Syu --noconfirm

# Install Zsh and oh-my-zsh
echo "Installing Zsh..."
sudo pacman -S zsh --noconfirm

# Set Zsh as the default shell
echo "Setting Zsh as the default shell..."
chsh -s $(which zsh)

# Optional: Install Git if you want to clone oh-my-zsh
if ! command -v git &> /dev/null; then
    echo "Installing Git..."
    sudo pacman -S git --noconfirm
fi

# Install Oh My Zsh
echo "Installing Oh My Zsh..."
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Change Zsh configuration if necessary
# This will copy the default .zshrc configuration
echo "Copying default Zsh configuration..."
cp ~/.zshrc ~/.zshrc.bak  # Backup existing .zshrc if it exists
cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc

# Notify the user
echo "Zsh has been installed and set as the default shell."
echo "You may need to log out and back in for changes to take effect."

# Optional: Start zsh now
echo "Starting Zsh..."
exec zsh


