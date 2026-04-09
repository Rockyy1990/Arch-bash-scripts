#!/bin/bash

################################################################################
# Systemd Service Manager - Interaktives Management-Skript (KORRIGIERT)
################################################################################

set -o pipefail
IFS=$'\n\t'

# === FARBDEFINITIONEN ===
readonly COLOR_RESET='\033[0m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_WHITE='\033[1;37m'

# === GLOBALE VARIABLEN ===
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === TRAP FÜR SAUBERES CLEANUP ===
trap cleanup EXIT INT TERM

cleanup() {
    sudo -k 2>/dev/null || true
}

# === HILFSFUNKTIONEN FÜR AUSGABEN ===

print_header() {
    clear
    echo -e "${COLOR_CYAN}${COLOR_BOLD}════════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_BLUE}${COLOR_BOLD}  Systemd Service Manager${COLOR_RESET}"
    echo -e "${COLOR_CYAN}${COLOR_BOLD}════════════════════════════════════════${COLOR_RESET}\n"
}

print_success() {
    echo -e "${COLOR_GREEN}${COLOR_BOLD}✓${COLOR_RESET} ${COLOR_GREEN}$*${COLOR_RESET}"
}

print_error() {
    echo -e "${COLOR_RED}${COLOR_BOLD}✗${COLOR_RESET} ${COLOR_RED}$*${COLOR_RESET}" >&2
}

print_warning() {
    echo -e "${COLOR_YELLOW}${COLOR_BOLD}⚠${COLOR_RESET} ${COLOR_YELLOW}$*${COLOR_RESET}"
}

print_info() {
    echo -e "${COLOR_BLUE}${COLOR_BOLD}ℹ${COLOR_RESET} ${COLOR_BLUE}$*${COLOR_RESET}"
}

print_divider() {
    echo -e "${COLOR_CYAN}────────────────────────────────────────${COLOR_RESET}"
}

# === SUDO-AUTHENTIFIZIERUNG ===

authenticate_sudo() {
    print_info "Sudo-Authentifizierung erforderlich..."

    if ! sudo -v 2>/dev/null; then
        print_error "Sudo-Authentifizierung fehlgeschlagen!"
        exit 1
    fi

    # Keep-alive für Sudo-Session
    (while true; do sudo -n true 2>/dev/null; sleep 60; done) &
    print_success "Authentifizierung erfolgreich."
    sleep 1
}

# === VALIDIERUNGSFUNKTIONEN ===

get_service_name() {
    local service="$1"

    # Automatisch .service hinzufügen wenn nicht vorhanden
    if [[ ! "$service" =~ \.service$ ]]; then
        service="${service}.service"
    fi

    echo "$service"
}

validate_service_name() {
    local service="$1"

    # Automatisch .service hinzufügen
    if [[ ! "$service" =~ \.service$ ]]; then
        service="${service}.service"
    fi

    # Direkter Check mit systemctl cat - zuverlässigste Methode
    systemctl cat "$service" &>/dev/null
    return $?
}

# === SERVICESTATUS-ANZEIGE ===

show_service_status() {
    local service="$1"
    service=$(get_service_name "$service")

    if ! validate_service_name "$service"; then
        print_error "Service '$service' nicht gefunden!"
        return 1
    fi

    print_divider
    print_info "Status für: ${COLOR_WHITE}$service${COLOR_RESET}"
    print_divider

    # Detaillierte Systemd-Informationen
    local status_output active_state unit_file_state

    status_output=$(systemctl show "$service" 2>/dev/null)

    if [[ -z "$status_output" ]]; then
        print_error "Kann Status nicht abrufen."
        return 1
    fi

    # Wichtige Felder extrahieren
    active_state=$(echo "$status_output" | grep "^ActiveState=" | cut -d= -f2)
    unit_file_state=$(systemctl is-enabled "$service" 2>/dev/null || echo "disabled")

    # Status mit Farbe anzeigen
    case "$active_state" in
        active)
            echo -e "Aktiv:        ${COLOR_GREEN}${COLOR_BOLD}$active_state${COLOR_RESET}"
            ;;
        inactive|failed)
            echo -e "Aktiv:        ${COLOR_RED}${COLOR_BOLD}$active_state${COLOR_RESET}"
            ;;
        *)
            echo -e "Aktiv:        ${COLOR_YELLOW}${COLOR_BOLD}$active_state${COLOR_RESET}"
            ;;
    esac

    echo -e "Autostart:    $unit_file_state"
    echo ""

    # Logs anzeigen
    print_info "Letzte Log-Einträge:"
    journalctl -u "$service" -n 5 --no-pager 2>/dev/null || echo "Keine Logs verfügbar"

    return 0
}

