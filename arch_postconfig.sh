#!/bin/bash

echo ""
echo "
||==================================||
|| # Archlinux postinstall script # ||
||==================================||
"
echo ""

echo ""
echo "Installation summary:"
echo ""
echo " - Chaotic AUR (optional)"
echo " - Update mirrors (reflector)"
echo " - Core system packages: base-devel, efibootmgr, git, curl, ufw, fwupd, bash-completion, gvfs, samba, openssh, smartmontools, xfsdump, f2fs-tools, udftools, gnome-disk-utility"
echo " - Development/runtime: python, pip, pyenv, deno"
echo " - Wayland/X11 support and related libs"
echo " - Fonts: Noto, DejaVu, Liberation, OpenSans"
echo " - Graphics (AMD): mesa, OpenCL, Vulkan packages"
echo " - Media & apps: vivaldi (+ffmpeg codecs), discord, qbittorrent, gwenview, smplayer, ark, pipewire, ffmpeg, gstreamer plugins"
echo " - Optional: Printing (CUPS), Wine & Steam, virt-manager, yt-dlp"
echo " - AUR helper: yay and selected AUR packages (onlyoffice-bin, protonup-qt-bin, ttf-ms-fonts, ventoy-bin, nomachine, telegram-desktop-bin, teams-for-linux-bin, bottles, timeshift + autosnap)"
echo "......."
echo ""
read -p "..Press any key to continue.."
clear


echo ""
read -p "Do you wont to use the chaotic aur? (yes/no): " install_chaotic_aur

if [[ "$install_chaotic_aur" =~ ^(ja|j|yes|y)$ ]]; then
    echo "Starting installation.."

#---------------------------------------------------------------------------------------
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB

sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

sudo tee -a /etc/environment <<EOF
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF

sudo pacman -Syyu
#----------------------------------------------------------------------------------------

    echo "Chaotic-AUR is installed"
else
    echo "Installation aborted."
fi

echo ""
read -p "If you use btrfs do you wont to install snapper with snap-pac and btrfs-assistant? (yes/no): " install_snapper

if [[ "$install_snapper" =~ ^(ja|j|yes|y)$ ]]; then
    echo "Starting installation.."

sudo pacman -Sy
sudo pacman -S --needed --noconfirm btrfs-assistant snap-pac snapper


    echo "Snapper is installed"
else
    echo "Installation aborted."
fi


echo ""
read -p "First off all check and modifi the pacman.conf. Press any key to do that."
sudo nano /etc/pacman.conf
sudo pacman -Sy

sudo pacman -S --needed --noconfirm reflector
reflector --verbose --latest 8 --country "Germany" --protocol https --sort rate --save /etc/pacman.d/mirrorlist
sudo systemctl enable reflector.timer
sudo pacman -Sy
clear


echo ""
echo "Install system packages"
sleep 2
sudo pacman -S --needed --noconfirm base-devel fakeroot efibootmgr git curl ufw fwupd bash-completion gvfs samba openssh smartmontools xfsdump f2fs-tools udftools gnome-disk-utility
sudo pacman -S --needed --noconfirm appmenu-gtk-module xdg-desktop-portal deno ethtool rsync python-pip pyenv python-av python-cachy python-opengl sof-firmware
sudo pacman -S --needed --noconfirm wayland-protocols egl-wayland waylandpp plasma-wayland-protocols kwayland-integration
echo ""

echo "Complete x11 support"
sleep 2
sudo pacman -S --needed --noconfirm xorg-server-xvfb xorg-xkill xorg-xinput xorg-xrandr libxv libxcomposite libxinerama
sudo pacman -S --needed --noconfirm lib32-libxcomposite lib32-libxrandr lib32-libxfixes
echo ""

echo "Install common fonts"
sleep 2
sudo pacman -S --needed --noconfirm noto-fonts noto-fonts-cjk ttf-dejavu ttf-liberation ttf-opensans
echo ""

echo "Install graphics (AMD)"
sleep 2
sudo pacman -S --needed --noconfirm mesa-utils opencl-mesa vulkan-mesa-implizit-layers vulkan-radeon vulkan-dzn vulkan-swrast vulkan-icd-loader vulkan-validation-layers
echo ""

echo "Install needed stuff"
sleep 2
sudo pacman -S --needed --noconfirm vivaldi vivaldi-ffmpeg-codecs discord qbittorrent gwenview smplayer ark cameractrls pipewire-v4l2 rtkit gst-plugin-pipewire ffmpeg flac lame
sudo pacman -S --needed --noconfirm gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-plugin-va gst-plugins-espeak



echo ""
read -p "Do you wont to install Printing support? (yes/no): " install_printing

