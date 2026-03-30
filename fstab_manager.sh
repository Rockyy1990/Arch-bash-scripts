#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# FStab Manager - Automatische Einträge Tool

# ============================================================
# ANSI Farbcodes
# ============================================================
YELLOW='\033[93m'
GREEN='\033[92m'
RED='\033[91m'
BLUE='\033[94m'
CYAN='\033[96m'
RESET='\033[0m'
BOLD='\033[1m'

FSTAB_PATH="/etc/fstab"
BACKUP_DIR="/etc/fstab.backups"

# ============================================================
# SUDO CHECK - Direkt beim Start nach Passwort fragen
# ============================================================
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}${BOLD}Root-Rechte erforderlich. Bitte sudo-Passwort eingeben:${RESET}"
        SCRIPT_PATH="$(realpath "$BASH_SOURCE")"
        exec sudo bash "$SCRIPT_PATH" "$@"
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
    echo -e "${YELLOW}${BOLD}╔════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}${BOLD}║     /etc/fstab Manager - Automatische Einträge Tool        ║${RESET}"
    echo -e "${YELLOW}${BOLD}╚════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

print_menu() {
    print_header
    echo -e "${YELLOW}${BOLD}HAUPTMENÜ:${RESET}"
    echo -e "${YELLOW}  1${RESET} - Neuer Eintrag hinzufügen"
    echo -e "${YELLOW}  2${RESET} - /tmp in RAM mounten"
    echo -e "${YELLOW}  3${RESET} - Ramdisk erstellen"
    echo -e "${YELLOW}  4${RESET} - Aktuelle /etc/fstab anzeigen"
    echo -e "${YELLOW}  5${RESET} - Backup wiederherstellen"
    echo -e "${YELLOW}  6${RESET} - System neu starten"
    echo -e "${YELLOW}  0${RESET} - Beenden"
    echo
}

press_enter() {
    echo -e "${YELLOW}Drücken Sie Enter zum Fortfahren...${RESET}"
    read -r
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
        return 0
    else
        echo -e "${RED}✗ Fehler beim Backup${RESET}"
        return 1
    fi
}

ask_backup() {
    while true; do
        echo -e -n "${YELLOW}Sicherung der /etc/fstab erstellen? (j/n): ${RESET}"
        read -r response
        case "${response,,}" in
            j|y)
                create_backup
                return $?
                ;;
            n)
                return 0
                ;;
            *)
                echo -e "${RED}Ungültige Eingabe. Bitte 'j' oder 'n' eingeben.${RESET}"
                ;;
        esac
    done
}

# ============================================================
# VALIDIERUNG
# ============================================================
validate_uuid() {
    local uuid="\$1"
    uuid="${uuid// /}"
    if [[ ${#uuid} -lt 8 ]]; then
        return 1
    fi
    echo "$uuid"
    return 0
}

# ============================================================
# INTERAKTIVE ABFRAGEN
# ============================================================
get_filesystem() {
    local filesystems=('ext4' 'xfs' 'btrfs' 'jfs' 'vfat' 'ntfs' 'iso9660')
    local count=${#filesystems[@]}

    echo -e "
${YELLOW}Dateisystem:${RESET}"
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
                SELECTED_FS="${custom:-ext4}"
                return 0
            fi
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done
}

get_mount_options() {
    echo -e "
${YELLOW}Mount-Optionen:${RESET}"
    echo -e "${YELLOW}  1${RESET} - defaults"
    echo -e "${YELLOW}  2${RESET} - defaults,nofail"
    echo -e "${YELLOW}  3${RESET} - defaults,noatime"
    echo -e "${YELLOW}  4${RESET} - defaults,nofail,noatime"
    echo -e "${YELLOW}  5${RESET} - Benutzerdefiniert eingeben"

    while true; do
        echo -e -n "${YELLOW}Wählen Sie (1-5): ${RESET}"
        read -r choice
        case "$choice" in
            1) SELECTED_OPTIONS="defaults";                  return 0 ;;
            2) SELECTED_OPTIONS="defaults,nofail";           return 0 ;;
            3) SELECTED_OPTIONS="defaults,noatime";          return 0 ;;
            4) SELECTED_OPTIONS="defaults,nofail,noatime";   return 0 ;;
            5)
                echo -e -n "${YELLOW}Geben Sie Mount-Optionen ein: ${RESET}"
                read -r custom
                SELECTED_OPTIONS="${custom:-defaults}"
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
    local entry="\$1"
    local comment="\$2"

    {
        if [[ -n "$comment" ]]; then
            echo "$comment"
        fi
        echo "$entry"
    } >> "$FSTAB_PATH"

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Eintrag erfolgreich hinzugefügt!${RESET}"
    else
        echo -e "${RED}✗ Fehler beim Schreiben in ${FSTAB_PATH}${RESET}"
    fi
}

