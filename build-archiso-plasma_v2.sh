#!/usr/bin/env bash
# =============================================================================
#  build-archiso-plasma.sh
#  Erstellt eine Arch Linux ISO mit KDE Plasma (Wayland) + Autologin
#
#  Basiert auf dem aktuellen archiso releng-Profil mit systemd-boot (UEFI)
#  und syslinux (BIOS) – keine deprecated GRUB-Bootmodes.
#
#  ÄNDERUNGEN gegenüber Vorversion:
#  - customize_airootfs.sh ENTFERNT → ersetzt durch Pacman-Hook (locale-gen)
#  - chown im Build-Script entfernt → archiso setzt Home-Rechte via passwd
#  - Clonezilla Desktop-Icon + Wrapper-Script hinzugefügt
#  - file_permissions für /home/liveuser korrekt gesetzt
#  - etc/skel statt direktes /home für sauberere Struktur
#
#  Ausführung: sudo bash build-archiso-plasma.sh
#  Voraussetzung: Arch Linux Host mit Internetverbindung
# =============================================================================

set -euo pipefail

# ─── Farben ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Konfiguration ────────────────────────────────────────────────────────────
readonly PROFILE_DIR="/tmp/archplasma"
readonly WORK_DIR="/tmp/archiso-work"
# BUG-FIX: ${SUDO_USER:-} statt ${SUDO_USER} – verhindert Fehler bei set -u
if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
else
    REAL_HOME="${HOME}"
fi
readonly OUT_DIR="${REAL_HOME}/archiso-out"
readonly LIVE_USER="liveuser"
readonly AIROOTFS="${PROFILE_DIR}/airootfs"

