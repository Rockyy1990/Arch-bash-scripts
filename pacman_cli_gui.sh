#!/bin/bash

# Farben definieren
ORANGE='\033[0;33m'
RESET='\033[0m'

# Funktion für das Menü
show_menu() {
    echo -e "${ORANGE}Bitte wählen Sie eine Option:${RESET}"
    echo -e "${ORANGE}1.${RESET} System aktualisieren (pacman -Syu)"
    echo -e "${ORANGE}2.${RESET} Arch-Keyring aktualisieren"
    echo -e "${ORANGE}3.${RESET} Paket installieren"
    echo -e "${ORANGE}4.${RESET} Paket entfernen"
    echo -e "${ORANGE}5.${RESET} Paket suchen"
    echo -e "${ORANGE}6.${RESET} Installierte Pakete anzeigen"
    echo -e "${ORANGE}7.${RESET} Paketinformationen anzeigen"
    echo -e "${ORANGE}8.${RESET} Verwaiste Pakete entfernen"
    echo -e "${ORANGE}9.${RESET} Paket-Cache leeren"
    echo -e "${ORANGE}11.${RESET} Paketdatenbank reparieren"
    echo -e "${ORANGE}0.${RESET} Beenden"
    echo -n "Ihre Wahl: "
}

# Hauptschleife
while true; do
    show_menu
    read -r choice

    case "$choice" in
        1)
            echo "System wird aktualisiert..."
            sudo pacman -Syu
            ;;
        2)
            echo "Arch-Keyring wird aktualisiert..."
            sudo pacman -Sy archlinux-keyring
            ;;
        3)
            echo -n "Geben Sie den Namen des Pakets ein, das installiert werden soll: "
            read -r paket
            sudo pacman -S --needed --noconfirm "$paket"
            ;;
        4)
            echo -n "Geben Sie den Namen des Pakets ein, das entfernt werden soll: "
            read -r paket
            sudo pacman -R "$paket"
            ;;
        5)
            echo -n "Geben Sie den Namen des Pakets ein, das gesucht werden soll: "
            read -r paket
            pacman -Ss "$paket"
            ;;
        6)
            echo "Installierte Pakete:"
            pacman -Q
            ;;
        7)
            echo -n "Geben Sie den Namen des Pakets ein, um Informationen anzuzeigen: "
            read -r paket
            pacman -Qi "$paket"
            ;;
        8)
            echo "Verwaiste Pakete werden entfernt..."
            sudo pacman -Rns $(pacman -Qtdq)
            ;;
        9)
            echo "Paket-Cache wird geleert..."
            sudo pacman -Scc --noconfirm
            ;;
        11)
            echo "Datenbank wird repariert..."
            sudo pacman -D --asdeps $(pacman -Qdtq)
            ;;
        0)
            echo "Programm beendet."
            break
            ;;
        *)
            echo "Ungültige Auswahl. Bitte versuchen Sie es erneut."
            ;;
    esac
    echo -e "\nDrücken Sie die Eingabetaste, um fortzufahren..."
    read -r
clear
done
