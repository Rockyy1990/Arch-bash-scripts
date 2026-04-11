#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#===============================================================================
#  archlinux_gparted_live_creator.sh
#  Erstellt eine Arch-Linux-Live-ISO mit GParted, gnome-disk-utility, rsync
#  und weiteren Festplatten-/Backup-Werkzeugen auf MATE-Basis.
#
#  Aktualisiert für archiso >= 80 (2025+):
#    - archisosearchuuid statt archisodevice
#    - mkinitcpio microcode-Hook statt externer ucode-Images
#    - Pacman-Hook statt deprecated customize_airootfs.sh
#    - %ARCH%-Template statt hardcoded x86_64
#    - GRUB search via %ARCHISO_SEARCH_FILENAME%
#    - Live-User via Pacman-Hook (kein Überschreiben von System-Usern)
#
#  Nutzung:  sudo bash archlinux_gparted_live_creator.sh
#            oder:  bash archlinux_gparted_live_creator.sh  (fragt nach Passwort)
#===============================================================================

#--- Konfiguration -------------------------------------------------------------
readonly ISO_NAME="archlinux-gparted-live"
readonly ISO_LABEL="ARCHGPARTED"
ISO_VERSION="$(date +%Y.%m.%d)"
readonly ISO_VERSION
readonly PROFILE_DIR="/tmp/${ISO_NAME}-profile"
readonly WORK_DIR="/tmp/${ISO_NAME}-work"
readonly REAL_USER="${SUDO_USER:-${USER}}"
OUT_DIR="$(eval echo "~${REAL_USER}")/iso-output"
readonly OUT_DIR

#--- Farbausgabe ---------------------------------------------------------------
readonly ROT='\033[0;31m'
readonly GRUEN='\033[0;32m'
readonly GELB='\033[1;33m'
readonly BLAU='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly RESET='\033[0m'

info()   { echo -e "${BLAU}[INFO]${RESET}   $*"; }
ok()     { echo -e "${GRUEN}[  OK]${RESET}   $*"; }
warn()   { echo -e "${GELB}[WARN]${RESET}   $*"; }
fehler() { echo -e "${ROT}[FEHLER]${RESET} $*" >&2; exit 1; }

#--- Banner --------------------------------------------------------------------
banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
    ╔═════════════════════════════════════════════════════════╗
    ║          Archlinux Gparted Live ISO – Builder           ║
    ║           Partitionierung · Backup · Wartung            ║
    ╚═════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
}

#--- Hilfsfunktionen -----------------------------------------------------------
aufraeumen() {
    local verz
    for verz in "$PROFILE_DIR" "$WORK_DIR"; do
        if [[ -d "$verz" ]]; then
            warn "Entferne altes Verzeichnis: ${verz}"
            rm -rf "$verz"
        fi
    done
}

erstelle_verzeichnis() {
    local pfad
    for pfad in "$@"; do
        mkdir -p "${PROFILE_DIR}/airootfs/${pfad}"
    done
}

#===============================================================================
#  HAUPTPROGRAMM
#===============================================================================
banner

#--- Root-Prüfung --------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    info "Root-Rechte werden benötigt. Bitte Passwort eingeben:"
    exec sudo bash "$0" "$@"
fi

#--- Abhängigkeiten prüfen -----------------------------------------------------
info "Prüfe Abhängigkeiten auf dem Host-System ..."
declare -a FEHLENDE_PAKETE=()
for paket in archiso grub; do
    pacman -Qi "$paket" &>/dev/null || FEHLENDE_PAKETE+=("$paket")
done