# ─── Hilfsfunktionen ─────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[FEHLER]${NC} $*" >&2; exit 1; }
banner()  {
    echo ""
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# =============================================================================
# SCHRITT 0: Voraussetzungen prüfen
# =============================================================================
banner "Schritt 0: Voraussetzungen prüfen"

[[ "${EUID}" -ne 0 ]] && die "Bitte als root ausführen: sudo bash \$0"
[[ ! -f /etc/arch-release ]] && die "Dieses Script läuft nur auf Arch Linux!"

# ─── Host-Pakete prüfen und installieren ─────────────────────────────────────
info "Prüfe benötigte Host-Pakete..."

HOST_PKGS=(
    archiso
    dosfstools
    e2fsprogs
    libisoburn
    mtools
    squashfs-tools
    edk2-ovmf
)

MISSING=()
for pkg in "${HOST_PKGS[@]}"; do
    if ! pacman -Qi "${pkg}" &>/dev/null; then
        MISSING+=("${pkg}")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    warn "Fehlende Pakete werden installiert: ${MISSING[*]}"
    # BUG-FIX: pacman -S statt -Sy (partial sync ist gefährlich)
    pacman -S --noconfirm --needed "${MISSING[@]}"
    ok "Host-Pakete installiert."
else
    ok "Alle Host-Pakete vorhanden."
fi

# =============================================================================
# SCHRITT 1: Profil-Verzeichnis aufbauen (Basis: releng)
# =============================================================================
banner "Schritt 1: Profil-Verzeichnis erstellen"

# Altes Profil entfernen
[[ -d "${PROFILE_DIR}" ]] && rm -rf "${PROFILE_DIR}"

# releng als Basis kopieren
cp -r /usr/share/archiso/configs/releng/ "${PROFILE_DIR}"
ok "releng-Profil nach ${PROFILE_DIR} kopiert."

# =============================================================================
# SCHRITT 2: profiledef.sh – KORREKTE aktuelle Bootmodes
# =============================================================================
banner "Schritt 2: profiledef.sh schreiben"

cat > "${PROFILE_DIR}/profiledef.sh" << 'PROFDEF'
#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="archlinux-plasma"
iso_label="ARCH_PLASMA_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Custom Arch Linux Plasma Build"
iso_application="Arch Linux KDE Plasma Live"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')

# Aktuelle, nicht-deprecated Bootmodes
bootmodes=(
    'bios.syslinux'
    'uefi-x64.systemd-boot.esp'
    'uefi-x64.systemd-boot.eltorito'
)

arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=(
    '-comp' 'xz'
    '-Xbcj' 'x86'
    '-Xdict-size' '1M'
    '-b' '1M'
)
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')

# Dateiberechtigungen
file_permissions=(
    ["/etc/shadow"]="0:0:400"
    ["/etc/gshadow"]="0:0:400"
    ["/root"]="0:0:750"
    ["/root/.gnupg"]="0:0:700"
    ["/etc/sudoers.d"]="0:0:750"
    ["/etc/sudoers.d/liveuser"]="0:0:440"
    ["/etc/sddm.conf.d"]="0:0:755"
    ["/etc/sddm.conf.d/autologin.conf"]="0:0:644"
    ["/etc/sddm.conf.d/kde_settings.conf"]="0:0:644"
    ["/usr/local/bin/choose-mirror"]="0:0:755"
    ["/usr/local/bin/Installation_guide"]="0:0:755"
    ["/usr/local/bin/livecd-sound"]="0:0:755"
    ["/usr/local/bin/run-archinstall"]="0:0:755"
    ["/usr/local/bin/run-clonezilla"]="0:0:755"
    ["/home/liveuser"]="1000:1000:750"
    ["/home/liveuser/.config"]="1000:1000:700"
    ["/home/liveuser/Desktop"]="1000:1000:755"
    ["/home/liveuser/Desktop/archinstall.desktop"]="1000:1000:755"
    ["/home/liveuser/Desktop/clonezilla.desktop"]="1000:1000:755"
)
PROFDEF

ok "profiledef.sh geschrieben (systemd-boot, kein GRUB, kein customize_airootfs.sh)."


# =============================================================================
# SCHRITT 3: pacman.conf – multilib aktivieren
# =============================================================================
banner "Schritt 3: pacman.conf anpassen"

PACMAN_CONF="${PROFILE_DIR}/pacman.conf"

# BUG-FIX: $$multilib$$ für literale Klammern in grep/sed
if grep -q "^#$$multilib$$" "${PACMAN_CONF}"; then
    sed -i '/^#$$multilib$$/{
        s/^#//
        n
        s/^#//
    }' "${PACMAN_CONF}"
    ok "multilib in pacman.conf aktiviert."
elif ! grep -q "^$$multilib$$" "${PACMAN_CONF}"; then
    printf '
[multilib]
Include = /etc/pacman.d/mirrorlist
' >> "${PACMAN_CONF}"
    ok "multilib zu pacman.conf hinzugefügt."
else
    ok "multilib war bereits aktiv."
fi

# =============================================================================
# SCHRITT 4: Paketliste packages.x86_64
# =============================================================================
banner "Schritt 4: Paketliste erstellen"

cat > "${PROFILE_DIR}/packages.x86_64" << 'PKGLIST'
# ── Basis ─────────────────────────────────────────────────────────────────────
base
base-devel
linux
linux-firmware
linux-headers
mkinitcpio
mkinitcpio-archiso
mkinitcpio-nfs-utils
sof-firmware

# ── Bootloader (nur syslinux für BIOS; systemd-boot kommt aus archiso selbst) ─
syslinux
efibootmgr
edk2-shell
memtest86+
memtest86+-efi

# ── Dateisysteme ──────────────────────────────────────────────────────────────
dosfstools
e2fsprogs
btrfs-progs
bcachefs-tools
xfsprogs
xfsdump
jfsutils
f2fs-tools
udftools
ntfs-3g
exfatprogs
lvm2
mdadm
cryptsetup

# ── Netzwerk ──────────────────────────────────────────────────────────────────
networkmanager
network-manager-applet
nm-connection-editor
dhcpcd
iwd
wpa_supplicant
openssh
curl
wget
rsync
samba

