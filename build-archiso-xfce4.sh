#!/usr/bin/env bash
# =============================================================================
#  build-archiso-xfce4.sh
#  Erstellt eine Arch Linux ISO mit XFCE4 (Xorg) + LightDM Autologin
#
#  Basiert auf dem aktuellen archiso releng-Profil mit systemd-boot (UEFI)
#  und syslinux (BIOS) – keine deprecated GRUB-Bootmodes.
#
#  HINWEIS: Alle XFCE4-Konfigurationen werden nach ~/.config/ geschrieben,
#           NICHT nach /etc/xdg/, um Konflikte mit Paket-Dateien zu vermeiden.
#
#  Ausführung: sudo bash build-archiso-xfce4.sh
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
readonly PROFILE_DIR="/tmp/archxfce"
readonly WORK_DIR="/tmp/archiso-work"
if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
else
    REAL_HOME="${HOME}"
fi
readonly OUT_DIR="${REAL_HOME}/archiso-out"
readonly LIVE_USER="liveuser"
readonly AIROOTFS="${PROFILE_DIR}/airootfs"
readonly USER_HOME="${AIROOTFS}/home/${LIVE_USER}"
readonly USER_XFCONF="${USER_HOME}/.config/xfce4/xfconf/xfce-perchannel-xml"

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

[[ "${EUID}" -ne 0 ]] && die "Bitte als root ausführen: sudo bash $0"
[[ ! -f /etc/arch-release ]] && die "Dieses Script läuft nur auf Arch Linux!"

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
    pacman -Sy --noconfirm --needed "${MISSING[@]}"
    ok "Host-Pakete installiert."
else
    ok "Alle Host-Pakete vorhanden."
fi

# =============================================================================
# SCHRITT 1: Profil-Verzeichnis aufbauen (Basis: releng)
# =============================================================================
banner "Schritt 1: Profil-Verzeichnis erstellen"

[[ -d "${PROFILE_DIR}" ]] && rm -rf "${PROFILE_DIR}"
cp -r /usr/share/archiso/configs/releng/ "${PROFILE_DIR}"
ok "releng-Profil nach ${PROFILE_DIR} kopiert."

# =============================================================================
# SCHRITT 2: profiledef.sh
# =============================================================================
banner "Schritt 2: profiledef.sh schreiben"

cat > "${PROFILE_DIR}/profiledef.sh" << 'PROFILEDEF'
#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="archlinux-xfce4"
iso_label="ARCH_XFCE4_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Custom Arch Linux XFCE4 Build"
iso_application="Arch Linux XFCE4 Live"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')

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

file_permissions=(
    ["/etc/shadow"]="0:0:400"
    ["/etc/gshadow"]="0:0:400"
    ["/root"]="0:0:750"
    ["/root/.gnupg"]="0:0:700"
    ["/etc/sudoers.d"]="0:0:750"
    ["/etc/sudoers.d/liveuser"]="0:0:440"
    ["/etc/lightdm"]="0:0:755"
    ["/etc/lightdm/lightdm.conf"]="0:0:644"
    ["/etc/lightdm/lightdm-gtk-greeter.conf"]="0:0:644"
    ["/usr/local/bin/choose-mirror"]="0:0:755"
    ["/usr/local/bin/Installation_guide"]="0:0:755"
    ["/usr/local/bin/livecd-sound"]="0:0:755"
    ["/usr/local/bin/xfce4-fixup.sh"]="0:0:755"
)
PROFILEDEF

ok "profiledef.sh geschrieben."

# =============================================================================
# SCHRITT 3: pacman.conf – multilib aktivieren
# =============================================================================
banner "Schritt 3: pacman.conf anpassen"

PACMAN_CONF="${PROFILE_DIR}/pacman.conf"

if grep -q '^#\[multilib\]' "${PACMAN_CONF}"; then
    sed -i '/^#\[multilib\]/{
        s/^#//
        n
        s/^#//
    }' "${PACMAN_CONF}"
    ok "multilib in pacman.conf aktiviert."
elif ! grep -q '^\[multilib\]' "${PACMAN_CONF}"; then
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> "${PACMAN_CONF}"
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

# ── Bootloader ────────────────────────────────────────────────────────────────
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
polkit-gnome
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

# ── Xorg / Display ───────────────────────────────────────────────────────────
xorg-server
xorg-xinit
xorg-xrandr
xorg-xsetroot
xorg-xset
xorg-xdpyinfo
xorg-xinput
xorg-xhost
xorg-xprop
xorg-xwininfo
xf86-input-libinput
xf86-video-amdgpu
xf86-video-ati
xf86-video-intel
xf86-video-nouveau
xf86-video-vesa
xf86-video-fbdev
xf86-video-qxl
xclip
xsel

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

# ── XFCE4 Desktop ────────────────────────────────────────────────────────────
xfce4
xfce4-goodies
xfce4-whiskermenu-plugin
xfce4-pulseaudio-plugin
xfce4-notifyd
xfce4-screenshooter
xfce4-taskmanager
xfce4-terminal
xfce4-clipman-plugin
xfce4-power-manager
xfce4-battery-plugin
xfce4-cpugraph-plugin
xfce4-netload-plugin
xfce4-systemload-plugin
xfce4-wavelan-plugin
xfce4-weather-plugin

# ── LightDM (Display-Manager) ────────────────────────────────────────────────
lightdm
lightdm-gtk-greeter
lightdm-gtk-greeter-settings

