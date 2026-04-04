#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# ============================================================
# FStab Manager - Automatisches Einträge-Verwaltungstool
# Version 3.0
#
# Beschreibung:
#   Interaktives Terminal-Tool zur komfortablen Verwaltung der
#   /etc/fstab. Ermöglicht das Hinzufügen, Bearbeiten, Löschen,
#   Prüfen und Sichern von fstab-Einträgen sowie Ramdisk- und
#   tmpfs-Management. Enthält Schutzmaßnahmen wie automatische
#   Backups, Syntax-Validierung und Duplikat-Erkennung.
#
# Nutzung:
#   sudo bash fstab_manager.sh
#   (Root-Rechte werden automatisch angefordert)
#
# Changelog v3.0:
#   - Bugfixes: sudo-Weitergabe, write_entry Fehlerprüfung,
#     Duplikat-Erkennung mit exaktem Pfadvergleich,
#     UUID-Validierung verschärft
#   - Neue Funktionen: Eintrag bearbeiten, Einträge mounten/
#     unmounten, Backup-Diff, fstab-Export mit Erklärungen,
#     Mount-Status-Übersicht, Eintrag suchen/filtern
#   - Konstanten als readonly, wiederverwendbare Eingabe-Helfer,
#     konsistentere Fehlerbehandlung
# ============================================================

set -o pipefail

# ============================================================
# KONSTANTEN
# Beschreibung: Globale Konfigurationswerte und ANSI-Farbcodes
#   für die Terminalausgabe. readonly verhindert versehentliche
#   Überschreibung zur Laufzeit.
# ============================================================
readonly YELLOW='\033[93m'
readonly GREEN='\033[92m'
readonly RED='\033[91m'
readonly BLUE='\033[94m'
readonly CYAN='\033[96m'
readonly GRAY='\033[90m'
readonly MAGENTA='\033[95m'
readonly RESET='\033[0m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly UNDERLINE='\033[4m'

readonly FSTAB_PATH="/etc/fstab"
readonly BACKUP_DIR="/etc/fstab.backups"
readonly MAX_BACKUPS=20
readonly LOG_FILE="/var/log/fstab_manager.log"
readonly VERSION="3.0"

# ============================================================
# LOGGING
# Beschreibung: Schreibt Aktionen mit Zeitstempel in die
#   Logdatei. Fehler werden stillschweigend ignoriert, falls
#   die Logdatei nicht beschreibbar ist.
# Parameter: $1 = Nachricht (String)
# ============================================================
log_action() {
    local message="$1"
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" >> "$LOG_FILE" 2>/dev/null
}

# ============================================================
# SUDO CHECK
# Beschreibung: Prüft ob Root-Rechte vorliegen. Falls nicht,
#   wird das Script per exec mit sudo neu gestartet. Die
#   Original-Argumente werden korrekt durchgereicht.
# Hinweis: exec ersetzt den aktuellen Prozess — das exit
#   danach ist nur ein Sicherheitsnetz.
# ============================================================
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}${BOLD}Root-Rechte erforderlich. Bitte sudo-Passwort eingeben:${RESET}"
        local script_path
        script_path="$(realpath "${BASH_SOURCE[0]}")"
        # Originalargumente des Scripts übergeben (nicht die der Funktion)
        exec sudo bash "$script_path" "${ORIG_ARGS[@]}"
        exit 1
    fi
}

# ============================================================
# HILFSFUNKTIONEN
# Beschreibung: Allgemeine Eingabe- und Anzeige-Helfer, die
#   im gesamten Script wiederverwendet werden.
# ============================================================

# --- Bildschirm löschen ---
clear_screen() {
    clear 2>/dev/null || printf '\033[2J\033[H'
}

# --- Trennlinie ausgeben ---
# Parameter: $1 = Zeichen (Standard '─'), $2 = Länge (Standard 60)
print_separator() {
    local char="${1:-─}"
    local len="${2:-60}"
    local line=""
    for ((i = 0; i < len; i++)); do
        line+="$char"
    done
    echo -e "${GRAY}${line}${RESET}"
}

# --- Programmkopf anzeigen ---
print_header() {
    clear_screen
    echo -e "${YELLOW}${BOLD}╔═══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${YELLOW}${BOLD}║       /etc/fstab Manager — Verwaltungstool v${VERSION}          ║${RESET}"
    echo -e "${YELLOW}${BOLD}╚═══════════════════════════════════════════════════════════╝${RESET}"
    echo
}

# --- Hauptmenü anzeigen ---
# Beschreibung: Zeigt alle verfügbaren Menüpunkte mit
#   Kurzbeschreibungen an.
print_menu() {
    print_header
    echo -e "${YELLOW}${BOLD}HAUPTMENÜ:${RESET}"
    echo -e "${YELLOW}   1${RESET} — Neuer Eintrag hinzufügen        ${DIM}(UUID/PARTUUID/LABEL/Gerät)${RESET}"
    echo -e "${YELLOW}   2${RESET} — /tmp in RAM mounten             ${DIM}(tmpfs für /tmp)${RESET}"
    echo -e "${YELLOW}   3${RESET} — Ramdisk erstellen               ${DIM}(tmpfs mit benutzerdefinierter Größe)${RESET}"
    echo -e "${YELLOW}   4${RESET} — Aktuelle /etc/fstab anzeigen    ${DIM}(mit Zeilennummern)${RESET}"
    echo -e "${YELLOW}   5${RESET} — Eintrag löschen                 ${DIM}(interaktive Auswahl)${RESET}"
    echo -e "${YELLOW}   6${RESET} — Eintrag bearbeiten              ${DIM}(bestehenden Eintrag ändern)${RESET}"
    echo -e "${YELLOW}   7${RESET} — fstab Syntax prüfen             ${DIM}(findmnt + mount --fake)${RESET}"
    echo -e "${YELLOW}   8${RESET} — Partitionen & Laufwerke         ${DIM}(lsblk, blkid, Mounts)${RESET}"
    echo -e "${YELLOW}   9${RESET} — Mount-Status prüfen             ${DIM}(konfiguriert vs. gemountet)${RESET}"
    echo -e "${YELLOW}  10${RESET} — Einträge mounten/unmounten      ${DIM}(mount -a oder einzeln)${RESET}"
    echo -e "${YELLOW}  11${RESET} — Eintrag suchen/filtern          ${DIM}(nach Gerät, Mountpoint, FS)${RESET}"
    echo -e "${YELLOW}  12${RESET} — fstab Export mit Erklärungen    ${DIM}(dokumentierte Kopie)${RESET}"
    echo -e "${YELLOW}  13${RESET} — Backup wiederherstellen         ${DIM}(aus ${BACKUP_DIR})${RESET}"
    echo -e "${YELLOW}  14${RESET} — Backup-Diff anzeigen            ${DIM}(Vergleich mit aktuellem Stand)${RESET}"
    echo -e "${YELLOW}  15${RESET} — Alte Backups aufräumen           ${DIM}(über Limit ${MAX_BACKUPS} löschen)${RESET}"
    echo -e "${YELLOW}  16${RESET} — System neu starten              ${DIM}(mit Countdown)${RESET}"
    echo -e "${YELLOW}   0${RESET} — Beenden"
    echo
}

# --- Enter-Taste zum Fortfahren ---
press_enter() {
    echo
    echo -e "${YELLOW}Drücken Sie Enter zum Fortfahren...${RESET}"
    read -r
}