if [[ "$install_printing" =~ ^(ja|j|yes|y)$ ]]; then
    echo "Starting installation.."

    # Installs printing support
    sudo pacman -S --needed --noconfirm cups cups-filters cups-pdf ghostscript gutenprint system-config-printer
    sudo systemctl enable cups.service
    sudo systemctl enable cups.socket

    echo "Install and config complete"
else
    echo "Installation aborted."
fi

echo ""
read -p "Do you wont to install wine and steam gaming platform? (yes/no): " install_wine_steam

if [[ "$install_wine_steam" =~ ^(ja|j|yes|y)$ ]]; then
    echo "Starting installation.."

    # Install Windows api support and steam gaming platform
    sudo pacman -S --needed --noconfirm wine-staging wine-mono wine-gecko winetricks vkd3d libgdiplus steam protontricks gamemode

    echo "Install and config complete"
else
    echo "Installation aborted."
fi

echo ""
read -p "Do you wont to install virt-manager? (yes/no): " install_virt_manager

if [[ "$install_virt_manager" =~ ^(ja|j|yes|y)$ ]]; then
    echo "Starting installation.."
    sudo pacman -S --needed --noconfirm libvirt libvirt-python virt-manager qemu-full qemu-guest-agent libguestfs vde2 swtpm dnsmasq dmidecode

    echo "Activate libvirt.."
    sudo systemctl enable --now libvirtd.service virtlogd.service

    echo "Add current user to  libvirt-group..."
    sudo usermod -aG libvirt "$USER"

    echo "Activate the default network.."
    sudo virsh net-autostart default
    sudo virsh net-start default

    echo "Install and config complete"
else
    echo "Installation aborted."
fi

echo ""
read -p "Do you wont to download yt-dlp? (yes/no): " install_ytdlp

if [[ "$install_ytdlp" =~ ^(ja|j|yes|y)$ ]]; then
    echo "Starting installation.."

    # Download yt-dlp from github and move to /usr/local/bin
    curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /tmp/yt-dlp
    chmod +x /tmp/yt-dlp
    sudo mkdir -p /usr/local/bin
    sudo mv /tmp/yt-dlp /usr/local/bin/

    echo "Install and config complete"
else
    echo "Installation aborted."
fi
echo ""


echo "Install yay AUR-Helper"
sleep 1
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si
cd ..
rm -rf yay-bin/


echo "Install some needed aur packages"
sleep 1
yay -S onlyoffice-bin protonup-qt-bin ttf-ms-fonts ventoy-bin nomachine
yay -S telegram-desktop-bin teams-for-linux-bin

echo ""
echo "Install wine bottles"
yay -S bottles

echo ""
echo "Install timeshift"
yay -S timeshift timeshift-autosnap



# Set I/O sheduler settings
cat > /etc/udev/rules.d/60-ioschedulers.rules <<'EOF'
# NVMe SSDs - Verwende 'none' (beste Performance)
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"

# SATA SSDs und eMMC - Verwende 'bfq' (bessere Responsiveness)
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="bfq"

# Rotierende Festplatten - Verwende 'bfq'
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

sudo udevadm control --reload


# Add some needed varaibles to /etc/environment
sudo tee -a /etc/environment <<EOF
CPU_LIMIT=0
CPU_GOVERNOR=performance
GPU_USE_SYNC_OBJECTS=1
PYTHONOPTIMIZE=1
ELEVATOR=deadline
TRANSPARENT_HUGEPAGES=always
MALLOC_CONF=background_thread:true
MALLOC_CHECK=0
MALLOC_TRACE=0
LD_DEBUG_OUTPUT=0
LP_PERF=no_mipmap,no_linear,no_mip_linear,no_tex,no_blend,no_depth,no_alphatest
LESSSECURE=1
PAGER=less
EDITOR=nano
VISUAL=nano
AMD_VULKAN_ICD=RADV
RADV_PERFTEST=aco,sam,nggc
RADV_DEBUG=novrsflatshading
EOF


echo ""
read -p "Do you wont to install various performance tweaks? (yes/no): " install_performance_tweaks

if [[ "$install_performance_tweaks" =~ ^(ja|j|yes|y)$ ]]; then
    echo "Starting installation.."

    yay -S irqbalance ananicy-cpp memavaild nohang preload prelockd uresourced
    sudo systemctl enable irqbalance
    sudo systemctl disable systemd-oomd
    sudo systemctl enable ananicy-cpp
    sudo systemctl enable memavaild
    sudo systemctl enable nohang
    sudo systemctl enable preload
    sudo systemctl enable prelockd
    sudo systemctl enable uresourced
    sudo sed -i 's|zram_checking_enabled = False|zram_checking_enabled = True|g' /etc/nohang/nohang.conf

    echo "Install and config complete"
else
    echo "Installation aborted."
fi

echo ""
echo "Config the firewall and enable it for start at boot"
sleep 2

