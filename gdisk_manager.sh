#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# gdisk_manager.sh – Linux Partitionsverwaltung mit sgdisk
# Unterstützt: GPT, EFI, vfat · exfat · ext4 · xfs · jfs · btrfs
#
# Verwendung: sudo bash gdisk_manager.sh [/dev/GERÄT]
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
IFS=$'
\t'


# ── Konstanten ─────────────────────────────────────────────────────────────────

readonly LINE='──────────────────────────────────────────────────────────────────────'
readonly LINE2='══════════════════════════════════════════════════════════════════════'
readonly SCRIPT_NAME="$(basename "\$0")"

# Dateisystem-Definitionen: "fs_name|mkfs_cmd|beschreibung"
readonly -a FILESYSTEMS=(
    "vfat|mkfs.vfat|FAT32   (EFI / Boot)"
    "exfat|mkfs.exfat|exFAT  (Portabel / Windows-kompatibel)"
    "ext4|mkfs.ext4|ext4    (Linux Standard)"
    "xfs|mkfs.xfs|XFS     (High Performance)"
    "jfs|mkfs.jfs|JFS     (IBM Journaling)"
    "btrfs|mkfs.btrfs|Btrfs   (Modern Copy-on-Write)"
)

# Partitionstypen: "code|beschreibung"
readonly -a PARTITION_TYPES=(
    "ef00|EFI System Partition"
    "8300|Linux Filesystem"
    "8200|Linux Swap"
    "8302|Linux /home"
    "ef02|BIOS Boot Partition"
)

# Label-Limits je Dateisystem
declare -A LABEL_LIMITS=(
    [vfat]=11  [exfat]=15 [ext4]=16
    [xfs]=12   [jfs]=16   [btrfs]=256
)

# Globale Gerätevariable
DEVICE=""


# ── Hilfsfunktionen ────────────────────────────────────────────────────────────

# Gibt ein Feld aus einem |-getrennten Eintrag zurück (1-basiert)
_field() {
    echo "${1}" | cut -d'|' -f"${2}"
}

# Gibt den korrekten Partitionspfad zurück (NVMe/eMMC-kompatibel)
partition_device() {
    local device="${1}" num="${2}"
    if [[ "${device}" == *nvme* || "${device}" == *mmcblk* ]]; then
        echo "${device}p${num}"
    else
        echo "${device}${num}"
    fi
}

# Kürzt einen String auf die angegebene Maximallänge
truncate_label() {
    local label="${1}" limit="${2}"
    echo "${label:0:${limit}}"
}


# ── Voraussetzungen ────────────────────────────────────────────────────────────

# check_root() {
#    if [[ "${EUID}" -ne 0 ]]; then
#        echo "❌ Fehler: ${SCRIPT_NAME} muss als root ausgeführt werden!"
#        echo "   Verwendung: sudo bash ${SCRIPT_NAME}"
#        exit 1
#    fi
#}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "  🔐 Root-Rechte erforderlich – sudo Passwort eingeben:"
        exec sudo bash "${BASH_SOURCE[0]}" "$@"
    fi
}

check_gdisk() {
    if ! command -v sgdisk &>/dev/null; then
        echo "❌ Fehler: sgdisk ist nicht installiert!"
        echo "   Debian/Ubuntu : sudo apt install gdisk"
        echo "   Arch Linux    : sudo pacman -S gptfdisk"
        exit 1
    fi
}

check_missing_tools() {
    local -a missing=()
    local entry mkfs_cmd

    for entry in "${FILESYSTEMS[@]}"; do
        mkfs_cmd="$(_field "${entry}" 2)"
        command -v "${mkfs_cmd}" &>/dev/null || missing+=("${mkfs_cmd}")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "  ⚠️  Fehlende mkfs-Werkzeuge: ${missing[*]}"
        echo "     Installation:"
        echo "       sudo apt install e2fsprogs xfsprogs jfsutils btrfs-progs exfatprogs dosfstools"
        return 1
    fi
    return 0
}


# ── UI-Hilfsfunktionen ─────────────────────────────────────────────────────────