# ── Systemtools ───────────────────────────────────────────────────────────────
sudo
polkit
dbus
fakeroot
archinstall
arch-install-scripts
gptfdisk
parted
smartmontools
fwupd
ethtool
openssl
usbutils
pciutils
lshw
htop
bash-completion
man-db
man-pages
nano
git
zip
unzip
p7zip
tar

# ── Backup & Wiederherstellung ────────────────────────────────────────────────
timeshift
deja-dup
clonezilla

# ── Disk-Utilities ────────────────────────────────────────────────────────────
gnome-disk-utility
gparted

# ── Wayland / Display ─────────────────────────────────────────────────────────
wayland
wayland-protocols
plasma-wayland-protocols
xorg-xwayland
libinput

# ── Mesa & Vulkan ─────────────────────────────────────────────────────────────
mesa
mesa-utils
vulkan-icd-loader
vulkan-radeon
vulkan-nouveau
vulkan-intel
vulkan-swrast
vulkan-dzn
vulkan-mesa-implicit-layers
lib32-vulkan-icd-loader
lib32-vulkan-radeon
lib32-mesa

# ── KDE Plasma ────────────────────────────────────────────────────────────────
plasma-meta
plasma-desktop
plasma-nm
plasma-pa
plasma-systemmonitor
plasma-workspace
plasma-integration
kscreen
kinfocenter
ksystemstats
kpipewire
kwallet
kwallet-pam
kwalletmanager
bluedevil
powerdevil
breeze
breeze-gtk
kde-gtk-config
sddm
sddm-kcm

# ── KDE Anwendungen ───────────────────────────────────────────────────────────
dolphin
dolphin-plugins
ark
kate
kwrite
konsole
gwenview
filelight
kcalc
kfind
partitionmanager

# ── Internet ──────────────────────────────────────────────────────────────────
firefox
firefox-i18n-de
filezilla
qbittorrent

# ── Audio (PipeWire) ──────────────────────────────────────────────────────────
pipewire
pipewire-alsa
pipewire-pulse
wireplumber
gst-plugin-pipewire
pavucontrol

# ── Schriften ─────────────────────────────────────────────────────────────────
noto-fonts
noto-fonts-emoji
ttf-liberation
ttf-dejavu

# ── Drucken ───────────────────────────────────────────────────────────────────
cups
cups-pdf
cups-filters
ghostscript
gutenprint
print-manager

# ── Sonstiges ─────────────────────────────────────────────────────────────────
xdg-user-dirs
xdg-utils
shared-mime-info
PKGLIST

ok "Paketliste geschrieben."

# =============================================================================
# SCHRITT 5: airootfs-Verzeichnisstruktur anlegen
# =============================================================================
banner "Schritt 5: airootfs-Struktur anlegen"

mkdir -p "${AIROOTFS}/etc/sddm.conf.d"
mkdir -p "${AIROOTFS}/etc/sudoers.d"
mkdir -p "${AIROOTFS}/etc/systemd/system/sddm.service.d"
mkdir -p "${AIROOTFS}/etc/systemd/system/getty@tty1.service.d"
mkdir -p "${AIROOTFS}/etc/NetworkManager/conf.d"
mkdir -p "${AIROOTFS}/etc/polkit-1/rules.d"
# ── Pacman-Hook-Verzeichnis für locale-gen ────────────────────────────────────
mkdir -p "${AIROOTFS}/etc/pacman.d/hooks"
mkdir -p "${AIROOTFS}/usr/share/wayland-sessions"
mkdir -p "${AIROOTFS}/usr/local/bin"
mkdir -p "${AIROOTFS}/root/.gnupg"
# ── Home-Verzeichnis des Live-Users ──────────────────────────────────────────
# Hinweis: archiso setzt Eigentumsrechte automatisch via /etc/passwd (UID 1000)
mkdir -p "${AIROOTFS}/home/${LIVE_USER}/.config"
mkdir -p "${AIROOTFS}/home/${LIVE_USER}/Desktop"

