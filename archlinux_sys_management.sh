#!/usr/bin/env bash

# ============================================================
#   Archlinux Management Tool
#   Farben: Menü=Orange | Pacman=Hellblau | Warnung=Rot
# ============================================================

# --- Farbdefinitionen ---
RESET="\033[0m"
ORANGE="\033[38;5;214m"       # Menüfarbe
HELLBLAU="\033[38;5;117m"     # Pacman-Farbe
ROT="\033[38;5;196m"          # Warnfarbe
WEISS="\033[1;37m"            # Hervorhebung
GRAU="\033[38;5;245m"         # Trennlinien / dezente Elemente
GRUEN="\033[38;5;82m"         # Erfolg / Info

# --- Hilfsfunktionen ---
trennlinie_kurz() {
    echo -e "${GRAU}  ---------------------------------------${RESET}"
}

trennlinie_header() {
    echo -e "${GRAU}  ---------------------------------${RESET}"
}

kernel_version() {
    echo -e "${GRUEN}  Kernel: $(uname -r)${RESET}"
}

pause() {
    echo ""
    echo -e "${GRAU}  [Eingabe drücken, um fortzufahren...]${RESET}"
    read -r
}

bestaetigung() {
    local frage="$1"
    echo -e "${ROT}  ⚠  ${frage} [j/N]: ${RESET}\c"
    read -r antwort
    [[ "$antwort" =~ ^[jJ]$ ]]
}

# --- Menü anzeigen ---
zeige_menue() {
    clear
    echo ""
    trennlinie_header
    echo -e "${ORANGE}      Archlinux Management Tool${RESET}"
    trennlinie_header
    kernel_version
    trennlinie_kurz

    echo -e "${HELLBLAU}  1.${RESET}  ${WEISS}Pacman Paket Cache löschen${RESET}"
    echo -e "${HELLBLAU}  2.${RESET}  ${WEISS}Pacman Repos aktualisieren${RESET}"
    echo -e "${HELLBLAU}  3.${RESET}  ${WEISS}Pacman archlinux-keyring erneuern${RESET}"
    trennlinie_kurz

    echo -e "${HELLBLAU}  4.${RESET}  ${WEISS}Archlinux system upgrade (noconfirm)${RESET}"
    echo -e "${HELLBLAU}  5.${RESET}  ${WEISS}Archlinux system upgrade (yay -Syu) ${RESET}"
    trennlinie_kurz

    echo -e "${HELLBLAU}  6.${RESET}  ${WEISS}Zeige verwaiste Pakete${RESET}"
    echo -e "${ROT}  7.${RESET}  ${WEISS}Lösche verwaiste Pakete${RESET}"
    trennlinie_kurz

    echo -e "${HELLBLAU}  8.${RESET}  ${WEISS}Pakete installieren (yay)${RESET}"
    echo -e "${ROT}  9.${RESET}  ${WEISS}Pakete entfernen (yay)${RESET}"
    trennlinie_kurz

    echo -e "${GRAU} 10.${RESET}  ${WEISS}Pacman config anzeigen (nano/sudo)${RESET}"
    echo -e "${GRAU} 11.${RESET}  ${WEISS}Pacman mirrors anzeigen (nano/sudo)${RESET}"
    echo -e "${GRAU} 12.${RESET}  ${WEISS}Journal anzeigen${RESET}"
    trennlinie_kurz

    echo -e "${ROT} 13.${RESET}  ${WEISS}System neustart${RESET}"
    echo -e "${GRAU} 14.${RESET}  ${WEISS}Script beenden${RESET}"
    trennlinie_kurz
    echo ""
    echo -e "${ORANGE}  Auswahl: ${RESET}\c"
}

# --- Aktionen ---

aktion_1() {
    echo -e "\n${HELLBLAU}  → Paket Cache wird geleert...${RESET}\n"
    sudo pacman -Scc --noconfirm
    pause
}

aktion_2() {
    echo -e "\n${HELLBLAU}  → Pacman Repos werden aktualisiert...${RESET}\n"
    sudo pacman -Sy
    sudo pacman -Fyy
    pause
}

aktion_3() {
    echo -e "\n${HELLBLAU}  → archlinux-keyring wird erneuert...${RESET}\n"
    sudo pacman -Sy --noconfirm archlinux-keyring
    sudo pacman-key --init
    sudo pacman-key --populate archlinux
    pause
}

