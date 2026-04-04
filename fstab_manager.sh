#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# FStab Manager - Automatische Einträge Tool
# Version 2.0

set -o pipefail

# ============================================================
# ANSI Farbcodes
# ============================================================
YELLOW='\033[93m'
GREEN='\033[92m'
RED='\033[91m'
BLUE='\033[94m'
CYAN='\033[96m'
GRAY='\033[90m'
RESET='\033[0m'
BOLD='\033[1m'

FSTAB_PATH="/etc/fstab"
BACKUP_DIR="/etc/fstab.backups"
MAX_BACKUPS=20
LOG_FILE="/var/log/fstab_manager.log"

# ============================================================
# LOGGING
# ============================================================
log_action() {
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] ${message}" >> "$LOG_FILE" 2>/dev/null
}

# ============================================================
# SUDO CHECK - Direkt beim Start nach Passwort fragen
# ============================================================
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}${BOLD}Root-Rechte erforderlich. Bitte sudo-Passwort eingeben:${RESET}"
        local script_path
        script_path="$(realpath "${BASH_SOURCE[0]}")"
        exec sudo bash "$script_path" "$@"
        exit 1
    fi
}

# ============================================================
# HILFSFUNKTIONEN
# ============================================================
clear_screen() {
    clear
}

print_header() {
    clear_screen
    echo -e "${YELLOW}${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}${BOLD}║     /etc/fstab Manager - Automatische Einträge Tool       ║${RESET}"
    echo -e "${YELLOW}${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo
}

print_menu() {
    print_header
    echo -e "${YELLOW}${BOLD}HAUPTMENÜ:${RESET}"
    echo -e "${YELLOW}   1${RESET} - Neuer Eintrag hinzufügen"
    echo -e "${YELLOW}   2${RESET} - /tmp in RAM mounten"
    echo -e "${YELLOW}   3${RESET} - Ramdisk erstellen"
    echo -e "${YELLOW}   4${RESET} - Aktuelle /etc/fstab anzeigen"
    echo -e "${YELLOW}   5${RESET} - Eintrag löschen"
    echo -e "${YELLOW}   6${RESET} - fstab Syntax prüfen"
    echo -e "${YELLOW}   7${RESET} - Partitionen & Laufwerke anzeigen"
    echo -e "${YELLOW}   8${RESET} - Backup wiederherstellen"
    echo -e "${YELLOW}   9${RESET} - Alte Backups aufräumen"
    echo -e "${YELLOW}  10${RESET} - System neu starten"
    echo -e "${YELLOW}   0${RESET} - Beenden"
    echo
}

press_enter() {
    echo
    echo -e "${YELLOW}Drücken Sie Enter zum Fortfahren...${RESET}"
    read -r
}

confirm_action() {
    local prompt="$1"
    while true; do
        echo -e -n "${YELLOW}${prompt} (j/n): ${RESET}"
        read -r response
        case "${response,,}" in
            j|y) return 0 ;;
            n)   return 1 ;;
            *)   echo -e "${RED}Ungültige Eingabe. Bitte 'j' oder 'n' eingeben.${RESET}" ;;
        esac
    done
}

# ============================================================
# BACKUP FUNKTIONEN
# ============================================================
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p -m 700 "$BACKUP_DIR"
    fi
}

create_backup() {
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_path="${BACKUP_DIR}/fstab_backup_${timestamp}"

    if cp -p "$FSTAB_PATH" "$backup_path" 2>/dev/null; then
        echo -e "${GREEN}✓ Backup erstellt: ${backup_path}${RESET}"
        log_action "Backup erstellt: ${backup_path}"
        return 0
    else
        echo -e "${RED}✗ Fehler beim Backup${RESET}"
        return 1
    fi
}

ask_backup() {
    if confirm_action "Sicherung der /etc/fstab erstellen?"; then
        create_backup
        return $?
    fi
    return 0
}