# ── GTK-Themes & Icons ───────────────────────────────────────────────────────
papirus-icon-theme
adwaita-icon-theme
gnome-themes-extra
lxappearance

# ── Dateimanager-Erweiterungen ────────────────────────────────────────────────
thunar-archive-plugin
thunar-media-tags-plugin
thunar-volman
gvfs
gvfs-mtp
gvfs-smb
gvfs-afc
gvfs-nfs
tumbler
ffmpegthumbnailer

# ── Internet ──────────────────────────────────────────────────────────────────
firefox
firefox-i18n-de
filezilla
qbittorrent

# ── Multimedia ────────────────────────────────────────────────────────────────
ristretto
parole

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
system-config-printer

# ── Compositor & Hilfspakete ─────────────────────────────────────────────────
picom
numlockx
catfish
mousepad
galculator
engrampa
xarchiver

# ── Sonstiges ─────────────────────────────────────────────────────────────────
xdg-user-dirs
xdg-utils
shared-mime-info
PKGLIST

ok "Paketliste geschrieben."

# =============================================================================
# SCHRITT 5: airootfs-Verzeichnisstruktur anlegen
#
#  WICHTIG: Alle XFCE4-Konfigurationen kommen in ~/.config/
#           NICHT in /etc/xdg/ – dort installieren die Pakete ihre Defaults
#           und es gibt sonst "conflicting files"-Fehler beim Build.
# =============================================================================
banner "Schritt 5: airootfs-Struktur anlegen"

# ── Systemverzeichnisse ──────────────────────────────────────────────────────
mkdir -p "${AIROOTFS}/etc/lightdm"
mkdir -p "${AIROOTFS}/etc/sudoers.d"
mkdir -p "${AIROOTFS}/etc/systemd/system/getty@tty1.service.d"
mkdir -p "${AIROOTFS}/etc/systemd/system/multi-user.target.wants"
mkdir -p "${AIROOTFS}/etc/systemd/system/network-online.target.wants"
mkdir -p "${AIROOTFS}/etc/NetworkManager/conf.d"
mkdir -p "${AIROOTFS}/etc/polkit-1/rules.d"
mkdir -p "${AIROOTFS}/etc/X11/xorg.conf.d"
mkdir -p "${AIROOTFS}/etc/fonts"
mkdir -p "${AIROOTFS}/usr/local/bin"
mkdir -p "${AIROOTFS}/root/.gnupg"

# ── User-Verzeichnisse (alle Configs hierher – KEINE /etc/xdg/ Konflikte) ───
mkdir -p "${USER_XFCONF}"
mkdir -p "${USER_HOME}/.config/xfce4/panel"
mkdir -p "${USER_HOME}/.config/xfce4/terminal"
mkdir -p "${USER_HOME}/.config/autostart"
mkdir -p "${USER_HOME}/.config/gtk-3.0"
mkdir -p "${USER_HOME}/.config/picom"
mkdir -p "${USER_HOME}/.local/share/xfce4/helpers"
mkdir -p "${USER_HOME}/Desktop"
mkdir -p "${USER_HOME}/Dokumente"
mkdir -p "${USER_HOME}/Downloads"
mkdir -p "${USER_HOME}/Bilder"
mkdir -p "${USER_HOME}/Musik"
mkdir -p "${USER_HOME}/Videos"

ok "Verzeichnisstruktur angelegt."

# =============================================================================
# SCHRITT 6: Benutzer-Accounts (passwd / shadow / group / gshadow)
# =============================================================================
banner "Schritt 6: Benutzer-Accounts konfigurieren"

if ! grep -q "^${LIVE_USER}:" "${AIROOTFS}/etc/passwd" 2>/dev/null; then
    echo "${LIVE_USER}:x:1000:1000:Live User:/home/${LIVE_USER}:/bin/bash" \
        >> "${AIROOTFS}/etc/passwd"
fi

if ! grep -q "^${LIVE_USER}:" "${AIROOTFS}/etc/shadow" 2>/dev/null; then
    echo "${LIVE_USER}::19000:0:99999:7:::" >> "${AIROOTFS}/etc/shadow"
fi

declare -A GROUPS_MAP=(
    ["wheel"]="10"
    ["audio"]="92"
    ["video"]="985"
    ["storage"]="998"
    ["optical"]="93"
    ["network"]="90"
    ["power"]="98"
    ["autologin"]="1001"
    ["liveuser"]="1000"
)

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

for grp in "${!GROUPS_MAP[@]}"; do
    if ! grep -q "^${grp}:" "${AIROOTFS}/etc/gshadow" 2>/dev/null; then
        echo "${grp}:::${LIVE_USER}" >> "${AIROOTFS}/etc/gshadow"
    fi
done

ok "Benutzer '${LIVE_USER}' eingetragen."

# =============================================================================
# SCHRITT 7: sudo-Konfiguration
# =============================================================================
banner "Schritt 7: sudo konfigurieren"

cat > "${AIROOTFS}/etc/sudoers.d/liveuser" << EOF
${LIVE_USER} ALL=(ALL:ALL) NOPASSWD: ALL
EOF

ok "sudo-Regel geschrieben."

# =============================================================================
# SCHRITT 8: LightDM Autologin
# =============================================================================
banner "Schritt 8: LightDM Autologin konfigurieren"

cat > "${AIROOTFS}/etc/lightdm/lightdm.conf" << EOF
[LightDM]
logind-check-graphical=true
run-directory=/run/lightdm