aktion_4() {
    echo -e "\n${HELLBLAU}  → System upgrade wird durchgeführt...${RESET}\n"
    sudo pacman -Syu --noconfirm
    pause
}

aktion_5() {
    echo -e "\n${HELLBLAU}  → System upgrade mit yay wird durchgeführt...${RESET}\n"
    yay -Syu --noconfirm
    pause
}

aktion_6() {
    echo -e "\n${HELLBLAU}  → Verwaiste Pakete:${RESET}\n"
    verwaist=$(pacman -Qdt 2>/dev/null)
    if [[ -z "$verwaist" ]]; then
        echo -e "${GRUEN}  Keine verwaisten Pakete gefunden.${RESET}"
    else
        echo -e "${WEISS}$verwaist${RESET}"
    fi
    pause
}

aktion_7() {
    verwaist=$(pacman -Qdtq 2>/dev/null)
    if [[ -z "$verwaist" ]]; then
        echo -e "\n${GRUEN}  Keine verwaisten Pakete zum Löschen vorhanden.${RESET}"
    else
        echo -e "\n${ROT}  Folgende Pakete werden entfernt:${RESET}"
        echo -e "${WEISS}$verwaist${RESET}\n"
        if bestaetigung "Verwaiste Pakete wirklich löschen?"; then
            sudo pacman -Rns $verwaist --noconfirm
        else
            echo -e "${GRAU}  Abgebrochen.${RESET}"
        fi
    fi
    pause
}

aktion_8() {
    echo -e "${ORANGE}  Paketname(n) eingeben: ${RESET}\c"
    read -r pakete
    if [[ -n "$pakete" ]]; then
        echo -e "\n${HELLBLAU}  → Installiere: ${pakete}${RESET}\n"
        yay -S --needed --noconfirm $pakete
    else
        echo -e "${ROT}  Kein Paketname angegeben.${RESET}"
    fi
    pause
}

aktion_9() {
    echo -e "${ORANGE}  Paketname(n) eingeben: ${RESET}\c"
    read -r pakete
    if [[ -n "$pakete" ]]; then
        echo -e "\n${ROT}  Folgende Pakete werden entfernt: ${pakete}${RESET}\n"
        if bestaetigung "Pakete wirklich entfernen?"; then
            yay -R --noconfirm $pakete
        else
            echo -e "${GRAU}  Abgebrochen.${RESET}"
        fi
    else
        echo -e "${ROT}  Kein Paketname angegeben.${RESET}"
    fi
    pause
}

aktion_10() {
    echo -e "\n${GRAU}  → Pacman config wird geöffnet...${RESET}\n"
    sudo nano /etc/pacman.conf
}

aktion_11() {
    echo -e "\n${GRAU}  → Pacman mirrors wird geöffnet...${RESET}\n"
    sudo nano /etc/pacman.d/mirrorlist
}

aktion_12() {
    echo -e "\n${GRAU}  → Journal wird angezeigt (q zum Beenden)...${RESET}\n"
    sudo journalctl -xe --no-pager | less
}

aktion_13() {
    if bestaetigung "System wirklich neu starten?"; then
        echo -e "\n${ROT}  → System wird neu gestartet...${RESET}\n"
        sudo reboot
    else
        echo -e "${GRAU}  Abgebrochen.${RESET}"
        pause
    fi
}

# --- Hauptschleife ---
while true; do
    zeige_menue
    read -r auswahl

    case "$auswahl" in
        1)  aktion_1  ;;
        2)  aktion_2  ;;
        3)  aktion_3  ;;
        4)  aktion_4  ;;
        5)  aktion_5  ;;
        6)  aktion_6  ;;
        7)  aktion_7  ;;
        8)  aktion_8  ;;
        9)  aktion_9  ;;
        10) aktion_10 ;;
        11) aktion_11 ;;
        12) aktion_12 ;;
        13) aktion_13 ;;
        14)
            echo -e "\n${GRAU}  Auf Wiedersehen.${RESET}\n"
            exit 0
            ;;
        *)
            echo -e "\n${ROT}  Ungültige Auswahl: \"${auswahl}\"${RESET}"
            pause
            ;;
    esac
done
