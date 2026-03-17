#!/bin/bash

################################################################################
# YAY AUR Helper Interactive Menu
# Ein benutzerfreundliches CLI-Menu für alle yay-Funktionen
# Datum: 17.03.2026
################################################################################

# Farben für bessere Lesbarkeit
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Funktionen für Ausgabe
print_header() {
    clear
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                    YAY AUR Helper                      ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_submenu_header() {
    echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${MAGENTA}${BOLD}$1${NC}"
    echo -e "${MAGENTA}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}${BOLD}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}${BOLD}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}${BOLD}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}${BOLD}⚠ $1${NC}"
}

pause_menu() {
    echo ""
    echo -e "${YELLOW}Drücke Enter zum Fortfahren...${NC}"
    read -r
}

# Hauptmenü
main_menu() {
    while true; do
        print_header

        echo -e "${BOLD}Wähle eine Option:${NC}"
        echo ""
        echo -e "${GREEN}[1]${NC}  Pakete suchen"
        echo -e "${GREEN}[2]${NC}  Paket installieren"
        echo -e "${GREEN}[3]${NC}  Pakete aktualisieren"
        echo -e "${GREEN}[4]${NC}  Paket deinstallieren"
        echo -e "${GREEN}[5]${NC}  Paketinformationen anzeigen"
        echo -e "${GREEN}[6]${NC}  Abhängigkeiten bereinigen"
        echo -e "${GREEN}[7]${NC}  Erweiterte Funktionen"
        echo -e "${GREEN}[8]${NC}  System-Informationen"
        echo -e "${GREEN}[9]${NC}  Einstellungen"
        echo -e "${RED}[0]${NC}  Beenden"
        echo ""
        read -p "Eingabe: " choice

        case $choice in
            1) search_packages ;;
            2) install_package ;;
            3) update_packages ;;
            4) remove_package ;;
            5) package_info ;;
            6) clean_dependencies ;;
            7) advanced_menu ;;
            8) system_info ;;
            9) settings_menu ;;
            0)
                echo -e "${CYAN}Auf Wiedersehen!${NC}"
                exit 0
                ;;
            *)
                print_error "Ungültige Eingabe!"
                sleep 1
                ;;
        esac
    done
}

# 1. Pakete suchen
search_packages() {
    print_header
    print_submenu_header "Pakete suchen"

    read -p "Suchbegriff eingeben: " search_term

    if [ -z "$search_term" ]; then
        print_error "Suchbegriff kann nicht leer sein!"
        pause_menu
        return
    fi

    print_info "Durchsuche offizielle Repos und AUR..."
    yay -Ss "$search_term"

    pause_menu
}

# 2. Paket installieren
install_package() {
    print_header
    print_submenu_header "Paket installieren"

    read -p "Paketnamen eingeben (mehrere mit Leerzeichen trennen): " packages

    if [ -z "$packages" ]; then
        print_error "Paketname kann nicht leer sein!"
        pause_menu
        return
    fi

    print_info "Installiere Paket(e): $packages"
    yay -S $packages

    if [ $? -eq 0 ]; then
        print_success "Paket(e) erfolgreich installiert!"
    else
        print_error "Installation fehlgeschlagen!"
    fi

    pause_menu
}

# 3. Pakete aktualisieren
update_packages() {
    print_header
    print_submenu_header "Pakete aktualisieren"

    echo -e "${BOLD}Wähle Aktualisierungstyp:${NC}"
    echo ""
    echo -e "${GREEN}[1]${NC}  Alle Pakete aktualisieren (AUR + offizielle Repos)"
    echo -e "${GREEN}[2]${NC}  Nur AUR-Pakete aktualisieren"
    echo -e "${GREEN}[3]${NC}  Nur offizielle Repo-Pakete aktualisieren"
    echo -e "${RED}[0]${NC}  Abbrechen"
    echo ""
    read -p "Eingabe: " update_choice

    case $update_choice in
        1)
            print_info "Aktualisiere alle Pakete..."
            yay -Syu
            ;;
        2)
            print_info "Aktualisiere nur AUR-Pakete..."
            yay -Sua
            ;;
        3)
            print_info "Aktualisiere nur offizielle Repo-Pakete..."
            yay -Syu --repo
            ;;
        0)
            return
            ;;
        *)
            print_error "Ungültige Eingabe!"
            ;;
    esac

    pause_menu
}

