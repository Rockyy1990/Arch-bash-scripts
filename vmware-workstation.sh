#!/usr/bin/env bash

read -p "The chaotic repo need to be installed"

sudo pacman -S --needed fuse2 gtkmm linux-headers pcsclite libcanberra 

sudo pacman -S --needed vmware-workstation

sudo systemctl enable vmware-networks.service

sudo systemctl enable vmware-usbarbitrator.service


# Enabling networking
cat <<EOF | sudo tee /etc/systemd/system/vmware-networks-server.service
[Unit]
Description=VMware Networks
Wants=vmware-networks-configuration.service
After=vmware-networks-configuration.service

[Service]
Type=forking
ExecStartPre=-/sbin/modprobe vmnet
ExecStart=/usr/bin/vmware-networks --start
ExecStop=/usr/bin/vmware-networks --stop

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable vmware-networks-server.service


# Create and enable the vmware.service
cat <<EOF | sudo tee /etc/systemd/system/vmware.service
[Unit]
Description=VMware daemon
Requires=vmware-usbarbitrator.service
Before=vmware-usbarbitrator.service
After=network.target

[Service]
ExecStart=/etc/init.d/vmware start
ExecStop=/etc/init.d/vmware stop
PIDFile=/var/lock/subsys/vmware
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl enable vmware.service

# Reload services and start vmware.service and usbarbitrator.service
sudo systemctl daemon-reload
sudo systemctl start vmware.service vmware-usbarbitrator.service 

# Recompiling VMware kernel modules
sudo  vmware-modconfig --console --install-all

# Load the VMware modules
sudo modprobe -a vmw_vmci vmmon