[Seat:*]
autologin-user=${LIVE_USER}
autologin-user-timeout=0
autologin-session=xfce
user-session=xfce
greeter-session=lightdm-gtk-greeter
session-wrapper=/etc/lightdm/Xsession

[XDMCPServer]
enabled=false

[VNCServer]
enabled=false
EOF

cat > "${AIROOTFS}/etc/lightdm/lightdm-gtk-greeter.conf" << 'EOF'
[greeter]
theme-name=Arc-Dark
icon-theme-name=Papirus-Dark
font-name=Noto Sans 11
xft-antialias=true
xft-dpi=96
xft-hintstyle=hintslight
xft-rgba=rgb
indicators=~host;~spacer;~clock;~spacer;~session;~language;~a11y;~power
clock-format=%H:%M  %a, %d. %b %Y
background=#2e3440
user-background=false
position=50%,center 50%,center
EOF

ok "LightDM Autologin konfiguriert."

# =============================================================================
# SCHRITT 9: XFCE4-Konfigurationen (alle in ~/.config/ !)
#
#  Dateien in ~/.config/xfce4/xfconf/xfce-perchannel-xml/ überschreiben
#  die Paket-Defaults aus /etc/xdg/ – OHNE Dateikonflikte.
# =============================================================================
banner "Schritt 9: XFCE4 Desktop-Konfiguration (User-Level)"

# ── 9a: xfwm4 ────────────────────────────────────────────────────────────────
cat > "${USER_XFCONF}/xfwm4.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Arc-Dark"/>
    <property name="title_font" type="string" value="Noto Sans Bold 10"/>
    <property name="placement_ratio" type="int" value="20"/>
    <property name="placement_mode" type="string" value="center"/>
    <property name="snap_to_border" type="bool" value="true"/>
    <property name="snap_to_windows" type="bool" value="true"/>
    <property name="snap_width" type="int" value="10"/>
    <property name="wrap_windows" type="bool" value="false"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="cycle_draw_frame" type="bool" value="true"/>
    <property name="cycle_raise" type="bool" value="true"/>
    <property name="cycle_tabwin_mode" type="int" value="0"/>
    <property name="tile_on_move" type="bool" value="true"/>
    <property name="mousewheel_rollup" type="bool" value="false"/>
    <property name="box_move" type="bool" value="false"/>
    <property name="box_resize" type="bool" value="false"/>
  </property>
</channel>
EOF
ok "  xfwm4.xml"

# ── 9b: xsettings ────────────────────────────────────────────────────────────
cat > "${USER_XFCONF}/xsettings.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Arc-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorSize" type="int" value="24"/>
    <property name="EnableEventSounds" type="bool" value="false"/>
    <property name="EnableInputFeedbackSounds" type="bool" value="false"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="FontName" type="string" value="Noto Sans 10"/>
    <property name="MonospaceFontName" type="string" value="Noto Sans Mono 10"/>
    <property name="CursorThemeName" type="string" value="Adwaita"/>
    <property name="CursorThemeSize" type="int" value="24"/>
    <property name="ButtonImages" type="bool" value="true"/>
    <property name="MenuImages" type="bool" value="true"/>
    <property name="DecorationLayout" type="string" value="menu:minimize,maximize,close"/>
  </property>
  <property name="Xft" type="empty">
    <property name="Antialias" type="int" value="1"/>
    <property name="Hinting" type="int" value="1"/>
    <property name="HintStyle" type="string" value="hintslight"/>
    <property name="RGBA" type="string" value="rgb"/>
    <property name="DPI" type="int" value="96"/>
    <property name="Lcdfilter" type="string" value="lcddefault"/>
  </property>
</channel>
EOF
ok "  xsettings.xml"

# ── 9c: xfce4-desktop ────────────────────────────────────────────────────────
cat > "${USER_XFCONF}/xfce4-desktop.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="desktop-icons" type="empty">
    <property name="style" type="int" value="2"/>
    <property name="file-icons" type="empty">
      <property name="show-home" type="bool" value="true"/>
      <property name="show-filesystem" type="bool" value="true"/>
      <property name="show-removable" type="bool" value="true"/>
      <property name="show-trash" type="bool" value="true"/>
    </property>
    <property name="icon-size" type="uint" value="48"/>
    <property name="tooltip-size" type="double" value="64"/>
    <property name="font-size" type="double" value="10"/>
    <property name="use-custom-font-size" type="bool" value="true"/>
  </property>
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorscreen" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="rgba1" type="array">
            <value type="double" value="0.180392"/>
            <value type="double" value="0.203922"/>
            <value type="double" value="0.250980"/>
            <value type="double" value="1.000000"/>
          </property>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
ok "  xfce4-desktop.xml"

