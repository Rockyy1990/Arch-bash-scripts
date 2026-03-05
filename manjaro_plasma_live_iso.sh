#!/bin/bash

echo "
-----------------------------------------------------------------------------------
 Manjaro Plasma Live ISO Builder Script
 Automatisierte ISO-Erstellung für Plasma Desktop
 Basierend auf: https://wiki.manjaro.org/index.php/Build_Manjaro_ISOs_with_buildiso
-----------------------------------------------------------------------------------
"
echo ""
read -p "Drücke eine beliebige taste um fortzufahren.."
echo ""

echo "Bereite vor..."
sleep 1

sudo rm -rf /var/lib/manjaro-tools/buildiso/
sudo rm -rf ~/iso-profiles
sudo pacman-mirrors --country Germany
sudo pacman -S --needed --noconfirm pacman-contrib
sudo paccache -ruk0
sudo pacman -Syy

git clone https://gitlab.manjaro.org/profiles-and-settings/iso-profiles.git ~/iso-profiles

echo ""
echo "Fertig. Fahre nun mit der erstellung der live iso fort.. "
sleep 3
clear

set -e  # Script beendet sich bei Fehlern

# Farbige Ausgabe
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfiguration
PROFILE="kde"         # Plasma verwendet das kde-Profil
BRANCH="stable"       # stable, testing, unstable
KERNEL="linux618"     # Kernel-Version
BUILD_TYPE="full"     # full oder minimal
ISO_OUTPUT="/var/cache/manjaro-tools/iso/manjaro/kde"
CONFIG_DIR="$HOME/.config/manjaro-tools"
PROFILES_DIR="$HOME/iso-profiles"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$HOME/manjaro_build_${TIMESTAMP}.log"

################################################################################
# Funktionen
################################################################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

log_output() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

check_disk_space() {
    print_header "Überprüfe Festplattenplatz"

    local required_space=20  # GB
    local available=$(df / | awk 'NR==2 {print int($4/1024/1024)}')

    print_info "Erforderlicher Speicher: ${required_space} GB"
    print_info "Verfügbarer Speicher: ${available} GB"

    if [ "$available" -lt "$required_space" ]; then
        print_error "Nicht genug Festplattenplatz! Mindestens ${required_space} GB erforderlich."
        exit 1
    fi

    print_success "Ausreichend Speicher verfügbar"
}

check_system_updated() {
    print_header "Überprüfe Systemaktualisierung"

    print_warning "Bitte stelle sicher, dass dein System aktualisiert ist:"
    print_info "sudo pacman -Syu"
    read -p "System wurde aktualisiert? (j/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        print_error "Bitte aktualisiere dein System zuerst."
        exit 1
    fi

    print_success "System ist aktuell"
}

install_tools() {
    print_header "Installiere Manjaro Tools"

    if ! command -v buildiso &> /dev/null; then
        print_warning "buildiso nicht gefunden. Installiere manjaro-tools-iso-git..."
        sudo pacman -Syu --noconfirm git manjaro-tools-iso-git
        print_success "Tools installiert"
    else
        print_success "manjaro-tools-iso-git bereits installiert"
    fi
}

setup_config() {
    print_header "Konfiguriere manjaro-tools"

    # Erstelle Konfigurationsverzeichnis
    mkdir -p "$CONFIG_DIR"

    # Kopiere oder erstelle Konfigurationsdatei
    if [ ! -f "$CONFIG_DIR/manjaro-tools.conf" ]; then
        print_info "Erstelle Konfigurationsdatei..."

        cat > "$CONFIG_DIR/manjaro-tools.conf" << 'EOF'
# Manjaro Tools Konfiguration

# Standard-Branch
target_branch=stable

# Cache-Verzeichnis
cache_dir=/var/cache/manjaro-tools

# Build-Verzeichnis
chroots_dir=/var/lib/manjaro-tools

# Log-Verzeichnis
log_dir=/var/log/manjaro-tools

# Mirror-Server
build_mirror=https://mirror.alpix.eu/manjaro/stable/$repo/$arch

# ISO Profile Verzeichnis
iso_profiles_dir=$HOME/iso-profiles

# Kernel
kernel=linux618

# Kompression
iso_compression=zstd
EOF
        print_success "Konfigurationsdatei erstellt"
    else
        print_success "Konfigurationsdatei existiert bereits"
    fi
}

download_profiles() {


    if [ -d "$PROFILES_DIR" ]; then

read -p "Beliebige Taste drücken zum konfigurieren der profile.conf datei für die Manjaro iso"
nano -w ~/iso-profiles/manjaro/kde/profile.conf

cat << EOF | tee -a ~/iso-profiles/manjaro/kde/Packages-Desktop
xfsdump
udftools
f2fs-tools
efibootmgr
gnome-disk-utility
pacman-contrib
kio-admin
wayland-protocols
plasma-wayland-protocols
waylandpp
dwayland
egl-wayland
python-pywayland
vulkan-dzn
vulkan-swrast
vulkan-validation-layers
vulkan-extra-layers
opencl-mesa
gsmartcontrol
filezilla
soundconverter
ffmpeg
vivaldi
vivaldi-ffmpeg-codecs
discord
cameractrls
pipewire-v4l2
pipewire-libcamera
gst-plugins-pipewire
yt-dlp
deno
yay
EOF

sed -i '/^firefox$/d' ~/iso-profiles/manjaro/kde/Packages-Desktop
sed -i '/^yakuake$/d' ~/iso-profiles/manjaro/kde/Packages-Desktop
sed -i '/^htop$/d' ~/iso-profiles/manjaro/kde/Packages-Desktop
sed -i '/^kdeconnect$/d' ~/iso-profiles/manjaro/kde/Packages-Desktop

read -p "Beliebige Taste drücken um Packages-Desktop zu kontrollieren und gegebenenfalls zu bearbeiten..."
nano -w ~/iso-profiles/manjaro/kde/Packages-Desktop


    else
        print_info "Klone ISO-Profile Repository..."
        #git clone https://gitlab.manjaro.org/profiles-and-settings/iso-profiles.git "$HOME/iso-profiles"
    fi

    print_success "ISO-Profile verfügbar unter: $PROFILES_DIR"
}

