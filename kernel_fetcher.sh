#!/bin/bash

# Define color variables for bright green, bright red, and reset
BOLD_BRIGHT_GREEN="\e[1;92m"
BOLD_BRIGHT_RED="\e[1;91m"
RESET="\e[0m"

# Clear the terminal and enable immediate script exit on errors
clear
set -e

# Function to print messages in bright green
print_green() {
    echo -e "${BOLD_BRIGHT_GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${RESET}"
}

# Function to print kernel version in bright red bold
print_red_bold() {
    echo -e "${BOLD_BRIGHT_RED}$1${RESET}"
}

sudo pacman -S --needed --noconfirm clang compiler-rt

# Variables
KERNEL_DIR="$HOME/kernel_build"
KERNEL_BASE_URL="https://cdn.kernel.org/pub/linux/kernel"
CURRENT_KERNEL_VERSION=$(uname -r | cut -d '-' -f1)  # Extract major.minor version
MAJOR_VERSION=$(echo "$CURRENT_KERNEL_VERSION" | cut -d '.' -f1)  # Major version (e.g., 6)
LATEST_KERNEL_VERSION=""
LATEST_KERNEL_TARBALL=""

# Function to get the latest kernel version from kernel.org
get_latest_kernel_version() {
    print_green "Fetching the latest kernel version from cdn.kernel.org..."

    local version_list
    version_list=$(wget -qO- "$KERNEL_BASE_URL/v${MAJOR_VERSION}.x/" | \
        grep -oP 'linux-\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -n 1)

    if [ -z "$version_list" ]; then
        print_green "Failed to fetch the latest kernel version. Exiting."
        exit 1
    fi

    LATEST_KERNEL_VERSION=$version_list
    LATEST_KERNEL_TARBALL="linux-${LATEST_KERNEL_VERSION}.tar.xz"

    print_green "Latest kernel version found: $(print_red_bold "$LATEST_KERNEL_VERSION")"
}

# Function to check if the latest kernel version is already installed
check_existing_kernel() {
    local current_kernel
    current_kernel=$(uname -r | cut -d '-' -f1)
    if [ "$current_kernel" == "$LATEST_KERNEL_VERSION" ]; then
        print_green "The most recent kernel version is installed: $(print_red_bold "$LATEST_KERNEL_VERSION")"
        exit 0
    fi
}

# Function to download and extract the kernel source
download_kernel() {
    print_green "Downloading Linux Kernel $LATEST_KERNEL_VERSION..."
    mkdir -p "$KERNEL_DIR"
    cd "$KERNEL_DIR" || { print_green "Failed to change directory to $KERNEL_DIR. Exiting."; exit 1; }

    local kernel_url="$KERNEL_BASE_URL/v${MAJOR_VERSION}.x/${LATEST_KERNEL_TARBALL}"

    # Show progress bar while downloading
    wget -q --show-progress --progress=bar:force "$kernel_url" -O "$LATEST_KERNEL_TARBALL"

    # Check if download succeeded
    if [ ! -f "$LATEST_KERNEL_TARBALL" ]; then
        print_green "Failed to download kernel source from $kernel_url. Exiting."
        exit 1
    fi

    tar -xf "$LATEST_KERNEL_TARBALL" || { print_green "Failed to extract kernel source. Exiting."; exit 1; }
    cd "linux-${LATEST_KERNEL_VERSION}" || { print_green "Failed to change directory to linux-${LATEST_KERNEL_VERSION}. Exiting."; exit 1; }
}

# Function to extract and update the current kernel configuration
extract_and_update_config() {
    print_green "Extracting current kernel configuration..."

    if [ -f /proc/config.gz ]; then
        if ! zcat /proc/config.gz > .config; then
            print_green "Failed to extract kernel configuration. Exiting."
            exit 1
        fi
    else
        print_green "/proc/config.gz not found. Using default configuration."
        if ! make defconfig; then
            print_green "Failed to create default configuration. Exiting."
            exit 1
        fi
    fi

    print_green "Kernel configuration extracted successfully!"
}

# Function to compile the kernel
compile_kernel() {
    print_green "Preparing to compile the kernel..."

    # Set architecture to x86_64
    #export ARCH=x86_64
    

    # Update the configuration to reflect new kernel options
    print_green "Updating kernel configuration..."
    if ! make olddefconfig; then
        print_green "Failed to update kernel configuration. Exiting."
        exit 1
    fi

    # Compile the kernel
    print_green "Compiling the kernel..."
    if ! make -j"$(nproc)"; then
        print_green "Kernel compilation failed. Exiting."
        exit 1
    fi
    print_green "Kernel compiled successfully!"
}

# Function to install the modules
install_modules() {
    print_green "Installing kernel modules..."
    if ! sudo make modules; then
        print_green "Failed to build kernel modules. Exiting."
        exit 1
    fi

    if ! sudo make modules_install; then
        print_green "Failed to install kernel modules. Exiting."
        exit 1
    fi
    print_green "Kernel modules installed successfully!"
}

# Function to copy the kernel to /boot
install_kernel() {
    print_green "Installing the kernel..."
    if ! sudo make install; then
        print_green "Kernel installation failed. Exiting."
        exit 1
    fi

    # Copy and rename the kernel image
    local kernel_image="arch/x86/boot/bzImage"
    local destination_image="/boot/vmlinuz-linux${LATEST_KERNEL_VERSION}"

    sudo cp -v "$kernel_image" "$destination_image"

    print_green "Kernel installed and copied to /boot as $(print_red_bold "vmlinuz-linux${LATEST_KERNEL_VERSION}")"
}

# Function to update GRUB and set the new kernel as default
update_grub_and_set_default() {
    print_green "Updating GRUB configuration..."

    # Capture the output of grub-mkconfig
    local grub_output
    grub_output=$(sudo grub-mkconfig -o /boot/grub/grub.cfg 2>&1)

    # Parse and beautify the output
    while IFS= read -r line; do
        if [[ $line == *"Found linux image:"* ]]; then
            echo -e "${BOLD_BRIGHT_GREEN}[FOUND]${RESET} $line"
        elif [[ $line == *"Warning:"* ]]; then
            echo -e "${BOLD_BRIGHT_RED}[WARNING]${RESET} $line"
        elif [[ $line == *"Adding boot menu entry"* ]]; then
            echo -e "${BOLD_BRIGHT_GREEN}[INFO]${RESET} $line"
        else
            echo -e "${BOLD_BRIGHT_GREEN}[INFO]${RESET} $line"
        fi
    done <<< "$grub_output"

    # Prompt user for confirmation before changing GRUB configuration
    print_green "Do you want to set the new kernel as the default in GRUB? (y/N)"
    read -r user_input
    if [[ ! "$user_input" =~ ^[Yy]$ ]]; then
        print_green "Skipping GRUB update. Exiting."
        exit 0
    fi

    # Manually set GRUB_DEFAULT to the new kernel version in /etc/default/grub
    print_green "Setting the new kernel as the default in GRUB..."

    local kernel_entry="Advanced options for Arch Linux>Arch Linux, with Linux ${LATEST_KERNEL_VERSION}"

    # Use sed to update GRUB_DEFAULT in /etc/default/grub
    sudo sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"${kernel_entry}\"/" /etc/default/grub

    print_green "New kernel set as default. You may need to reboot for changes to take effect."
}

# Function to clean up temporary files
cleanup() {
    print_green "Cleaning up..."
    rm -f "$KERNEL_DIR/$LATEST_KERNEL_TARBALL"
    print_green "Cleanup completed!"
}

# Handle script interruptions
trap 'print_green "Aborting..."; cleanup; exit 1;' INT TERM

# Automating the process
get_latest_kernel_version
check_existing_kernel
download_kernel
extract_and_update_config
compile_kernel
install_modules
install_kernel
update_grub_and_set_default
cleanup

# Final message
print_green "Kernel build and installation completed!"