if [[ ${#FEHLENDE_PAKETE[@]} -gt 0 ]]; then
    warn "Fehlende Pakete: ${FEHLENDE_PAKETE[*]} – werden installiert ..."
    pacman -Syu --noconfirm "${FEHLENDE_PAKETE[@]}" \
        || fehler "Konnte Abhängigkeiten nicht installieren."
fi
ok "Alle Abhängigkeiten verfügbar."

#--- Alte Build-Reste entfernen ------------------------------------------------
aufraeumen

#--- Profil vom releng-Template kopieren ---------------------------------------
info "Kopiere releng-Profil nach ${PROFILE_DIR} ..."
if [[ ! -d /usr/share/archiso/configs/releng ]]; then
    fehler "archiso releng-Profil nicht gefunden. Ist archiso korrekt installiert?"
fi
cp -r /usr/share/archiso/configs/releng/ "$PROFILE_DIR"
ok "Profil kopiert."

#===============================================================================
#  1) Paketliste (packages.x86_64)
#===============================================================================
info "Erstelle angepasste Paketliste ..."
cat > "${PROFILE_DIR}/packages.x86_64" << 'PACKAGES'
# ── Basis-System ─────────────────────────────────────────────────────────────
base
linux
linux-firmware
mkinitcpio
mkinitcpio-archiso
syslinux
sudo
polkit
dbus
fakeroot

# ── Boot & UEFI ──────────────────────────────────────────────────────────────
efibootmgr
grub
memtest86+
memtest86+-efi
edk2-shell

# ── Microcode (vom mkinitcpio microcode-Hook eingebunden) ────────────────────
amd-ucode
intel-ucode

# ── Netzwerk ─────────────────────────────────────────────────────────────────
networkmanager
iwd
openssh
wget
curl

# ── Grafische Oberfläche (MATE – Autologin via getty/startx) ─────────────────
xorg-server
xorg-xinit
xorg-xrandr
xorg-xwayland
xf86-video-vesa
xf86-video-amdgpu
xf86-video-intel
xf86-video-nouveau
libxvmc
libxdamage
libxext
mesa
mesa-utils


# MATE Desktop
mate
mate-extra
mate-icon-theme
mate-themes
mate-terminal
mate-power-manager
mate-control-center
mate-utils


# Sonstige Desktop-Abhängigkeiten
xdg-user-dirs
xdg-utils
dbus-glib
network-manager-applet

# ── Partitionierung & Festplatten ────────────────────────────────────────────
gparted
parted
dosfstools
ntfs-3g
exfatprogs
e2fsprogs
btrfs-progs
xfsprogs
f2fs-tools
jfsutils
f2fs-tools
mdadm
lvm2
dmraid
cryptsetup
fsarchiver
testdisk
hdparm
smartmontools
nvme-cli
sdparm
sg3_utils
gptfdisk
util-linux

# ── Erweiterte Disk-Tools ────────────────────────────────────────────────────
gnome-disk-utility
rsync
deja-dup

# ── Datenrettung ─────────────────────────────────────────────────────────────
ddrescue

# ── Archiv-Tools ─────────────────────────────────────────────────────────────
p7zip
unzip
zip
xz
zstd

# ── Terminal-Werkzeuge ───────────────────────────────────────────────────────
vim
nano
htop
lsof
tree
tmux
bash-completion
man-db
less

# ── Hardware-Info ────────────────────────────────────────────────────────────
pciutils
usbutils
lshw
dmidecode
PACKAGES

PAKET_ANZAHL=$(grep -cve '^\s*#' -e '^\s*$' "${PROFILE_DIR}/packages.x86_64")
ok "Paketliste geschrieben (${PAKET_ANZAHL} Pakete)."

#===============================================================================
#  2) mkinitcpio-Konfiguration (microcode-Hook)
#===============================================================================
info "Erstelle mkinitcpio-Konfiguration mit microcode-Hook ..."
erstelle_verzeichnis "etc/mkinitcpio.conf.d"

cat > "${PROFILE_DIR}/airootfs/etc/mkinitcpio.conf.d/archiso.conf" << 'EOF'
# mkinitcpio-Konfiguration für Archlinux Gparted Live ISO
# Der microcode-Hook ersetzt separate ucode.img-Dateien in der initrd.
HOOKS=(base udev microcode modconf kms memdisk archiso archiso_loop_mnt block filesystems keyboard)
COMPRESSION="xz"
EOF
ok "mkinitcpio-Konfiguration erstellt."

#===============================================================================
#  3) profiledef.sh
#===============================================================================
info "Passe profiledef.sh an ..."
cat > "${PROFILE_DIR}/profiledef.sh" << PROFILEDEF
#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="${ISO_NAME}"
iso_label="${ISO_LABEL}"
iso_publisher="Archlinux Gparted Live ISO <https://github.com>"
iso_application="Archlinux Gparted Live ISO – Partitionierung, Backup & Wartung"
iso_version="${ISO_VERSION}"
install_dir="arch"
buildmodes=('iso')
bootmodes=(
  'bios.syslinux'
  'uefi.grub'
)
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/sudoers.d/10-live"]="0:0:440"
  ["/root"]="0:0:750"
  ["/usr/local/bin/setup-live-user.sh"]="0:0:755"
)
PROFILEDEF
ok "profiledef.sh angepasst."

#===============================================================================
#  4) GRUB-Konfiguration (UEFI) – aktualisiert für archiso >= 80
#===============================================================================
info "Passe GRUB-Konfiguration an ..."
mkdir -p "${PROFILE_DIR}/grub"
cat > "${PROFILE_DIR}/grub/grub.cfg" << 'GRUBCFG'
# --- Archlinux Gparted Live ISO – GRUB (UEFI) ---
# Aktualisiert: archisosearchuuid, microcode-Hook, %ARCH%-Template,
#               search via %ARCHISO_SEARCH_FILENAME%

insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660
insmod ntfs
insmod ntfscomp
insmod exfat
insmod udf
insmod gzio

# Grafik-Modus
if loadfont "${prefix}/fonts/unicode.pf2" ; then
    insmod all_video
    set gfxmode="auto"
    terminal_input console
    terminal_output console
fi

# Serielle Konsole (optional, für Headless-Systeme)
insmod serial
if serial --unit=0 --speed=115200; then
    terminal_input --append serial
    terminal_output --append serial
fi

# ISO-Medium finden via Search-Filename (nicht mehr via Label)
if search --no-floppy --set=archiso_device --file '%ARCHISO_SEARCH_FILENAME%'; then
    set root="${archiso_device}"
fi

set default=0
set timeout=10
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

# Hinweis: Keine separaten amd-ucode.img/intel-ucode.img in der initrd nötig.
# Der mkinitcpio microcode-Hook bindet Microcode direkt in initramfs-linux.img ein.

menuentry "Archlinux Gparted Live ISO (%ARCH%, UEFI)" --class arch --class gnu-linux --class gnu --class os --id 'archlinux' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}

menuentry "Archlinux Gparted Live ISO (%ARCH%, UEFI) – Verbose" --class arch --class gnu-linux --class gnu --class os --id 'archlinux-verbose' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID%
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}