# === SERVICE-VERWALTUNG ===

start_service() {
    local service="$1"
    service=$(get_service_name "$service")

    if ! validate_service_name "$service"; then
        print_error "Service '$service' nicht gefunden!"
        return 1
    fi

    print_info "Starte Service: $service"

    if sudo systemctl start "$service" 2>/dev/null; then
        print_success "Service gestartet."
        sleep 1
        show_service_status "$service"
        return 0
    else
        print_error "Konnte Service nicht starten. Siehe Log:"
        sudo journalctl -u "$service" -n 10 --no-pager 2>/dev/null || echo "Keine Logs"
        return 1
    fi
}

stop_service() {
    local service="$1"
    service=$(get_service_name "$service")

    if ! validate_service_name "$service"; then
        print_error "Service '$service' nicht gefunden!"
        return 1
    fi

    print_warning "Stoppe Service: $service"

    if sudo systemctl stop "$service" 2>/dev/null; then
        print_success "Service gestoppt."
        sleep 1
        show_service_status "$service"
        return 0
    else
        print_error "Konnte Service nicht stoppen."
        return 1
    fi
}

restart_service() {
    local service="$1"
    service=$(get_service_name "$service")

    if ! validate_service_name "$service"; then
        print_error "Service '$service' nicht gefunden!"
        return 1
    fi

    print_info "Starte Service neu: $service"

    if sudo systemctl restart "$service" 2>/dev/null; then
        print_success "Service neu gestartet."
        sleep 1
        show_service_status "$service"
        return 0
    else
        print_error "Konnte Service nicht neu starten."
        return 1
    fi
}

reload_service() {
    local service="$1"
    service=$(get_service_name "$service")

    if ! validate_service_name "$service"; then
        print_error "Service '$service' nicht gefunden!"
        return 1
    fi

    print_info "Lade Service-Konfiguration neu: $service"

    if sudo systemctl reload "$service" 2>/dev/null; then
        print_success "Service-Konfiguration neu geladen."
        sleep 1
        show_service_status "$service"
        return 0
    else
        print_error "Konnte Service nicht neu laden. Versuche restart..."
        restart_service "$service"
        return $?
    fi
}

enable_service() {
    local service="$1"
    service=$(get_service_name "$service")

    if ! validate_service_name "$service"; then
        print_error "Service '$service' nicht gefunden!"
        return 1
    fi

    print_info "Aktiviere Autostart: $service"

    if sudo systemctl enable "$service" 2>/dev/null; then
        print_success "Service wird beim Systemstart geladen."
        return 0
    else
        print_error "Konnte Autostart nicht aktivieren."
        return 1
    fi
}

disable_service() {
    local service="$1"
    service=$(get_service_name "$service")

    if ! validate_service_name "$service"; then
        print_error "Service '$service' nicht gefunden!"
        return 1
    fi

    print_warning "Deaktiviere Autostart: $service"

    if sudo systemctl disable "$service" 2>/dev/null; then
        print_success "Service wird nicht mehr beim Start geladen."
        return 0
    else
        print_error "Konnte Autostart nicht deaktivieren."
        return 1
    fi
}