# UFW config
sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow 22/tcp comment "SSH"
sudo ufw allow 22/udp comment "SSH"
sudo ufw limit 22/tcp comment "SSH Rate Limit"
sudo ufw limit 22/udp comment "SSH Rate Limit (UDP)"

sudo ufw allow 53/tcp comment "DNS"
sudo ufw allow 53/udp comment "DNS"
sudo ufw limit 53/udp comment "DNS Rate Limit"

sudo ufw allow 80/tcp comment "HTTP"
sudo ufw allow 443/tcp comment "HTTPS"
sudo ufw limit 80/tcp comment "HTTP Rate Limit"
sudo ufw limit 443/tcp comment "HTTPS Rate Limit"

sudo ufw allow 139/tcp comment "Samba"
sudo ufw allow 445/tcp comment "Samba"

sudo ufw allow 4000/tcp comment "Nomachine"
sudo ufw limit 4000/tcp comment "Nomachine Rate Limit"

# Activates ufw logging
sudo ufw logging on
sudo ufw logging medium

sudo ufw enable


echo ""
echo "Now the last steps..."
sleep 1

# Set journal size to 100M
sudo journalctl --vacuum-size=100M
sudo journalctl --vacuum-time=2weeks

# ssh config
cat >> /etc/ssh/sshd_config <<'EOF'

# Optimize performance
TCPKeepAlive yes
ClientAliveInterval 60
ClientAliveCountMax 3
Compression no
UseDNS no
EOF



echo ""
read -p "Do you wont to install the arch system manager? (yes/no): " install_arch_sys_management

if [[ "$install_arch_sys_management" =~ ^(ja|j|yes|y)$ ]]; then
    echo "Starting installation.."

touch ~/Schreibtisch/arch_sys_management.py
chmod +x ~/Schreibtisch/arch_sys_management.py
sudo tee -a ~/Schreibtisch/arch_sys_management.py <<EOF
#!/usr/bin/env python3

import os
import subprocess
import sys

# Farben definieren
ORANGE = '\033[38;5;208m'
BLUE = '\033[34m'
RESET = '\033[0m'

def clear_screen():
    os.system('clear')

def print_menu():
    clear_screen()
    print(f"{ORANGE}{'='*50}")
    print(f"{'='*50}{RESET}")
    print(f"{ORANGE}        ARCH LINUX SYSTEM MANAGEMENT{RESET}")
    print(f"{ORANGE}{'='*50}")
    print(f"{'='*50}{RESET}\n")

    print(f"{ORANGE}1. System Upgrade{RESET}")
    print(f"{ORANGE}2. System Upgrade mit YAY{RESET}")
    print(f"{ORANGE}3. Pacman Cache leeren{RESET}")
    print(f"{ORANGE}4. Arch Linux Keyring erneuern{RESET}")
    print(f"{ORANGE}5. Pacman Datenbank aktualisieren{RESET}")
    print(f"{ORANGE}6. Beenden{RESET}\n")

def success_message():
    print(f"\n{BLUE}Erfolgreich ausgeführt!{RESET}\n")
    input("Drücke Enter zum Fortfahren...")

def execute_command(command, description):
    print(f"\n{ORANGE}Führe aus: {description}{RESET}")
    print(f"{ORANGE}Befehl: {command}{RESET}\n")

    try:
        result = subprocess.run(command, shell=True, check=True)
        if result.returncode == 0:
            success_message()
        else:
            print(f"{ORANGE}Fehler beim Ausführen des Befehls!{RESET}")
            input("Drücke Enter zum Fortfahren...")
    except subprocess.CalledProcessError as e:
        print(f"{ORANGE}Fehler: {e}{RESET}")
        input("Drücke Enter zum Fortfahren...")
    except Exception as e:
        print(f"{ORANGE}Fehler: {e}{RESET}")
        input("Drücke Enter zum Fortfahren...")

def main():
    while True:
        print_menu()
        choice = input(f"{ORANGE}Wähle eine Option (1-6): {RESET}").strip()

        if choice == '1':
            execute_command('sudo pacman -Syu', 'System Upgrade')
        elif choice == '2':
            execute_command('yay -Syu', 'System Upgrade mit YAY')
        elif choice == '3':
            execute_command('sudo pacman -Scc --noconfirm', 'Pacman Cache leeren')
        elif choice == '4':
            execute_command('sudo pacman-key --init && sudo pacman-key --populate archlinux', 'Arch Linux Keyring erneuern')
        elif choice == '5':
            execute_command('sudo pacman -Fyy', 'Pacman Datenbank aktualisieren')
        elif choice == '6':
            clear_screen()
            print(f"{ORANGE}Auf Wiedersehen!{RESET}")
            sys.exit(0)
        else:
            print(f"{ORANGE}Ungültige Auswahl. Bitte versuche es erneut.{RESET}")
            input("Drücke Enter zum Fortfahren...")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{ORANGE}Skript beendet.{RESET}")
        sys.exit(0)
