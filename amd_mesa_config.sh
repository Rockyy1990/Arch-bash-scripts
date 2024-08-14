#!/bin/bash

set -e

echo "Updating system..."
pacman -Syu --noconfirm

echo "Installing necessary packages..."
pacman -S --needed --noconfirm \
    mesa \
    mesa-demos \
    xf86-video-amdgpu \
    vulkan-radeon \
    lib32-mesa \
    lib32-vulkan-radeon \
    amd-ucode \
    linux-firmware

echo "Configuring Mesa for AMD..."
# Create a configuration file for Mesa
cat <<EOL | sudo tee /etc/X11/xorg.conf.d/20-amdgpu.conf
Section "Device"
    Identifier "AMD"
    Driver "amdgpu"
    Option "TearFree" "true"
    Option "AccelMethod" "glamor"
    Option "DRI" "3"
EndSection
EOL

# Setting environment variables for best performance
if [ ! -d "$HOME/.config/environment.d" ]; then
    mkdir -p "$HOME/.config/environment.d"
fi

cat <<EOL | tee $HOME/.config/environment.d/graphics.env
MESA_LOADER_DRIVER_OVERRIDE="radeonsi"
VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/radeon_icd.x86_64.json"
EOL

echo "Creating a bash script to set performance settings..."
cat <<'EOL' | sudo tee /usr/local/bin/amd_performance_tuning.sh
#!/bin/bash

# Enable AMD Cool 'n' Quiet
echo "Enabling AMD Cool 'n' Quiet..."
echo "auto" | tee /sys/class/drm/card0/device/power_dpm_force_performance_level

# Set the power profile
echo "Set the performance mode to high..."
echo "high" | tee /sys/class/drm/card0/device/power_dpm_state
EOL

sudo chmod +x /usr/local/bin/amd_performance_tuning.sh

echo "Enabling and starting the performance tuning script..."
sudo systemctl enable amd_performance_tuning.service
sudo systemctl start amd_performance_tuning.service

# Create the service file
cat <<EOL | sudo tee /etc/systemd/system/amd_performance_tuning.service
[Unit]
Description=AMD Performance Tuning

[Service]
Type=oneshot
ExecStart=/usr/local/bin/amd_performance_tuning.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

echo "All done! Please reboot your system for changes to take effect."

