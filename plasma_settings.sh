#!/usr/bin/env bash

# Last Edit: 21.02.2025

read -p "Plasma Desktop settings.. Press any key to continue."

# KDE tweaks
kwriteconfig5 --file kwinrc --group Compositing --key "Enabled" --type bool true
kwriteconfig5 --file kwinrc --group Compositing --key "LatencyPolicy" "ExtremelyLow"
kwriteconfig5 --file kwinrc --group Compositing --key "AnimationSpeed" 3
kwriteconfig5 --file kwinrc --group Windows --key "AutoRaiseInterval" 125
kwriteconfig5 --file kwinrc --group Windows --key "DelayFocusInterval" 125
kwriteconfig5 --file kdeglobals --group KDE --key "AnimationDurationFactor" 0.125
kwriteconfig5 --file ksplashrc --group KSplash --key Engine "none"
kwriteconfig5 --file ksplashrc --group KSplash --key Theme "none"
kwriteconfig5 --file klaunchrc --group FeedbackStyle --key "BusyCursor" --type bool false
kwriteconfig5 --file klaunchrc --group BusyCursorSettings --key "Blinking" --type bool false
kwriteconfig5 --file klaunchrc --group BusyCursorSettings --key "Bouncing" --type bool false
kwriteconfig5 --file kwalletrc --group Wallet --key "Enabled" --type bool false
kwriteconfig5 --file kwalletrc --group Wallet --key "First Use" --type bool false

sudo pacman -S --needed --noconfirm plasma-workspace-wallpapers

echo ""
echo "Settings are set. Reboot in 3 seconds."
sleep 3
sudo reboot