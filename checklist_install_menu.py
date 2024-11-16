#!/usr/bin/env python

import os
import subprocess

# Available packages for installation
packages = {
    "1": "vim",
    "2": "git",
    "3": "curl",
    "4": "htop",
    "5": "tmux",
    "6": "python",
}

# Selected packages
selected_packages = []

def print_menu():
    os.system('clear')  # Clear the terminal screen
    print("Arch Linux Interactive Install Menu")
    print("Select packages to install (press Enter to toggle selection):")
    print("Press 'c' to continue or 'q' to quit.")
    print()
    
    for key, package in packages.items():
        prefix = "[x]" if key in selected_packages else "[ ]"
        print(f"{prefix} {key}. {package}")

def toggle_selection(package_key):
    # Toggle the selection of a package
    if package_key in selected_packages:
        selected_packages.remove(package_key)
    else:
        selected_packages.append(package_key)

def install_packages():
    if not selected_packages:
        print("No packages selected.")
        return
    
    pkg_list = ' '.join([packages[key] for key in selected_packages])
    print(f"Installing packages: {pkg_list}")
    
    # Uncomment the next line to actually install packages
    # subprocess.run(['sudo', 'pacman', '-S', '--noconfirm'] + pkg_list.split())
    print("Packages installed!")  # Mock message for safety

def main():
    while True:
        print_menu()
        choice = input("Select a package by number (or 'c' to continue, 'q' to quit): ").strip()
        
        if choice.lower() == 'q':
            print("Exiting...")
            break
        elif choice.lower() == 'c':
            install_packages()
            break
        elif choice in packages:
            toggle_selection(choice)
        else:
            print("Invalid selection. Please try again.")

if __name__ == "__main__":
    main()