# ── 9d: xfce4-panel ──────────────────────────────────────────────────────────
cat > "${USER_XFCONF}/xfce4-panel.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="22"/>
      <property name="size" type="uint" value="30"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
        <value type="int" value="4"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="7"/>
        <value type="int" value="8"/>
        <value type="int" value="9"/>
        <value type="int" value="10"/>
        <value type="int" value="11"/>
        <value type="int" value="12"/>
        <value type="int" value="13"/>
        <value type="int" value="14"/>
      </property>
      <property name="nrows" type="uint" value="1"/>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="whiskermenu"/>
    <property name="plugin-2" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-3" type="string" value="tasklist">
      <property name="show-labels" type="bool" value="true"/>
      <property name="flat-buttons" type="bool" value="true"/>
      <property name="grouping" type="uint" value="1"/>
    </property>
    <property name="plugin-4" type="string" value="separator">
      <property name="expand" type="bool" value="true"/>
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-5" type="string" value="pager">
      <property name="rows" type="uint" value="1"/>
    </property>
    <property name="plugin-6" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-7" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
    </property>
    <property name="plugin-8" type="string" value="statusnotifier"/>
    <property name="plugin-9" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="show-notifications" type="bool" value="true"/>
    </property>
    <property name="plugin-10" type="string" value="power-manager-plugin"/>
    <property name="plugin-11" type="string" value="notification-plugin"/>
    <property name="plugin-12" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-13" type="string" value="clock">
      <property name="digital-layout" type="uint" value="3"/>
      <property name="digital-date-format" type="string" value="%a, %d. %b"/>
      <property name="digital-time-format" type="string" value="%H:%M"/>
    </property>
    <property name="plugin-14" type="string" value="actions"/>
  </property>
</channel>
EOF
ok "  xfce4-panel.xml"

# ── 9e: Thunar ────────────────────────────────────────────────────────────────
cat > "${USER_XFCONF}/thunar.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="thunar" version="1.0">
  <property name="default-view" type="string" value="ThunarDetailsView"/>
  <property name="last-view" type="string" value="ThunarDetailsView"/>
  <property name="last-show-hidden" type="bool" value="false"/>
  <property name="last-details-view-column-order" type="string" value="THUNAR_COLUMN_NAME,THUNAR_COLUMN_SIZE,THUNAR_COLUMN_TYPE,THUNAR_COLUMN_DATE_MODIFIED"/>
  <property name="last-details-view-visible-columns" type="string" value="THUNAR_COLUMN_NAME,THUNAR_COLUMN_SIZE,THUNAR_COLUMN_TYPE,THUNAR_COLUMN_DATE_MODIFIED"/>
  <property name="last-details-view-zoom-level" type="string" value="THUNAR_ZOOM_LEVEL_38_PERCENT"/>
  <property name="misc-single-click" type="bool" value="false"/>
  <property name="misc-thumbnail-mode" type="string" value="THUNAR_THUMBNAIL_MODE_ALWAYS"/>
  <property name="misc-date-style" type="string" value="THUNAR_DATE_STYLE_SHORT"/>
  <property name="misc-middle-click-in-tab" type="bool" value="true"/>
  <property name="misc-open-new-window-as-tab" type="bool" value="true"/>
  <property name="misc-volume-management" type="bool" value="true"/>
  <property name="shortcuts-icon-size" type="string" value="THUNAR_ICON_SIZE_24"/>
</channel>
EOF
ok "  thunar.xml"

# ── 9f: xfce4-terminal ───────────────────────────────────────────────────────
cat > "${USER_HOME}/.config/xfce4/terminal/terminalrc" << 'EOF'
[Configuration]
FontName=Noto Sans Mono 11
FontUseSystem=FALSE
MiscCursorBlinks=TRUE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_IBEAM
MiscDefaultGeometry=110x30
ScrollingUnlimited=TRUE
ScrollingBar=TERMINAL_SCROLLBAR_NONE
ColorBackground=#2e2e34344040
ColorForeground=#d3d3d7d7cfcf
ColorCursor=#d3d3d7d7cfcf
BackgroundMode=TERMINAL_BACKGROUND_TRANSPARENT
BackgroundDarkness=0.920000
TabActivityColor=#aa0000
MiscShowUnsafePasteDialog=TRUE
MiscHighlightUrls=TRUE
EOF
ok "  terminalrc"

# ── 9g: xfce4-power-manager ──────────────────────────────────────────────────
cat > "${USER_XFCONF}/xfce4-power-manager.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="power-button-action" type="uint" value="3"/>
    <property name="sleep-button-action" type="uint" value="1"/>
    <property name="hibernate-button-action" type="uint" value="2"/>
    <property name="dpms-enabled" type="bool" value="true"/>
    <property name="blank-on-ac" type="int" value="15"/>
    <property name="dpms-on-ac-sleep" type="uint" value="20"/>
    <property name="dpms-on-ac-off" type="uint" value="30"/>
    <property name="blank-on-battery" type="int" value="5"/>
    <property name="dpms-on-battery-sleep" type="uint" value="10"/>
    <property name="dpms-on-battery-off" type="uint" value="15"/>
    <property name="brightness-on-battery" type="uint" value="30"/>
    <property name="lid-action-on-battery" type="uint" value="1"/>
    <property name="lid-action-on-ac" type="uint" value="0"/>
    <property name="critical-power-action" type="uint" value="1"/>
    <property name="critical-power-level" type="uint" value="5"/>
    <property name="show-tray-icon" type="int" value="1"/>
    <property name="general-notification" type="bool" value="true"/>
  </property>
</channel>
EOF
ok "  xfce4-power-manager.xml"