menuentry "Archlinux Gparted Live ISO (%ARCH%, UEFI) – Copy to RAM" --class arch --class gnu-linux --class gnu --class os --id 'archlinux-copytoram' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% copytoram quiet splash
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}

if [ "${grub_platform}" == 'efi' -a "${grub_cpu}" == 'x86_64' -a -f '/boot/memtest86+/memtest.efi' ]; then
    menuentry 'Memtest86+ (RAM-Test)' --class memtest86 --class memtest --class gnu --class tool {
        set gfxpayload=800x600,1024x768
        linux /boot/memtest86+/memtest.efi
    }
fi

menuentry "UEFI Firmware Settings" --id 'uefi-firmware' {
    fwsetup
}

menuentry "System neu starten" --id 'reboot' {
    reboot
}

menuentry "System ausschalten" --id 'poweroff' {
    halt
}
GRUBCFG

# Loopback-Konfiguration (ISO von GRUB aus starten)
cat > "${PROFILE_DIR}/grub/loopback.cfg" << 'LOOPBACK'
menuentry "Archlinux Gparted Live ISO (%ARCH%, UEFI) – Loopback" --class arch --class gnu-linux --class gnu --class os --id 'archlinux-loopback' {
    set gfxpayload=keep
    linux /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux archisobasedir=%INSTALL_DIR% img_dev=$imgdevpath img_loop=$isofile quiet splash
    initrd /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
}
LOOPBACK

ok "GRUB-Konfiguration angepasst."

#===============================================================================
#  5) Syslinux-Konfiguration (BIOS) – aktualisiert
#===============================================================================
info "Passe Syslinux-Konfiguration an ..."
mkdir -p "${PROFILE_DIR}/syslinux"

cat > "${PROFILE_DIR}/syslinux/syslinux.cfg" << 'SYSLINUXCFG'
SERIAL 0 115200
UI vesamenu.c32

DEFAULT archlinux
PROMPT 1
TIMEOUT 100

MENU TITLE Archlinux Gparted Live ISO
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

INCLUDE boot/syslinux/archiso_sys-linux.cfg
SYSLINUXCFG

