#!/usr/bin/env bash

# Last Edit: 06.02.2025

# Skript zur Installation und Konfiguration von Wayland für den Plasma-Desktop auf Arch Linux mit AMD GPU Unterstützung und Optimierungen

# Überprüfen, ob das Skript mit Root-Rechten ausgeführt wird
if [ "$EUID" -ne 0 ]; then
    echo "Bitte das Skript mit sudo oder als Root ausführen."
    exit 1
fi

# List of packages to be installed
echo -e "The following packages will be installed:"
echo -e "- plasma"
echo -e "- wayland"
echo -e "- plasma-wayland-session"
echo -e "- kwin"
echo -e "- wayland-protocols"
echo -e "- xorg-xwayland"
echo -e "- xf86-video-amdgpu"
echo -e "- gamemode"
echo ""
sleep 3

# System upgrade
echo "System wird aktualisiert..."
pacman -Syu --noconfirm

# Install needed plasma and wayland packages
echo "Installiere notwendige Pakete für Wayland und Plasma..."
pacman -S --needed --noconfirm plasma wayland plasma-wayland-session kwin wayland-protocols xorg-xwayland gamemode
pacman -S --needed --noconfirm xf86-video-amdgpu mesa mesa-vulkan

# Wayland config
echo "Konfiguriere Wayland für Plasma..."
mkdir -p /etc/sddm.conf.d/
cat <<EOL > /etc/sddm.conf.d/wayland.conf
[General]
Session=plasmawayland.desktop
EOL

# KWin optimize config
echo "Optimiere KWin Konfiguration..."
mkdir -p ~/.config/kwin/
cat <<EOL > ~/.config/kwinrc
[Compositing]
OpenGLIsUnsafe=false
Backend=OpenGL
EOL

# AMD GPU spezifische Konfiguration für aktuelle RX-Karten
echo "Konfiguriere AMD GPU Einstellungen für aktuelle RX-Karten..."
cat <<EOL > /etc/modprobe.d/amdgpu.conf
options amdgpu si_support=1
options amdgpu enable_powerplay=1
options amdgpu power_dpm_enable=1
options amdgpu dc=1
options amdgpu vramlimit=0
EOL

# Plasma Desktop Optimierungen
echo "Optimiere Plasma Desktop Einstellungen..."
mkdir -p ~/.config/plasma-workspace/
cat <<EOL > ~/.config/plasma-workspace/env/plasma_env.sh
#!/bin/bash
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
EOL
chmod +x ~/.config/plasma-workspace/env/plasma_env.sh

# Autostart für Gamemode aktivieren
echo "Aktiviere Gamemode beim Start..."
mkdir -p ~/.config/autostart/
cat <<EOL > ~/.config/autostart/gamemode.desktop
[Desktop Entry]
Type=Application
Exec=gamemoded
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Gamemode
Comment=Start Gamemode for better performance
EOL

# Benutzer informieren
echo ""
echo -e "Install and config complete. "
read -p "Press any key to reboot .."
sudo reboot