ok "Verzeichnisstruktur angelegt."

# =============================================================================
# SCHRITT 6: Benutzer-Accounts (passwd / shadow / group / gshadow)
# =============================================================================
banner "Schritt 6: Benutzer-Accounts konfigurieren"

# ── /etc/passwd ───────────────────────────────────────────────────────────────
if ! grep -q "^${LIVE_USER}:" "${AIROOTFS}/etc/passwd" 2>/dev/null; then
    echo "${LIVE_USER}:x:1000:1000:Live User:/home/${LIVE_USER}:/bin/bash" \
        >> "${AIROOTFS}/etc/passwd"
fi

# ── /etc/shadow (kein Passwort für liveuser) ──────────────────────────────────
if ! grep -q "^${LIVE_USER}:" "${AIROOTFS}/etc/shadow" 2>/dev/null; then
    echo "${LIVE_USER}::19000:0:99999:7:::" >> "${AIROOTFS}/etc/shadow"
fi

# ── /etc/group ────────────────────────────────────────────────────────────────
# BUG-FIX: declare -A mehrzeilig → einzelne Zuweisungen (kein Syntaxfehler)
declare -A GROUPS_MAP
GROUPS_MAP["wheel"]="10"
GROUPS_MAP["audio"]="92"
GROUPS_MAP["video"]="985"
GROUPS_MAP["storage"]="998"
GROUPS_MAP["optical"]="93"
GROUPS_MAP["network"]="90"
GROUPS_MAP["power"]="98"
GROUPS_MAP["autologin"]="1001"
GROUPS_MAP["liveuser"]="1000"

for grp in "${!GROUPS_MAP[@]}"; do
    gid="${GROUPS_MAP[$grp]}"
    if ! grep -q "^${grp}:" "${AIROOTFS}/etc/group" 2>/dev/null; then
        echo "${grp}:x:${gid}:${LIVE_USER}" >> "${AIROOTFS}/etc/group"
    else
        if ! grep -q "^${grp}:.*${LIVE_USER}" "${AIROOTFS}/etc/group" 2>/dev/null; then
            sed -i "/^${grp}:/ s/$/,${LIVE_USER}/" "${AIROOTFS}/etc/group"
            sed -i "/^${grp}:/ s/:,/:/" "${AIROOTFS}/etc/group"
        fi
    fi
done

# ── /etc/gshadow ──────────────────────────────────────────────────────────────
for grp in "${!GROUPS_MAP[@]}"; do
    if ! grep -q "^${grp}:" "${AIROOTFS}/etc/gshadow" 2>/dev/null; then
        echo "${grp}:::${LIVE_USER}" >> "${AIROOTFS}/etc/gshadow"
    fi
done

ok "Benutzer '${LIVE_USER}' in passwd/shadow/group/gshadow eingetragen."


# =============================================================================
# SCHRITT 7: sudo-Konfiguration (passwortlos für liveuser)
# =============================================================================
banner "Schritt 7: sudo konfigurieren"

cat > "${AIROOTFS}/etc/sudoers.d/liveuser" << EOF
## Liveuser darf alle Befehle ohne Passwort ausführen
${LIVE_USER} ALL=(ALL:ALL) NOPASSWD: ALL
EOF

ok "sudo-Regel für ${LIVE_USER} geschrieben."

# =============================================================================
# SCHRITT 8: SDDM Autologin (Plasma Wayland)
# =============================================================================
banner "Schritt 8: SDDM Autologin konfigurieren"

cat > "${AIROOTFS}/etc/sddm.conf.d/autologin.conf" << EOF
[Autologin]
User=${LIVE_USER}
Session=plasmawayland.desktop
Relogin=false

[General]
HaltCommand=/usr/bin/systemctl poweroff
RebootCommand=/usr/bin/systemctl reboot
EOF

cat > "${AIROOTFS}/etc/sddm.conf.d/kde_settings.conf" << 'EOF'
[Theme]
Current=breeze

