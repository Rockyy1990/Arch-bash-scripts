#!/bin/bash

################################################################################
# Flatpak-Verwaltungs-Tool v2.0
# Mit farbiger Menüführung, sudo-Authentifizierung und erweiterten Funktionen
################################################################################

set -o pipefail

# ============================================================================
# FARBEN UND KONSTANTEN
# ============================================================================

ORANGE='\033[38;5;208m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# Breite für die Rahmen
BOX_W=40

# ============================================================================
# HILFSFUNKTIONEN
# ============================================================================



success_msg() { echo -e "${GREEN}${BOLD}✓ $1${RESET}"; }
error_msg()   { echo -e "${RED}${BOLD}✗ $1${RESET}"; }
warn_msg()    { echo -e "${YELLOW}${BOLD}⚠ $1${RESET}"; }
info_msg()    { echo -e "${BLUE}${BOLD}ℹ $1${RESET}"; }

separator() {
    echo -e "${ORANGE}$(printf '─%.0s' $(seq 1 $BOX_W))${RESET}"
}

press_enter() {
    echo ""
    read -rp $'\033[1;33mDrücke ENTER zum Fortfahren...\033[0m'
}

# Bestätigungsabfrage – gibt 0 (ja) oder 1 (nein) zurück
confirm() {
    local prompt="${1:-Fortfahren?}"
    while true; do
        read -rp "$prompt [j/n]: " answer
        case "${answer,,}" in
            j|ja)  return 0 ;;
            n|nein) return 1 ;;
            *) warn_msg "Bitte 'j' oder 'n' eingeben." ;;
        esac
    done
}

# Prüft ob flatpak verfügbar ist
check_flatpak() {
    if ! command -v flatpak &>/dev/null; then
        error_msg "Flatpak ist nicht installiert!"
        exit 1
    fi
}