# === ERWEITERTE FUNKTIONEN ===

list_all_services() {
    print_header
    print_info "Alle systemd-Services:"
    print_divider

    systemctl list-unit-files --type=service --no-pager 2>/dev/null | head -20

    echo ""
    print_info "... (q zum Beenden)"
}

list_running_services() {
    print_header
    print_info "Laufende Services:"
    print_divider

    systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -20
}

search_service() {
    local search_term="$1"

    if [[ -z "$search_term" ]]; then
        return 1
    fi

    print_header
    print_info "Suchergebnisse für: ${COLOR_WHITE}$search_term${COLOR_RESET}"
    print_divider

    systemctl list-unit-files --type=service --no-pager 2>/dev/null | grep -i "$search_term" || print_warning "Keine Dienste gefunden."
}

show_failed_services() {
    print_header
    print_warning "Fehlerhafte Services:"
    print_divider

    local failed
    failed=$(systemctl list-units --type=service --state=failed --no-pager 2>/dev/null)

    if [[ -z "$failed" ]]; then
        print_success "Keine fehlerhaften Services gefunden."
    else
        echo "$failed" | head -20
    fi
}

show_system_summary() {
    print_header
    print_info "System-Zusammenfassung:"
    print_divider

    echo -n "Systemd-Version: "
    systemctl --version 2>/dev/null | head -1

    echo ""
    echo -n "Laufende Services: "
    systemctl list-units --type=service --state=running --no-pager 2>/dev/null | tail -1

    echo -n "Fehlerhafte Services: "
    systemctl list-units --type=service --state=failed --no-pager 2>/dev/null | wc -l

    echo ""
    print_divider
    print_info "Letzte Systemd-Logs:"
    journalctl -u systemd -n 5 --no-pager 2>/dev/null || echo "Keine Einträge"
}

# === MENÜ-FUNKTIONEN ===

show_main_menu() {
    print_header

    echo -e "${COLOR_BOLD}Hauptmenü:${COLOR_RESET}"
    print_divider
    echo "  1) Service-Status anzeigen"
    echo "  2) Service starten"
    echo "  3) Service stoppen"
    echo "  4) Service neu starten"
    echo "  5) Service-Konfiguration neu laden"
    print_divider
    echo "  6) Autostart aktivieren"
    echo "  7) Autostart deaktivieren"
    print_divider
    echo "  8) Alle Services auflisten"
    echo "  9) Nur laufende Services"
    echo " 10) Service suchen"
    echo " 11) Fehlerhafte Services"
    echo " 12) System-Zusammenfassung"
    print_divider
    echo "  0) Beenden"
    print_divider
    echo ""
}

show_service_menu() {
    echo -e "\n${COLOR_BOLD}Service-Operation:${COLOR_RESET}"
    echo -e "  ${COLOR_YELLOW}a)${COLOR_RESET} Status anzeigen"
    echo -e "  ${COLOR_GREEN}b)${COLOR_RESET} Starten"
    echo -e "  ${COLOR_RED}c)${COLOR_RESET} Stoppen"
    echo -e "  ${COLOR_BLUE}d)${COLOR_RESET} Neu starten"
    echo -e "  ${COLOR_CYAN}e)${COLOR_RESET} Neu laden"
    echo -e "  ${COLOR_WHITE}f)${COLOR_RESET} Autostart an/aus"
    echo -e "  ${COLOR_YELLOW}g)${COLOR_RESET} Zurück zum Hauptmenü"
    echo ""
}