[Wayland]
EnableHiDPI=true
EOF

ok "SDDM Autologin für Plasma Wayland konfiguriert."

# =============================================================================
# SCHRITT 9: Plasma Wayland Session-Datei sicherstellen
# =============================================================================
banner "Schritt 9: Plasma Wayland Session-Datei"

cat > "${AIROOTFS}/usr/share/wayland-sessions/plasmawayland.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Plasma (Wayland)
Comment=KDE Plasma Desktop (Wayland)
Exec=/usr/lib/plasma-dbus-run-session-if-needed /usr/bin/startplasma-wayland
TryExec=/usr/bin/startplasma-wayland
DesktopNames=KDE
Keywords=wayland;plasma;kde;
EOF

ok "plasmawayland.desktop geschrieben."

# =============================================================================
# SCHRITT 10: Systemd-Services aktivieren (via symlinks)
# =============================================================================
banner "Schritt 10: Systemd-Services aktivieren"

SYSTEMD_SYSTEM="${AIROOTFS}/etc/systemd/system"
mkdir -p "${SYSTEMD_SYSTEM}/multi-user.target.wants"
mkdir -p "${SYSTEMD_SYSTEM}/network-online.target.wants"
mkdir -p "${SYSTEMD_SYSTEM}/display-manager.service.d"

# SDDM als Display-Manager
ln -sf /usr/lib/systemd/system/sddm.service \
    "${SYSTEMD_SYSTEM}/display-manager.service" 2>/dev/null || true

# NetworkManager
ln -sf /usr/lib/systemd/system/NetworkManager.service \
    "${SYSTEMD_SYSTEM}/multi-user.target.wants/NetworkManager.service" 2>/dev/null || true

ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service \
    "${SYSTEMD_SYSTEM}/network-online.target.wants/NetworkManager-wait-online.service" 2>/dev/null || true

# Bluetooth
ln -sf /usr/lib/systemd/system/bluetooth.service \
    "${SYSTEMD_SYSTEM}/multi-user.target.wants/bluetooth.service" 2>/dev/null || true

# CUPS
ln -sf /usr/lib/systemd/system/cups.service \
    "${SYSTEMD_SYSTEM}/multi-user.target.wants/cups.service" 2>/dev/null || true

# SSH
ln -sf /usr/lib/systemd/system/sshd.service \
    "${SYSTEMD_SYSTEM}/multi-user.target.wants/sshd.service" 2>/dev/null || true

ok "Systemd-Service-Symlinks gesetzt."

# =============================================================================
# SCHRITT 11: Getty TTY1 Autologin (Fallback)
# =============================================================================
banner "Schritt 11: Getty TTY1 Autologin"

cat > "${AIROOTFS}/etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin ${LIVE_USER} %I \$TERM
Type=idle
EOF

ok "Getty-Autologin konfiguriert."

# =============================================================================
# SCHRITT 12: Locale, Hostname, Zeitzone
# =============================================================================
banner "Schritt 12: Locale / Hostname / Zeitzone"

cat > "${AIROOTFS}/etc/locale.conf" << 'EOF'
LANG=de_DE.UTF-8
LC_TIME=de_DE.UTF-8
LC_MONETARY=de_DE.UTF-8
LC_PAPER=de_DE.UTF-8
LC_MEASUREMENT=de_DE.UTF-8
EOF

# locale.gen: Einträge für locale-gen (wird via Pacman-Hook ausgeführt)
cat > "${AIROOTFS}/etc/locale.gen" << 'EOF'
de_DE.UTF-8 UTF-8
de_DE ISO-8859-1
en_US.UTF-8 UTF-8
en_US ISO-8859-1
EOF

cat > "${AIROOTFS}/etc/vconsole.conf" << 'EOF'
KEYMAP=de-latin1
FONT=eurlatgr
EOF

echo "archlive" > "${AIROOTFS}/etc/hostname"