# App-ID Eingabe mit Validierung (einfacher Regex-Check)
read_app_id() {
    local prompt="${1:-App-ID eingeben}"
    local app_id
    read -rp "$prompt: " app_id

    if [[ -z "$app_id" ]]; then
        warn_msg "Keine App-ID eingegeben."
        return 1
    fi

    # Grundlegende Validierung: nur erlaubte Zeichen
    if [[ ! "$app_id" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        error_msg "Ungültige App-ID: Nur Buchstaben, Zahlen, '.', '-' und '_' erlaubt."
        return 1
    fi

    echo "$app_id"
    return 0
}

# ============================================================================
# MENÜ
# ============================================================================

show_menu() {
    clear
    echo -e "${ORANGE}${BOLD}"
    echo "┌────────────────────────────────────────┐"
    echo "│       Flatpak Verwaltung  v2.0         │"
    echo "└────────────────────────────────────────┘"
    echo -e "${RESET}"
    separator
    echo -e " ${BOLD} 1${RESET}  ${CYAN}Update${RESET}             alle Pakete aktualisieren"
    echo -e " ${BOLD} 2${RESET}  ${CYAN}Liste${RESET}              installierte Apps anzeigen"
    echo -e " ${BOLD} 3${RESET}  ${CYAN}Quellen${RESET}            Remotes anzeigen"
    separator
    echo -e " ${BOLD} 4${RESET}  ${CYAN}Installieren${RESET}       App von Flathub installieren"
    echo -e " ${BOLD} 5${RESET}  ${CYAN}Deinstallieren${RESET}     App entfernen"
    echo -e " ${BOLD} 6${RESET}  ${CYAN}Suchen${RESET}             Flathub durchsuchen"
    separator
    echo -e " ${BOLD} 7${RESET}  ${CYAN}Reparieren${RESET}         flatpak repair ausführen"
    echo -e " ${BOLD} 8${RESET}  ${CYAN}Aufräumen${RESET}          unbenutzte Runtimes entfernen"
    echo -e " ${BOLD} 9${RESET}  ${CYAN}Berechtigungen${RESET}     Override verwalten"
    echo -e " ${BOLD}10${RESET}  ${CYAN}Info${RESET}               Version & Runtimes anzeigen"
    separator
    echo -e " ${RED}${BOLD} 0${RESET}  ${DIM}Beenden${RESET}"
    separator
    echo ""
}

# ============================================================================
# FUNKTIONEN
# ============================================================================

# 1 – Update
do_update() {
    clear
    info_msg "Starte Flatpak-Update..."
    echo ""

    if flatpak update -y; then
        success_msg "Update erfolgreich abgeschlossen."
    else
        error_msg "Update fehlgeschlagen."
    fi
    press_enter
}

# 2 – Liste
do_list() {
    clear
    info_msg "Installierte Flatpak-Anwendungen:"
    echo ""

    local count
    count=$(flatpak list --app --columns=application | tail -n +1 | wc -l)

    flatpak list --app --columns=name,application,version,size | column -t -s $'\t'
    echo ""
    success_msg "$count App(s) installiert."
    press_enter
}

# 3 – Quellen
do_remotes() {
    clear
    info_msg "Konfigurierte Flatpak-Quellen:"
    echo ""

    flatpak remotes --show-disabled --columns=name,title,url,options
    echo ""
    press_enter
}

# 4 – Installieren
do_install() {
    clear
    echo -e "${BLUE}${BOLD}Flatpak Installation${RESET}"
    echo ""

    local app_id
    app_id=$(read_app_id "App-ID eingeben (z.B. org.gnome.Gedit)") || { press_enter; return; }

    echo ""
    info_msg "Installiere ${BOLD}$app_id${RESET}${BLUE}..."
    echo ""

    if flatpak install -y flathub "$app_id"; then
        success_msg "$app_id erfolgreich installiert."
    else
        error_msg "Installation von $app_id fehlgeschlagen."
    fi
    press_enter
}

# 5 – Deinstallieren
do_remove() {
    clear
    echo -e "${RED}${BOLD}Flatpak Deinstallation${RESET}"
    echo ""

    info_msg "Installierte Apps:"
    echo ""
    flatpak list --app --columns=application,name | column -t -s $'\t'
    echo ""

    local app_id
    app_id=$(read_app_id "App-ID zum Entfernen eingeben") || { press_enter; return; }

    # Prüfen ob die App überhaupt installiert ist
    if ! flatpak info "$app_id" &>/dev/null; then
        error_msg "$app_id ist nicht installiert."
        press_enter
        return
    fi

    echo ""
    warn_msg "Diese Aktion ist nicht rückgängig zu machen!"
    if confirm "Möchten Sie ${BOLD}$app_id${RESET} wirklich deinstallieren?"; then
        echo ""
        info_msg "Entferne $app_id..."

        if sudo flatpak uninstall -y "$app_id"; then
            success_msg "$app_id erfolgreich entfernt."

            # Optionaler Cleanup
            echo ""
            if confirm "Unbenutzte Runtimes ebenfalls entfernen?"; then
                sudo flatpak uninstall --unused -y
                success_msg "Aufräumen abgeschlossen."
            fi
        else
            error_msg "Fehler beim Entfernen von $app_id."
        fi
    else
        info_msg "Abgebrochen."
    fi
    press_enter
}

# 6 – Suchen
do_search() {
    clear
    echo -e "${BLUE}${BOLD}Flatpak Suche${RESET}"
    echo ""

    local search_term
    read -rp "Suchbegriff eingeben: " search_term

    if [[ -z "$search_term" ]]; then
        warn_msg "Kein Suchbegriff eingegeben."
        press_enter
        return
    fi

    clear
    info_msg "Suche nach '${BOLD}$search_term${RESET}${BLUE}'..."
    echo ""

    local results
    results=$(flatpak search "$search_term" 2>/dev/null)

    if [[ -z "$results" ]]; then
        error_msg "Keine Ergebnisse gefunden."
        press_enter
        return
    fi

    # Ergebnisse nummeriert anzeigen
    local -a app_ids=()
    local idx=0

    while IFS= read -r line; do
        idx=$((idx + 1))
        if [[ $idx -eq 1 ]]; then
            echo -e "${BOLD}     $line${RESET}"
            separator
        else
            # App-ID aus der Zeile extrahieren (zweite Spalte, Tab-getrennt)
            local aid
            aid=$(echo "$line" | awk -F'\t' '{print $NF}')
            app_ids+=("$aid")

            if (( idx % 2 == 0 )); then
                printf "${GREEN} %3d  %s${RESET}\n" "${#app_ids[@]}" "$line"
            else
                printf "${CYAN} %3d  %s${RESET}\n" "${#app_ids[@]}" "$line"
            fi
        fi
    done <<< "$results"

    echo ""
    separator
    echo -e "${DIM}Nummer eingeben zum Installieren, oder leer lassen zum Abbrechen.${RESET}"
    echo ""

    local selection
    read -rp "Auswahl: " selection

    if [[ -n "$selection" && "$selection" =~ ^[0-9]+$ ]]; then
        if (( selection >= 1 && selection <= ${#app_ids[@]} )); then
            local chosen="${app_ids[$((selection - 1))]}"
            echo ""
            info_msg "Installiere ${BOLD}$chosen${RESET}${BLUE}..."
            echo ""
            if flatpak install -y flathub "$chosen"; then
                success_msg "$chosen erfolgreich installiert."
            else
                error_msg "Installation fehlgeschlagen."
            fi
        else
            warn_msg "Ungültige Nummer."
        fi
    fi
    press_enter
}

# 7 – Reparieren
do_repair() {
    clear
    echo -e "${YELLOW}${BOLD}Flatpak Reparatur${RESET}"
    echo ""
    warn_msg "Dies kann einige Minuten dauern..."
    echo ""

    if confirm "Reparatur jetzt starten?"; then
        echo ""
        if sudo flatpak repair; then
            success_msg "Reparatur erfolgreich."
        else
            error_msg "Reparatur fehlgeschlagen."
        fi
    else
        info_msg "Abgebrochen."
    fi
    press_enter
}

# 8 – Aufräumen (NEU)
do_cleanup() {
    clear
    echo -e "${BLUE}${BOLD}Flatpak Aufräumen${RESET}"
    echo ""

    info_msg "Prüfe unbenutzte Runtimes..."
    echo ""

    local unused
    unused=$(flatpak uninstall --unused 2>&1 | head -20)

    if [[ "$unused" == *"Nothing unused"* ]] || [[ -z "$unused" ]]; then
        success_msg "Keine unbenutzten Runtimes gefunden – alles sauber!"
    else
        echo "$unused"
        echo ""
        if confirm "Unbenutzte Runtimes jetzt entfernen?"; then
            echo ""
            if sudo flatpak uninstall --unused -y; then
                success_msg "Aufräumen abgeschlossen."
            else
                error_msg "Aufräumen fehlgeschlagen."
            fi
        else
            info_msg "Abgebrochen."
        fi
    fi
    press_enter
}

# 9 – Berechtigungen / Override
do_override() {
    clear
    echo -e "${BLUE}${BOLD}Flatpak Berechtigungen (Override)${RESET}"
    echo ""

    info_msg "Installierte Apps:"
    echo ""
    flatpak list --app --columns=application,name | column -t -s $'\t'
    echo ""

    local app_id
    app_id=$(read_app_id "App-ID eingeben") || { press_enter; return; }

    # Prüfen ob installiert
    if ! flatpak info "$app_id" &>/dev/null; then
        error_msg "$app_id ist nicht installiert."
        press_enter
        return
    fi

    # Aktuelle Overrides anzeigen
    echo ""
    info_msg "Aktuelle Overrides für $app_id:"
    flatpak override --show "$app_id" 2>/dev/null || echo -e "${DIM}  (keine)${RESET}"
    echo ""

    separator
    echo -e "${YELLOW}${BOLD}Häufige Override-Optionen:${RESET}"
    echo -e "  ${BOLD}1${RESET}  --filesystem=host         Voller Dateisystem-Zugriff"
    echo -e "  ${BOLD}2${RESET}  --filesystem=home          Home-Verzeichnis"
    echo -e "  ${BOLD}3${RESET}  --socket=x11               X11-Zugriff"
    echo -e "  ${BOLD}4${RESET}  --socket=wayland            Wayland-Zugriff"
    echo -e "  ${BOLD}5${RESET}  --device=dri                GPU-Zugriff"
    echo -e "  ${BOLD}6${RESET}  --reset                     Alle Overrides zurücksetzen"
    echo -e "  ${BOLD}7${RESET}  Eigene Option eingeben"
    echo ""

    local override_option
    read -rp "Auswahl (1-7): " ov_choice

    case "$ov_choice" in
        1) override_option="--filesystem=host" ;;
        2) override_option="--filesystem=home" ;;
        3) override_option="--socket=x11" ;;
        4) override_option="--socket=wayland" ;;
        5) override_option="--device=dri" ;;
        6) override_option="--reset" ;;
        7)
            read -rp "Override-Option eingeben: " override_option
            if [[ -z "$override_option" ]]; then
                warn_msg "Keine Option eingegeben."
                press_enter
                return
            fi
            ;;
        *)
            warn_msg "Ungültige Auswahl."
            press_enter
            return
            ;;
    esac

    echo ""
    info_msg "Wende Override an: ${BOLD}$override_option${RESET}"

    # shellcheck disable=SC2086
    if flatpak override $override_option "$app_id"; then
        success_msg "Override erfolgreich angewendet."
    else
        error_msg "Fehler beim Anwenden des Override."
    fi
    press_enter
}