cleanup_backups() {
    print_header
    echo -e "${YELLOW}${BOLD}Alte Backups aufräumen${RESET}"
    echo

    local -a backups
    mapfile -t backups < <(ls -1t "${BACKUP_DIR}"/fstab_backup_* 2>/dev/null)
    local total=${#backups[@]}

    if [[ $total -eq 0 ]]; then
        echo -e "${RED}Keine Backups vorhanden.${RESET}"
        press_enter
        return
    fi

    echo -e "${CYAN}Vorhandene Backups: ${total}${RESET}"
    echo -e "${CYAN}Aufbewahrungslimit: ${MAX_BACKUPS}${RESET}"
    echo

    if (( total <= MAX_BACKUPS )); then
        echo -e "${GREEN}✓ Anzahl ist im Rahmen, kein Aufräumen nötig.${RESET}"
        press_enter
        return
    fi

    local to_delete=$(( total - MAX_BACKUPS ))
    echo -e "${YELLOW}Es werden die ${to_delete} ältesten Backups gelöscht.${RESET}"

    if confirm_action "Fortfahren?"; then
        local deleted=0
        # Die ältesten sind am Ende der nach Datum sortierten Liste
        for (( i = MAX_BACKUPS; i < total; i++ )); do
            if rm -f "${backups[$i]}" 2>/dev/null; then
                (( deleted++ ))
            fi
        done
        echo -e "${GREEN}✓ ${deleted} alte Backups gelöscht.${RESET}"
        log_action "${deleted} alte Backups aufgeräumt"
    else
        echo -e "${YELLOW}Abgebrochen.${RESET}"
    fi

    press_enter
}

# ============================================================
# VALIDIERUNG
# ============================================================
validate_uuid() {
    local uuid="$1"
    uuid="${uuid// /}"

    # Standard-UUID: 8-4-4-4-12 Hexadezimal
    if [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        echo "$uuid"
        return 0
    fi

    # Kurze PARTUUID (z.B. bei GPT: 8 Hex-Zeichen oder mit Suffix)
    if [[ "$uuid" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{2})?$ ]]; then
        echo "$uuid"
        return 0
    fi

    # Volle PARTUUID (GPT): gleiche Struktur wie UUID
    if [[ "$uuid" =~ ^[0-9a-fA-F-]{20,}$ ]]; then
        echo "$uuid"
        return 0
    fi

    return 1
}

validate_mountpoint() {
    local mp="$1"
    if [[ "$mp" != /* ]]; then
        echo -e "${RED}Mountpoint muss mit / beginnen${RESET}"
        return 1
    fi
    if [[ "$mp" =~ [[:space:]] ]]; then
        echo -e "${RED}Mountpoint darf keine Leerzeichen enthalten${RESET}"
        return 1
    fi
    return 0
}

check_duplicate_mountpoint() {
    local mountpoint="$1"
    if grep -v '^\s*#' "$FSTAB_PATH" | grep -qw "$mountpoint"; then
        echo -e "${RED}⚠ WARNUNG: Mountpoint '${mountpoint}' existiert bereits in fstab!${RESET}"
        if ! confirm_action "Trotzdem fortfahren?"; then
            return 1
        fi
    fi
    return 0
}

validate_fstab_syntax() {
    print_header
    echo -e "${YELLOW}${BOLD}fstab Syntax-Prüfung${RESET}"
    echo

    if ! command -v findmnt &>/dev/null; then
        echo -e "${RED}findmnt nicht verfügbar. Verwende manuelle Prüfung...${RESET}"
        echo
        _manual_fstab_check
        press_enter
        return
    fi

    echo -e "${CYAN}Prüfe mit findmnt --verify...${RESET}"
    echo

    local output
    output=$(findmnt --verify --tab-file "$FSTAB_PATH" 2>&1)
    local rc=$?

    if [[ $rc -eq 0 && -z "$output" ]]; then
        echo -e "${GREEN}✓ Keine Fehler gefunden. fstab ist syntaktisch korrekt.${RESET}"
    elif [[ $rc -eq 0 ]]; then
        echo -e "${YELLOW}⚠ Warnungen:${RESET}"
        echo "$output"
    else
        echo -e "${RED}✗ Fehler gefunden:${RESET}"
        echo "$output"
    fi

    echo
    # Zusätzlich: mount --fake --all testen
    echo -e "${CYAN}Prüfe mit mount --fake --all...${RESET}"
    output=$(mount --fake --all 2>&1)
    rc=$?
    if [[ $rc -eq 0 ]]; then
        echo -e "${GREEN}✓ mount --fake --all erfolgreich.${RESET}"
    else
        echo -e "${RED}✗ mount --fake --all fehlgeschlagen:${RESET}"
        echo "$output"
    fi

    press_enter
}

_manual_fstab_check() {
    local line_num=0
    local errors=0
    while IFS= read -r line; do
        (( line_num++ ))
        # Kommentare und leere Zeilen ignorieren
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        local fields
        read -ra fields <<< "$line"
        if [[ ${#fields[@]} -lt 4 ]]; then
            echo -e "${RED}Zeile ${line_num}: Zu wenige Felder (${#fields[@]}/min. 4): ${line}${RESET}"
            (( errors++ ))
        elif [[ ${#fields[@]} -gt 6 ]]; then
            echo -e "${YELLOW}Zeile ${line_num}: Zu viele Felder (${#fields[@]}): ${line}${RESET}"
            (( errors++ ))
        fi
    done < "$FSTAB_PATH"

    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}✓ Keine offensichtlichen Fehler gefunden.${RESET}"
    else
        echo -e "${RED}${errors} potenzielle(r) Fehler gefunden.${RESET}"
    fi
}

# ============================================================
# INTERAKTIVE ABFRAGEN
# ============================================================
get_filesystem() {
    local filesystems=('ext4' 'xfs' 'btrfs' 'jfs' 'vfat' 'ntfs' 'exfat' 'iso9660' 'swap')
    local count=${#filesystems[@]}

    echo -e "\n${YELLOW}Dateisystem:${RESET}"
    for i in "${!filesystems[@]}"; do
        echo -e "${YELLOW}  $((i+1))${RESET} - ${filesystems[$i]}"
    done
    echo -e "${YELLOW}  $((count+1))${RESET} - Benutzerdefiniert"

    while true; do
        echo -e -n "${YELLOW}Wählen Sie (1-$((count+1))): ${RESET}"
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice-1))
            if (( idx >= 0 && idx < count )); then
                SELECTED_FS="${filesystems[$idx]}"
                return 0
            elif (( idx == count )); then
                echo -e -n "${YELLOW}Geben Sie Dateisystem ein: ${RESET}"
                read -r custom
                if [[ -z "$custom" ]]; then
                    echo -e "${RED}Eingabe darf nicht leer sein${RESET}"
                    continue
                fi
                SELECTED_FS="$custom"
                return 0
            fi
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done
}

get_mount_options() {
    echo -e "\n${YELLOW}Mount-Optionen:${RESET}"
    echo -e "${YELLOW}  1${RESET} - defaults"
    echo -e "${YELLOW}  2${RESET} - defaults,nofail"
    echo -e "${YELLOW}  3${RESET} - defaults,noatime"
    echo -e "${YELLOW}  4${RESET} - defaults,nofail,noatime"
    echo -e "${YELLOW}  5${RESET} - defaults,noatime,nodiratime"
    echo -e "${YELLOW}  6${RESET} - Benutzerdefiniert eingeben"

    while true; do
        echo -e -n "${YELLOW}Wählen Sie (1-6): ${RESET}"
        read -r choice
        case "$choice" in
            1) SELECTED_OPTIONS="defaults";                      return 0 ;;
            2) SELECTED_OPTIONS="defaults,nofail";               return 0 ;;
            3) SELECTED_OPTIONS="defaults,noatime";              return 0 ;;
            4) SELECTED_OPTIONS="defaults,nofail,noatime";       return 0 ;;
            5) SELECTED_OPTIONS="defaults,noatime,nodiratime";   return 0 ;;
            6)
                echo -e -n "${YELLOW}Geben Sie Mount-Optionen ein: ${RESET}"
                read -r custom
                if [[ -z "$custom" ]]; then
                    echo -e "${RED}Eingabe darf nicht leer sein${RESET}"
                    continue
                fi
                SELECTED_OPTIONS="$custom"
                return 0
                ;;
            *)
                echo -e "${RED}Ungültige Eingabe${RESET}"
                ;;
        esac
    done
}

# ============================================================
# EINTRAG SCHREIBEN
# ============================================================
write_entry() {
    local entry="$1"
    local comment="$2"

    # Leerzeile vor neuem Eintrag für bessere Lesbarkeit
    local last_char
    last_char=$(tail -c 1 "$FSTAB_PATH" 2>/dev/null)
    if [[ -n "$last_char" && "$last_char" != $'\n' ]]; then
        echo "" >> "$FSTAB_PATH"
    fi

    {
        if [[ -n "$comment" ]]; then
            echo "$comment"
        fi
        echo "$entry"
    } >> "$FSTAB_PATH"

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Eintrag erfolgreich hinzugefügt!${RESET}"
        log_action "Eintrag hinzugefügt: ${entry}"
    else
        echo -e "${RED}✗ Fehler beim Schreiben in ${FSTAB_PATH}${RESET}"
    fi
}

# ============================================================
# MENÜ-FUNKTIONEN
# ============================================================

# --- 1) Neuer Eintrag ---
add_fstab_entry() {
    print_header
    echo -e "${YELLOW}${BOLD}Neuer /etc/fstab Eintrag${RESET}\n"

    ask_backup || return

    # UUID oder PARTUUID oder Gerätepfad
    local id_type
    while true; do
        echo -e "\n${YELLOW}Quell-Identifikation:${RESET}"
        echo -e "${YELLOW}  1${RESET} - UUID"
        echo -e "${YELLOW}  2${RESET} - PARTUUID"
        echo -e "${YELLOW}  3${RESET} - LABEL"
        echo -e "${YELLOW}  4${RESET} - Gerätepfad (z.B. /dev/sda1)"
        echo -e -n "${YELLOW}Wählen Sie (1-4): ${RESET}"
        read -r choice
        case "$choice" in
            1) id_type="UUID";     break ;;
            2) id_type="PARTUUID"; break ;;
            3) id_type="LABEL";    break ;;
            4) id_type="DEVICE";   break ;;
            *) echo -e "${RED}Ungültige Eingabe${RESET}" ;;
        esac
    done

    # ID-Wert / Gerätepfad
    local id_value
    local source_prefix
    if [[ "$id_type" == "DEVICE" ]]; then
        while true; do
            echo -e -n "${YELLOW}Geben Sie Gerätepfad ein (z.B. /dev/sda1): ${RESET}"
            read -r id_value
            if [[ "$id_value" == /dev/* ]]; then
                source_prefix="$id_value"
                break
            fi
            echo -e "${RED}Gerätepfad muss mit /dev/ beginnen${RESET}"
        done
    elif [[ "$id_type" == "LABEL" ]]; then
        echo -e -n "${YELLOW}Geben Sie LABEL ein: ${RESET}"
        read -r id_value
        if [[ -z "$id_value" ]]; then
            echo -e "${RED}Label darf nicht leer sein${RESET}"
            press_enter
            return
        fi
        source_prefix="LABEL=${id_value}"
    else
        while true; do
            echo -e -n "${YELLOW}Geben Sie ${id_type} ein: ${RESET}"
            read -r id_value
            if validate_uuid "$id_value" > /dev/null; then
                break
            fi
            echo -e "${RED}Ungültige ${id_type} — erwartet: Hexadezimal-Format (z.B. xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)${RESET}"
        done
        source_prefix="${id_type}=${id_value}"
    fi

    # Mountpoint
    local mountpoint
    while true; do
        echo -e -n "${YELLOW}Geben Sie Mountpoint ein (z.B. /mnt/data): ${RESET}"
        read -r mountpoint
        validate_mountpoint "$mountpoint" && break
    done

    # Duplikat-Check
    check_duplicate_mountpoint "$mountpoint" || { press_enter; return; }

    # Dateisystem
    get_filesystem
    local filesystem="$SELECTED_FS"

    # Spezialfall: swap
    if [[ "$filesystem" == "swap" ]]; then
        mountpoint="none"
        local options="sw"
        local dump=0
        local pass_num=0
    else
        # Mount-Optionen
        get_mount_options
        local options="$SELECTED_OPTIONS"

        # dump-Flag
        local dump
        while true; do
            echo -e -n "${YELLOW}dump-Flag (0 oder 1, Standard 0): ${RESET}"
            read -r dump
            dump="${dump:-0}"
            if [[ "$dump" == "0" || "$dump" == "1" ]]; then
                break
            fi
            echo -e "${RED}Bitte 0 oder 1 eingeben${RESET}"
        done

        # pass-Flag
        local pass_num
        while true; do
            echo -e -n "${YELLOW}pass-Flag (0, 1 oder 2, Standard 0): ${RESET}"
            read -r pass_num
            pass_num="${pass_num:-0}"
            if [[ "$pass_num" == "0" || "$pass_num" == "1" || "$pass_num" == "2" ]]; then
                break
            fi
            echo -e "${RED}Bitte 0, 1 oder 2 eingeben${RESET}"
        done
    fi

    # Beschreibung
    local description
    echo -e -n "${YELLOW}Beschreibung (optional): ${RESET}"
    read -r description

    # Eintrag zusammenstellen
    local comment=""
    [[ -n "$description" ]] && comment="# ${description}"
    local entry="${source_prefix} ${mountpoint} ${filesystem} ${options} ${dump} ${pass_num}"

    # Vorschau
    echo -e "\n${CYAN}Vorschau:${RESET}"
    [[ -n "$comment" ]] && echo -e "${GRAY}${comment}${RESET}"
    echo "$entry"
    echo

    if confirm_action "Eintrag hinzufügen?"; then
        write_entry "$entry" "$comment"

        # Mountpoint-Verzeichnis erstellen falls nötig
        if [[ "$mountpoint" != "none" && ! -d "$mountpoint" ]]; then
            if confirm_action "Verzeichnis '${mountpoint}' existiert nicht. Erstellen?"; then
                mkdir -p "$mountpoint" && echo -e "${GREEN}✓ Verzeichnis erstellt${RESET}"
            fi
        fi
    else
        echo -e "${YELLOW}Abgebrochen.${RESET}"
    fi

    press_enter
}

# --- 2) /tmp in RAM ---
mount_tmp_to_ram() {
    print_header
    echo -e "${YELLOW}${BOLD}/tmp in RAM mounten${RESET}\n"

    # Prüfen ob bereits vorhanden
    if grep -v '^\s*#' "$FSTAB_PATH" | grep -q 'tmpfs.*/tmp'; then
        echo -e "${RED}⚠ Es existiert bereits ein tmpfs-Eintrag für /tmp in fstab!${RESET}"
        if ! confirm_action "Trotzdem fortfahren?"; then
            press_enter
            return
        fi
    fi

    ask_backup || return

    # RAM-Größe abfragen
    local total_ram_mb
    total_ram_mb=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
    if [[ -n "$total_ram_mb" ]]; then
        echo -e "${CYAN}Verfügbarer RAM: ca. ${total_ram_mb} MB${RESET}"
    fi

    local size_pct
    echo -e -n "${YELLOW}Größe in % des RAM (Standard 50): ${RESET}"
    read -r size_pct
    size_pct="${size_pct:-50}"

    if ! [[ "$size_pct" =~ ^[0-9]+$ ]] || (( size_pct < 1 || size_pct > 90 )); then
        echo -e "${RED}Ungültige Größe (1-90%)${RESET}"
        press_enter
        return
    fi

    local entry="tmpfs /tmp tmpfs defaults,size=${size_pct}%,noatime,nosuid,nodev 0 0"
    local comment="# /tmp in RAM (${size_pct}%)"

    echo -e "\n${CYAN}Vorschau:${RESET}"
    echo -e "${GRAY}${comment}${RESET}"
    echo "$entry"

    if confirm_action "Eintrag hinzufügen?"; then
        write_entry "$entry" "$comment"
    fi

    press_enter
}

# --- 3) Ramdisk erstellen ---
create_ramdisk() {
    print_header
    echo -e "${YELLOW}${BOLD}Ramdisk erstellen${RESET}\n"

    ask_backup || return

    local mountpoint
    while true; do
        echo -e -n "${YELLOW}Mountpoint für Ramdisk (z.B. /mnt/ramdisk): ${RESET}"
        read -r mountpoint
        validate_mountpoint "$mountpoint" && break
    done

    check_duplicate_mountpoint "$mountpoint" || { press_enter; return; }

    # Größe mit Einheit
    local size unit
    echo -e -n "${YELLOW}Größe (Standard 8): ${RESET}"
    read -r size
    size="${size:-8}"

    if ! [[ "$size" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Ungültige Größe${RESET}"
        press_enter
        return
    fi

    echo -e "${YELLOW}Einheit:${RESET}"
    echo -e "${YELLOW}  1${RESET} - MB"
    echo -e "${YELLOW}  2${RESET} - GB (Standard)"
    echo -e -n "${YELLOW}Wählen Sie (1-2): ${RESET}"
    read -r unit_choice
    case "$unit_choice" in
        1) unit="M" ;;
        *) unit="G" ;;
    esac

    local entry="tmpfs ${mountpoint} tmpfs defaults,size=${size}${unit},noatime,nosuid,nodev 0 0"
    local comment="# Ramdisk ${size}${unit}"

    echo -e "\n${CYAN}Vorschau:${RESET}"
    echo -e "${GRAY}${comment}${RESET}"
    echo "$entry"

    if confirm_action "Eintrag hinzufügen?"; then
        write_entry "$entry" "$comment"

        if [[ ! -d "$mountpoint" ]]; then
            if confirm_action "Verzeichnis '${mountpoint}' erstellen?"; then
                mkdir -p "$mountpoint" && echo -e "${GREEN}✓ Verzeichnis erstellt${RESET}"
            fi
        fi
    fi

    press_enter
}

# --- 4) fstab anzeigen ---
show_fstab() {
    print_header
    echo -e "${CYAN}${BOLD}Aktuelle /etc/fstab:${RESET}\n"

    if [[ ! -f "$FSTAB_PATH" ]]; then
        echo -e "${RED}Fehler: ${FSTAB_PATH} nicht gefunden${RESET}"
        press_enter
        return
    fi

    local line_num=0
    while IFS= read -r line; do
        (( line_num++ ))
        local num_display
        num_display=$(printf "%3d" "$line_num")
        if [[ "$line" =~ ^[[:space:]]*$ ]]; then
            echo -e "${GRAY}${num_display} │${RESET}"
        elif [[ "$line" == \#* ]]; then
            echo -e "${GRAY}${num_display} │ ${YELLOW}${line}${RESET}"
        else
            echo -e "${GRAY}${num_display} │${RESET} ${line}"
        fi
    done < "$FSTAB_PATH"

    echo
    echo -e "${CYAN}Gesamt: ${line_num} Zeile(n)${RESET}"

    press_enter
}

# --- 5) Eintrag löschen ---
delete_fstab_entry() {
    print_header
    echo -e "${YELLOW}${BOLD}fstab-Eintrag löschen${RESET}\n"

    if [[ ! -f "$FSTAB_PATH" ]]; then
        echo -e "${RED}Fehler: ${FSTAB_PATH} nicht gefunden${RESET}"
        press_enter
        return
    fi

    # Nur aktive (nicht-Kommentar, nicht-leere) Zeilen anzeigen
    local -a entries=()
    local -a line_numbers=()
    local line_num=0

    while IFS= read -r line; do
        (( line_num++ ))
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        entries+=("$line")
        line_numbers+=("$line_num")
    done < "$FSTAB_PATH"

    if [[ ${#entries[@]} -eq 0 ]]; then
        echo -e "${RED}Keine aktiven Einträge gefunden.${RESET}"
        press_enter
        return
    fi

    echo -e "${CYAN}Aktive Einträge:${RESET}\n"
    for i in "${!entries[@]}"; do
        echo -e "${YELLOW}  $((i+1))${RESET} - ${entries[$i]}"
    done
    echo

    local choice
    while true; do
        echo -e -n "${YELLOW}Welchen Eintrag löschen? (1-${#entries[@]}, 0=Abbruch): ${RESET}"
        read -r choice
        if [[ "$choice" == "0" ]]; then
            echo -e "${YELLOW}Abgebrochen.${RESET}"
            press_enter
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice-1))
            if (( idx >= 0 && idx < ${#entries[@]} )); then
                break
            fi
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done

    local target_line="${line_numbers[$idx]}"
    local target_entry="${entries[$idx]}"

    echo -e "\n${RED}Zu löschender Eintrag (Zeile ${target_line}):${RESET}"
    echo "$target_entry"
    echo

    if confirm_action "Wirklich löschen?"; then
        ask_backup || return

        # Zeile entfernen (plus ggf. direkt davor stehenden Kommentar)
        local prev_line=$(( target_line - 1 ))
        local prev_content=""
        if (( prev_line > 0 )); then
            prev_content=$(sed -n "${prev_line}p" "$FSTAB_PATH")
        fi

        if [[ "$prev_content" =~ ^[[:space:]]*# ]]; then
            # Kommentar + Eintrag löschen
            sed -i "${prev_line},${target_line}d" "$FSTAB_PATH"
            echo -e "${GREEN}✓ Eintrag und zugehöriger Kommentar gelöscht.${RESET}"
        else
            sed -i "${target_line}d" "$FSTAB_PATH"
            echo -e "${GREEN}✓ Eintrag gelöscht.${RESET}"
        fi
        log_action "Eintrag gelöscht: ${target_entry}"
    else
        echo -e "${YELLOW}Abgebrochen.${RESET}"
    fi

    press_enter
}

# --- 7) Partitionen & Laufwerke anzeigen ---
show_partitions() {
    print_header
    echo -e "${CYAN}${BOLD}Partitionen & Laufwerke${RESET}\n"

    # lsblk
    if command -v lsblk &>/dev/null; then
        echo -e "${YELLOW}${BOLD}── lsblk ──────────────────────────────────────────────${RESET}"
        lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,UUID,LABEL 2>/dev/null
        echo
    else
        echo -e "${RED}lsblk nicht verfügbar${RESET}"
    fi

    # blkid
    if command -v blkid &>/dev/null; then
        echo -e "${YELLOW}${BOLD}── blkid ──────────────────────────────────────────────${RESET}"
        blkid 2>/dev/null
        echo
    else
        echo -e "${RED}blkid nicht verfügbar${RESET}"
    fi

    # Aktuell gemountete Dateisysteme
    echo -e "${YELLOW}${BOLD}── Aktive Mounts ──────────────────────────────────────${RESET}"
    findmnt --real -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || mount | grep '^/dev'

    press_enter
}

# --- 8) Backup wiederherstellen ---
restore_backup() {
    print_header
    echo -e "${YELLOW}${BOLD}Backup wiederherstellen${RESET}\n"

    local -a backups
    mapfile -t backups < <(ls -1t "${BACKUP_DIR}"/fstab_backup_* 2>/dev/null | head -10)

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${RED}Keine Backups gefunden.${RESET}"
        press_enter
        return
    fi

    echo -e "${CYAN}Verfügbare Backups (neueste zuerst):${RESET}\n"
    for i in "${!backups[@]}"; do
        local bname bsize bdate
        bname=$(basename "${backups[$i]}")
        bsize=$(stat -c '%s' "${backups[$i]}" 2>/dev/null || echo "?")
        bdate=$(stat -c '%y' "${backups[$i]}" 2>/dev/null | cut -d. -f1)
        echo -e "${YELLOW}  $((i+1))${RESET} - ${bname}  ${GRAY}(${bsize} Bytes, ${bdate})${RESET}"
    done
    echo

    local choice
    while true; do
        echo -e -n "${YELLOW}Wählen Sie Backup (1-${#backups[@]}, 0=Abbruch): ${RESET}"
        read -r choice
        if [[ "$choice" == "0" ]]; then
            echo -e "${YELLOW}Abgebrochen.${RESET}"
            press_enter
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice-1))
            if (( idx >= 0 && idx < ${#backups[@]} )); then
                break
            fi
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done

    local selected="${backups[$idx]}"

    # Inhalt des Backups anzeigen
    echo -e "\n${CYAN}Inhalt des Backups:${RESET}"
    cat "$selected"
    echo

    if confirm_action "fstab mit diesem Backup überschreiben?"; then
        # Aktuelle fstab vorher sichern
        create_backup
        if cp -p "$selected" "$FSTAB_PATH" 2>/dev/null; then
            echo -e "${GREEN}✓ Backup wiederhergestellt: $(basename "$selected")${RESET}"
            log_action "Backup wiederhergestellt: $(basename "$selected")"
        else
            echo -e "${RED}✗ Fehler beim Wiederherstellen${RESET}"
        fi
    else
        echo -e "${YELLOW}Abgebrochen.${RESET}"
    fi

    press_enter
}

# --- 10) System neu starten ---
restart_system() {
    print_header
    echo -e "${RED}${BOLD}WARNUNG: System wird neu gestartet!${RESET}"
    echo -e "${YELLOW}Alle ungespeicherten Daten gehen verloren.${RESET}\n"

    if ! confirm_action "Wirklich neu starten?"; then
        echo -e "${YELLOW}Neustart abgebrochen.${RESET}"
        press_enter
        return
    fi

    local countdown
    echo -e -n "${YELLOW}Countdown in Sekunden (0=Abbruch, max 300, Standard 10): ${RESET}"
    read -r countdown
    countdown="${countdown:-10}"

    if ! [[ "$countdown" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Ungültige Eingabe${RESET}"
        press_enter
        return
    fi

    if (( countdown == 0 )); then
        echo -e "${YELLOW}Neustart abgebrochen.${RESET}"
        press_enter
        return
    fi

    (( countdown > 300 )) && countdown=300

    echo -e "${RED}Neustart in ${countdown} Sekunden...${RESET}"
    echo -e "${GRAY}(Ctrl+C zum Abbrechen)${RESET}"
    log_action "System-Neustart geplant in ${countdown}s"

    sleep "$countdown" && reboot

    press_enter
}

# ============================================================
# BEENDEN
# ============================================================
shutdown_program() {
    clear_screen
    echo -e "${YELLOW}${BOLD}Auf Wiedersehen!${RESET}"
    echo -e "${GREEN}Das Programm wird beendet.${RESET}"
    log_action "Programm beendet"
    exit 0
}

# ============================================================
# HAUPTSCHLEIFE
# ============================================================
main() {
    check_sudo "$@"
    create_backup_dir
    log_action "Programm gestartet"

    while true; do
        print_menu
        echo -e -n "${YELLOW}Wählen Sie eine Option (0-10): ${RESET}"
        read -r choice

        case "$choice" in
            1)  add_fstab_entry      ;;
            2)  mount_tmp_to_ram     ;;
            3)  create_ramdisk       ;;
            4)  show_fstab           ;;
            5)  delete_fstab_entry   ;;
            6)  validate_fstab_syntax ;;
            7)  show_partitions      ;;
            8)  restore_backup       ;;
            9)  cleanup_backups      ;;
            10) restart_system       ;;
            0)  shutdown_program     ;;
            *)
                echo -e "${RED}Ungültige Eingabe. Bitte 0-10 eingeben.${RESET}"
                press_enter
                ;;
        esac
    done
}

# Ctrl+C abfangen
trap 'echo -e "\n${RED}Programm durch Benutzer unterbrochen (Ctrl+C)${RESET}"; log_action "Durch Ctrl+C beendet"; exit 0' INT

main "$@"
