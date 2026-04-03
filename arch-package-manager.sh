#!/bin/bash

# Farben definieren
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Funktionen für Ausgabe
print_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}       Arch Linux Package Manager${CYAN}     ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""
}

print_error() {
    echo -e "${RED}✗ Fehler: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Pacman Menü
pacman_menu() {
    while true; do
        print_header
        echo -e "${YELLOW}=== PACMAN GUI ===${NC}"
        echo ""
        echo -e "${GREEN}1)${NC} Paketlisten aktualisieren (pacman -Sy)"
        echo -e "${GREEN}2)${NC} Pakete installieren"
        echo -e "${GREEN}3)${NC} Pakete entfernen (mit Abhängigkeiten)"
        echo -e "${GREEN}4)${NC} Einzelnes Paket entfernen (ohne Abhängigkeiten)"
        echo -e "${GREEN}5)${NC} Cache leeren (pacman -Scc)"
        echo -e "${GREEN}6)${NC} Systemupgrade (pacman -Syu)"
        echo -e "${GREEN}7)${NC} Pacman Reparatur & Wartung"
        echo -e "${GREEN}8)${NC} Zurück zum Hauptmenü"
        echo ""
        read -p "Wähle eine Option [1-8]: " choice

        case $choice in
            1)
                print_header
                print_info "Aktualisiere Paketlisten..."
                sudo pacman -Sy
                if [ $? -eq 0 ]; then
                    print_success "Paketlisten erfolgreich aktualisiert"
                else
                    print_error "Fehler beim Aktualisieren der Paketlisten"
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            2)
                print_header
                read -p "Paketname eingeben (durch Leerzeichen trennen): " packages
                if [ -z "$packages" ]; then
                    print_error "Keine Pakete eingegeben"
                else
                    print_info "Installiere Pakete: $packages"
                    sudo pacman -S $packages
                    if [ $? -eq 0 ]; then
                        print_success "Pakete erfolgreich installiert"
                    else
                        print_error "Fehler beim Installieren"
                    fi
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            3)
                print_header
                read -p "Paketname eingeben (durch Leerzeichen trennen): " packages
                if [ -z "$packages" ]; then
                    print_error "Keine Pakete eingegeben"
                else
                    print_warning "Entferne Pakete: $packages"
                    sudo pacman -R $packages
                    if [ $? -eq 0 ]; then
                        print_success "Pakete erfolgreich entfernt"
                    else
                        print_error "Fehler beim Entfernen"
                    fi
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            4)
                print_header
                read -p "Paketname eingeben: " package
                if [ -z "$package" ]; then
                    print_error "Keine Paket eingegeben"
                else
                    print_warning "Entferne Paket ohne Abhängigkeiten: $package"
                    sudo pacman -Rdd $package
                    if [ $? -eq 0 ]; then
                        print_success "Paket erfolgreich entfernt"
                    else
                        print_error "Fehler beim Entfernen"
                    fi
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            5)
                print_header
                print_warning "Leere Cache..."
                sudo pacman -Scc
                if [ $? -eq 0 ]; then
                    print_success "Cache erfolgreich geleert"
                else
                    print_error "Fehler beim Leeren des Cache"
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            6)
                print_header
                print_info "Führe Systemupgrade durch..."
                sudo pacman -Syu
                if [ $? -eq 0 ]; then
                    print_success "Systemupgrade erfolgreich abgeschlossen"
                else
                    print_error "Fehler beim Systemupgrade"
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            7)
                pacman_repair_menu
                ;;
            8)
                return
                ;;
            *)
                print_error "Ungültige Option"
                sleep 1
                ;;
        esac
    done
}

