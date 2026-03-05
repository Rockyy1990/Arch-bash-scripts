#!/bin/bash

# ============================================================================
# Manjaro Package Installation Script
# ============================================================================
# Dieses Script installiert eine umfangreiche Sammlung von Paketen für
# Manjaro Linux mit professionellem Logging und Fehlerbehandlung.
# ============================================================================

set -euo pipefail

# Farben definieren
readonly ORANGE='\033[38;5;208m'
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# ============================================================================
# Logging-Funktionen
# ============================================================================

log_info() {
    echo -e "${ORANGE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# ============================================================================
# Paketliste
# ============================================================================

declare -a PACKAGES=(
    # Dateisystem- und Speicher-Tools
    "xfsdump"
    "udftools"
    "f2fs-tools"

    # Boot und UEFI
    "efibootmgr"

    # Disk Management
    "gnome-disk-utility"
    "gsmartcontrol"

    # Paketmanagement
    "pacman-contrib"
    "yay"

    # Desktop-Umgebung und Admin
    "kio-admin"

    # Wayland Support
    "wayland-protocols"
    "plasma-wayland-protocols"
    "waylandpp"
    "dwayland"
    "egl-wayland"
    "python-pywayland"

    # Vulkan und Grafik
    "vulkan-dzn"
    "vulkan-swrast"
    "vulkan-validation-layers"
    "vulkan-extra-layers"
    "opencl-mesa"

    # Multimedia
    "ffmpeg"
    "soundconverter"
    "handbrake"
    "pipewire-v4l2"
    "pipewire-libcamera"
    "gst-plugins-pipewire"
    "cameractrls"
    "obs-studio"

    # Internet und Kommunikation
    "filezilla"
    "vivaldi"
    "vivaldi-ffmpeg-codecs"
    "discord"
    "yt-dlp"

    # Gaming und Wine
    "wine"
    "wine-mono"
    "winetricks"
    "steam"
    "protontricks"
    "protonup-qt"
    "gamemode"

    # USB Tools
    "mintstick"

    # Entwicklung
    "deno"
)

# Pakete zum Entfernen
declare -a REMOVE_PACKAGES=(
    "firefox"
    "kdeconnect"
)

# ============================================================================
# Hauptfunktionen
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Dieses Script muss mit Root-Rechten ausgeführt werden!"
        exit 1
    fi
}

check_system() {
    log_info "Überprüfe Systemvoraussetzungen..."

    if ! command -v pacman &> /dev/null; then
        log_error "Pacman nicht gefunden. Dieses Script ist nur für Manjaro/Arch gedacht!"
        exit 1
    fi

    log_success "Systemvoraussetzungen erfüllt"
}

update_system() {
    log_info "Aktualisiere Paketdatenbank und System..."
    pacman -Syu --noconfirm
    log_success "System aktualisiert"
}

remove_packages() {
    local total=${#REMOVE_PACKAGES[@]}
    local current=0

    if [ $total -eq 0 ]; then
        log_info "Keine Pakete zum Entfernen"
        return
    fi

    echo ""
    log_warning "Entferne ${total} Pakete..."
    echo ""

    for package in "${REMOVE_PACKAGES[@]}"; do
        ((current++))
        log_info "[${current}/${total}] Entferne: ${ORANGE}${package}${NC}"

        if pacman -R "$package" --noconfirm 2>/dev/null; then
            log_success "✓ ${package} erfolgreich entfernt"
        else
            log_warning "⚠ ${package} war nicht installiert oder konnte nicht entfernt werden"
        fi
        echo ""
    done
}

install_packages() {
    local total=${#PACKAGES[@]}
    local current=0

    log_info "Starte Installation von ${total} Paketen..."
    echo ""

    for package in "${PACKAGES[@]}"; do
        ((current++))
        log_info "[${current}/${total}] Installiere: ${ORANGE}${package}${NC}"

        if pacman -S "$package" --noconfirm 2>/dev/null; then
            log_success "✓ ${package} erfolgreich installiert"
        else
            log_warning "⚠ ${package} konnte nicht installiert werden (möglicherweise bereits vorhanden)"
        fi
        echo ""
    done
}

install_aur_packages() {
    log_info "Installiere AUR-Pakete über yay..."

    # Prüfe ob yay vorhanden ist
    if ! command -v yay &> /dev/null; then
        log_warning "yay nicht gefunden, überspringe AUR-Pakete"
        return
    fi

    # Beispiel für zusätzliche AUR-Pakete (optional)
    declare -a AUR_PACKAGES=(
        # Hier können zusätzliche AUR-Pakete hinzugefügt werden
    )

    if [ ${#AUR_PACKAGES[@]} -gt 0 ]; then
        for package in "${AUR_PACKAGES[@]}"; do
            log_info "Installiere AUR-Paket: ${ORANGE}${package}${NC}"
            yay -S "$package" --noconfirm || log_warning "AUR-Paket ${package} konnte nicht installiert werden"
        done
    fi
}

cleanup() {
    log_info "Räume auf und entferne verwaiste Abhängigkeiten..."
    pacman -Sc --noconfirm
    pacman -Rns $(pacman -Qdtq) --noconfirm 2>/dev/null || true
    log_success "Aufräumen abgeschlossen"
}

show_summary() {
    echo ""
    echo -e "${ORANGE}════════════════════════════════════════════════════${NC}"
    echo -e "${ORANGE}Installation abgeschlossen!${NC}"
    echo -e "${ORANGE}════════════════════════════════════════════════════${NC}"
    echo ""
    log_success "Alle verfügbaren Pakete wurden installiert"
    log_success "Folgende Pakete wurden entfernt: ${REMOVE_PACKAGES[*]}"
    echo ""
    log_info "Nächste Schritte:"
    echo "  • Starten Sie Ihren Computer neu: ${ORANGE}reboot${NC}"
    echo "  • Konfigurieren Sie Steam unter ~/.steam"
    echo "  • Aktivieren Sie Wayland in Ihren Desktop-Einstellungen"
    echo "  • Verwenden Sie Vivaldi als Standard-Browser"
    echo ""
}

# ============================================================================
# Hauptprogramm
# ============================================================================

main() {
    clear

    echo -e "${ORANGE}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     Manjaro Package Installation Script v2.0       ║"
    echo "║     Professionelle Paketinstallation für Manjaro   ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""

    check_root
    check_system

    log_warning "Dieses Script wird:"
    echo "  • ${#REMOVE_PACKAGES[@]} Paket(e) entfernen: ${REMOVE_PACKAGES[*]}"
    echo "  • ${#PACKAGES[@]} Paket(e) installieren"
    echo ""
    read -p "Möchten Sie fortfahren? (j/n) " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        log_warning "Installation abgebrochen"
        exit 0
    fi

    echo ""
    update_system
    echo ""
    remove_packages
    echo ""
    install_packages
    echo ""
    install_aur_packages
    echo ""
    cleanup
    echo ""
    show_summary
}

# ============================================================================
# Fehlerbehandlung
# ============================================================================

trap 'log_error "Script wurde unterbrochen"; exit 1' INT TERM

# Script ausführen
main "$@"