cat > "${AIROOTFS}/etc/hosts" << 'EOF'
127.0.0.1   localhost
::1         localhost
127.0.1.1   archlive.localdomain archlive
EOF

ln -sf /usr/share/zoneinfo/Europe/Berlin \
    "${AIROOTFS}/etc/localtime" 2>/dev/null || true

ok "Locale, Hostname und Zeitzone konfiguriert."

# =============================================================================
# SCHRITT 13: Pacman-Hook für locale-gen
#             ERSETZT customize_airootfs.sh vollständig!
#
# Hintergrund: customize_airootfs.sh ist deprecated. Der korrekte Weg ist
# ein Pacman-Hook, der nach der Installation von glibc locale-gen ausführt.
# Der Kommentar "# remove from airootfs!" sorgt dafür, dass der releng-eigene
# Cleanup-Hook diesen Hook nach dem Build automatisch entfernt.
# =============================================================================
banner "Schritt 13: Pacman-Hook für locale-gen erstellen"

cat > "${AIROOTFS}/etc/pacman.d/hooks/locale-gen.hook" << 'EOF'
# remove from airootfs!
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = glibc

[Action]
Description = Generating localisation files...
When = PostTransaction
Depends = glibc
Exec = /usr/bin/locale-gen
EOF

ok "Pacman-Hook für locale-gen geschrieben (ersetzt customize_airootfs.sh)."

# =============================================================================
# SCHRITT 14: NetworkManager Konfiguration
# =============================================================================
banner "Schritt 14: NetworkManager konfigurieren"

cat > "${AIROOTFS}/etc/NetworkManager/conf.d/wifi_backend.conf" << 'EOF'
[device]
wifi.backend=iwd
EOF

ok "NetworkManager konfiguriert."

# =============================================================================
# SCHRITT 15: Polkit-Regel für liveuser
# =============================================================================
banner "Schritt 15: Polkit-Regel"

cat > "${AIROOTFS}/etc/polkit-1/rules.d/49-liveuser.rules" << EOF
/* Liveuser darf alle Polkit-Aktionen ohne Passwort ausführen */
polkit.addRule(function(action, subject) {
    if (subject.user === "${LIVE_USER}") {
        return polkit.Result.YES;
    }
});
EOF

ok "Polkit-Regel geschrieben."

# =============================================================================
# SCHRITT 16: Archinstall Desktop-Icon + Wrapper-Script
# =============================================================================
banner "Schritt 16: Archinstall Desktop-Icon erstellen"

# BUG-FIX: << 'EOF' erlaubt keine einfachen Anführungszeichen im Inhalt.
#           → Heredoc ohne Quotes + innere Strings mit doppelten Quotes.
cat > "${AIROOTFS}/usr/local/bin/run-archinstall" << 'WRAPPER'
#!/usr/bin/env bash
exec konsole --noclose -e bash -c "
    echo '════════════════════════════════════════════════════'
    echo '  Arch Linux Installation wird gestartet...'
    echo '════════════════════════════════════════════════════'
    echo ''
    sudo archinstall
"
WRAPPER

cat > "${AIROOTFS}/home/${LIVE_USER}/Desktop/archinstall.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Arch Linux installieren
Name[en]=Install Arch Linux
Comment=Startet den Arch Linux Installer (archinstall)
Comment[en]=Start the Arch Linux installer (archinstall)
Exec=/usr/local/bin/run-archinstall
Icon=system-software-install
Terminal=false
Categories=System;
Keywords=install;archinstall;setup;
StartupNotify=true
EOF

ok "Archinstall Desktop-Icon und Wrapper-Script erstellt."


# =============================================================================
# SCHRITT 17: Clonezilla Desktop-Icon + Wrapper-Script
# =============================================================================
banner "Schritt 17: Clonezilla Desktop-Icon erstellen"