# ── 9h: xfce4-keyboard-shortcuts ─────────────────────────────────────────────
cat > "${USER_XFCONF}/xfce4-keyboard-shortcuts.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-keyboard-shortcuts" version="1.0">
  <property name="commands" type="empty">
    <property name="default" type="empty">
      <property name="&lt;Super&gt;e" type="string" value="thunar"/>
      <property name="&lt;Super&gt;t" type="string" value="xfce4-terminal"/>
      <property name="&lt;Super&gt;l" type="string" value="xflock4"/>
      <property name="&lt;Super&gt;r" type="string" value="xfce4-appfinder"/>
      <property name="Print" type="string" value="xfce4-screenshooter"/>
      <property name="&lt;Alt&gt;F2" type="string" value="xfce4-appfinder --collapsed"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;t" type="string" value="xfce4-terminal"/>
      <property name="&lt;Primary&gt;&lt;Alt&gt;Delete" type="string" value="xfce4-session-logout"/>
      <property name="&lt;Super&gt;p" type="string" value="xfce4-display-settings --minimal"/>
    </property>
  </property>
  <property name="xfwm4" type="empty">
    <property name="default" type="empty">
      <property name="&lt;Super&gt;Left" type="string" value="tile_left_key"/>
      <property name="&lt;Super&gt;Right" type="string" value="tile_right_key"/>
      <property name="&lt;Super&gt;Up" type="string" value="maximize_window_key"/>
      <property name="&lt;Super&gt;Down" type="string" value="hide_window_key"/>
      <property name="&lt;Alt&gt;F4" type="string" value="close_window_key"/>
      <property name="&lt;Alt&gt;F9" type="string" value="hide_window_key"/>
      <property name="&lt;Alt&gt;F10" type="string" value="maximize_window_key"/>
      <property name="&lt;Alt&gt;F11" type="string" value="fullscreen_key"/>
      <property name="&lt;Alt&gt;Tab" type="string" value="cycle_windows_key"/>
      <property name="&lt;Super&gt;d" type="string" value="show_desktop_key"/>
    </property>
  </property>
</channel>
EOF
ok "  xfce4-keyboard-shortcuts.xml"

# ── 9i: xfce4-session ────────────────────────────────────────────────────────
cat > "${USER_XFCONF}/xfce4-session.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="FailsafeSessionName" type="string" value="Failsafe"/>
    <property name="SaveOnExit" type="bool" value="false"/>
    <property name="AutoSave" type="bool" value="false"/>
    <property name="LockCommand" type="string" value="xflock4"/>
  </property>
  <property name="sessions" type="empty">
    <property name="Failsafe" type="empty">
      <property name="IsFailsafe" type="bool" value="true"/>
      <property name="Count" type="int" value="5"/>
      <property name="Client0_Command" type="array">
        <value type="string" value="xfwm4"/>
      </property>
      <property name="Client0_Priority" type="int" value="15"/>
      <property name="Client0_PerScreen" type="bool" value="false"/>
      <property name="Client1_Command" type="array">
        <value type="string" value="xfsettingsd"/>
      </property>
      <property name="Client1_Priority" type="int" value="20"/>
      <property name="Client1_PerScreen" type="bool" value="false"/>
      <property name="Client2_Command" type="array">
        <value type="string" value="xfce4-panel"/>
      </property>
      <property name="Client2_Priority" type="int" value="25"/>
      <property name="Client2_PerScreen" type="bool" value="false"/>
      <property name="Client3_Command" type="array">
        <value type="string" value="Thunar"/>
        <value type="string" value="--daemon"/>
      </property>
      <property name="Client3_Priority" type="int" value="30"/>
      <property name="Client3_PerScreen" type="bool" value="false"/>
      <property name="Client4_Command" type="array">
        <value type="string" value="xfdesktop"/>
      </property>
      <property name="Client4_Priority" type="int" value="35"/>
      <property name="Client4_PerScreen" type="bool" value="false"/>
    </property>
  </property>
</channel>
EOF
ok "  xfce4-session.xml"

# ── 9j: xfce4-notifyd ────────────────────────────────────────────────────────
cat > "${USER_XFCONF}/xfce4-notifyd.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-notifyd" version="1.0">
  <property name="theme" type="string" value="Default"/>
  <property name="notify-location" type="uint" value="2"/>
  <property name="expire-timeout" type="int" value="5"/>
  <property name="initial-opacity" type="double" value="0.95"/>
  <property name="primary-monitor" type="uint" value="0"/>
  <property name="do-fadeout" type="bool" value="true"/>
  <property name="do-slideout" type="bool" value="true"/>
</channel>
EOF
ok "  xfce4-notifyd.xml"

ok "Alle XFCE4-Konfigurationen in ~/.config/ geschrieben."

# =============================================================================
# SCHRITT 10: Picom Compositor (User-Level)
# =============================================================================
banner "Schritt 10: Picom Compositor (User-Level)"

cat > "${USER_HOME}/.config/picom/picom.conf" << 'EOF'
backend = "glx";
vsync = true;
glx-no-stencil = true;
glx-no-rebind-pixmap = true;
use-damage = true;
unredir-if-possible = true;

shadow = true;
shadow-radius = 8;
shadow-offset-x = -5;
shadow-offset-y = -5;
shadow-opacity = 0.35;
shadow-exclude = [
    "name = 'Notification'",
    "class_g = 'Conky'",
    "class_g ?= 'Notify-osd'",
    "class_g = 'xfce4-notifyd'",
    "_GTK_FRAME_EXTENTS@:c"
];

inactive-opacity = 0.95;
active-opacity = 1.0;
frame-opacity = 1.0;
inactive-opacity-override = false;

fading = true;
fade-in-step = 0.04;
fade-out-step = 0.04;
fade-delta = 5;

corner-radius = 6;
rounded-corners-exclude = [
    "window_type = 'dock'",
    "window_type = 'desktop'"
];