cat > "${PROFILE_DIR}/syslinux/archiso_sys-linux.cfg" << 'SYSLINUXBOOT'
LABEL archlinux
    TEXT HELP
    Archlinux Gparted Live ISO starten (%ARCH%, BIOS)
    ENDTEXT
    MENU LABEL Archlinux Gparted Live ISO (%ARCH%, BIOS)
    LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
    INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
    APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% quiet splash

LABEL archlinux-verbose
    TEXT HELP
    Archlinux Gparted Live ISO starten (%ARCH%, BIOS) – Verbose
    ENDTEXT
    MENU LABEL Archlinux Gparted Live ISO (%ARCH%, BIOS) – Verbose
    LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
    INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
    APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID%

LABEL archlinux-copytoram
    TEXT HELP
    Archlinux Gparted Live ISO in RAM laden (%ARCH%, BIOS)
    ENDTEXT
    MENU LABEL Archlinux Gparted Live ISO (%ARCH%, BIOS) – Copy to RAM
    LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
    INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
    APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% copytoram quiet splash

LABEL reboot
    MENU LABEL System neu starten
    COM32 reboot.c32

LABEL poweroff
    MENU LABEL System ausschalten
    COM32 poweroff.c32
SYSLINUXBOOT
ok "Syslinux-Konfiguration angepasst."

#===============================================================================
#  6) Live-User Setup-Script (wird via Pacman-Hook ausgeführt)
#
#  WICHTIG: Wir legen KEINE statischen passwd/group/shadow/gshadow-Dateien
#  in airootfs/ ab! Das würde alle von Paketen angelegten System-Benutzer
#  (polkitd, dbus, avahi, colord, systemd-* etc.) zerstören, weil
#  mkarchiso airootfs/ NACH der Paketinstallation kopiert.
#
#  Stattdessen erstellt ein Pacman-Hook den Live-Benutzer NACH der
#  Installation aller Pakete, sodass alle System-User erhalten bleiben.
#===============================================================================
info "Erstelle Live-User Setup-Mechanismus ..."

erstelle_verzeichnis \
    "usr/local/bin" \
    "etc/pacman.d/hooks" \
    "etc/sudoers.d" \
    "etc/polkit-1/rules.d" \
    "etc/X11/xorg.conf.d" \
    "etc/systemd/system/multi-user.target.wants"

# --- Setup-Script: Erstellt den Live-Benutzer (Build-Zeit + Boot-Zeit) -------
cat > "${PROFILE_DIR}/airootfs/usr/local/bin/setup-live-user.sh" << 'SETUPSCRIPT'
#!/usr/bin/env bash
#===============================================================================
# setup-live-user.sh
# Wird DOPPELT ausgeführt (Belt-and-Suspenders):
#   1. Zur BUILD-Zeit via Pacman-Hook (nach Paketinstallation)
#   2. Zur BOOT-Zeit via systemd live-user-setup.service (vor getty)
#
# Alle Operationen sind idempotent – mehrfaches Ausführen ist sicher.
#===============================================================================
set -euo pipefail

LIVE_USER="live"
LIVE_UID=1000
LIVE_GID=1000
LIVE_HOME="/home/${LIVE_USER}"
LIVE_COMMENT="Archlinux Gparted Live"
LIVE_SHELL="/usr/bin/bash"
LIVE_GROUPS="wheel,storage,optical,power,network,video,audio"

log() { echo "[setup-live-user] $*"; }

# --- Gruppe "live" anlegen (idempotent) ---
if ! getent group "${LIVE_USER}" &>/dev/null; then
    groupadd -g "${LIVE_GID}" "${LIVE_USER}" && log "Gruppe '${LIVE_USER}' angelegt."
fi

# --- Benutzer anlegen (idempotent) ---
if ! id "${LIVE_USER}" &>/dev/null; then
    useradd -m \
        -u "${LIVE_UID}" \
        -g "${LIVE_GID}" \
        -G "${LIVE_GROUPS}" \
        -c "${LIVE_COMMENT}" \
        -s "${LIVE_SHELL}" \
        -d "${LIVE_HOME}" \
        "${LIVE_USER}" && log "Benutzer '${LIVE_USER}' angelegt."
else
    usermod -aG "${LIVE_GROUPS}" "${LIVE_USER}" 2>/dev/null || true
    log "Benutzer '${LIVE_USER}' existiert bereits – Gruppen aktualisiert."
