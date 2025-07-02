#!/usr/bin/env bash

# Last Edit: 01.07.25

echo ""
echo " ---------------------------"
echo "   Archlinux Server config  "
echo "----------------------------"
echo ""
echo " These environments are recommended:
        XFCE4
		Gnome
        Cinnamon
"		
echo ""
read -p "Press any key to start the server config."
echo ""


# Update the system
sudo pacman -Syu --noconfirm

# Install necessary packages
sudo pacman -S --needed --noconfirm base-devel fakeroot pacman-contrib dkms gsmartcontrol gnome-firmware gvfs gvfs-smb gvfs-nfs ufw samba libwbclient git curl openssh
sudo pacman -S --needed --noconfirm mesa mesa-utils opencl-mesa vulkan-mesa-layers vulkan-tools
sudo pacman -S --needed --noconfirm firefox firefox-i18n-de mousepad brasero



# Install Yay from AUR
if ! command -v yay &> /dev/null; then
  echo "Installing Yay..."
  git clone https://aur.archlinux.org/yay.git || { echo "Failed to clone Yay repository"; exit 1; }
  cd yay || exit
  makepkg -si --noconfirm || { echo "Failed to install Yay"; exit 1; }
  cd .. && rm -r yay
else
  echo "Yay is already installed."
fi


# Install additional packages
yay -S --needed nomachine webmin 
yay -S --needed makemkv makemkv-libaacs jre-openjdk
yay -S --needed faudio

sudo pacman -S --needed ffmpeg fdkaac libmad0 flac lame twolame libtheora libmatroska x264 x265 a52dec libsoxr libdvdcss gst-libav rtkit
sudo pacman -S --needed celluloid handbrake soundconverter yt-dlp pavucontrol


# Install nvidia drivers
sudo pacman -S --needed --noconfirm nvidia nvidia-utils opencl-nvidia libxnvctrl libvdpau nvidia-settings


# Install and config virt-manager
sudo pacman -S --needed qemu qemu-user-binfmt virt-manager virt-viewer swtpm dnsmasq bridge-utils libguestfs ebtables iptables-nft
sudo usermod -aG libvirt,kvm $(whoami)
sudo modprobe -r kvm_amd
sudo modprobe kvm_amd nested=1
echo "options kvm-amd nested=1" | sudo tee /etc/modprobe.d/kvm-amd.conf



# Setup automatic system upgrades
sudo pacman -S cronie --noconfirm
sudo touch /usr/local/bin/auto-update.sh

cat << 'EOF' | sudo tee /usr/local/bin/auto-update.sh
#!/usr/bin/env bash

# Update the package database and upgrade the system
pacman -Syu --noconfirm

# Log the output
echo "System updated on $(date)" >> /var/log/auto-update.log
EOF

sudo chmod +x /usr/local/bin/auto-update.sh


# Add cron job for automatic updates
echo "0 2 */5 * * /usr/local/bin/auto-update.sh" | sudo crontab -


# Setup UFW firewall if available
if command -v ufw >/dev/null 2>&1; then
  echo "Configuring UFW firewall..."
  sudo ufw default deny incoming
  sudo ufw default allow outgoing
  sudo ufw allow OpenSSH
  sudo ufw allow samba
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw allow 10000
  sudo ufw allow 4000/tcp
  sudo ufw allow 4000/udp
  sudo ufw --force enable
else
  echo "UFW not installed, skipping firewall configuration"
fi

# Start and enable services
sudo systemctl start sshd
sudo systemctl enable sshd

sudo systemctl start cronie
sudo systemctl enable cronie

sudo systemctl enable --now libvirtd
sudo virsh net-autostart default


sudo systemctl enable fstrim
sudo fstrim -av

clear
echo ""
echo "Archlinux server configuration completed successfully."
echo "You can access Webmin at https://your-server-ip:10000"
echo ""
sleep 2
read -p "Press any key to reboot the server.."
sudo reboot