wintypes:
{
    tooltip = { fade = true; shadow = false; opacity = 0.95; focus = true; };
    dock = { shadow = false; };
    dnd = { shadow = false; };
    popup_menu = { shadow = true; opacity = 1.0; };
    dropdown_menu = { shadow = true; opacity = 1.0; };
};
EOF

# Picom Autostart – Hidden=true → standardmäßig AUS (xfwm4 hat eigenen Compositor)
cat > "${USER_HOME}/.config/autostart/picom.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Picom Compositor
Exec=picom --config ~/.config/picom/picom.conf -b
Hidden=true
NoDisplay=true
X-XFCE-Autostart-Override=false
OnlyShowIn=XFCE;
EOF

ok "Picom konfiguriert (User-Level, standardmäßig deaktiviert)."

# =============================================================================
# SCHRITT 11: Autostart-Einträge (User-Level)
# =============================================================================
banner "Schritt 11: Autostart-Einträge"

cat > "${USER_HOME}/.config/autostart/polkit-gnome.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
OnlyShowIn=XFCE;
X-XFCE-Autostart-Override=true
EOF

cat > "${USER_HOME}/.config/autostart/numlockx.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=NumLock
Exec=numlockx on
OnlyShowIn=XFCE;
X-XFCE-Autostart-Override=true
EOF

ok "Autostart-Einträge geschrieben."

# =============================================================================
# SCHRITT 12: Xorg-Konfiguration
# =============================================================================
banner "Schritt 12: Xorg-Konfiguration"

cat > "${AIROOTFS}/etc/X11/xorg.conf.d/00-keyboard.conf" << 'EOF'
Section "InputClass"
    Identifier "keyboard-layout"
    MatchIsKeyboard "on"
    Option "XkbLayout" "de"
    Option "XkbVariant" ""
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
EOF

cat > "${AIROOTFS}/etc/X11/xorg.conf.d/30-touchpad.conf" << 'EOF'
Section "InputClass"
    Identifier "touchpad"
    Driver "libinput"
    MatchIsTouchpad "on"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "NaturalScrolling" "on"
    Option "ScrollMethod" "twofinger"
    Option "DisableWhileTyping" "on"
    Option "ClickMethod" "clickfinger"
EndSection
EOF

ok "Xorg-Konfiguration geschrieben."

# =============================================================================
# SCHRITT 13: Systemd-Services aktivieren
# =============================================================================
banner "Schritt 13: Systemd-Services aktivieren"

SYSTEMD_SYSTEM="${AIROOTFS}/etc/systemd/system"

ln -sf /usr/lib/systemd/system/lightdm.service \
    "${SYSTEMD_SYSTEM}/display-manager.service" 2>/dev/null || true

ln -sf /usr/lib/systemd/system/NetworkManager.service \
    "${SYSTEMD_SYSTEM}/multi-user.target.wants/NetworkManager.service" 2>/dev/null || true
ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service \
    "${SYSTEMD_SYSTEM}/network-online.target.wants/NetworkManager-wait-online.service" 2>/dev/null || true

ln -sf /usr/lib/systemd/system/bluetooth.service \
    "${SYSTEMD_SYSTEM}/multi-user.target.wants/bluetooth.service" 2>/dev/null || true

ln -sf /usr/lib/systemd/system/cups.service \
    "${SYSTEMD_SYSTEM}/multi-user.target.wants/cups.service" 2>/dev/null || true

ln -sf /usr/lib/systemd/system/sshd.service \
    "${SYSTEMD_SYSTEM}/multi-user.target.wants/sshd.service" 2>/dev/null || true

ok "Systemd-Service-Symlinks gesetzt."

# =============================================================================
# SCHRITT 14: Getty TTY1 Autologin (Fallback)
# =============================================================================
banner "Schritt 14: Getty TTY1 Autologin"

cat > "${AIROOTFS}/etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin ${LIVE_USER} %I \$TERM
Type=idle
EOF

ok "Getty-Autologin konfiguriert."

# =============================================================================
# SCHRITT 15: Locale, Hostname, Zeitzone
# =============================================================================
banner "Schritt 15: Locale / Hostname / Zeitzone"

cat > "${AIROOTFS}/etc/locale.conf" << 'EOF'
LANG=de_DE.UTF-8
LC_TIME=de_DE.UTF-8
LC_MONETARY=de_DE.UTF-8
LC_PAPER=de_DE.UTF-8
LC_MEASUREMENT=de_DE.UTF-8
EOF

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
# SCHRITT 16: NetworkManager Konfiguration
# =============================================================================
banner "Schritt 16: NetworkManager konfigurieren"

cat > "${AIROOTFS}/etc/NetworkManager/conf.d/wifi_backend.conf" << 'EOF'
[device]
wifi.backend=iwd
EOF

ok "NetworkManager konfiguriert."

# =============================================================================
# SCHRITT 17: Polkit-Regel
# =============================================================================
banner "Schritt 17: Polkit-Regel"

cat > "${AIROOTFS}/etc/polkit-1/rules.d/49-liveuser.rules" << EOF
polkit.addRule(function(action, subject) {
    if (subject.user === "${LIVE_USER}") {
        return polkit.Result.YES;
    }
});
EOF

ok "Polkit-Regel geschrieben."

# =============================================================================
# SCHRITT 18: Fontconfig Optimierung
# =============================================================================
banner "Schritt 18: Fontconfig Optimierung"