# Pacman Reparatur Menü
pacman_repair_menu() {
    while true; do
        print_header
        echo -e "${RED}=== PACMAN REPARATUR & WARTUNG ===${NC}"
        echo ""
        echo -e "${GREEN}1)${NC} Archlinux-Keyring aktualisieren (pacman -Sy archlinux-keyring)"
        echo -e "${GREEN}2)${NC} Etc-Dateien synchronisieren (pacdiff)"
        echo -e "${GREEN}3)${NC} Beschädigte Paketdatenbank reparieren"
        echo -e "${GREEN}4)${NC} Paketdatenbank leeren und neu aufbauen"
        echo -e "${GREEN}5)${NC} Verwaiste Pakete entfernen"
        echo -e "${GREEN}6)${NC} Systemintegrität überprüfen"
        echo -e "${GREEN}7)${NC} Vollständige Systemreparatur"
        echo -e "${GREEN}8)${NC} Pacman-Konfiguration überprüfen"
        echo -e "${GREEN}9)${NC} Zurück zum Pacman-Menü"
        echo ""
        read -p "Wähle eine Option [1-9]: " choice

        case $choice in
            1)
                print_header
                print_warning "Aktualisiere Archlinux-Keyring..."
                print_info "Dies ist wichtig für die Paket-Signaturverifikation"
                sudo pacman -Sy archlinux-keyring
                if [ $? -eq 0 ]; then
                    print_success "Archlinux-Keyring erfolgreich aktualisiert"
                else
                    print_error "Fehler beim Aktualisieren des Keyrings"
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            2)
                print_header
                print_info "Synchronisiere /etc-Dateien..."
                print_warning "Dies zeigt Unterschiede zwischen aktuellen und neuen Konfigurationsdateien"

                if ! command -v pacdiff &> /dev/null; then
                    print_error "pacdiff ist nicht installiert"
                    print_info "Installiere es mit: sudo pacman -S pacman-contrib"
                else
                    sudo pacdiff
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            3)
                print_header
                print_warning "Repariere beschädigte Paketdatenbank..."
                print_info "Dies kann einige Zeit dauern"

                sudo rm -f /var/lib/pacman/db.lck
                if [ $? -eq 0 ]; then
                    print_success "Datenbank-Lock-Datei entfernt"
                fi

                sudo pacman -Syy
                if [ $? -eq 0 ]; then
                    print_success "Paketdatenbank erfolgreich repariert"
                else
                    print_error "Fehler bei der Reparatur"
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            4)
                print_header
                print_warning "WARNUNG: Dies wird die Paketdatenbank leeren und neu aufbauen!"
                print_warning "Dies sollte nur im Notfall durchgeführt werden."
                read -p "Fortfahren? (j/N): " confirm

                if [[ $confirm == "j" || $confirm == "J" ]]; then
                    print_info "Leere alte Datenbank..."
                    sudo rm -rf /var/lib/pacman/sync/*

                    print_info "Baue Datenbank neu auf..."
                    sudo pacman -Syy

                    if [ $? -eq 0 ]; then
                        print_success "Paketdatenbank erfolgreich neu aufgebaut"
                    else
                        print_error "Fehler beim Neuaufbau"
                    fi
                else
                    print_info "Abgebrochen"
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            5)
                print_header
                print_info "Suche verwaiste Pakete..."
                orphaned=$(pacman -Qtd)

                if [ -z "$orphaned" ]; then
                    print_success "Keine verwaisten Pakete gefunden"
                else
                    echo -e "${YELLOW}Verwaiste Pakete gefunden:${NC}"
                    echo "$orphaned"
                    echo ""
                    read -p "Entfernen? (j/N): " confirm

                    if [[ $confirm == "j" || $confirm == "J" ]]; then
                        sudo pacman -R $(pacman -Qtdq)
                        if [ $? -eq 0 ]; then
                            print_success "Verwaiste Pakete entfernt"
                        else
                            print_error "Fehler beim Entfernen"
                        fi
                    fi
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            6)
                print_header
                print_info "Überprüfe Systemintegrität..."
                print_info "Dies überprüft alle installierten Dateien..."

                sudo pacman -Qk
                if [ $? -eq 0 ]; then
                    print_success "Systemintegrität ist OK"
                else
                    print_warning "Einige Probleme gefunden - siehe oben"
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            7)
                print_header
                print_warning "WARNUNG: Vollständige Systemreparatur wird durchgeführt!"
                print_warning "Dies führt mehrere Reparaturschritte nacheinander aus."
                read -p "Fortfahren? (j/N): " confirm

                if [[ $confirm == "j" || $confirm == "J" ]]; then
                    print_info "Schritt 1: Entferne Lock-Datei..."
                    sudo rm -f /var/lib/pacman/db.lck

                    print_info "Schritt 2: Aktualisiere Keyring..."
                    sudo pacman -Sy archlinux-keyring

                    print_info "Schritt 3: Aktualisiere Paketlisten..."
                    sudo pacman -Syy

                    print_info "Schritt 4: Überprüfe Integrität..."
                    sudo pacman -Qk

                    print_info "Schritt 5: Entferne verwaiste Pakete..."
                    sudo pacman -R $(pacman -Qtdq) 2>/dev/null

                    print_success "Vollständige Systemreparatur abgeschlossen"
                else
                    print_info "Abgebrochen"
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            8)
                print_header
                print_info "Zeige Pacman-Konfiguration..."
                echo ""
                sudo cat /etc/pacman.conf | grep -v "^#" | grep -v "^$"
                read -p "Drücke Enter um fortzufahren..."
                ;;
            9)
                return
                ;;
            *)
                print_error "Ungültige Option"
                sleep 1
                ;;
        esac
    done
}

# YAY Menü
yay_menu() {
    # Prüfe ob yay installiert ist
    if ! command -v yay &> /dev/null; then
        print_header
        print_error "yay ist nicht installiert"
        print_info "Installiere yay mit: sudo pacman -S yay"
        read -p "Drücke Enter um fortzufahren..."
        return
    fi

    while true; do
        print_header
        echo -e "${MAGENTA}=== YAY AUR-HELPER ===${NC}"
        echo ""
        echo -e "${GREEN}1)${NC} Pakete aus AUR installieren (yay -S)"
        echo -e "${GREEN}2)${NC} Pakete entfernen (yay -R)"
        echo -e "${GREEN}3)${NC} Nach Paketen suchen (yay -Ss)"
        echo -e "${GREEN}4)${NC} AUR-Pakete aktualisieren (yay -Syu)"
        echo -e "${GREEN}5)${NC} Zurück zum Hauptmenü"
        echo ""
        read -p "Wähle eine Option [1-5]: " choice

        case $choice in
            1)
                print_header
                read -p "Paketname eingeben (durch Leerzeichen trennen): " packages
                if [ -z "$packages" ]; then
                    print_error "Keine Pakete eingegeben"
                else
                    print_info "Installiere AUR-Pakete: $packages"
                    yay -S $packages
                    if [ $? -eq 0 ]; then
                        print_success "Pakete erfolgreich installiert"
                    else
                        print_error "Fehler beim Installieren"
                    fi
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            2)
                print_header
                read -p "Paketname eingeben (durch Leerzeichen trennen): " packages
                if [ -z "$packages" ]; then
                    print_error "Keine Pakete eingegeben"
                else
                    print_warning "Entferne Pakete: $packages"
                    yay -R $packages
                    if [ $? -eq 0 ]; then
                        print_success "Pakete erfolgreich entfernt"
                    else
                        print_error "Fehler beim Entfernen"
                    fi
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            3)
                print_header
                read -p "Suchbegriff eingeben: " search_term
                if [ -z "$search_term" ]; then
                    print_error "Kein Suchbegriff eingegeben"
                else
                    print_info "Suche nach: $search_term"
                    yay -Ss $search_term
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
            4)
                print_header
                print_info "Aktualisiere AUR-Pakete..."
                yay -Syu
                if [ $? -eq 0 ]; then
                    print_success "AUR-Pakete erfolgreich aktualisiert"
                else
                    print_error "Fehler beim Aktualisieren"
                fi
                read -p "Drücke Enter um fortzufahren..."
                ;;
                        5)
                return
                ;;
            *)
                print_error "Ungültige Option"
                sleep 1
                ;;
        esac
    done
}

# Hauptmenü
main_menu() {
    while true; do
        print_header
        echo -e "${WHITE}=== HAUPTMENÜ ===${NC}"
        echo ""
        echo -e "${GREEN}1)${NC} PACMAN Paketmanager"
        echo -e "${GREEN}2)${NC} YAY AUR-Helper"
        echo -e "${GREEN}3)${NC} Beenden"
        echo ""
        read -p "Wähle eine Option [1-3]: " choice

        case $choice in
            1)
                pacman_menu
                ;;
            2)
                yay_menu
                ;;
            3)
                clear
                echo -e "${GREEN}Auf Wiedersehen!${NC}"
                exit 0
                ;;
            *)
                print_error "Ungültige Option"
                sleep 1
                ;;
        esac
    done
}

# Script starten
main_menu


