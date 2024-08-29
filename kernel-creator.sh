#!/usr/bin/env bash

set -e

read -p "Read this script before execute !! 
The default dir for the kernel source is /home/(user)/Downloads"

sudo pacman -S --needed --noconfirm base-devel gcc make bc cpio

export CFLAGS='-march=native'
export CXXFLAGS='-march=native'
export ARCH='x86_64'

# Define the directory containing the extracted kernel sources
KERNEL_SOURCES_DIR="/home/lxadmin/Downloads/"

# Array to hold the kernel source directories
kernels=()
choices=()

# Gather the kernel folders available in the given directory
while IFS= read -r -d '' kernel; do
    kernels+=("$kernel")
    choices+=("$(basename "$kernel")")
done < <(find "$KERNEL_SOURCES_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

# Display a menu for the user to select a kernel source
PS3="Select a kernel to compile: "
select choice in "${choices[@]}"; do
    if [[ -n "$choice" ]]; then
        echo "You selected $choice"
        break
    else
        echo "Invalid choice. Please try again."
    fi
done

# Get the selected kernel source directory
selected_kernel="${kernels[$REPLY-1]}"

# Change to the kernel source directory
cd "$selected_kernel"

# Clean previous builds if any
make mrproper
make clean

# Prepare the kernel configuration
# You might want to adjust this to use your specific config
make menuconfig

# Start the kernel compilation process with optimizations
# The `-j` flag tells make to use multiple jobs.
 make -j$(nproc)
make modules -j$(nproc)

# Install the compiled kernel
sudo  make modules_install 
sudo make install 

sudo grub-mkconfig -o /boot/grub/grub.cfg

make clean


echo "$(pwd) is now compiled and installed"