# 4. Paket deinstallieren
remove_package() {
    print_header
    print_submenu_header "Paket deinstallieren"

    read -p "Paketnamen eingeben (mehrere mit Leerzeichen trennen): " packages

    if [ -z "$packages" ]; then
        print_error "Paketname kann nicht leer sein!"
        pause_menu
        return
    fi

    echo ""
    echo -e "${BOLD}Deinstallationstyp:${NC}"
    echo ""
    echo -e "${GREEN}[1]${NC}  Paket nur entfernen"
    echo -e "${GREEN}[2]${NC}  Paket + Abhängigkeiten entfernen"
    echo -e "${GREEN}[3]${NC}  Paket + Abhängigkeiten + Konfiguration entfernen"
    echo -e "${RED}[0]${NC}  Abbrechen"
    echo ""
    read -p "Eingabe: " remove_choice

    case $remove_choice in
        1)
            yay -R $packages
            ;;
        2)
            yay -Rs $packages
            ;;
        3)
            yay -Rns $packages
            ;;
        0)
            return
            ;;
        *)
            print_error "Ungültige Eingabe!"
            ;;
    esac

    pause_menu
}

# 5. Paketinformationen
package_info() {
    print_header
    print_submenu_header "Paketinformationen"

    read -p "Paketnamen eingeben: " package

    if [ -z "$package" ]; then
        print_error "Paketname kann nicht leer sein!"
        pause_menu
        return
    fi

    echo ""
    echo -e "${BOLD}Wähle Informationstyp:${NC}"
    echo ""
    echo -e "${GREEN}[1]${NC}  Lokale Paketinformation (-Qi)"
    echo -e "${GREEN}[2]${NC}  Repo/AUR Paketinformation (-Si)"
    echo -e "${GREEN}[3]${NC}  Dateiinformation des Pakets (-Ql)"
    echo -e "${RED}[0]${NC}  Abbrechen"
    echo ""
    read -p "Eingabe: " info_choice

    case $info_choice in
        1)
            yay -Qi "$package"
            ;;
        2)
            yay -Si "$package"
            ;;
        3)
            yay -Ql "$package"
            ;;
        0)
            return
            ;;
        *)
            print_error "Ungültige Eingabe!"
            ;;
    esac

    pause_menu
}

# 6. Abhängigkeiten bereinigen
clean_dependencies() {
    print_header
    print_submenu_header "Abhängigkeiten bereinigen"

    echo ""
    echo -e "${BOLD}Bereinigungsoptionen:${NC}"
    echo ""
    echo -e "${GREEN}[1]${NC}  Nicht benötigte Abhängigkeiten entfernen (-Yc)"
    echo -e "${GREEN}[2]${NC}  Build-Dateien bereinigen (-Sc)"
    echo -e "${GREEN}[3]${NC}  Alle Cache-Dateien entfernen (-Scc)"
    echo -e "${GREEN}[4]${NC}  Uninstallierte Pakete aus Cache entfernen"
    echo -e "${RED}[0]${NC}  Abbrechen"
    echo ""
    read -p "Eingabe: " clean_choice

    case $clean_choice in
        1)
            print_info "Entferne nicht benötigte Abhängigkeiten..."
            yay -Yc
            print_success "Abhängigkeiten bereinigt!"
            ;;
        2)
            print_info "Bereinige Build-Dateien..."
            yay -Sc
            print_success "Build-Dateien bereinigt!"
            ;;
        3)
            print_info "Entferne alle Cache-Dateien..."
            yay -Scc
            print_success "Cache geleert!"
            ;;
        4)
            print_info "Entferne uninstallierte Pakete aus Cache..."
            yay -Scc --aur
            print_success "Uninstallierte Pakete entfernt!"
            ;;
        0)
            return
            ;;
        *)
            print_error "Ungültige Eingabe!"
            ;;
    esac

    pause_menu
}