fi

# --- Passwort entfernen (leeres Passwort für Autologin) ---
passwd -d "${LIVE_USER}" &>/dev/null || true

# --- Home-Verzeichnis einrichten ---
mkdir -p "${LIVE_HOME}/Desktop"
mkdir -p "${LIVE_HOME}/.config"
mkdir -p "${LIVE_HOME}/.local/share"
mkdir -p "${LIVE_HOME}/.cache"

# --- .xinitrc: startet MATE-Session via startx ---
cat > "${LIVE_HOME}/.xinitrc" << 'XINITRC'
#!/bin/sh
# Umgebung laden
[ -f /etc/xprofile ]       && . /etc/xprofile
[ -f "$HOME/.xprofile" ]   && . "$HOME/.xprofile"

# D-Bus Session (falls nicht bereits vorhanden)
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    eval "$(dbus-launch --sh-syntax --exit-with-x11)"
fi

# MATE starten
exec mate-session
XINITRC
chmod 755 "${LIVE_HOME}/.xinitrc"

# --- .bash_profile: Auto-startx auf TTY1 ---
cat > "${LIVE_HOME}/.bash_profile" << 'BASHPROFILE'
# Standardmäßige Profil-Dateien laden
[[ -f ~/.bashrc ]] && . ~/.bashrc

# Automatisch X starten, wenn:
#   - Wir auf TTY1 sind (nicht SSH, nicht anderes TTY)
#   - X noch nicht läuft
if [[ -z "${DISPLAY:-}" && "$(tty)" == "/dev/tty1" ]]; then
    exec startx -- -keeptty &>/dev/null
fi
BASHPROFILE