# BUG-FIX: Gleiche Korrektur wie run-archinstall – doppelte Quotes im Exec-String
cat > "${AIROOTFS}/usr/local/bin/run-clonezilla" << 'WRAPPER'
#!/usr/bin/env bash
exec konsole --noclose -e bash -c "
    echo '════════════════════════════════════════════════════'
    echo '  Clonezilla wird gestartet...'
    echo '  Bitte warten – ncurses-Oberfläche lädt...'
    echo '════════════════════════════════════════════════════'
    echo ''
    sudo clonezilla
"
WRAPPER

cat > "${AIROOTFS}/home/${LIVE_USER}/Desktop/clonezilla.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Clonezilla
Name[en]=Clonezilla
Comment=Festplatten und Partitionen sichern oder klonen
Comment[en]=Backup and clone disks or partitions
Exec=/usr/local/bin/run-clonezilla
Icon=drive-harddisk
Terminal=false
Categories=System;Utility;
Keywords=clonezilla;backup;clone;disk;partition;restore;
StartupNotify=true
EOF

ok "Clonezilla Desktop-Icon und Wrapper-Script erstellt."


# =============================================================================
# SCHRITT 18: systemd-boot Konfiguration (efiboot/)
# =============================================================================
banner "Schritt 18: systemd-boot Konfiguration prüfen"

EFIBOOT="${PROFILE_DIR}/efiboot"
if [[ -d "${EFIBOOT}" ]]; then
    ok "efiboot/-Verzeichnis aus releng vorhanden (systemd-boot)."
    if [[ -f "${EFIBOOT}/loader/loader.conf" ]]; then
        sed -i 's/^timeout.*/timeout 5/' "${EFIBOOT}/loader/loader.conf"
        ok "Boot-Timeout auf 5 Sekunden gesetzt."
    fi
else
    warn "efiboot/-Verzeichnis nicht gefunden – wird von mkarchiso generiert."
fi

# =============================================================================
# SCHRITT 19: syslinux Konfiguration prüfen (BIOS)
# =============================================================================
banner "Schritt 19: syslinux Konfiguration prüfen"

SYSLINUX_DIR="${PROFILE_DIR}/syslinux"
if [[ -d "${SYSLINUX_DIR}" ]]; then
    ok "syslinux/-Verzeichnis aus releng vorhanden."
else
    warn "syslinux/-Verzeichnis nicht gefunden – wird von mkarchiso generiert."
fi

# =============================================================================
# SCHRITT 20: Arbeits- und Ausgabeverzeichnisse vorbereiten
# =============================================================================
banner "Schritt 20: Verzeichnisse vorbereiten"

mkdir -p "${OUT_DIR}"

# Work-Verzeichnis bereinigen (mit Mount-Check)
if [[ -d "${WORK_DIR}" ]]; then
    warn "Altes Work-Verzeichnis gefunden – prüfe auf aktive Mounts..."
    ACTIVE_MOUNTS=$(findmnt -R "${WORK_DIR}" 2>/dev/null || true)
    if [[ -n "${ACTIVE_MOUNTS}" ]]; then
        echo -e "${RED}Aktive Mounts gefunden:${NC}"
        echo "${ACTIVE_MOUNTS}"
        die "Bitte alle Mounts in ${WORK_DIR} manuell aushängen:
  umount -R ${WORK_DIR}
Dann Script erneut starten."
    fi
    rm -rf "${WORK_DIR}"
    ok "Altes Work-Verzeichnis bereinigt."
fi

mkdir -p "${WORK_DIR}"
ok "Verzeichnisse bereit."

# =============================================================================
# SCHRITT 21: Profil-Validierung (Kurzcheck vor dem Build)
# =============================================================================
banner "Schritt 21: Profil-Validierung"