_clear() { clear; }
_pause() { read -rp $'
  [ Enter ] zurück zum Menü …'; }

_header() {
    local subtitle="${1:-}"
    _clear
    echo "${LINE2}"
    echo "  🖥️   LINUX PARTITIONSVERWALTUNG  –  GPT / EFI"
    echo "${LINE2}"
    echo "  Gerät : ${DEVICE}"
    [[ -n "${subtitle}" ]] && echo "  Aktion: ${subtitle}"
    echo "${LINE2}"
}

_confirm() {
    local prompt="${1}"
    local answer
    read -rp $"
  ⚠️   ${prompt}
  [ja / nein]: " answer
    [[ "${answer,,}" == "ja" ]]
}

# Zeigt eine nummerierte Auswahlliste; setzt globale Variable CHOSEN_INDEX (0-basiert)
CHOSEN_INDEX=-1
_choose() {
    local prompt="${1}"; shift
    local -a items=("$@")
    local i raw

    for (( i=0; i<${#items[@]}; i++ )); do
        printf "    %d.  %s
" $(( i + 1 )) "${items[${i}]}"
    done

    read -rp $"
  ${prompt} (1–${#items[@]}): " raw

    if [[ "${raw}" =~ ^[0-9]+$ ]] && (( raw >= 1 && raw <= ${#items[@]} )); then
        CHOSEN_INDEX=$(( raw - 1 ))
        return 0
    fi

    echo "  ❌ Ungültige Auswahl!"
    CHOSEN_INDEX=-1
    return 1
}

_show_partition_table() {
    echo ""
    printf "  %-58s

" "Aktuelle Partitionstabelle ──────────────────────────────────"
    sgdisk -p "${DEVICE}" 2>&1 || true
    echo "${LINE}"
}


# ── sgdisk-Operationen ─────────────────────────────────────────────────────────

sgdisk_list() {
    sgdisk -p "${DEVICE}" 2>&1
}

sgdisk_create_partition() {
    local start="${1}" end="${2}" type_code="${3}"
    local size_arg

    # Größenangabe zusammenbauen: "start:end" – leer = 0 (sgdisk-Standard)
    local s="${start:-0}"
    local e="${end:-0}"
    sgdisk -n "0:${s}:${e}" -t "0:${type_code}" "${DEVICE}"
}

sgdisk_delete_partition() {
    local num="${1}"
    sgdisk -d "${num}" "${DEVICE}"
}

sgdisk_change_type() {
    local num="${1}" type_code="${2}"
    sgdisk -t "${num}:${type_code}" "${DEVICE}"
}


# ── Dateisystem-Operationen ────────────────────────────────────────────────────

format_partition() {
    local part="${1}" fs_name="${2}" label="${3:-}"
    local mkfs_cmd limit truncated_label entry
    local -a cmd=()

    # mkfs-Befehl ermitteln
    for entry in "${FILESYSTEMS[@]}"; do
        if [[ "$(_field "${entry}" 1)" == "${fs_name}" ]]; then
            mkfs_cmd="$(_field "${entry}" 2)"
            break
        fi
    done

    limit="${LABEL_LIMITS[${fs_name}]}"
    truncated_label="$(truncate_label "${label}" "${limit}")"

    cmd=("${mkfs_cmd}")

    case "${fs_name}" in
        vfat)
            cmd+=("-F" "32")
            [[ -n "${truncated_label}" ]] && cmd+=("-n" "${truncated_label}")
            ;;
        xfs)
            cmd+=("-f")
            [[ -n "${truncated_label}" ]] && cmd+=("-L" "${truncated_label}")
            ;;
        exfat)
            [[ -n "${truncated_label}" ]] && cmd+=("-n" "${truncated_label}")
            ;;
        *)
            [[ -n "${truncated_label}" ]] && cmd+=("-L" "${truncated_label}")
            ;;
    esac

    cmd+=("${part}")

    if "${cmd[@]}" &>/dev/null; then
        return 0
    else
        return 1
    fi
}


# ── Menü-Aktionen ──────────────────────────────────────────────────────────────

action_show_partitions() {
    _header "Partitionstabelle anzeigen"
    echo ""
    sgdisk_list
    _pause
}

action_create_partition() {
    _header "Neue Partition erstellen"
    _show_partition_table

    local start end ptype_entry ptype_code
    local -a ptype_labels=()

    read -rp "  Startsektor (Enter = nächster freier Sektor): " start
    read -rp "  Endsektor / Größe  (z.B. +20G, +512M):       " end

    if [[ -z "${end}" ]]; then
        echo "  ❌ Endsektor / Größe ist erforderlich!"
        _pause; return
    fi

    local entry
    for entry in "${PARTITION_TYPES[@]}"; do
        ptype_labels+=("$(_field "${entry}" 2)  [$(_field "${entry}" 1)]")
    done

    echo ""
    echo "  Partitionstyp wählen:"
    echo ""
    if ! _choose "Partitionstyp" "${ptype_labels[@]}"; then
        _pause; return
    fi

    ptype_entry="${PARTITION_TYPES[${CHOSEN_INDEX}]}"
    ptype_code="$(_field "${ptype_entry}" 1)"

    echo "  ⏳ Erstelle Partition (${start:-Auto} → ${end}) …"

    if sgdisk_create_partition "${start}" "${end}" "${ptype_code}"; then
        echo "  ✅ Partition erfolgreich erstellt!"
    else
        echo "  ❌ Fehler beim Erstellen der Partition!"
    fi

    _pause
}

action_delete_partition() {
    _header "Partition löschen"
    _show_partition_table

    local num
    read -rp "  Partitionsnummer zum Löschen: " num

    if ! [[ "${num}" =~ ^[0-9]+$ ]]; then
        echo "  ❌ Bitte eine gültige Zahl eingeben!"
        _pause; return
    fi

    if ! _confirm "Partition ${num} wirklich löschen? Alle Daten gehen unwiderruflich verloren!"; then
        echo "  Abgebrochen."
        _pause; return
    fi

    echo "  ⏳ Lösche Partition ${num} …"

    if sgdisk_delete_partition "${num}"; then
        echo "  ✅ Partition erfolgreich gelöscht!"
    else
        echo "  ❌ Fehler beim Löschen der Partition!"
    fi

    _pause
}

action_change_type() {
    _header "Partitionstyp ändern"
    _show_partition_table

    local num ptype_entry ptype_code
    local -a ptype_labels=()

    read -rp "  Partitionsnummer: " num

    if ! [[ "${num}" =~ ^[0-9]+$ ]]; then
        echo "  ❌ Bitte eine gültige Zahl eingeben!"
        _pause; return
    fi

    local entry
    for entry in "${PARTITION_TYPES[@]}"; do
        ptype_labels+=("$(_field "${entry}" 2)  [$(_field "${entry}" 1)]")
    done

    echo ""
    echo "  Neuer Partitionstyp:"
    echo ""
    if ! _choose "Partitionstyp" "${ptype_labels[@]}"; then
        _pause; return
    fi

    ptype_entry="${PARTITION_TYPES[${CHOSEN_INDEX}]}"
    ptype_code="$(_field "${ptype_entry}" 1)"

    echo "  ⏳ Ändere Partition ${num} → $(_field "${ptype_entry}" 2) …"

    if sgdisk_change_type "${num}" "${ptype_code}"; then
        echo "  ✅ Partitionstyp erfolgreich geändert!"
    else
        echo "  ❌ Fehler beim Ändern des Partitionstyps!"
    fi

    _pause
}

action_format_partition() {
    _header "Partition formatieren"

    if ! check_missing_tools; then
        _pause; return
    fi

    local part label fs_entry fs_name
    local -a fs_labels=()

    read -rp $'
  Partitionsgerät (z.B. /dev/sda1 oder /dev/nvme0n1p1): ' part

    if [[ "${part}" != /dev/* ]]; then
        echo "  ❌ Ungültiges Format (muss mit /dev/ beginnen)!"
        _pause; return
    fi

    if [[ ! -b "${part}" ]]; then
        echo "  ❌ Gerät ${part} existiert nicht oder ist kein Block-Device!"
        _pause; return
    fi

    local entry
    for entry in "${FILESYSTEMS[@]}"; do
        fs_labels+=("$(_field "${entry}" 3)")
    done

    echo ""
    echo "  Dateisystem wählen:"
    echo ""
    if ! _choose "Dateisystem" "${fs_labels[@]}"; then
        _pause; return
    fi

    fs_entry="${FILESYSTEMS[${CHOSEN_INDEX}]}"
    fs_name="$(_field "${fs_entry}" 1)"

    read -rp "  Label (optional, Enter überspringen): " label

    if ! _confirm "${part} mit ${fs_name} formatieren?"; then
        echo "  Abgebrochen."
        _pause; return
    fi

    echo "  ⏳ Formatiere ${part} …"

    if format_partition "${part}" "${fs_name}" "${label}"; then
        echo "  ✅ ${part} erfolgreich mit ${fs_name} formatiert!"
        [[ -n "${label}" ]] && echo "     Label: ${label}"
    else
        echo "  ❌ Fehler beim Formatieren!"
    fi

    _pause
}

action_quick_partition() {
    _header "⚡ Schnellpartitionierung – EFI + Root"
    echo ""
    echo "  Erstellt automatisch:"
    echo ""
    echo "    •  EFI System Partition  –  512 MB            –  FAT32 (vfat)"
    echo "    •  Root-Partition        –  restlicher Platz  –  frei wählbar"
    echo ""
    echo "${LINE}"

    if ! _confirm "Alle vorhandenen Daten auf ${DEVICE} werden überschrieben. Wirklich fortfahren?"; then
        echo "  Abgebrochen."
        _pause; return
    fi

    # Root-Dateisystem wählen (vfat bleibt EFI vorbehalten)
    local -a root_fs_entries=() root_fs_labels=()
    local entry

    for entry in "${FILESYSTEMS[@]}"; do
        [[ "$(_field "${entry}" 1)" == "vfat" ]] && continue
        root_fs_entries+=("${entry}")
        root_fs_labels+=("$(_field "${entry}" 3)")
    done

    echo ""
    echo "  Dateisystem für die Root-Partition:"
    echo ""
    if ! _choose "Dateisystem" "${root_fs_labels[@]}"; then
        _pause; return
    fi

    local root_fs_entry="${root_fs_entries[${CHOSEN_INDEX}]}"
    local root_fs_name="$(_field "${root_fs_entry}" 1)"
    local efi_label root_label

    read -rp $'
  EFI-Label  (Standard: EFI):  ' efi_label
    read -rp    "  Root-Label (Standard: ROOT): " root_label
    efi_label="${efi_label:-EFI}"
    root_label="${root_label:-ROOT}"

    echo ""
    echo "${LINE}"

    # Schritt 1 – Partitionstabelle leeren
    echo "  ⏳ [0/4]  Leere bestehende Partitionstabelle …"
    if ! sgdisk -Z "${DEVICE}" &>/dev/null; then
        echo "  ❌ Fehler beim Leeren der Partitionstabelle!"; _pause; return
    fi
    echo "  ✅  Partitionstabelle geleert."

    # Schritt 2 – EFI-Partition
    echo "  ⏳ [1/4]  Erstelle EFI-Partition (512 MB) …"
    if ! sgdisk -n "1:0:+512M" -t "1:ef00" "${DEVICE}" &>/dev/null; then
        echo "  ❌ Fehler beim Erstellen der EFI-Partition!"; _pause; return
    fi
    echo "  ✅  EFI-Partition angelegt."

    # Schritt 3 – Root-Partition
    echo "  ⏳ [2/4]  Erstelle Root-Partition (restlicher Platz) …"
    if ! sgdisk -n "2:0:0" -t "2:8300" "${DEVICE}" &>/dev/null; then
        echo "  ❌ Fehler beim Erstellen der Root-Partition!"; _pause; return
    fi
    echo "  ✅  Root-Partition angelegt."

    local efi_part root_part
    efi_part="$(partition_device "${DEVICE}" 1)"
    root_part="$(partition_device "${DEVICE}" 2)"

    # Schritt 4 – EFI formatieren
    echo "  ⏳ [3/4]  Formatiere ${efi_part} mit FAT32 …"
    if ! format_partition "${efi_part}" "vfat" "${efi_label}"; then
        echo "  ❌ Fehler beim Formatieren der EFI-Partition!"; _pause; return
    fi
    echo "  ✅  ${efi_part} formatiert  (FAT32 · Label: ${efi_label})."

    # Schritt 5 – Root formatieren
    echo "  ⏳ [4/4]  Formatiere ${root_part} mit ${root_fs_name} …"
    if ! format_partition "${root_part}" "${root_fs_name}" "${root_label}"; then
        echo "  ❌ Fehler beim Formatieren der Root-Partition!"; _pause; return
    fi
    echo "  ✅  ${root_part} formatiert  (${root_fs_name} · Label: ${root_label})."

    # Zusammenfassung
    echo ""
    echo "${LINE2}"
    echo "  ✅   SCHNELLPARTITIONIERUNG ERFOLGREICH ABGESCHLOSSEN!"
    echo "${LINE2}"
    printf "
  EFI-Partition : %-18s 512 MB   FAT32          Label: %s
" \
        "${efi_part}" "${efi_label}"
    printf "  Root-Partition: %-18s Rest     %-14s Label: %s
" \
        "${root_part}" "${root_fs_name}" "${root_label}"
    echo ""
    echo "  Nächste Schritte:"
    echo "    sudo mount ${root_part} /mnt"
    echo "    sudo mkdir -p /mnt/boot/efi"
    echo "    sudo mount ${efi_part} /mnt/boot/efi"
    echo "${LINE2}"

    _pause
}

action_change_device() {
    _header "Gerät wechseln"

    echo ""
    echo "  Verfügbare Block-Geräte:"
    echo ""
    lsblk -d -o NAME,SIZE,TYPE,MODEL --noheadings 2>/dev/null \
        | while IFS= read -r line; do echo "    ${line}"; done

    local new_device
    read -rp $'
  Gerät eingeben (z.B. /dev/sda): ' new_device

    if [[ "${new_device}" != /dev/* ]]; then
        echo "  ❌ Ungültiges Format (muss mit /dev/ beginnen)!"
        _pause; return
    fi

    if [[ ! -b "${new_device}" ]]; then
        echo "  ❌ Gerät ${new_device} existiert nicht oder ist kein Block-Device!"
        _pause; return
    fi

    DEVICE="${new_device}"
    echo "  ✅ Gerät erfolgreich gewechselt zu ${DEVICE}."

    _pause
}


# ── Hauptmenü ──────────────────────────────────────────────────────────────────

main_menu() {
    local choice

    while true; do
        _header
        echo ""
        echo "  HAUPTMENÜ"
        echo ""
        echo "  [1]     Partitionstabelle anzeigen"
        echo "  [2]     Neue Partition erstellen"
        echo "  [3]     Partition löschen"
        echo "  [4]     Partitionstyp ändern"
        echo "  [5]     Partition formatieren"
        echo "  [6]  ⚡ Schnellpartitionierung  EFI + Root"
        echo "  [7]     Gerät wechseln"
        echo ""
        echo "  [0]     Beenden"
        echo ""

        read -rp "  Auswahl: " choice

        case "${choice}" in
            1) action_show_partitions  ;;
            2) action_create_partition ;;
            3) action_delete_partition ;;
            4) action_change_type      ;;
            5) action_format_partition ;;
            6) action_quick_partition  ;;
            7) action_change_device    ;;
            0)
                echo ""
                echo "  👋  Auf Wiedersehen!"
                echo ""
                exit 0
                ;;
            *)
                echo "  ❌ Ungültige Eingabe – bitte 0–7 wählen."
                _pause
                ;;
        esac
    done
}


# ── Einstiegspunkt ─────────────────────────────────────────────────────────────

main() {
    check_root
    check_gdisk

    if [[ -n "${1:-}" ]]; then
        DEVICE="${1}"
    else
        echo "${LINE2}"
        echo "  🖥️   LINUX PARTITIONSVERWALTUNG  –  GPT / EFI"
        echo "${LINE2}"
        echo ""
        echo "  Verfügbare Block-Geräte:"
        echo ""

        lsblk -d -o NAME,SIZE,TYPE,MODEL --noheadings 2>/dev/null \
            | while IFS= read -r line; do echo "    ${line}"; done \
            || echo "  (lsblk nicht verfügbar)"

        read -rp $'
  Gerät eingeben (z.B. /dev/sda): ' DEVICE
    fi

    if [[ "${DEVICE}" != /dev/* ]]; then
        echo "❌ Ungültiges Gerätformat!"
        exit 1
    fi

    if [[ ! -b "${DEVICE}" ]]; then
        echo "❌ Gerät ${DEVICE} existiert nicht oder ist kein Block-Device!"
        exit 1
    fi

    main_menu
}

trap 'echo ""; echo "  👋  Abgebrochen (Strg+C). Auf Wiedersehen!"; echo ""; exit 0' INT
trap 'echo ""; echo "❌ Kritischer Fehler in Zeile ${LINENO}. Abbruch."; exit 1' ERR

main "$@"
