#!/usr/bin/env python

import os
import subprocess

# Define the list of packages
packages = {
    1: "vim",
    2: "git",
    3: "htop",
    4: "curl",
    5: "neofetch",
    6: "firefox",
    7: "gimp",
    8: "vlc",
    9: "docker",
    10: "python",
    11: "nodejs",
    12: "ruby"
}

def print_menu():
    print("\n=== Arch Linux Package Installer ===")
    print("Select packages to install (separate with space, e.g., 1 3 5):")
    for key, value in packages.items():
        print(f"{key}. {value}")

def install_packages(selected_packages):
    if not selected_packages:
        print("No packages selected for installation.")
        return

    package_names = ' '.join(selected_packages)
    command = f"sudo pacman -S --needed --noconfirm {package_names}"

    try:
        print(f"\nInstalling packages: {package_names}...")
        subprocess.run(command, shell=True, check=True)
        print("Installation complete.")
    except subprocess.CalledProcessError as e:
        print(f"An error occurred during installation: {e}")

def main():
    print_menu()
    
    user_input = input("Enter your choices: ")
    selected_indices = user_input.split()

    # Convert indices to package names
    selected_packages = [packages[int(index)] for index in selected_indices if index.isdigit() and int(index) in packages]

    install_packages(selected_packages)

if __name__ == "__main__":
    main()