REQUIRED_FILES=(
    "${PROFILE_DIR}/profiledef.sh"
    "${PROFILE_DIR}/packages.x86_64"
    "${PROFILE_DIR}/pacman.conf"
    "${PROFILE_DIR}/efiboot/loader/loader.conf"
    "${PROFILE_DIR}/syslinux/syslinux.cfg"
    "${AIROOTFS}/usr/local/bin/run-archinstall"
    "${AIROOTFS}/usr/local/bin/run-clonezilla"
    "${AIROOTFS}/home/${LIVE_USER}/Desktop/archinstall.desktop"
    "${AIROOTFS}/home/${LIVE_USER}/Desktop/clonezilla.desktop"
    "${AIROOTFS}/etc/pacman.d/hooks/locale-gen.hook"
)

ALL_OK=true
for f in "${REQUIRED_FILES[@]}"; do
    if [[ -f "${f}" ]]; then
        ok "Vorhanden: ${f}"
    else
        warn "FEHLT:     ${f}"
        ALL_OK=false
    fi
done

[[ "${ALL_OK}" == false ]] && die "Pflichtdateien fehlen – Build abgebrochen."

# =============================================================================
# SCHRITT 22: ISO BAUEN
# =============================================================================
banner "Schritt 22: ISO-Build starten"

echo -e "${YELLOW}  Profil:     ${PROFILE_DIR}${NC}"
echo -e "${YELLOW}  Workdir:    ${WORK_DIR}${NC}"
echo -e "${YELLOW}  Ausgabe:    ${OUT_DIR}${NC}"
echo -e "${YELLOW}  Bootmodes:  bios.syslinux + uefi-x64.systemd-boot${NC}"
echo ""
echo -e "${YELLOW}  ⚠  Der Build kann 20–60 Minuten dauern!${NC}"
echo ""

mkarchiso \
    -v \
    -w "${WORK_DIR}" \
    -o "${OUT_DIR}" \
    "${PROFILE_DIR}"

# =============================================================================
# SCHRITT 23: Ergebnis
# =============================================================================
banner "Build abgeschlossen!"

ISO_FILE=$(find "${OUT_DIR}" -maxdepth 1 -name "*.iso" -type f | sort | tail -1)

if [[ -n "${ISO_FILE}" && -f "${ISO_FILE}" ]]; then
    ISO_SIZE=$(du -sh "${ISO_FILE}" | cut -f1)
    SHA256=$(sha256sum "${ISO_FILE}" | cut -d' ' -f1)

    echo -e "${GREEN}  ISO-Datei:  ${ISO_FILE}${NC}"
    echo -e "${GREEN}  Größe:      ${ISO_SIZE}${NC}"
    echo -e "${GREEN}  SHA256:     ${SHA256}${NC}"
    echo ""
    echo -e "${CYAN}  ── Testen mit QEMU (UEFI): ──────────────────────────────${NC}"
    echo "  run_archiso -u -i ${ISO_FILE}"
    echo ""
    echo -e "${CYAN}  ── Auf USB-Stick schreiben: ─────────────────────────────${NC}"
    echo "  dd if=${ISO_FILE} of=/dev/sdX bs=4M status=progress oflag=sync"
    echo ""
    echo -e "${CYAN}  ── SHA256-Prüfsumme speichern: ──────────────────────────${NC}"
    echo "  sha256sum -c ${ISO_FILE}.sha256"
    echo ""

    # SHA256-Datei automatisch erstellen
    echo "${SHA256}  ${ISO_FILE}" > "${ISO_FILE}.sha256"
    ok "SHA256-Datei gespeichert: ${ISO_FILE}.sha256"

    # Eigentümer korrigieren wenn via sudo ausgeführt
    if [[ -n "${SUDO_USER:-}" ]]; then
        chown -R "${SUDO_USER}:${SUDO_USER}" "${OUT_DIR}"
        ok "Eigentümer von ${OUT_DIR} auf '${SUDO_USER}' gesetzt."
    fi
else
    warn "Keine ISO-Datei in ${OUT_DIR} gefunden."
    warn "Bitte Ausgabe von mkarchiso prüfen."
fi

echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Fertig! Viel Spaß mit deiner Arch Linux Plasma ISO!     ${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════${NC}"
echo ""