EOF

touch ~/Schreibtisch/arch_package_installer.py
chmod +x ~/Schreibtisch/arch_package_installer.py
sudo tee -a ~/Schreibtisch/arch_package_installer.py <<EOF
#!/usr/bin/env python3

import os
import sys
import shlex
import subprocess
import shutil

def ensure_sudo():
    # Wenn nicht als root ausgeführt, relaunch mit sudo -E für Umgebungsvariablen
    if os.geteuid() != 0:
        try:
            cmd = ["sudo", "-E", sys.executable] + sys.argv
            os.execvp("sudo", cmd)
        except Exception as e:
            print("Fehler beim Aufruf von sudo:", e)
            sys.exit(1)

def run_command(cmd, run_as_root=False):
    try:
        print(f"\nAusführen: {cmd}\n")
        # split sicher anwenden
        proc = subprocess.run(shlex.split(cmd), check=False)
        return proc.returncode
    except FileNotFoundError:
        print("Fehler: Befehl nicht gefunden.")
        return 1
    except Exception as e:
        print("Fehler beim Ausführen:", e)
        return 1

def pacman_install():
    pkg = input("Pacman - Paketname zum Installieren: ").strip()
    if not pkg:
        print("Kein Paketname angegeben.")
        return
    noconfirm = input("Mit --noconfirm installieren? (j/N): ").strip().lower() == "j"
    cmd = f"pacman -S {pkg}"
    if noconfirm:
        cmd += " --noconfirm"
    run_command(cmd, run_as_root=True)

def yay_install():
    pkg = input("Yay - Paketname zum Installieren: ").strip()
    if not pkg:
        print("Kein Paketname angegeben.")
        return
    noconfirm = input("Mit --noconfirm installieren? (j/N): ").strip().lower() == "j"
    cmd = f"yay -S {pkg}"
    if noconfirm:
        cmd += " --noconfirm"
    run_command(cmd, run_as_root=False)

def yay_remove():
    pkg = input("Yay - Paketname zum Entfernen (entfernt Paket, nicht Abhängigkeiten automatisch): ").strip()
    if not pkg:
        print("Kein Paketname angegeben.")
        return
    # Optional: --noconfirm
    noconfirm = input("Mit --noconfirm entfernen? (j/N): ").strip().lower() == "j"
    cmd = f"yay -R {pkg}"
    if noconfirm:
        cmd += " --noconfirm"
    run_command(cmd, run_as_root=False)

def yay_search():
    term = input("Yay - Suchbegriff: ").strip()
    if not term:
        print("Kein Suchbegriff angegeben.")
        return
    cmd = f"yay -Ss {term}"
    run_command(cmd, run_as_root=False)

def check_dependencies():
    missing = []
    for prog in ("pacman", "yay", "sudo"):
        if not shutil.which(prog):
            missing.append(prog)
    if missing:
        print("Hinweis: Folgende Programme wurden nicht gefunden:", ", ".join(missing))

def menu():
    while True:
        print("\n--- Paket-Menü ---")
        print("1) Paket mit pacman installieren")
        print("2) Paket mit yay installieren")
        print("3) Paket mit yay suchen")
        print("4) Paket mit yay entfernen (yay -R)")
        print("5) Beenden")
        choice = input("Auswahl (1-5): ").strip()
        if choice == "1":
            pacman_install()
        elif choice == "2":
            yay_install()
        elif choice == "3":
            yay_search()
        elif choice == "4":
            yay_remove()
        elif choice == "5":
            print("Beenden.")
            break
        else:
            print("Ungültige Auswahl.")

if __name__ == "__main__":
    # Sicherstellen, dass sudo verfügbar ist und einmaliges Root-Prompt erfolgt
    if shutil.which("sudo") is None:
        print("Fehler: 'sudo' wurde nicht gefunden. Starte ohne Sudo-Erhöhung.")
    else:
        ensure_sudo()

    print("Hinweis: Dieses Skript führt Systembefehle aus. Verwende es mit Vorsicht.")
    check_dependencies()
    menu()
EOF

echo "Install and config complete"
else
    echo "Installation aborted."
fi
echo ""



echo "Enable fstrim.timer"
sleep 1
sudo systemctl enable fstrim.timer
sudo systemctl start fstrim.timer
sudo fstrim -av

echo ""
echo "Clean up package cache.."
sleep 1
sudo pacman -Scc --noconfirm

echo ""
echo "
----------------------------
 Postconfig is complete. :-)
----------------------------
"
read -p "Press any key to reboot the System"
sleep 1
sudo reboot