# Desktop-Shortcuts aus /etc/skel kopieren (falls vorhanden)
if [ -d /etc/skel/Desktop ]; then
    cp -n /etc/skel/Desktop/*.desktop "${LIVE_HOME}/Desktop/" 2>/dev/null || true
fi

# Berechtigungen korrigieren
chown -R "${LIVE_UID}:${LIVE_GID}" "${LIVE_HOME}"

# XDG_RUNTIME_DIR sicherstellen
RUNTIME_DIR="/run/user/${LIVE_UID}"
if [ ! -d "${RUNTIME_DIR}" ]; then
    mkdir -p "${RUNTIME_DIR}"
    chown "${LIVE_UID}:${LIVE_GID}" "${RUNTIME_DIR}"
    chmod 700 "${RUNTIME_DIR}"
fi

log "Einrichtung abgeschlossen."
SETUPSCRIPT

# --- Pacman-Hook: Setup-Script nach Paketinstallation ausführen --------------
# Triggert auf "base" (wird immer installiert), läuft als letztes (zz-Prefix)
cat > "${PROFILE_DIR}/airootfs/etc/pacman.d/hooks/zz-01-setup-live-user.hook" << 'EOF'
# remove from airootfs
[Trigger]
Operation = Install
Type = Package
Target = base

[Action]
Description = Erstelle Live-Benutzer ...
When = PostTransaction
Exec = /usr/local/bin/setup-live-user.sh
EOF

ok "Live-User Setup-Mechanismus erstellt."

#===============================================================================
#  7) Sudoers & Polkit
#===============================================================================
info "Erstelle Sudoers und Polkit-Regeln ..."

cat > "${PROFILE_DIR}/airootfs/etc/sudoers.d/10-live" << 'EOF'
live ALL=(ALL:ALL) NOPASSWD: ALL
EOF

cat > "${PROFILE_DIR}/airootfs/etc/polkit-1/rules.d/49-nopasswd-live.rules" << 'EOF'
polkit.addRule(function(action, subject) {
    if (subject.user === "live") {
        return polkit.Result.YES;
    }
});
EOF

ok "Sudoers und Polkit-Regeln erstellt."

#===============================================================================
#  8) Systemd-Services – Autologin via getty (ohne Display-Manager)
#
#  Ablauf:
#    1. systemd startet getty@tty1 mit Autologin als "live"
#    2. .bash_profile erkennt TTY1 + kein laufendes X → exec startx
#    3. .xinitrc startet dbus-launch + mate-session
#
#  Kein LightDM, kein Display-Manager, keine PAM-Autologin-Probleme.
#===============================================================================
info "Konfiguriere Autologin via getty ..."

# Multi-User Target als Standard (kein Graphical Target nötig ohne DM)
erstelle_verzeichnis "etc/systemd/system"
ln -sf /usr/lib/systemd/system/multi-user.target \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/default.target"

# NetworkManager
ln -sf /usr/lib/systemd/system/NetworkManager.service \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/NetworkManager.service"

# --- getty@tty1 Override: Autologin als "live" ---
erstelle_verzeichnis "etc/systemd/system/getty@tty1.service.d"
cat > "${PROFILE_DIR}/airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'EOF'
[Service]
# Standard-getty-Zeile überschreiben
ExecStart=
ExecStart=-/sbin/agetty --autologin live --noclear %I $TERM
Type=idle
EOF

# --- Live-User Setup Service (läuft vor getty) ---
cat > "${PROFILE_DIR}/airootfs/etc/systemd/system/live-user-setup.service" << 'EOF'
[Unit]
Description=Live-Benutzer einrichten
DefaultDependencies=no
Before=getty@tty1.service
After=systemd-sysusers.service systemd-tmpfiles-setup.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/setup-live-user.sh

[Install]
WantedBy=multi-user.target
EOF

# Service aktivieren
ln -sf /etc/systemd/system/live-user-setup.service \
    "${PROFILE_DIR}/airootfs/etc/systemd/system/multi-user.target.wants/live-user-setup.service"

ok "Autologin via getty konfiguriert."

#===============================================================================
#  10) Desktop-Shortcuts
#===============================================================================
info "Erstelle Desktop-Shortcuts ..."

# Desktop-Verzeichnis wird vom setup-live-user.sh erstellt.
# Hier legen wir die .desktop-Dateien im skel ab, und kopieren sie via Hook.
erstelle_verzeichnis "etc/skel/Desktop"

declare -A SHORTCUTS=(
    ["gparted"]="Name=GParted
Comment=Partitionen verwalten
Exec=pkexec gparted
Icon=gparted
Terminal=false
Type=Application
Categories=System;"

    ["gnome-disks"]="Name=GNOME Laufwerke
Comment=Festplatten und Laufwerke verwalten
Exec=gnome-disks
Icon=org.gnome.DiskUtility
Terminal=false
Type=Application
Categories=System;"

    ["deja-dup"]="Name=Déjà Dup Datensicherung
Comment=Dateien sichern und wiederherstellen
Exec=deja-dup
Icon=org.gnome.DejaDup
Terminal=false
Type=Application
Categories=System;Utility;"

    ["terminal"]="Name=Terminal
Comment=MATE Terminal
Exec=mate-terminal
Icon=utilities-terminal
Terminal=false
Type=Application
Categories=System;"
)

for name in "${!SHORTCUTS[@]}"; do
    cat > "${PROFILE_DIR}/airootfs/etc/skel/Desktop/${name}.desktop" << DESKTOP_EOF
[Desktop Entry]
${SHORTCUTS[$name]}
DESKTOP_EOF
done

ok "Desktop-Shortcuts erstellt."

#===============================================================================
#  11) Locale & Tastatur – via Pacman-Hook
#===============================================================================
info "Setze Locale und Tastatur auf Deutsch ..."

echo -e "de_DE.UTF-8 UTF-8\nen_US.UTF-8 UTF-8" \
    > "${PROFILE_DIR}/airootfs/etc/locale.gen"
echo "LANG=de_DE.UTF-8"   > "${PROFILE_DIR}/airootfs/etc/locale.conf"
echo "KEYMAP=de-latin1"    > "${PROFILE_DIR}/airootfs/etc/vconsole.conf"
echo "${ISO_NAME}"         > "${PROFILE_DIR}/airootfs/etc/hostname"

# Pacman-Hook: locale-gen nach glibc-Installation
cat > "${PROFILE_DIR}/airootfs/etc/pacman.d/hooks/40-locale-gen.hook" << 'EOF'
# remove from airootfs
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = glibc

[Action]
Description = Generiere Locales ...
When = PostTransaction
Exec = /usr/bin/locale-gen
EOF

# X11 Tastaturlayout
cat > "${PROFILE_DIR}/airootfs/etc/X11/xorg.conf.d/00-keyboard.conf" << 'EOF'
Section "InputClass"
    Identifier "Tastatur-Layout"
    MatchIsKeyboard "on"
    Option "XkbLayout"  "de"
    Option "XkbVariant" "nodeadkeys"
EndSection
EOF

ok "Locale und Tastatur gesetzt."

#===============================================================================
#  12) Systemd-Konfigurationen (Live-System-Anpassungen)
#===============================================================================
info "Erstelle zusätzliche Systemd-Konfigurationen ..."

# Volatile Journal-Speicher
erstelle_verzeichnis "etc/systemd/journald.conf.d"
cat > "${PROFILE_DIR}/airootfs/etc/systemd/journald.conf.d/volatile-storage.conf" << 'EOF'
[Journal]
Storage=volatile
EOF

# Kein Suspend auf Lid-Close
erstelle_verzeichnis "etc/systemd/logind.conf.d"
cat > "${PROFILE_DIR}/airootfs/etc/systemd/logind.conf.d/do-not-suspend.conf" << 'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchDocked=ignore
HandleLidSwitchExternalPower=ignore
EOF

ok "Systemd-Konfigurationen erstellt."

#===============================================================================
#  13) MOTD
#===============================================================================
cat > "${PROFILE_DIR}/airootfs/etc/motd" << 'EOF'

  ╔════════════════════════════════════════════════════════════╗
  ║          Archlinux Gparted Live ISO – Werkzeuge            ║
  ║                                                            ║
  ║  • GParted              – Partitionen verwalten            ║
  ║  • GNOME Laufwerke      – Festplatten verwalten            ║
  ║  • Déjà Dup             – Datensicherung                   ║
  ║  • rsync                – Dateisynchronisation             ║
  ║  • testdisk / ddrescue  – Datenrettung                     ║
  ║  • fsarchiver           – Dateisystem-Archivierung         ║
  ╚════════════════════════════════════════════════════════════╝

EOF

#===============================================================================
#  14) Statische passwd/group/shadow/gshadow aus airootfs entfernen
#      (Falls vom releng-Template mitgebracht)
#===============================================================================
info "Entferne statische Benutzerdateien aus dem Profil (werden via Hook erstellt) ..."
for datei in passwd shadow group gshadow; do
    rm -f "${PROFILE_DIR}/airootfs/etc/${datei}"
done
ok "Statische Benutzerdateien entfernt."

#===============================================================================
#  15) ISO bauen
#===============================================================================
echo ""
info "Starte ISO-Build mit mkarchiso ..."
info "  Profil:      ${PROFILE_DIR}"
info "  Arbeitsdir:  ${WORK_DIR}"
info "  Ausgabe:     ${OUT_DIR}"
echo ""

mkdir -p "$OUT_DIR"
chown "${REAL_USER}:${REAL_USER}" "$OUT_DIR"

if ! mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"; then
    fehler "mkarchiso ist fehlgeschlagen. Prüfe die Ausgabe oben."
fi

# Dateien dem echten Benutzer zuweisen
chown -R "${REAL_USER}:${REAL_USER}" "$OUT_DIR"

#--- Abschlussmeldung ----------------------------------------------------------
ISO_FILE=$(find "$OUT_DIR" -maxdepth 1 -name "${ISO_NAME}-*.iso" -printf '%f\n' 2>/dev/null | head -1)
echo ""
echo -e "${GRUEN}════════════════════════════════════════════════════════════════${RESET}"
echo -e "${GRUEN}  ISO erfolgreich erstellt!${RESET}"
echo -e "${GRUEN}════════════════════════════════════════════════════════════════${RESET}"
echo ""

if [[ -n "${ISO_FILE:-}" ]]; then
    ls -lh "${OUT_DIR}/${ISO_FILE}"
    echo ""
    info "Auf USB-Stick schreiben:"
    echo "  sudo dd bs=4M if=${OUT_DIR}/${ISO_FILE} of=/dev/sdX status=progress oflag=sync"
else
    warn "ISO-Datei nicht gefunden – prüfe ${OUT_DIR}"
fi
echo ""

#--- Aufräumen (optional) ------------------------------------------------------
read -rp "Work-Verzeichnis aufräumen? (${WORK_DIR}) [j/N] " antwort
if [[ "${antwort,,}" == "j" ]]; then
    rm -rf "$WORK_DIR" "$PROFILE_DIR"
    ok "Aufgeräumt."
else
    info "Work-Verzeichnis bleibt erhalten: ${WORK_DIR}"
fi