# --- Ja/Nein-Abfrage ---
# Beschreibung: Fragt den Benutzer nach Bestätigung.
#   Akzeptiert j/y für Ja, n für Nein.
# Parameter: $1 = Prompt-Text
# Rückgabe: 0 = Ja, 1 = Nein
confirm_action() {
    local prompt="$1"
    while true; do
        echo -e -n "${YELLOW}${prompt} (j/n): ${RESET}"
        read -r response
        case "${response,,}" in
            j|ja|y|yes) return 0 ;;
            n|nein|no)  return 1 ;;
            *)          echo -e "${RED}Ungültige Eingabe. Bitte 'j' oder 'n' eingeben.${RESET}" ;;
        esac
    done
}

# --- Generische Nummernauswahl aus einer Liste ---
# Beschreibung: Zeigt eine nummerierte Liste an und gibt den
#   gewählten Index (0-basiert) in MENU_CHOICE zurück.
#   Unterstützt optionalen Abbruch mit 0.
# Parameter: $1 = Überschrift, $2 = Abbruch erlaubt (0/1),
#            Rest = Einträge
# Rückgabe: 0 = Auswahl getroffen (Index in MENU_CHOICE),
#           1 = Abbruch
MENU_CHOICE=-1
select_from_list() {
    local header="$1"
    local allow_cancel="$2"
    shift 2
    local -a items=("$@")
    local count=${#items[@]}

    echo -e "\n${YELLOW}${header}:${RESET}"
    for i in "${!items[@]}"; do
        echo -e "${YELLOW}  $((i+1))${RESET} — ${items[$i]}"
    done

    if [[ "$allow_cancel" == "1" ]]; then
        echo -e "${YELLOW}  0${RESET} — Abbrechen"
    fi

    while true; do
        echo -e -n "${YELLOW}Wählen Sie (1-${count}): ${RESET}"
        read -r choice
        if [[ "$allow_cancel" == "1" && "$choice" == "0" ]]; then
            MENU_CHOICE=-1
            return 1
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            if (( idx >= 0 && idx < count )); then
                MENU_CHOICE=$idx
                return 0
            fi
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done
}

# ============================================================
# BACKUP FUNKTIONEN
# Beschreibung: Sicherungs- und Wiederherstellungslogik für
#   die fstab. Backups werden mit Zeitstempel im BACKUP_DIR
#   gespeichert. Die Anzahl ist auf MAX_BACKUPS begrenzt.
# ============================================================

# --- Backup-Verzeichnis erstellen ---
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p -m 700 "$BACKUP_DIR"
        log_action "Backup-Verzeichnis erstellt: ${BACKUP_DIR}"
    fi
}

# --- Backup der fstab erstellen ---
# Beschreibung: Kopiert die aktuelle fstab mit Zeitstempel-Suffix
#   ins Backup-Verzeichnis. Erhält Dateiberechtigungen (-p).
# Rückgabe: 0 = Erfolg, 1 = Fehler
create_backup() {
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_path="${BACKUP_DIR}/fstab_backup_${timestamp}"

    if cp -p "$FSTAB_PATH" "$backup_path" 2>/dev/null; then
        chmod 600 "$backup_path" 2>/dev/null
        echo -e "${GREEN}✓ Backup erstellt: ${backup_path}${RESET}"
        log_action "Backup erstellt: ${backup_path}"
        return 0
    else
        echo -e "${RED}✗ Fehler beim Backup${RESET}"
        return 1
    fi
}

# --- Backup-Abfrage ---
# Beschreibung: Fragt den Benutzer ob ein Backup erstellt
#   werden soll, bevor Änderungen vorgenommen werden.
ask_backup() {
    if confirm_action "Sicherung der /etc/fstab erstellen?"; then
        create_backup
        return $?
    fi
    return 0
}

# --- Backup-Liste abrufen ---
# Beschreibung: Füllt das Array BACKUP_LIST mit allen
#   vorhandenen Backups, sortiert nach Datum (neueste zuerst).
# Parameter: $1 = max. Anzahl (optional, Standard: alle)
BACKUP_LIST=()
get_backup_list() {
    local max="${1:-0}"
    BACKUP_LIST=()
    local cmd="ls -1t ${BACKUP_DIR}/fstab_backup_* 2>/dev/null"
    if (( max > 0 )); then
        cmd+=" | head -${max}"
    fi
    mapfile -t BACKUP_LIST < <(eval "$cmd")
}