# ============================================================
# MENÜ-FUNKTIONEN
# ============================================================

# --- 1) Neuer Eintrag ---
add_fstab_entry() {
    ask_backup || return

    clear_screen
    echo -e "${YELLOW}${BOLD}Neuer /etc/fstab Eintrag${RESET}
"

    # UUID oder PARTUUID
    local id_type
    while true; do
        echo -e "${YELLOW}UUID oder PARTUUID?${RESET}"
        echo -e "${YELLOW}  1${RESET} - UUID"
        echo -e "${YELLOW}  2${RESET} - PARTUUID"
        echo -e -n "${YELLOW}Wählen Sie (1-2): ${RESET}"
        read -r choice
        case "$choice" in
            1) id_type="UUID";     break ;;
            2) id_type="PARTUUID"; break ;;
            *) echo -e "${RED}Ungültige Eingabe${RESET}" ;;
        esac
    done

    # ID-Wert
    local id_value
    while true; do
        echo -e -n "${YELLOW}Geben Sie ${id_type} ein: ${RESET}"
        read -r id_value
        if validate_uuid "$id_value" > /dev/null; then
            break
        fi
        echo -e "${RED}Ungültige ${id_type}${RESET}"
    done

    # Mountpoint
    local mountpoint
    while true; do
        echo -e -n "${YELLOW}Geben Sie Mountpoint ein (z.B. /mnt/data): ${RESET}"
        read -r mountpoint
        if [[ "$mountpoint" == /* ]]; then
            break
        fi
        echo -e "${RED}Mountpoint muss mit / beginnen${RESET}"
    done

    # Dateisystem
    get_filesystem
    local filesystem="$SELECTED_FS"

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

    # Beschreibung
    local description
    echo -e -n "${YELLOW}Beschreibung (optional): ${RESET}"
    read -r description

    # Eintrag zusammenstellen
    local comment=""
    [[ -n "$description" ]] && comment="# ${description}"
    local entry="${id_type}=${id_value} ${mountpoint} ${filesystem} ${options} ${dump} ${pass_num}"

    # Vorschau
    echo -e "
${CYAN}Vorschau:${RESET}"
    [[ -n "$comment" ]] && echo "$comment"
    echo "$entry"

    while true; do
        echo -e -n "${YELLOW}Eintrag hinzufügen? (j/n): ${RESET}"
        read -r confirm
        case "${confirm,,}" in
            j|y)
                write_entry "$entry" "$comment"
                press_enter
                return
                ;;
            n)
                echo -e "${RED}Abgebrochen${RESET}"
                press_enter
                return
                ;;
            *)
                echo -e "${RED}Ungültige Eingabe${RESET}"
                ;;
        esac
    done
}

# --- 2) /tmp in RAM ---
mount_tmp_to_ram() {
    ask_backup || return

    local entry="tmpfs /tmp tmpfs defaults,size=50%,noatime 0 0"
    local comment="# /tmp in RAM"

    echo -e "
${CYAN}Vorschau:${RESET}"
    echo "$comment"
    echo "$entry"

    while true; do
        echo -e -n "${YELLOW}Eintrag hinzufügen? (j/n): ${RESET}"
        read -r confirm
        case "${confirm,,}" in
            j|y)
                write_entry "$entry" "$comment"
                press_enter
                return
                ;;
            n)
                press_enter
                return
                ;;
            *)
                echo -e "${RED}Ungültige Eingabe${RESET}"
                ;;
        esac
    done
}

# --- 3) Ramdisk erstellen ---
create_ramdisk() {
    ask_backup || return

    local mountpoint
    while true; do
        echo -e -n "${YELLOW}Mountpoint für Ramdisk (z.B. /mnt/ramdisk): ${RESET}"
        read -r mountpoint
        if [[ "$mountpoint" == /* ]]; then
            break
        fi
        echo -e "${RED}Mountpoint muss mit / beginnen${RESET}"
    done

    local size
    echo -e -n "${YELLOW}Größe in GB (Standard 8): ${RESET}"
    read -r size
    size="${size:-8}"

    if ! [[ "$size" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Ungültige Größe${RESET}"
        press_enter
        return
    fi

    local entry="tmpfs ${mountpoint} tmpfs defaults,size=${size}G,noatime 0 0"
    local comment="# Ramdisk ${size}GB"

    echo -e "
${CYAN}Vorschau:${RESET}"
    echo "$comment"
    echo "$entry"

    while true; do
        echo -e -n "${YELLOW}Eintrag hinzufügen? (j/n): ${RESET}"
        read -r confirm
        case "${confirm,,}" in
            j|y)
                write_entry "$entry" "$comment"
                press_enter
                return
                ;;
            n)
                press_enter
                return
                ;;
            *)
                echo -e "${RED}Ungültige Eingabe${RESET}"
                ;;
        esac
    done
}

# --- 4) fstab anzeigen ---
show_fstab() {
    echo -e "
${CYAN}Aktuelle /etc/fstab:${RESET}
"

    if [[ ! -f "$FSTAB_PATH" ]]; then
        echo -e "${RED}Fehler: ${FSTAB_PATH} nicht gefunden${RESET}"
        press_enter
        return
    fi

    local line_num=0
    while IFS= read -r line; do
        (( line_num++ ))
        if [[ "$line" == \#* ]]; then
            echo -e "${YELLOW}${line}${RESET}"
        else
            echo "$line"
        fi
    done < "$FSTAB_PATH"

    press_enter
}

# --- 5) Backup wiederherstellen ---
restore_backup() {
    local -a backups
    mapfile -t backups < <(ls -1r "${BACKUP_DIR}"/fstab_backup_* 2>/dev/null | head -10)

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo -e "${RED}Keine Backups gefunden${RESET}"
        press_enter
        return
    fi

    echo -e "${YELLOW}Verfügbare Backups:${RESET}
"
    for i in "${!backups[@]}"; do
        echo -e "${YELLOW}  $((i+1))${RESET} - $(basename "${backups[$i]}")"
    done

    local selected
    while true; do
        echo -e -n "${YELLOW}Wählen Sie Backup (1-${#backups[@]}): ${RESET}"
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice-1))
            if (( idx >= 0 && idx < ${#backups[@]} )); then
                selected="${backups[$idx]}"
                break
            fi
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done

    if cp -p "$selected" "$FSTAB_PATH" 2>/dev/null; then
        echo -e "${GREEN}✓ Backup wiederhergestellt: $(basename "$selected")${RESET}"
    else
        echo -e "${RED}✗ Fehler beim Wiederherstellen${RESET}"
    fi

    press_enter
}

# --- 6) System neu starten ---
restart_system() {
    echo -e "
${RED}${BOLD}WARNUNG: System wird neu gestartet!${RESET}"
    echo -e "${YELLOW}Alle ungespeicherten Daten gehen verloren.${RESET}
"

    local countdown
    echo -e -n "${YELLOW}Countdown in Sekunden (0=Abbruch, max 300): ${RESET}"
    read -r countdown

    if ! [[ "$countdown" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Ungültige Eingabe${RESET}"
        press_enter
        return
    fi

    if (( countdown <= 0 )); then
        echo -e "${YELLOW}Neustart abgebrochen${RESET}"
        press_enter
        return
    fi

    (( countdown > 300 )) && countdown=300

    local minutes=$(( countdown / 60 ))
    echo -e "${RED}Neustart in ${countdown} Sekunden (${minutes} Minute(n))...${RESET}"
    shutdown -r "+${minutes}"

    press_enter
}

# ============================================================
# BEENDEN
# ============================================================
shutdown_program() {
    clear_screen
    echo -e "${YELLOW}${BOLD}Auf Wiedersehen!${RESET}"
    echo -e "${GREEN}Das Programm wird beendet.${RESET}"
    exit 0
}

# ============================================================
# HAUPTSCHLEIFE
# ============================================================
main() {
    check_sudo "$@"
    create_backup_dir

    while true; do
        print_menu
        echo -e -n "${YELLOW}Wählen Sie eine Option (0-6): ${RESET}"
        read -r choice

        case "$choice" in
            1) add_fstab_entry   ;;
            2) mount_tmp_to_ram  ;;
            3) create_ramdisk    ;;
            4) show_fstab        ;;
            5) restore_backup    ;;
            6) restart_system    ;;
            0) shutdown_program  ;;
            *)
                echo -e "${RED}Ungültige Eingabe. Bitte 0-6 eingeben.${RESET}"
                press_enter
                ;;
        esac
    done
}

# Ctrl+C abfangen
trap 'echo -e "
${RED}Programm durch Benutzer unterbrochen (Ctrl+C)${RESET}"; exit 0' INT

main "$@"
