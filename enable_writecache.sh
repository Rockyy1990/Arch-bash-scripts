#!/bin/bash
echo ""
read -p "Optimize writes on disk and enable wirte cache. Press any key to continue.."
echo ""

echo -e "Optimize writes to the disk"
sudo sed -i -e s"/\#Storage=.*/Storage=none/"g /etc/systemd/coredump.conf
sudo sed -i -e s"/\#Seal=.*/Seal=no/"g /etc/systemd/coredump.conf
sudo sed -i -e s"/\#Storage=.*/Storage=none/"g /etc/systemd/journald.conf
sudo sed -i -e s"/\#Seal=.*/Seal=no/"g /etc/systemd/journald.conf

echo -e "Enable write cache"
echo -e "write back" | sudo tee /sys/block/*/queue/write_cache
sudo tune2fs -o journal_data_writeback $(df / | grep / | awk '{print $1}')
sudo tune2fs -O ^has_journal $(df / | grep / | awk '{print $1}')
sudo tune2fs -o journal_data_writeback $(df /home | grep /home | awk '{print $1}')
sudo tune2fs -O ^has_journal $(df /home | grep /home | awk '{print $1}')

echo -e "Enable fast commit"
sudo tune2fs -O fast_commit $(df / | grep / | awk '{print $1}')
sudo tune2fs -O fast_commit $(df /home | grep /home | awk '{print $1}')