verify_profile() {
    print_header "Verifiziere Plasma-Profil"

    if [ ! -d "$PROFILES_DIR/manjaro/kde" ]; then
        print_error "Plasma-Profil nicht gefunden unter $PROFILES_DIR/manjaro/kde"
        exit 1
    fi

    print_success "Plasma-Profil gefunden"

    # Zeige Profil-Struktur
    print_info "Profil-Struktur:"
    ls -la "$PROFILES_DIR/manjaro/kde/" | grep -E '^d|^-' | awk '{print "  " $NF}'
}

build_iso() {
    print_header "Erstelle Plasma Live ISO"

    print_info "Profil: $PROFILE"
    print_info "Branch: $BRANCH"
    print_info "Kernel: $KERNEL"
    print_info "Build-Typ: $BUILD_TYPE"

    local build_cmd="buildiso"

    # Füge Parameter hinzu
    if [ "$BUILD_TYPE" = "full" ]; then
        build_cmd="$build_cmd -f"
    fi

    build_cmd="$build_cmd -p $PROFILE -b $BRANCH -k $KERNEL"

    print_warning "Starte ISO-Build mit: $build_cmd"
    print_warning "Dies kann 15-30 Minuten oder länger dauern..."

    log_output "Starte Build-Prozess"

    if eval "$build_cmd" 2>&1 | tee -a "$LOG_FILE"; then
        print_success "ISO-Build erfolgreich abgeschlossen"
        log_output "ISO-Build erfolgreich"
    else
        print_error "ISO-Build fehlgeschlagen. Siehe Log für Details: $LOG_FILE"
        log_output "ISO-Build fehlgeschlagen"
        exit 1
    fi
}

verify_iso() {
    print_header "Verifiziere erstellte ISO"

    if [ -d "$ISO_OUTPUT" ]; then
        local iso_files=$(find "$ISO_OUTPUT" -name "*.iso" -type f)

        if [ -z "$iso_files" ]; then
            print_warning "Keine ISO-Datei gefunden in $ISO_OUTPUT"
            return 1
        fi

        print_success "ISO-Dateien gefunden:"
        while IFS= read -r iso_file; do
            local size=$(du -h "$iso_file" | cut -f1)
            local checksum=$(sha256sum "$iso_file" | awk '{print $1}')
            print_info "  Datei: $(basename "$iso_file")"
            print_info "  Größe: $size"
            print_info "  SHA256: $checksum"
            echo "$checksum  $(basename "$iso_file")" >> "$HOME/iso_checksums.txt"
        done <<< "$iso_files"

        return 0
    else
        print_error "Ausgabeverzeichnis nicht gefunden: $ISO_OUTPUT"
        return 1
    fi
}

cleanup() {
    print_header "Cleanup-Optionen"

    echo -e "\nWas möchtest du bereinigen?"
    echo "1) Nur Build-Verzeichnis löschen (empfohlen)"
    echo "2) Alles löschen (Build + Cache)"
    echo "3) Nichts löschen"
    read -p "Wähle Option (1-3): " cleanup_option

    case $cleanup_option in
        1)
            print_warning "Lösche Build-Verzeichnis..."
            sudo rm -rf /var/lib/manjaro-tools/buildiso/
            print_success "Build-Verzeichnis gelöscht"
            ;;
        2)
            print_warning "Lösche Build-Verzeichnis und Cache..."
            sudo rm -rf /var/lib/manjaro-tools/buildiso/
            sudo paccache -ruk0
            print_success "Build und Cache gelöscht"
            ;;
        3)
            print_info "Kein Cleanup durchgeführt"
            ;;
    esac
}

show_summary() {
    print_header "Build-Zusammenfassung"

    log_output "========== BUILD SUMMARY =========="
    log_output "Profil: $PROFILE"
    log_output "Branch: $BRANCH"
    log_output "Kernel: $KERNEL"
    log_output "Build-Typ: $BUILD_TYPE"
    log_output "Log-Datei: $LOG_FILE"

    if [ -f "$HOME/iso_checksums.txt" ]; then
        log_output "Checksummen-Datei: $HOME/iso_checksums.txt"
    fi

    print_success "ISO-Build abgeschlossen!"
    print_info "Log-Datei: $LOG_FILE"
    print_info "ISO-Dateien: $ISO_OUTPUT"
}

################################################################################
# Hauptprogramm
################################################################################

main() {
    print_header "Manjaro Plasma Live ISO Builder"
    print_info "Start: $(date)"

    log_output "========== BUILD START =========="

    # Führe alle Schritte aus
    check_disk_space
    check_system_updated
    install_tools
    setup_config
    download_profiles
    verify_profile
    build_iso

    if verify_iso; then
        cleanup
        show_summary
        print_success "Alles abgeschlossen!"
    else
        print_error "ISO-Verifikation fehlgeschlagen"
        exit 1
    fi

    log_output "========== BUILD END =========="
    print_info "Ende: $(date)"
}

# Starte Hauptprogramm
main "$@"