# 7. Erweiterte Funktionen
advanced_menu() {
    while true; do
        print_header
        print_submenu_header "Erweiterte Funktionen"

        echo -e "${BOLD}Wähle eine Option:${NC}"
        echo ""
        echo -e "${GREEN}[1]${NC}  Installierte Pakete auflisten"
        echo -e "${GREEN}[2]${NC}  Explizit installierte Pakete auflisten"
        echo -e "${GREEN}[3]${NC}  Verwaiste Pakete anzeigen"
        echo -e "${GREEN}[4]${NC}  Paket-Abhängigkeiten anzeigen"
        echo -e "${GREEN}[5]${NC}  Paket-Rückwärts-Abhängigkeiten anzeigen"
        echo -e "${GREEN}[6]${NC}  Paket-Größe anzeigen"
        echo -e "${GREEN}[7]${NC}  Für Paket abstimmen"
        echo -e "${GREEN}[8]${NC}  Abstimmung für Paket entfernen"
        echo -e "${GREEN}[9]${NC}  Datenbank neu generieren (-Y --gendb)"
        echo -e "${GREEN}[10]${NC} Upgrade-Statistiken anzeigen"
        echo -e "${RED}[0]${NC}  Zurück zum Hauptmenü"
        echo ""
        read -p "Eingabe: " adv_choice

        case $adv_choice in
            1)
                print_header
                print_submenu_header "Installierte Pakete"
                yay -Q | less
                ;;
            2)
                print_header
                print_submenu_header "Explizit installierte Pakete"
                yay -Qe | less
                ;;
            3)
                print_header
                print_submenu_header "Verwaiste Pakete"
                yay -Qt
                ;;
            4)
                print_header
                print_submenu_header "Paket-Abhängigkeiten"
                read -p "Paketnamen eingeben: " pkg
                yay -Qi "$pkg" | grep -A 20 "Depends On"
                ;;
            5)
                print_header
                print_submenu_header "Rückwärts-Abhängigkeiten"
                read -p "Paketnamen eingeben: " pkg
                yay -Ss "$pkg" | grep -B 1 "Depends On.*$pkg"
                ;;
            6)
                print_header
                print_submenu_header "Paket-Größe"
                read -p "Paketnamen eingeben: " pkg
                yay -Qi "$pkg" | grep -E "Installed Size"
                ;;
            7)
                read -p "Paketnamen eingeben (für Abstimmung): " pkg
                yay -Y --vote "$pkg"
                print_success "Für $pkg abgestimmt!"
                ;;
            8)
                read -p "Paketnamen eingeben (Abstimmung entfernen): " pkg
                yay -Y --unvote "$pkg"
                print_success "Abstimmung für $pkg entfernt!"
                ;;
            9)
                print_info "Regeneriere Datenbank..."
                yay -Y --gendb
                print_success "Datenbank regeneriert!"
                ;;
            10)
                print_header
                print_submenu_header "Upgrade-Statistiken"
                yay --stats
                ;;
            0)
                return
                ;;
            *)
                print_error "Ungültige Eingabe!"
                sleep 1
                ;;
        esac

        pause_menu
    done
}

# 8. System-Informationen
system_info() {
    print_header
    print_submenu_header "System-Informationen"

    echo -e "${BOLD}YAY Version:${NC}"
    yay --version

    echo ""
    echo -e "${BOLD}Pacman Konfiguration:${NC}"
    grep -E "^[^#]" /etc/pacman.conf | head -20

    echo ""
    echo -e "${BOLD}Installierte Pakete (Gesamt):${NC}"
    yay -Q | wc -l

    echo ""
    echo -e "${BOLD}AUR Pakete:${NC}"
    yay -Qm | wc -l

    echo ""
    echo -e "${BOLD}Offizielle Repo Pakete:${NC}"
    yay -Qn | wc -l

    pause_menu
}

# 9. Einstellungen
settings_menu() {
    while true; do
        print_header
        print_submenu_header "Einstellungen"

        echo -e "${BOLD}Wähle eine Option:${NC}"
        echo ""
        echo -e "${GREEN}[1]${NC}  YAY Konfiguration öffnen"
        echo -e "${GREEN}[2]${NC}  Pacman Konfiguration öffnen"
        echo -e "${GREEN}[3]${NC}  YAY Cache-Verzeichnis anzeigen"
        echo -e "${GREEN}[4]${NC}  Konfigurationsdateien auflisten"
        echo -e "${GREEN}[4]${NC}  Konfigurationsdateien auflisten"
        echo -e "${GREEN}[5]${NC}  YAY Hilfe anzeigen"
        echo -e "${RED}[0]${NC}  Zurück zum Hauptmenü"
        echo ""
        read -p "Eingabe: " settings_choice

        case $settings_choice in
            1)
                if [ -f "$HOME/.config/yay/config.json" ]; then
                    ${EDITOR:-nano} "$HOME/.config/yay/config.json"
                else
                    print_error "Konfigurationsdatei nicht gefunden!"
                fi
                ;;
            2)
                sudo ${EDITOR:-nano} /etc/pacman.conf
                ;;
            3)
                print_info "YAY Cache-Verzeichnis:"
                du -sh "$HOME/.cache/yay" 2>/dev/null || print_error "Cache-Verzeichnis nicht gefunden"
                ;;
            4)
                print_header
                print_submenu_header "Konfigurationsdateien"
                echo -e "${BOLD}YAY Konfiguration:${NC}"
                ls -la "$HOME/.config/yay/" 2>/dev/null || print_error "YAY Konfigurationsverzeichnis nicht gefunden"
                echo ""
                echo -e "${BOLD}Pacman Konfiguration:${NC}"
                ls -la /etc/pacman.conf /etc/pacman.d/ 2>/dev/null || print_error "Pacman Konfiguration nicht gefunden"
                ;;
            5)
                print_header
                print_submenu_header "YAY Hilfe"
                yay --help | less
                ;;
            0)
                return
                ;;
            *)
                print_error "Ungültige Eingabe!"
                sleep 1
                ;;
        esac

        pause_menu
    done
}

################################################################################
# Hauptprogramm
################################################################################

# Überprüfe, ob yay installiert ist
if ! command -v yay &> /dev/null; then
    print_error "YAY ist nicht installiert!"
    echo "Installation: git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si"
    exit 1
fi

# Starte Hauptmenü
main_menu