# 10 – Version & Info
do_info() {
    clear
    info_msg "Flatpak Systeminformationen:"
    echo ""

    echo -e "${BOLD}Version:${RESET}  $(flatpak --version)"
    echo ""

    local app_count rt_count
    app_count=$(flatpak list --app 2>/dev/null | wc -l)
    rt_count=$(flatpak list --runtime 2>/dev/null | wc -l)

    echo -e "${BOLD}Apps:${RESET}     $app_count installiert"
    echo -e "${BOLD}Runtimes:${RESET} $rt_count installiert"
    echo ""

    separator
    info_msg "Installierte Runtimes:"
    echo ""
    flatpak list --runtime --columns=name,version,size | column -t -s $'\t'
    echo ""
    press_enter
}

# ============================================================================
# HAUPTPROGRAMM
# ============================================================================

main() {
    check_flatpak
    check_sudo
    clear

    while true; do
        show_menu
        read -rp "Option wählen [0-10]: " choice

        case "$choice" in
            1)  do_update ;;
            2)  do_list ;;
            3)  do_remotes ;;
            4)  do_install ;;
            5)  do_remove ;;
            6)  do_search ;;
            7)  do_repair ;;
            8)  do_cleanup ;;
            9)  do_override ;;
            10) do_info ;;
            0)
                clear
                echo -e "${YELLOW}${BOLD}Auf Wiedersehen!${RESET}"
                exit 0
                ;;
            *)
                error_msg "Ungültige Eingabe – bitte 0-10 wählen."
                sleep 1
                ;;
        esac
    done
}

main "$@"