# --- Alte Backups aufräumen ---
# Beschreibung: Löscht die ältesten Backups wenn die Anzahl
#   das konfigurierte Limit (MAX_BACKUPS) überschreitet.
cleanup_backups() {
    print_header
    echo -e "${YELLOW}${BOLD}Alte Backups aufräumen${RESET}"
    echo
    print_separator

    get_backup_list
    local total=${#BACKUP_LIST[@]}

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
        for (( i = MAX_BACKUPS; i < total; i++ )); do
            if rm -f "${BACKUP_LIST[$i]}" 2>/dev/null; then
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
# Beschreibung: Funktionen zur Überprüfung von Benutzereingaben
#   wie UUIDs, Mountpoints und Duplikaten. Verhindert ungültige
#   Einträge in der fstab.
# ============================================================

# --- UUID validieren ---
# Beschreibung: Prüft ob ein String ein gültiges UUID-Format hat.
#   Unterstützt Standard-UUIDs (8-4-4-4-12), kurze PARTUUIDs
#   (8 oder 8-2 Hex-Zeichen) und volle GPT-PARTUUIDs.
# Parameter: $1 = UUID-String
# Ausgabe: Bereinigter UUID auf stdout
# Rückgabe: 0 = gültig, 1 = ungültig
validate_uuid() {
    local uuid="$1"
    uuid="${uuid// /}"

    # Standard-UUID: 8-4-4-4-12 Hexadezimal (z.B. 550e8400-e29b-41d4-a716-446655440000)
    if [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        echo "$uuid"
        return 0
    fi

    # Kurze PARTUUID (MBR): 8 Hex-Zeichen, optional mit -XX Suffix (z.B. a1b2c3d4-01)
    if [[ "$uuid" =~ ^[0-9a-fA-F]{8}(-[0-9a-fA-F]{2})?$ ]]; then
        echo "$uuid"
        return 0
    fi

    return 1
}

# --- Mountpoint validieren ---
# Beschreibung: Prüft ob der Mountpoint ein gültiger absoluter
#   Pfad ist (beginnt mit /) und keine Leerzeichen enthält.
# Parameter: $1 = Mountpoint-Pfad
# Rückgabe: 0 = gültig, 1 = ungültig
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
    if [[ "$mp" == "/" ]]; then
        echo -e "${RED}Root-Mountpoint (/) kann nicht geändert werden${RESET}"
        return 1
    fi
    return 0
}

# --- Duplikat-Mountpoint prüfen ---
# Beschreibung: Prüft ob ein Mountpoint bereits als aktiver
#   (nicht auskommentierter) Eintrag in der fstab existiert.
#   Verwendet exakten Feldvergleich statt grep -w, um falsche
#   Treffer bei ähnlichen Pfaden zu vermeiden (z.B. /mnt/data
#   vs. /mnt/data2).
# Parameter: $1 = Mountpoint-Pfad
# Rückgabe: 0 = ok (oder Benutzer bestätigt), 1 = Abbruch
check_duplicate_mountpoint() {
    local mountpoint="$1"
    local found=0

    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        local mp_field
        mp_field=$(awk '{print $2}' <<< "$line")
        if [[ "$mp_field" == "$mountpoint" ]]; then
            found=1
            break
        fi
    done < "$FSTAB_PATH"

    if [[ $found -eq 1 ]]; then
        echo -e "${RED}⚠ WARNUNG: Mountpoint '${mountpoint}' existiert bereits in fstab!${RESET}"
        if ! confirm_action "Trotzdem fortfahren?"; then
            return 1
        fi
    fi
    return 0
}

# --- fstab Syntax prüfen ---
# Beschreibung: Führt zwei Prüfungen durch:
#   1. findmnt --verify: Syntaktische Prüfung aller Felder
#   2. mount --fake --all: Simulierter Mount aller Einträge
#   Falls findmnt nicht verfügbar ist, wird eine manuelle
#   Feldanzahl-Prüfung durchgeführt.
validate_fstab_syntax() {
    print_header
    echo -e "${YELLOW}${BOLD}fstab Syntax-Prüfung${RESET}"
    echo
    print_separator

    if ! command -v findmnt &>/dev/null; then
        echo -e "${RED}findmnt nicht verfügbar. Verwende manuelle Prüfung...${RESET}"
        echo
        _manual_fstab_check
        press_enter
        return
    fi

    echo -e "${CYAN}Prüfe mit findmnt --verify...${RESET}"
    echo

    local output rc
    output=$(findmnt --verify --tab-file "$FSTAB_PATH" 2>&1)
    rc=$?

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
    print_separator
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

# --- Manuelle fstab-Prüfung (Fallback) ---
# Beschreibung: Zählt die Felder jeder aktiven Zeile und meldet
#   Abweichungen vom erwarteten Bereich (4–6 Felder).
_manual_fstab_check() {
    local line_num=0
    local errors=0
    while IFS= read -r line; do
        (( line_num++ ))
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        local -a fields
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
# Beschreibung: Wiederverwendbare Eingabe-Dialoge für
#   Dateisystem-Typ und Mount-Optionen.
# ============================================================

# --- Dateisystem auswählen ---
# Beschreibung: Zeigt eine Liste unterstützter Dateisysteme an
#   und speichert die Auswahl in SELECTED_FS.
SELECTED_FS=""
get_filesystem() {
    local -a filesystems=('ext4' 'xfs' 'btrfs' 'jfs' 'vfat' 'ntfs' 'exfat' 'iso9660' 'swap')

    local -a descriptions=(
        'Linux Standard (stabil, weit verbreitet)'
        'High-Performance (RHEL/CentOS Standard)'
        'Copy-on-Write (Snapshots, RAID)'
        'Journaling FS (IBM, stabil)'
        'FAT32 (USB-Sticks, EFI)'
        'Windows NTFS (Lese-/Schreibzugriff)'
        'exFAT (große USB-Laufwerke)'
        'CD/DVD Dateisystem'
        'Swap-Partition (Auslagerung)'
    )

    echo -e "\n${YELLOW}Dateisystem:${RESET}"
    for i in "${!filesystems[@]}"; do
        printf "  ${YELLOW}%2d${RESET} — %-10s ${DIM}%s${RESET}\n" "$((i+1))" "${filesystems[$i]}" "${descriptions[$i]}"
    done
    echo -e "  ${YELLOW}$((${#filesystems[@]}+1))${RESET} — Benutzerdefiniert"

    local count=${#filesystems[@]}
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

# --- Mount-Optionen auswählen ---
# Beschreibung: Bietet gängige Mount-Option-Kombinationen an.
#   Die Auswahl wird in SELECTED_OPTIONS gespeichert.
SELECTED_OPTIONS=""
get_mount_options() {
    local -a options=(
        'defaults'
        'defaults,nofail'
        'defaults,noatime'
        'defaults,nofail,noatime'
        'defaults,noatime,nodiratime'
        'defaults,nofail,x-systemd.automount'
    )
    local -a descriptions=(
        'Standardoptionen (rw,suid,dev,exec,auto,nouser,async)'
        'Kein Fehler beim Booten wenn Gerät fehlt'
        'Keine Aktualisierung der Zugriffszeitstempel'
        'Kein Fehler + keine Zugriffszeitstempel'
        'Kein Zugriffs-/Verzeichniszeitstempel'
        'Automatisches Mounten bei erstem Zugriff (systemd)'
    )

    echo -e "\n${YELLOW}Mount-Optionen:${RESET}"
    for i in "${!options[@]}"; do
        printf "  ${YELLOW}%d${RESET} — %-42s ${DIM}%s${RESET}\n" "$((i+1))" "${options[$i]}" "${descriptions[$i]}"
    done
    echo -e "  ${YELLOW}$((${#options[@]}+1))${RESET} — Benutzerdefiniert eingeben"

    local count=${#options[@]}
    while true; do
        echo -e -n "${YELLOW}Wählen Sie (1-$((count+1))): ${RESET}"
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice-1))
            if (( idx >= 0 && idx < count )); then
                SELECTED_OPTIONS="${options[$idx]}"
                return 0
            elif (( idx == count )); then
                echo -e -n "${YELLOW}Geben Sie Mount-Optionen ein: ${RESET}"
                read -r custom
                if [[ -z "$custom" ]]; then
                    echo -e "${RED}Eingabe darf nicht leer sein${RESET}"
                    continue
                fi
                SELECTED_OPTIONS="$custom"
                return 0
            fi
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done
}

# ============================================================
# AKTIVE EINTRÄGE LADEN
# Beschreibung: Liest alle aktiven (nicht auskommentierten,
#   nicht leeren) Zeilen aus der fstab in die Arrays
#   ACTIVE_ENTRIES und ACTIVE_LINE_NUMBERS.
# ============================================================
ACTIVE_ENTRIES=()
ACTIVE_LINE_NUMBERS=()
load_active_entries() {
    ACTIVE_ENTRIES=()
    ACTIVE_LINE_NUMBERS=()
    local line_num=0

    while IFS= read -r line; do
        (( line_num++ ))
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        ACTIVE_ENTRIES+=("$line")
        ACTIVE_LINE_NUMBERS+=("$line_num")
    done < "$FSTAB_PATH"
}

# ============================================================
# EINTRAG SCHREIBEN
# Beschreibung: Fügt einen neuen Eintrag (mit optionalem
#   Kommentar) an das Ende der fstab an. Stellt sicher, dass
#   eine Leerzeile als Abstandhalter vorhanden ist.
# Parameter: $1 = fstab-Zeile, $2 = Kommentarzeile (optional)
# Rückgabe: 0 = Erfolg, 1 = Fehler
# ============================================================
write_entry() {
    local entry="$1"
    local comment="$2"

    # Leerzeile vor neuem Eintrag sicherstellen
    local last_char
    last_char=$(tail -c 1 "$FSTAB_PATH" 2>/dev/null)
    if [[ -n "$last_char" && "$last_char" != $'\n' ]]; then
        echo "" >> "$FSTAB_PATH"
    fi

    # Schreiben mit expliziter Fehlerprüfung
    local write_ok=1
    if [[ -n "$comment" ]]; then
        if ! echo "$comment" >> "$FSTAB_PATH"; then
            write_ok=0
        fi
    fi
    if ! echo "$entry" >> "$FSTAB_PATH"; then
        write_ok=0
    fi

    if [[ $write_ok -eq 1 ]]; then
        echo -e "${GREEN}✓ Eintrag erfolgreich hinzugefügt!${RESET}"
        log_action "Eintrag hinzugefügt: ${entry}"
        return 0
    else
        echo -e "${RED}✗ Fehler beim Schreiben in ${FSTAB_PATH}${RESET}"
        return 1
    fi
}

# ============================================================
# MENÜ-FUNKTIONEN
# ============================================================

# --- 1) Neuer Eintrag hinzufügen ---
# Beschreibung: Führt den Benutzer Schritt für Schritt durch
#   die Erstellung eines neuen fstab-Eintrags:
#   1. Quell-Identifikation (UUID/PARTUUID/LABEL/Gerätepfad)
#   2. Mountpoint
#   3. Dateisystem
#   4. Mount-Optionen
#   5. dump- und pass-Flags
#   6. Optionale Beschreibung als Kommentar
#   Enthält Duplikat-Prüfung und optionale Verzeichniserstellung.
add_fstab_entry() {
    print_header
    echo -e "${YELLOW}${BOLD}Neuer /etc/fstab Eintrag${RESET}\n"
    print_separator

    ask_backup || return

    # Quell-Identifikation wählen
    local id_type
    local -a id_types=('UUID' 'PARTUUID' 'LABEL' 'Gerätepfad (z.B. /dev/sda1)')
    select_from_list "Quell-Identifikation" 1 "${id_types[@]}" || { press_enter; return; }
    case $MENU_CHOICE in
        0) id_type="UUID"     ;;
        1) id_type="PARTUUID" ;;
        2) id_type="LABEL"    ;;
        3) id_type="DEVICE"   ;;
    esac

    # ID-Wert / Gerätepfad eingeben
    local id_value source_prefix
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

    check_duplicate_mountpoint "$mountpoint" || { press_enter; return; }

    # Dateisystem
    get_filesystem
    local filesystem="$SELECTED_FS"

    # Spezialfall: swap
    local options dump pass_num
    if [[ "$filesystem" == "swap" ]]; then
        mountpoint="none"
        options="sw"
        dump=0
        pass_num=0
    else
        get_mount_options
        options="$SELECTED_OPTIONS"

        # dump-Flag
        while true; do
            echo -e -n "${YELLOW}dump-Flag (0 oder 1, Standard 0): ${RESET}"
            read -r dump
            dump="${dump:-0}"
            [[ "$dump" == "0" || "$dump" == "1" ]] && break
            echo -e "${RED}Bitte 0 oder 1 eingeben${RESET}"
        done

        # pass-Flag
        while true; do
            echo -e -n "${YELLOW}pass-Flag (0, 1 oder 2, Standard 0): ${RESET}"
            read -r pass_num
            pass_num="${pass_num:-0}"
            [[ "$pass_num" =~ ^[012]$ ]] && break
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
    print_separator
    [[ -n "$comment" ]] && echo -e "${GRAY}${comment}${RESET}"
    echo "$entry"
    print_separator

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

# --- 2) /tmp in RAM mounten ---
# Beschreibung: Erstellt einen tmpfs-Eintrag für /tmp mit
#   konfigurierbarer Größe (Prozent des RAM). Sinnvoll für
#   SSDs (weniger Schreibzugriffe) und Performance.
#   Sicherheitsoptionen: nosuid, nodev werden automatisch
#   gesetzt.
mount_tmp_to_ram() {
    print_header
    echo -e "${YELLOW}${BOLD}/tmp in RAM mounten${RESET}\n"
    print_separator

    # Prüfen ob bereits vorhanden (exakter Feldvergleich)
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        local fs_field mp_field
        fs_field=$(awk '{print $3}' <<< "$line")
        mp_field=$(awk '{print $2}' <<< "$line")
        if [[ "$fs_field" == "tmpfs" && "$mp_field" == "/tmp" ]]; then
            echo -e "${RED}⚠ Es existiert bereits ein tmpfs-Eintrag für /tmp in fstab!${RESET}"
            echo -e "${GRAY}   ${line}${RESET}"
            if ! confirm_action "Trotzdem fortfahren?"; then
                press_enter
                return
            fi
            break
        fi
    done < "$FSTAB_PATH"

    ask_backup || return

    # RAM-Größe anzeigen
    local total_ram_mb
    total_ram_mb=$(awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo 2>/dev/null)
    if [[ -n "$total_ram_mb" ]]; then
        echo -e "${CYAN}Verfügbarer RAM: ca. ${total_ram_mb} MB${RESET}"
    fi

    local size_pct
    echo -e -n "${YELLOW}Größe in % des RAM (Standard 50, erlaubt 1-90): ${RESET}"
    read -r size_pct
    size_pct="${size_pct:-50}"

    if ! [[ "$size_pct" =~ ^[0-9]+$ ]] || (( size_pct < 1 || size_pct > 90 )); then
        echo -e "${RED}Ungültige Größe (1-90%)${RESET}"
        press_enter
        return
    fi

    local entry="tmpfs /tmp tmpfs defaults,size=${size_pct}%,noatime,nosuid,nodev 0 0"
    local comment="# /tmp in RAM (${size_pct}% des RAM)"

    echo -e "\n${CYAN}Vorschau:${RESET}"
    print_separator
    echo -e "${GRAY}${comment}${RESET}"
    echo "$entry"
    print_separator

    if confirm_action "Eintrag hinzufügen?"; then
        write_entry "$entry" "$comment"
    fi

    press_enter
}

# --- 3) Ramdisk erstellen ---
# Beschreibung: Erstellt einen tmpfs-Eintrag mit fester Größe
#   (MB oder GB) an einem benutzerdefinierten Mountpoint.
#   Nützlich für temporäre Arbeitsdaten, Caches oder Build-
#   Verzeichnisse.
create_ramdisk() {
    print_header
    echo -e "${YELLOW}${BOLD}Ramdisk erstellen${RESET}\n"
    print_separator

    ask_backup || return

    local mountpoint
    while true; do
        echo -e -n "${YELLOW}Mountpoint für Ramdisk (z.B. /mnt/ramdisk): ${RESET}"
        read -r mountpoint
        validate_mountpoint "$mountpoint" && break
    done

    check_duplicate_mountpoint "$mountpoint" || { press_enter; return; }

    # Größe
    local size
    echo -e -n "${YELLOW}Größe (Standard 8): ${RESET}"
    read -r size
    size="${size:-8}"

    if ! [[ "$size" =~ ^[0-9]+$ ]] || (( size < 1 )); then
        echo -e "${RED}Ungültige Größe (muss > 0 sein)${RESET}"
        press_enter
        return
    fi

    # Einheit
    local unit
    local -a units=('MB' 'GB (Standard)')
    select_from_list "Einheit" 0 "${units[@]}"
    case $MENU_CHOICE in
        0) unit="M" ;;
        *) unit="G" ;;
    esac

    local entry="tmpfs ${mountpoint} tmpfs defaults,size=${size}${unit},noatime,nosuid,nodev 0 0"
    local comment="# Ramdisk ${size}${unit} auf ${mountpoint}"

    echo -e "\n${CYAN}Vorschau:${RESET}"
    print_separator
    echo -e "${GRAY}${comment}${RESET}"
    echo "$entry"
    print_separator

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
# Beschreibung: Gibt den kompletten Inhalt der /etc/fstab mit
#   Zeilennummern und Farbkodierung aus:
#   - Kommentare: gelb
#   - Leere Zeilen: grau
#   - Aktive Einträge: weiß
show_fstab() {
    print_header
    echo -e "${CYAN}${BOLD}Aktuelle /etc/fstab:${RESET}\n"

    if [[ ! -f "$FSTAB_PATH" ]]; then
        echo -e "${RED}Fehler: ${FSTAB_PATH} nicht gefunden${RESET}"
        press_enter
        return
    fi

    print_separator "═" 60
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
    print_separator "═" 60

    echo
    echo -e "${CYAN}Gesamt: ${line_num} Zeile(n)${RESET}"

    press_enter
}

# --- 5) Eintrag löschen ---
# Beschreibung: Zeigt alle aktiven fstab-Einträge nummeriert
#   an. Der Benutzer wählt den zu löschenden Eintrag. Falls
#   direkt über dem Eintrag ein Kommentar steht, wird dieser
#   ebenfalls entfernt. Backup wird vorher angeboten.
delete_fstab_entry() {
    print_header
    echo -e "${YELLOW}${BOLD}fstab-Eintrag löschen${RESET}\n"
    print_separator

    if [[ ! -f "$FSTAB_PATH" ]]; then
        echo -e "${RED}Fehler: ${FSTAB_PATH} nicht gefunden${RESET}"
        press_enter
        return
    fi

    load_active_entries

    if [[ ${#ACTIVE_ENTRIES[@]} -eq 0 ]]; then
        echo -e "${RED}Keine aktiven Einträge gefunden.${RESET}"
        press_enter
        return
    fi

    echo -e "${CYAN}Aktive Einträge:${RESET}\n"
    for i in "${!ACTIVE_ENTRIES[@]}"; do
        echo -e "${YELLOW}  $((i+1))${RESET} — ${ACTIVE_ENTRIES[$i]}"
    done
    echo

    local choice
    while true; do
        echo -e -n "${YELLOW}Welchen Eintrag löschen? (1-${#ACTIVE_ENTRIES[@]}, 0=Abbruch): ${RESET}"
        read -r choice
        if [[ "$choice" == "0" ]]; then
            echo -e "${YELLOW}Abgebrochen.${RESET}"
            press_enter
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            if (( idx >= 0 && idx < ${#ACTIVE_ENTRIES[@]} )); then
                break
            fi
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done

    local target_line="${ACTIVE_LINE_NUMBERS[$idx]}"
    local target_entry="${ACTIVE_ENTRIES[$idx]}"

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

# --- 6) Eintrag bearbeiten (NEU) ---
# Beschreibung: Ermöglicht das Ändern eines bestehenden fstab-
#   Eintrags. Der Benutzer wählt den Eintrag und dann das zu
#   ändernde Feld (Quelle, Mountpoint, Dateisystem, Optionen,
#   dump, pass). Die Änderung wird per sed in-place durchgeführt.
edit_fstab_entry() {
    print_header
    echo -e "${YELLOW}${BOLD}fstab-Eintrag bearbeiten${RESET}\n"
    print_separator

    if [[ ! -f "$FSTAB_PATH" ]]; then
        echo -e "${RED}Fehler: ${FSTAB_PATH} nicht gefunden${RESET}"
        press_enter
        return
    fi

    load_active_entries

    if [[ ${#ACTIVE_ENTRIES[@]} -eq 0 ]]; then
        echo -e "${RED}Keine aktiven Einträge gefunden.${RESET}"
        press_enter
        return
    fi

    echo -e "${CYAN}Aktive Einträge:${RESET}\n"
    for i in "${!ACTIVE_ENTRIES[@]}"; do
        echo -e "${YELLOW}  $((i+1))${RESET} — ${ACTIVE_ENTRIES[$i]}"
    done
    echo

    # Eintrag auswählen
    local choice
    while true; do
        echo -e -n "${YELLOW}Welchen Eintrag bearbeiten? (1-${#ACTIVE_ENTRIES[@]}, 0=Abbruch): ${RESET}"
        read -r choice
        [[ "$choice" == "0" ]] && { echo -e "${YELLOW}Abgebrochen.${RESET}"; press_enter; return; }
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            (( idx >= 0 && idx < ${#ACTIVE_ENTRIES[@]} )) && break
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done

    local target_line="${ACTIVE_LINE_NUMBERS[$idx]}"
    local target_entry="${ACTIVE_ENTRIES[$idx]}"

    # Felder aufsplitten
    local -a fields
    read -ra fields <<< "$target_entry"

    # Felder mit Standardwerten auffüllen
    while [[ ${#fields[@]} -lt 6 ]]; do
        fields+=("0")
    done

    echo -e "\n${CYAN}Aktueller Eintrag (Zeile ${target_line}):${RESET}"
    print_separator
    echo -e "  ${BOLD}Quelle:${RESET}      ${fields[0]}"
    echo -e "  ${BOLD}Mountpoint:${RESET}  ${fields[1]}"
    echo -e "  ${BOLD}Dateisystem:${RESET} ${fields[2]}"
    echo -e "  ${BOLD}Optionen:${RESET}    ${fields[3]}"
    echo -e "  ${BOLD}dump:${RESET}        ${fields[4]}"
    echo -e "  ${BOLD}pass:${RESET}        ${fields[5]}"
    print_separator

    # Feld zum Bearbeiten wählen
    local -a field_names=('Quelle' 'Mountpoint' 'Dateisystem' 'Optionen' 'dump-Flag' 'pass-Flag')
    select_from_list "Welches Feld ändern?" 1 "${field_names[@]}" || { press_enter; return; }
    local field_idx=$MENU_CHOICE

    # Neuen Wert eingeben
    local new_value
    echo -e -n "${YELLOW}Neuer Wert für '${field_names[$field_idx]}' [aktuell: ${fields[$field_idx]}]: ${RESET}"
    read -r new_value

    if [[ -z "$new_value" ]]; then
        echo -e "${YELLOW}Keine Änderung vorgenommen.${RESET}"
        press_enter
        return
    fi

    # Validierung je nach Feld
    case $field_idx in
        1) # Mountpoint
            if ! validate_mountpoint "$new_value"; then
                press_enter
                return
            fi
            ;;
        4) # dump
            if [[ "$new_value" != "0" && "$new_value" != "1" ]]; then
                echo -e "${RED}dump muss 0 oder 1 sein${RESET}"
                press_enter
                return
            fi
            ;;
        5) # pass
            if [[ ! "$new_value" =~ ^[012]$ ]]; then
                echo -e "${RED}pass muss 0, 1 oder 2 sein${RESET}"
                press_enter
                return
            fi
            ;;
    esac

    fields[$field_idx]="$new_value"
    local new_entry="${fields[*]}"

    echo -e "\n${CYAN}Neuer Eintrag:${RESET}"
    print_separator
    echo "$new_entry"
    print_separator

    if confirm_action "Änderung übernehmen?"; then
        ask_backup || return

        # Alte Zeile ersetzen (sed mit sicherem Delimiter)
        sed -i "${target_line}s|.*|${new_entry}|" "$FSTAB_PATH"

        echo -e "${GREEN}✓ Eintrag aktualisiert.${RESET}"
        log_action "Eintrag bearbeitet: Zeile ${target_line}: ${target_entry} → ${new_entry}"
    else
        echo -e "${YELLOW}Abgebrochen.${RESET}"
    fi

    press_enter
}

# --- 7) fstab Syntax prüfen ---
# (siehe validate_fstab_syntax oben)

# --- 8) Partitionen & Laufwerke anzeigen ---
# Beschreibung: Zeigt eine umfassende Übersicht aller
#   erkannten Blockgeräte, deren UUIDs, Labels und aktive
#   Mountpoints. Nutzt lsblk, blkid und findmnt/mount.
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

    # Aktive Mounts
    echo -e "${YELLOW}${BOLD}── Aktive Mounts ──────────────────────────────────────${RESET}"
    if command -v findmnt &>/dev/null; then
        findmnt --real -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null
    else
        mount | grep '^/dev'
    fi

    press_enter
}

# --- 9) Mount-Status prüfen (NEU) ---
# Beschreibung: Vergleicht die fstab-Einträge mit den aktuell
#   gemounteten Dateisystemen. Zeigt für jeden Eintrag an, ob
#   er tatsächlich gemountet ist (✓) oder nicht (✗).
#   Nützlich zur Fehlerdiagnose nach Boot-Problemen.
check_mount_status() {
    print_header
    echo -e "${CYAN}${BOLD}Mount-Status: Konfiguriert vs. Gemountet${RESET}\n"
    print_separator "═" 70

    if [[ ! -f "$FSTAB_PATH" ]]; then
        echo -e "${RED}Fehler: ${FSTAB_PATH} nicht gefunden${RESET}"
        press_enter
        return
    fi

    local line_num=0
    local mounted=0 not_mounted=0 skipped=0

    printf "  ${BOLD}%-35s %-12s %-8s${RESET}\n" "MOUNTPOINT" "DATEISYSTEM" "STATUS"
    print_separator "─" 70

    while IFS= read -r line; do
        (( line_num++ ))
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        local -a fields
        read -ra fields <<< "$line"
        local mp="${fields[1]}"
        local fs="${fields[2]}"

        # swap und none überspringen
        if [[ "$mp" == "none" || "$fs" == "swap" ]]; then
            # Prüfe ob Swap aktiv ist
            if [[ "$fs" == "swap" ]]; then
                if swapon --show 2>/dev/null | grep -q "${fields[0]}" 2>/dev/null; then
                    printf "  ${GREEN}%-35s %-12s ✓ aktiv${RESET}\n" "${fields[0]}" "$fs"
                    (( mounted++ ))
                else
                    printf "  ${RED}%-35s %-12s ✗ inaktiv${RESET}\n" "${fields[0]}" "$fs"
                    (( not_mounted++ ))
                fi
            else
                (( skipped++ ))
            fi
            continue
        fi

        # Prüfen ob gemountet
        if findmnt --target "$mp" &>/dev/null 2>&1; then
            printf "  ${GREEN}%-35s %-12s ✓ gemountet${RESET}\n" "$mp" "$fs"
            (( mounted++ ))
        else
            printf "  ${RED}%-35s %-12s ✗ nicht gemountet${RESET}\n" "$mp" "$fs"
            (( not_mounted++ ))
        fi
    done < "$FSTAB_PATH"

    print_separator "─" 70
    echo
    echo -e "${GREEN}Gemountet: ${mounted}${RESET}  |  ${RED}Nicht gemountet: ${not_mounted}${RESET}  |  ${GRAY}Übersprungen: ${skipped}${RESET}"

    press_enter
}

# --- 10) Einträge mounten/unmounten (NEU) ---
# Beschreibung: Bietet drei Optionen:
#   a) mount -a: Alle fstab-Einträge mounten
#   b) Einzelnen Mountpoint mounten
#   c) Einzelnen Mountpoint unmounten
#   Nützlich um neue Einträge ohne Neustart zu aktivieren.
mount_unmount_entries() {
    print_header
    echo -e "${YELLOW}${BOLD}Einträge mounten / unmounten${RESET}\n"
    print_separator

    local -a actions=(
        'Alle fstab-Einträge mounten (mount -a)'
        'Einzelnen Mountpoint mounten'
        'Einzelnen Mountpoint unmounten'
    )
    select_from_list "Aktion wählen" 1 "${actions[@]}" || { press_enter; return; }

    case $MENU_CHOICE in
        0)  # mount -a
            echo -e "\n${CYAN}Führe mount -a aus...${RESET}"
            local output
            output=$(mount -a 2>&1)
            local rc=$?
            if [[ $rc -eq 0 ]]; then
                echo -e "${GREEN}✓ mount -a erfolgreich.${RESET}"
                log_action "mount -a ausgeführt"
            else
                echo -e "${RED}✗ mount -a fehlgeschlagen:${RESET}"
                echo "$output"
            fi
            ;;
        1)  # Einzeln mounten
            load_active_entries
            if [[ ${#ACTIVE_ENTRIES[@]} -eq 0 ]]; then
                echo -e "${RED}Keine aktiven Einträge gefunden.${RESET}"
                press_enter
                return
            fi

            echo -e "\n${CYAN}Einträge:${RESET}"
            for i in "${!ACTIVE_ENTRIES[@]}"; do
                local mp
                mp=$(awk '{print $2}' <<< "${ACTIVE_ENTRIES[$i]}")
                echo -e "${YELLOW}  $((i+1))${RESET} — ${mp}  ${DIM}(${ACTIVE_ENTRIES[$i]})${RESET}"
            done
            echo

            local choice
            echo -e -n "${YELLOW}Welchen Eintrag mounten? (1-${#ACTIVE_ENTRIES[@]}, 0=Abbruch): ${RESET}"
            read -r choice
            [[ "$choice" == "0" ]] && { press_enter; return; }

            if [[ "$choice" =~ ^[0-9]+$ ]]; then
                local idx=$((choice - 1))
                if (( idx >= 0 && idx < ${#ACTIVE_ENTRIES[@]} )); then
                    local target_mp
                    target_mp=$(awk '{print $2}' <<< "${ACTIVE_ENTRIES[$idx]}")
                    echo -e "${CYAN}Mounte ${target_mp}...${RESET}"
                    local output
                    output=$(mount "$target_mp" 2>&1)
                    if [[ $? -eq 0 ]]; then
                        echo -e "${GREEN}✓ ${target_mp} erfolgreich gemountet.${RESET}"
                        log_action "Gemountet: ${target_mp}"
                    else
                        echo -e "${RED}✗ Fehler:${RESET} ${output}"
                    fi
                else
                    echo -e "${RED}Ungültige Eingabe${RESET}"
                fi
            fi
            ;;
        2)  # Einzeln unmounten
            echo -e -n "\n${YELLOW}Mountpoint zum Unmounten (z.B. /mnt/data): ${RESET}"
            read -r target_mp
            if [[ -z "$target_mp" ]]; then
                echo -e "${YELLOW}Abgebrochen.${RESET}"
                press_enter
                return
            fi

            if ! findmnt --target "$target_mp" &>/dev/null 2>&1; then
                echo -e "${RED}${target_mp} ist nicht gemountet.${RESET}"
                press_enter
                return
            fi

            if confirm_action "${target_mp} unmounten?"; then
                local output
                output=$(umount "$target_mp" 2>&1)
                if [[ $? -eq 0 ]]; then
                    echo -e "${GREEN}✓ ${target_mp} erfolgreich unmountet.${RESET}"
                    log_action "Unmountet: ${target_mp}"
                else
                    echo -e "${RED}✗ Fehler:${RESET} ${output}"
                    echo -e "${GRAY}Tipp: Prüfen Sie ob noch Prozesse auf ${target_mp} zugreifen (lsof ${target_mp})${RESET}"
                fi
            fi
            ;;
    esac

    press_enter
}

# --- 11) Eintrag suchen/filtern (NEU) ---
# Beschreibung: Durchsucht alle aktiven fstab-Einträge nach
#   einem Suchbegriff (Gerät, Mountpoint, Dateisystem, UUID).
#   Groß-/Kleinschreibung wird ignoriert.
search_fstab_entries() {
    print_header
    echo -e "${YELLOW}${BOLD}fstab-Einträge suchen/filtern${RESET}\n"
    print_separator

    echo -e -n "${YELLOW}Suchbegriff eingeben (Gerät, Mountpoint, UUID, FS-Typ...): ${RESET}"
    read -r search_term

    if [[ -z "$search_term" ]]; then
        echo -e "${RED}Kein Suchbegriff eingegeben.${RESET}"
        press_enter
        return
    fi

    echo -e "\n${CYAN}Ergebnisse für '${search_term}':${RESET}\n"
    print_separator

    local found=0
    local line_num=0

    while IFS= read -r line; do
        (( line_num++ ))
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Case-insensitive Suche
        if echo "$line" | grep -qi "$search_term"; then
            # Treffer hervorheben
            local highlighted
            highlighted=$(echo "$line" | grep -i --color=never "$search_term" | \
                sed "s/${search_term}/$(printf "${BOLD}${GREEN}")&$(printf "${RESET}")/gi" 2>/dev/null || echo "$line")
            echo -e "${GRAY}Zeile ${line_num}:${RESET} ${highlighted}"
            (( found++ ))
        fi
    done < "$FSTAB_PATH"

    print_separator
    echo

    if [[ $found -eq 0 ]]; then
        echo -e "${RED}Keine Treffer gefunden.${RESET}"
    else
        echo -e "${GREEN}${found} Treffer gefunden.${RESET}"
    fi

    press_enter
}

# --- 12) fstab Export mit Erklärungen (NEU) ---
# Beschreibung: Erstellt eine Kopie der fstab in der jeder
#   Eintrag mit einer ausführlichen Erklärung der einzelnen
#   Felder versehen wird. Wird als Textdatei gespeichert.
#   Nützlich zur Dokumentation oder zum Lernen.
export_fstab_explained() {
    print_header
    echo -e "${YELLOW}${BOLD}fstab Export mit Erklärungen${RESET}\n"
    print_separator

    local output_file="/tmp/fstab_erklaert_$(date '+%Y%m%d_%H%M%S').txt"

    {
        echo "============================================================"
        echo " /etc/fstab — Dokumentierter Export"
        echo " Erstellt am: $(date '+%Y-%m-%d %H:%M:%S')"
        echo " Hostname: $(hostname 2>/dev/null || echo 'unbekannt')"
        echo "============================================================"
        echo ""
        echo "Format: <Gerät>  <Mountpoint>  <Dateisystem>  <Optionen>  <dump>  <pass>"
        echo ""
        echo "============================================================"
        echo ""

        local line_num=0
        while IFS= read -r line; do
            (( line_num++ ))

            if [[ "$line" =~ ^[[:space:]]*$ ]]; then
                echo ""
                continue
            fi

            if [[ "$line" =~ ^[[:space:]]*# ]]; then
                echo "$line"
                continue
            fi

            echo "$line"

            # Felder erklären
            local -a f
            read -ra f <<< "$line"

            echo "  │"
            echo "  ├─ Quelle:      ${f[0]:-?}"
            if [[ "${f[0]}" == UUID=* ]]; then
                echo "  │                (Identifikation über UUID — stabil bei Hardware-Änderungen)"
            elif [[ "${f[0]}" == PARTUUID=* ]]; then
                echo "  │                (Identifikation über Partitions-UUID)"
            elif [[ "${f[0]}" == LABEL=* ]]; then
                echo "  │                (Identifikation über Label — kann manuell gesetzt werden)"
            elif [[ "${f[0]}" == /dev/* ]]; then
                echo "  │                (Gerätepfad — kann sich bei Hardware-Änderungen verschieben)"
            elif [[ "${f[0]}" == "tmpfs" ]]; then
                echo "  │                (tmpfs — RAM-basiertes Dateisystem)"
            fi

            echo "  ├─ Mountpoint:  ${f[1]:-?}"
            echo "  ├─ Dateisystem: ${f[2]:-?}"

            # Optionen aufschlüsseln
            echo "  ├─ Optionen:    ${f[3]:-defaults}"
            if [[ -n "${f[3]}" ]]; then
                local IFS_BAK="$IFS"
                IFS=',' read -ra opts <<< "${f[3]}"
                IFS="$IFS_BAK"
                for opt in "${opts[@]}"; do
                    local desc=""
                    case "$opt" in
                        defaults)         desc="Standard (rw,suid,dev,exec,auto,nouser,async)" ;;
                        ro)               desc="Nur-Lesen" ;;
                        rw)               desc="Lesen und Schreiben" ;;
                        noatime)          desc="Zugriffszeitstempel nicht aktualisieren" ;;
                        nodiratime)       desc="Verzeichnis-Zeitstempel nicht aktualisieren" ;;
                        relatime)         desc="Zugriffszeitstempel nur bei Änderung" ;;
                        nosuid)           desc="SUID/SGID-Bits ignorieren (Sicherheit)" ;;
                        nodev)            desc="Gerätedateien ignorieren (Sicherheit)" ;;
                        noexec)           desc="Ausführung von Programmen verhindern" ;;
                        nofail)           desc="Kein Boot-Fehler wenn Gerät fehlt" ;;
                        auto)             desc="Automatisch mounten bei boot/mount -a" ;;
                        noauto)           desc="Nicht automatisch mounten" ;;
                        user)             desc="Normale Benutzer dürfen mounten" ;;
                        nouser)           desc="Nur Root darf mounten" ;;
                        sw)               desc="Swap-Partition" ;;
                        discard)          desc="TRIM-Unterstützung (SSD)" ;;
                        x-systemd.automount) desc="Automatisches Mounten bei Zugriff (systemd)" ;;
                        size=*)           desc="Größenlimit: ${opt#size=}" ;;
                        *)                desc="(benutzerdefiniert)" ;;
                    esac
                    [[ -n "$desc" ]] && echo "  │     └─ ${opt}: ${desc}"
                done
            fi

            echo "  ├─ dump:        ${f[4]:-0}  (0=kein Backup durch dump, 1=Backup)"
            echo "  └─ pass:        ${f[5]:-0}  (0=kein fsck, 1=Root zuerst, 2=danach)"
            echo ""
        done < "$FSTAB_PATH"

    } > "$output_file"

    echo -e "${GREEN}✓ Dokumentierte fstab exportiert nach:${RESET}"
    echo -e "  ${CYAN}${output_file}${RESET}"
    echo

    if confirm_action "Inhalt jetzt anzeigen?"; then
        echo
        cat "$output_file"
    fi

    log_action "fstab Export erstellt: ${output_file}"
    press_enter
}

# --- 13) Backup wiederherstellen ---
# Beschreibung: Zeigt die letzten 10 Backups mit Dateigröße
#   und Datum an. Nach Auswahl wird der Inhalt angezeigt und
#   nach Bestätigung wird die aktuelle fstab überschrieben.
#   Vorher wird automatisch ein Backup der aktuellen fstab
#   erstellt.
restore_backup() {
    print_header
    echo -e "${YELLOW}${BOLD}Backup wiederherstellen${RESET}\n"
    print_separator

    get_backup_list 10

    if [[ ${#BACKUP_LIST[@]} -eq 0 ]]; then
        echo -e "${RED}Keine Backups gefunden.${RESET}"
        press_enter
        return
    fi

    echo -e "${CYAN}Verfügbare Backups (neueste zuerst):${RESET}\n"
    for i in "${!BACKUP_LIST[@]}"; do
        local bname bsize bdate
        bname=$(basename "${BACKUP_LIST[$i]}")
        bsize=$(stat -c '%s' "${BACKUP_LIST[$i]}" 2>/dev/null || echo "?")
        bdate=$(stat -c '%y' "${BACKUP_LIST[$i]}" 2>/dev/null | cut -d. -f1)
        echo -e "${YELLOW}  $((i+1))${RESET} — ${bname}  ${GRAY}(${bsize} Bytes, ${bdate})${RESET}"
    done
    echo

    local choice
    while true; do
        echo -e -n "${YELLOW}Wählen Sie Backup (1-${#BACKUP_LIST[@]}, 0=Abbruch): ${RESET}"
        read -r choice
        if [[ "$choice" == "0" ]]; then
            echo -e "${YELLOW}Abgebrochen.${RESET}"
            press_enter
            return
        fi
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            if (( idx >= 0 && idx < ${#BACKUP_LIST[@]} )); then
                break
            fi
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done

    local selected="${BACKUP_LIST[$idx]}"

    echo -e "\n${CYAN}Inhalt des Backups:${RESET}"
    print_separator
    cat "$selected"
    print_separator
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

# --- 14) Backup-Diff anzeigen (NEU) ---
# Beschreibung: Vergleicht ein ausgewähltes Backup mit der
#   aktuellen fstab und zeigt die Unterschiede an. Verwendet
#   diff mit farbiger Ausgabe (grün = hinzugefügt, rot =
#   entfernt). Falls diff nicht verfügbar, wird comm verwendet.
show_backup_diff() {
    print_header
    echo -e "${YELLOW}${BOLD}Backup-Diff: Vergleich mit aktuellem Stand${RESET}\n"
    print_separator

    get_backup_list 10

    if [[ ${#BACKUP_LIST[@]} -eq 0 ]]; then
        echo -e "${RED}Keine Backups gefunden.${RESET}"
        press_enter
        return
    fi

    echo -e "${CYAN}Verfügbare Backups (neueste zuerst):${RESET}\n"
    for i in "${!BACKUP_LIST[@]}"; do
        local bname bdate
        bname=$(basename "${BACKUP_LIST[$i]}")
        bdate=$(stat -c '%y' "${BACKUP_LIST[$i]}" 2>/dev/null | cut -d. -f1)
        echo -e "${YELLOW}  $((i+1))${RESET} — ${bname}  ${GRAY}(${bdate})${RESET}"
    done
    echo

    local choice
    while true; do
        echo -e -n "${YELLOW}Welches Backup vergleichen? (1-${#BACKUP_LIST[@]}, 0=Abbruch): ${RESET}"
        read -r choice
        [[ "$choice" == "0" ]] && { press_enter; return; }
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            local idx=$((choice - 1))
            (( idx >= 0 && idx < ${#BACKUP_LIST[@]} )) && break
        fi
        echo -e "${RED}Ungültige Eingabe${RESET}"
    done

    local selected="${BACKUP_LIST[$idx]}"

    echo -e "\n${CYAN}Unterschiede: $(basename "$selected") ↔ aktuelle fstab${RESET}"
    print_separator

    if command -v diff &>/dev/null; then
        local diff_output
        diff_output=$(diff --unified=3 "$selected" "$FSTAB_PATH" 2>&1)
        if [[ -z "$diff_output" ]]; then
            echo -e "${GREEN}✓ Keine Unterschiede — Backup und aktuelle fstab sind identisch.${RESET}"
        else
            # Farbige Ausgabe
            while IFS= read -r dline; do
                if [[ "$dline" == ---* || "$dline" == +++* ]]; then
                    echo -e "${BOLD}${dline}${RESET}"
                elif [[ "$dline" == @@* ]]; then
                    echo -e "${CYAN}${dline}${RESET}"
                elif [[ "$dline" == +* ]]; then
                    echo -e "${GREEN}${dline}${RESET}"
                elif [[ "$dline" == -* ]]; then
                    echo -e "${RED}${dline}${RESET}"
                else
                    echo "$dline"
                fi
            done <<< "$diff_output"
        fi
    else
        echo -e "${YELLOW}diff nicht verfügbar. Zeige beide Dateien nebeneinander:${RESET}"
        echo
        echo -e "${RED}=== Backup ===${RESET}"
        cat "$selected"
        echo
        echo -e "${GREEN}=== Aktuell ===${RESET}"
        cat "$FSTAB_PATH"
    fi

    print_separator
    press_enter
}

# --- 15) Alte Backups aufräumen ---
# (siehe cleanup_backups oben)

# --- 16) System neu starten ---
# Beschreibung: Startet das System nach Bestätigung und
#   konfiguriertem Countdown neu. Der Countdown kann
#   zwischen 0 (Abbruch) und 300 Sekunden betragen.
#   Ctrl+C bricht den Countdown ab.
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

    # Visueller Countdown
    for (( i = countdown; i > 0; i-- )); do
        printf "\r${RED}Neustart in %3d Sekunden... ${RESET}" "$i"
        sleep 1
    done
    echo

    reboot
}

# ============================================================
# BEENDEN
# Beschreibung: Räumt auf und beendet das Programm sauber.
# ============================================================
shutdown_program() {
    clear_screen
    echo -e "${YELLOW}${BOLD}Auf Wiedersehen!${RESET}"
    echo -e "${GREEN}fstab Manager v${VERSION} wird beendet.${RESET}"
    log_action "Programm beendet"
    exit 0
}

# ============================================================
# HAUPTSCHLEIFE
# Beschreibung: Initialisiert das Programm (sudo-Check,
#   Backup-Verzeichnis) und zeigt das Hauptmenü in einer
#   Endlosschleife an. Jede Benutzereingabe wird an die
#   entsprechende Funktion weitergeleitet.
# ============================================================
main() {
    check_sudo
    create_backup_dir
    log_action "Programm gestartet (v${VERSION})"

    while true; do
        print_menu
        echo -e -n "${YELLOW}Wählen Sie eine Option (0-16): ${RESET}"
        read -r choice

        case "$choice" in
            1)  add_fstab_entry        ;;
            2)  mount_tmp_to_ram       ;;
            3)  create_ramdisk         ;;
            4)  show_fstab             ;;
            5)  delete_fstab_entry     ;;
            6)  edit_fstab_entry       ;;
            7)  validate_fstab_syntax  ;;
            8)  show_partitions        ;;
            9)  check_mount_status     ;;
            10) mount_unmount_entries  ;;
            11) search_fstab_entries   ;;
            12) export_fstab_explained ;;
            13) restore_backup         ;;
            14) show_backup_diff       ;;
            15) cleanup_backups        ;;
            16) restart_system         ;;
            0)  shutdown_program       ;;
            *)
                echo -e "${RED}Ungültige Eingabe. Bitte 0-16 eingeben.${RESET}"
                press_enter
                ;;
        esac
    done
}

# ============================================================
# SIGNAL HANDLING & START
# Beschreibung: Fängt Ctrl+C ab und beendet das Programm
#   sauber. ORIG_ARGS speichert die Startparameter für die
#   korrekte Weitergabe an sudo.
# ============================================================
ORIG_ARGS=("$@")
trap 'echo -e "\n${RED}Programm durch Benutzer unterbrochen (Ctrl+C)${RESET}"; log_action "Durch Ctrl+C beendet"; exit 0' INT

main