cat > "${AIROOTFS}/etc/fonts/local.conf" << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="antialias" mode="assign"><bool>true</bool></edit>
    <edit name="hinting" mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle" mode="assign"><const>hintslight</const></edit>
    <edit name="rgba" mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter" mode="assign"><const>lcddefault</const></edit>
    <edit name="embeddedbitmap" mode="assign"><bool>false</bool></edit>
  </match>
  <alias>
    <family>sans-serif</family>
    <prefer><family>Noto Sans</family></prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer><family>Noto Serif</family></prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer><family>Noto Sans Mono</family></prefer>
  </alias>
</fontconfig>
EOF

ok "Fontconfig geschrieben."

# =============================================================================
# SCHRITT 19: GTK-Einstellungen & Bookmarks
# =============================================================================
banner "Schritt 19: GTK-Einstellungen & Bookmarks"

cat > "${USER_HOME}/.config/gtk-3.0/settings.ini" << 'EOF'
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-cursor-theme-name=Adwaita
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans 10
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintslight
gtk-xft-rgba=rgb
gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size=GTK_ICON_SIZE_SMALL_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-application-prefer-dark-theme=1
EOF

cat > "${USER_HOME}/.config/gtk-3.0/bookmarks" << EOF
file:///home/${LIVE_USER}/Dokumente Dokumente
file:///home/${LIVE_USER}/Downloads Downloads
file:///home/${LIVE_USER}/Bilder Bilder
file:///home/${LIVE_USER}/Musik Musik
file:///home/${LIVE_USER}/Videos Videos
EOF

cat > "${USER_HOME}/.gtkrc-2.0" << 'EOF'
gtk-theme-name="Arc-Dark"
gtk-icon-theme-name="Papirus-Dark"
gtk-cursor-theme-name="Adwaita"
gtk-cursor-theme-size=24
gtk-font-name="Noto Sans 10"
gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size=GTK_ICON_SIZE_SMALL_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle="hintslight"
gtk-xft-rgba="rgb"
EOF

ok "GTK-Einstellungen geschrieben."

# =============================================================================
# SCHRITT 20: Desktop-Verknüpfungen
# =============================================================================
banner "Schritt 20: Desktop-Verknüpfungen"

cat > "${USER_HOME}/Desktop/Install-Arch.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Arch Linux installieren
Comment=Öffnet ein Terminal mit archinstall
Exec=xfce4-terminal -e "sudo archinstall"
Icon=system-software-install
Terminal=false
Categories=System;
StartupNotify=true
EOF

cat > "${USER_HOME}/Desktop/Thunar.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Dateien
Exec=thunar
Icon=system-file-manager
Terminal=false
EOF

cat > "${USER_HOME}/Desktop/Firefox.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Firefox
Exec=firefox
Icon=firefox
Terminal=false
EOF

cat > "${USER_HOME}/Desktop/Terminal.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Terminal
Exec=xfce4-terminal
Icon=utilities-terminal
Terminal=false
EOF

ok "Desktop-Verknüpfungen erstellt."

# =============================================================================
# SCHRITT 21: .bashrc
# =============================================================================
banner "Schritt 21: .bashrc für liveuser"