service_submenu() {
    local service="$1"
    service=$(get_service_name "$service")

    if ! validate_service_name "$service"; then
        print_error "Service '$service' nicht gefunden!"
        sleep 2
        return 1
    fi

    while true; do
        print_header
        echo -e "Service: ${COLOR_WHITE}$service${COLOR_RESET}"
        show_service_menu

        read -p "Wähle eine Option [a-g]: " -r option

        case "$option" in
            a|A)
                show_service_status "$service"
                ;;
            b|B)
                start_service "$service"
                ;;
            c|C)
                read -p "Sicher? (j/n): " -r confirm
                if [[ "$confirm" =~ ^[Jj]$ ]]; then
                    stop_service "$service"
                else
                    print_info "Abgebrochen."
                fi
                ;;
            d|D)
                restart_service "$service"
                ;;
            e|E)
                reload_service "$service"
                ;;
            f|F)
                local enabled
                enabled=$(systemctl is-enabled "$service" 2>/dev/null)
                if [[ "$enabled" == "enabled" ]]; then
                    disable_service "$service"
                else
                    enable_service "$service"
                fi
                ;;
            g|G)
                return 0
                ;;
            *)
                print_error "Ungültige Option!"
                sleep 1
                ;;
        esac

        read -p "Drücke Enter zum Fortfahren..."
    done
}

# === HAUPTSCHLEIFE ===

main() {
    # Authentifizierung beim Start
    authenticate_sudo

    while true; do
        show_main_menu

        read -p "Wähle eine Option [0-12]: " -r choice

        case "$choice" in
            1)
                read -p "Service-Name eingeben: " -r service
                if [[ -n "$service" ]]; then
                    show_service_status "$service"
                    read -p "Drücke Enter zum Fortfahren..."
                else
                    print_warning "Keine Eingabe!"
                    sleep 1
                fi
                ;;
            2)
                read -p "Service-Name eingeben: " -r service
                if [[ -n "$service" ]]; then
                    start_service "$service"
                    read -p "Drücke Enter zum Fortfahren..."
                else
                    print_warning "Keine Eingabe!"
                    sleep 1
                fi
                ;;
            3)
                read -p "Service-Name eingeben: " -r service
                if [[ -n "$service" ]]; then
                    stop_service "$service"
                    read -p "Drücke Enter zum Fortfahren..."
                else
                    print_warning "Keine Eingabe!"
                    sleep 1
                fi
                ;;
            4)
                read -p "Service-Name eingeben: " -r service
                if [[ -n "$service" ]]; then
                    restart_service "$service"
                    read -p "Drücke Enter zum Fortfahren..."
                else
                    print_warning "Keine Eingabe!"
                    sleep 1
                fi
                ;;
            5)
                read -p "Service-Name eingeben: " -r service
                if [[ -n "$service" ]]; then
                    reload_service "$service"
                    read -p "Drücke Enter zum Fortfahren..."
                else
                    print_warning "Keine Eingabe!"
                    sleep 1
                fi
                ;;
            6)
                read -p "Service-Name eingeben: " -r service
                if [[ -n "$service" ]]; then
                    enable_service "$service"
                    read -p "Drücke Enter zum Fortfahren..."
                else
                    print_warning "Keine Eingabe!"
                    sleep 1
                fi
                ;;
            7)
                read -p "Service-Name eingeben: " -r service
                if [[ -n "$service" ]]; then
                    disable_service "$service"
                    read -p "Drücke Enter zum Fortfahren..."
                else
                    print_warning "Keine Eingabe!"
                    sleep 1
                fi
                ;;
            8)
                list_all_services
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            9)
                list_running_services
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            10)
                read -p "Suchbegriff eingeben: " -r search_term
                if [[ -n "$search_term" ]]; then
                    search_service "$search_term"
                    read -p "Drücke Enter zum Fortfahren..."
                else
                    print_warning "Keine Eingabe!"
                    sleep 1
                fi
                ;;
            11)
                show_failed_services
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            12)
                show_system_summary
                read -p "Drücke Enter zum Fortfahren..."
                ;;
            0)
                print_info "Auf Wiedersehen!"
                exit 0
                ;;
            *)
                print_error "Ungültige Option!"
                sleep 1
                ;;
        esac
    done
}

# === SCRIPT-START ===

main "$@"
