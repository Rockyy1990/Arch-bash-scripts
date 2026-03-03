#!/bin/bash

echo "
# Arch Linux ISO Creator Script
# Dieses Script erstellt eine benutzerdefinierte Arch Linux Installation ISO
"
echo ""
read -p "Beliebige Taste drücken um forzufahren.."
clear

set -e  # Beende bei Fehler

# Konfiguration
ISO_NAME="archlinux-custom"
ISO_VERSION="$(date +%Y.%m.%d)"
BUILD_DIR="./archiso-build"
OUTPUT_DIR="./iso-output"

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funktionen
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Dieses Script muss als root ausgeführt werden!"
        exit 1
    fi
}

check_dependencies() {
    log_info "Überprüfe Abhängigkeiten..."
    local deps=("archiso" "mkarchiso" "git")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_warn "$dep nicht gefunden. Installiere archiso..."
            pacman -S --noconfirm archiso
            break
        fi
    done
    log_info "Abhängigkeiten OK"
}

setup_directories() {
    log_info "Erstelle Verzeichnisse..."
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
    
    # Kopiere die Standard-Archiso-Profile
    if [[ ! -d "$BUILD_DIR/releng" ]]; then
        cp -r /usr/share/archiso/configs/releng "$BUILD_DIR/"
    fi
}

customize_iso() {
    log_info "Passe ISO an..."
    local profile_dir="$BUILD_DIR/releng"
    
    # Ändere den Dateinamen
    sed -i "s/iso_name=.*/iso_name=$ISO_NAME/" "$profile_dir/profiledef.sh"
    sed -i "s/iso_version=.*/iso_version=$ISO_VERSION/" "$profile_dir/profiledef.sh"
    
    # Optional: Zusätzliche Pakete installieren
    # Uncomment die nächste Zeile und füge Pakete hinzu
    # echo "vim git curl wget" >> "$profile_dir/packages.x86_64"
    
    log_info "ISO-Anpassungen abgeschlossen"
}

build_iso() {
    log_info "Baue ISO... (dies kann einige Minuten dauern)"
    
    cd "$BUILD_DIR/releng"
    mkarchiso -v -o "$OUTPUT_DIR" .
    
    if [[ $? -eq 0 ]]; then
        log_info "ISO erfolgreich erstellt!"
    else
        log_error "Fehler beim Erstellen der ISO"
        exit 1
    fi
}

cleanup() {
    log_info "Räume auf..."
    # Optional: Entferne Build-Verzeichnis nach erfolgreicher Erstellung
    # rm -rf "$BUILD_DIR"
    log_info "Fertig!"
}

show_result() {
    log_info "ISO-Datei(en) in $OUTPUT_DIR:"
    ls -lh "$OUTPUT_DIR"/*.iso 2>/dev/null || log_warn "Keine ISO-Dateien gefunden"
}

# Hauptprogramm
main() {
    log_info "Starte Arch Linux ISO-Erstellung..."
    
    check_root
    check_dependencies
    setup_directories
    customize_iso
    build_iso
    show_result
    cleanup
    
    log_info "Prozess abgeschlossen!"
}

# Starte das Script
main