cat > "${USER_HOME}/.bashrc" << 'BASHRC'
[[ $- != *i* ]] && return
PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -Iv'
alias mkdir='mkdir -pv'
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias ..='cd ..'
alias ...='cd ../..'
[[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion
HISTSIZE=5000
HISTFILESIZE=10000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
BASHRC

ok ".bashrc geschrieben."

# =============================================================================
# SCHRITT 22: Fixup-Script (Desktop-Icons vertrauenswürdig machen)
# =============================================================================
banner "Schritt 22: Fixup-Script"

cat > "${AIROOTFS}/usr/local/bin/xfce4-fixup.sh" << 'FIXUPSCRIPT'
#!/usr/bin/env bash
MARKER="${HOME}/.config/.xfce4-fixup-done"
[[ -f "${MARKER}" ]] && exit 0
for f in "${HOME}/Desktop"/*.desktop; do
    [[ -f "${f}" ]] && chmod +x "${f}"
done
xdg-user-dirs-update 2>/dev/null || true
touch "${MARKER}"
FIXUPSCRIPT

chmod +x "${AIROOTFS}/usr/local/bin/xfce4-fixup.sh"

cat > "${USER_HOME}/.config/autostart/xfce4-fixup.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=XFCE4 Fixup
Exec=/usr/local/bin/xfce4-fixup.sh
OnlyShowIn=XFCE;
X-XFCE-Autostart-Override=true
NoDisplay=true
EOF

ok "Fixup-Script erstellt."

# =============================================================================
# SCHRITT 23: Dateieigentümer korrigieren
# =============================================================================
banner "Schritt 23: Dateieigentümer"

chown -R 1000:1000 "${USER_HOME}" 2>/dev/null || true
ok "Eigentümer gesetzt (UID/GID 1000)."

# =============================================================================
# SCHRITT 24: systemd-boot + syslinux prüfen
# =============================================================================
banner "Schritt 24: Boot-Konfiguration prüfen"

EFIBOOT="${PROFILE_DIR}/efiboot"
if [[ -d "${EFIBOOT}" ]]; then
    ok "efiboot/ vorhanden."
    if [[ -f "${EFIBOOT}/loader/loader.conf" ]]; then
        sed -i 's/^timeout.*/timeout 5/' "${EFIBOOT}/loader/loader.conf"
        ok "Boot-Timeout auf 5s gesetzt."
    fi
else
    warn "efiboot/ nicht gefunden – mkarchiso generiert es."
fi

SYSLINUX_DIR="${PROFILE_DIR}/syslinux"
if [[ -d "${SYSLINUX_DIR}" ]]; then
    ok "syslinux/ vorhanden."
else
    warn "syslinux/ nicht gefunden – mkarchiso generiert es."
fi

# =============================================================================
# SCHRITT 25: Verzeichnisse vorbereiten
# =============================================================================
banner "Schritt 25: Verzeichnisse vorbereiten"

mkdir -p "${OUT_DIR}"

if [[ -d "${WORK_DIR}" ]]; then
    warn "Altes Work-Verzeichnis gefunden – prüfe Mounts..."
    ACTIVE_MOUNTS=$(findmnt | grep "${WORK_DIR}" || true)
    if [[ -n "${ACTIVE_MOUNTS}" ]]; then
        echo -e "${RED}Aktive Mounts:${NC}"
        echo "${ACTIVE_MOUNTS}"
        die "Bitte Mounts aushängen: umount -R ${WORK_DIR}"
    fi
    rm -rf "${WORK_DIR}"
    ok "Altes Work-Verzeichnis bereinigt."
fi

mkdir -p "${WORK_DIR}"
ok "Verzeichnisse bereit."

# =============================================================================
# SCHRITT 26: Profil-Validierung
# =============================================================================
banner "Schritt 26: Profil-Validierung"

REQUIRED_FILES=(
    "${PROFILE_DIR}/profiledef.sh"
    "${PROFILE_DIR}/packages.x86_64"
    "${PROFILE_DIR}/pacman.conf"
)

ALL_OK=true
for f in "${REQUIRED_FILES[@]}"; do
    if [[ -f "${f}" ]]; then
        ok "Pflicht:  ${f}"
    else
        warn "FEHLT:   ${f}"
        ALL_OK=false
    fi
done

# Optional (aus releng)
for f in "${PROFILE_DIR}/efiboot/loader/loader.conf" "${PROFILE_DIR}/syslinux/syslinux.cfg"; do
    if [[ -f "${f}" ]]; then
        ok "Optional: ${f}"
    else
        warn "Optional: ${f} (mkarchiso generiert ggf.)"
    fi
done

[[ "${ALL_OK}" == false ]] && die "Pflichtdateien fehlen – Build abgebrochen."

info "Prüfe Paketliste auf Duplikate..."
DUPES=$(grep -v '^#' "${PROFILE_DIR}/packages.x86_64" | grep -v '^$' | sort | uniq -d)
if [[ -n "${DUPES}" ]]; then
    warn "Duplikate: ${DUPES}"
else
    ok "Keine Duplikate."
fi

# =============================================================================
# SCHRITT 27: ISO BAUEN
# =============================================================================
banner "Schritt 27: ISO-Build starten"

echo -e "${YELLOW}  Profil:     ${PROFILE_DIR}${NC}"
echo -e "${YELLOW}  Workdir:    ${WORK_DIR}${NC}"
echo -e "${YELLOW}  Ausgabe:    ${OUT_DIR}${NC}"
echo -e "${YELLOW}  Desktop:    XFCE4 (Xorg) + LightDM Autologin${NC}"
echo -e "${YELLOW}  Bootmodes:  bios.syslinux + uefi-x64.systemd-boot${NC}"
echo ""
echo -e "${YELLOW}  Der Build kann 20–60 Minuten dauern!${NC}"
echo ""

mkarchiso \
    -v \
    -w "${WORK_DIR}" \
    -o "${OUT_DIR}" \
    "${PROFILE_DIR}"

# =============================================================================
# SCHRITT 28: Ergebnis
# =============================================================================
banner "Build abgeschlossen!"

ISO_FILE=$(find "${OUT_DIR}" -maxdepth 1 -name "*.iso" | sort | tail -1)

if [[ -n "${ISO_FILE}" && -f "${ISO_FILE}" ]]; then
    ISO_SIZE=$(du -sh "${ISO_FILE}" | cut -f1)
    SHA256=$(sha256sum "${ISO_FILE}" | cut -d' ' -f1)

    echo -e "${GREEN}  ISO:    ${ISO_FILE}${NC}"
    echo -e "${GREEN}  Größe:  ${ISO_SIZE}${NC}"
    echo -e "${GREEN}  SHA256: ${SHA256}${NC}"
    echo ""
    echo -e "${CYAN}  Testen:   run_archiso -u -i ${ISO_FILE}${NC}"
    echo -e "${CYAN}  USB:      dd if=${ISO_FILE} of=/dev/sdX bs=4M status=progress oflag=sync${NC}"
    echo ""

    echo "${SHA256}  ${ISO_FILE}" > "${ISO_FILE}.sha256"
    ok "SHA256-Datei: ${ISO_FILE}.sha256"

    if [[ -n "${SUDO_USER:-}" ]]; then
        chown -R "${SUDO_USER}:${SUDO_USER}" "${OUT_DIR}"
        ok "Eigentümer auf '${SUDO_USER}' gesetzt."
    fi
else
    warn "Keine ISO-Datei in ${OUT_DIR} gefunden."
    warn "Bitte mkarchiso-Ausgabe prüfen."
fi

echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Fertig! Viel Spaß mit deiner Arch Linux XFCE4 ISO!    ${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════${NC}"
echo ""
