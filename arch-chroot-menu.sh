#!/usr/bin/env bash
# ================================================================
#  arch-chroot-menu.sh  –  v3.0
#  Interaktives Menü zum Chrooten in eine Arch Linux Installation
#  EFI · Automount · Trap-Cleanup · Erweiterte Funktionen
#
#  Verwendung:  bash arch-chroot-menu.sh [OPTIONEN]
#  Optionen:    -m <pfad>   Mountpoint (Standard: /mnt)
#               -l <datei>  Protokoll in Datei schreiben
#               -h          Hilfe anzeigen
#  Benötigt:    arch-install-scripts (arch-chroot, genfstab)
# ================================================================

# kein set -e: interaktive Skripte brauchen explizite Fehlerbehandlung
set -uo pipefail

readonly VERSION="3.0"

# ── Farben (deaktiviert wenn stdout kein TTY) ─────────────────────
if [[ -t 1 ]]; then
    readonly RED='\033[1;31m'
    readonly GRN='\033[1;32m'
    readonly YLW='\033[1;33m'
    readonly BLU='\033[1;34m'
    readonly CYN='\033[1;36m'
    readonly WHT='\033[1;37m'
    readonly DIM='\033[2m'
    readonly RST='\033[0m'
else
    # shellcheck disable=SC2034
    readonly RED='' GRN='' YLW='' BLU='' CYN='' WHT='' DIM='' RST=''
fi

# ── Globale Variablen ─────────────────────────────────────────────
CHROOT_DIR="/mnt"
MOUNT_ROOT=""
MOUNT_EFI=""
LOG_FILE=""
# Verhindert spuriösen Cleanup-Trap vor dem ersten Mount
MOUNTED_BY_US=false

# ── Logging ───────────────────────────────────────────────────────
_log() { [[ -n "$LOG_FILE" ]] && printf "[%s] %s\n" "$(date '+%F %T')" "$*" >> "$LOG_FILE"; }
info()  { printf "${BLU}[INFO]${RST}   %s\n"   "$*";     _log "INFO  $*"; }
ok()    { printf "${GRN}[OK]${RST}     %s\n"   "$*";     _log "OK    $*"; }
warn()  { printf "${YLW}[WARN]${RST}   %s\n"   "$*" >&2; _log "WARN  $*"; }
error() { printf "${RED}[FEHLER]${RST} %s\n"   "$*" >&2; _log "ERROR $*"; }
die()   { error "$*"; exit 1; }

# ── Hilfe ─────────────────────────────────────────────────────────
print_help() {
    cat <<EOF
Verwendung: $(basename "$0") [OPTIONEN]

Optionen:
  -m, --mountpoint <pfad>   Chroot-Zielverzeichnis (Standard: /mnt)
  -l, --log <datei>         Protokoll in Datei schreiben
  -h, --help                Diese Hilfe anzeigen

Beispiele:
  $(basename "$0")
  $(basename "$0") -m /mnt/arch
  $(basename "$0") -m /mnt -l /tmp/chroot-session.log
EOF
}

# ── Argumente parsen ──────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--mountpoint)
                [[ -z "${2:-}" ]] && die "Option '$1' benötigt ein Argument."
                CHROOT_DIR="$2"; shift 2 ;;
            -l|--log)
                [[ -z "${2:-}" ]] && die "Option '$1' benötigt ein Argument."
                LOG_FILE="$2"; shift 2 ;;
            -h|--help)
                print_help; exit 0 ;;
            *)
                die "Unbekannte Option: '$1'. Verwende -h für Hilfe." ;;
        esac
    done
}

# ── Sudo-Eskalation ───────────────────────────────────────────────
# Startet sich selbst mit sudo neu → Passwortabfrage direkt beim Start.
require_root() {
    if [[ $EUID -ne 0 ]]; then
        printf "${YLW}Root-Rechte erforderlich – sudo wird angefragt …${RST}\n"
        exec sudo -- "$0" "$@"
        # exec ersetzt den Prozess; was folgt wird nie erreicht
        die "sudo konnte nicht ausgeführt werden."
    fi
}

# ── Cleanup-Trap ──────────────────────────────────────────────────
# Hängt automatisch aus bei Ctrl+C, kill oder unbehandeltem Fehler.
_cleanup() {
    local sig="${1:-EXIT}"
    if [[ "$MOUNTED_BY_US" == true ]]; then
        printf "\n"
        warn "Signal ${sig} empfangen – räume auf …"
        umount_all
    fi
}
trap '_cleanup EXIT'          EXIT
trap '_cleanup INT;  exit 130' INT
trap '_cleanup TERM; exit 143' TERM

# ── Banner ────────────────────────────────────────────────────────
print_banner() {
    clear
    printf "${CYN}"
    printf "  ╔══════════════════════════════════════════════════╗\n"
    printf "  ║      Arch Linux  ·  chroot  Helper  v%-10s  ║\n" "$VERSION"
    printf "  ║      EFI  ·  Automount  ·  Cleanup-Trap          ║\n"
    printf "  ╚══════════════════════════════════════════════════╝\n"
    printf "${RST}"
    [[ -n "$LOG_FILE" ]]       && printf "  ${DIM}Protokoll : %s${RST}\n" "$LOG_FILE"
    [[ "$CHROOT_DIR" != "/mnt" ]] && printf "  ${DIM}Mountpoint: %s${RST}\n" "$CHROOT_DIR"
    printf "\n"
}

# ── Blockgeräte auflisten ─────────────────────────────────────────
list_devices() {
    printf "${WHT}Verfügbare Blockgeräte:${RST}\n"
    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT 2>/dev/null \
        || lsblk 2>/dev/null \
        || printf "(lsblk nicht verfügbar)\n"
    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
}

# ── Partition interaktiv wählen ───────────────────────────────────
# Verwendung: select_partition "Prompt" varname [optional=false]
# Schreibt Ergebnis sicher per printf -v (kein eval).
select_partition() {
    local prompt="$1"
    local varname="$2"
    local optional="${3:-false}"
    local part=""

    printf "\n"
    list_devices
    printf "\n"

    while true; do
        printf "${YLW}%s${RST} (z.B. /dev/sda2" "$prompt"
        [[ "$optional" == true ]] && printf ", Enter = überspringen"
        printf "): "
        read -r part

        # Leerzeichen trimmen
        part="${part// /}"

        if [[ -z "$part" ]]; then
            if [[ "$optional" == true ]]; then
                printf -v "$varname" '%s' ""
                return 0
            fi
            warn "Pflichtfeld – bitte eine Partition angeben."
            continue
        fi

        if [[ -b "$part" ]]; then
            printf -v "$varname" '%s' "$part"
            ok "Gewählt: $part"
            return 0
        fi

        error "'$part' ist kein gültiges Blockgerät."
    done
}

# ── Bestätigungsdialog (wiederverwendbar) ─────────────────────────
# Verwendung: confirm "Frage?" && echo "Ja-Pfad"
# Rückgabe: 0 = Ja, 1 = Nein
confirm() {
    local prompt="${1:-Fortfahren?}"
    local ans=""
    printf "${YLW}%s [j/N]: ${RST}" "$prompt"
    read -r ans
    ans="${ans,,}"   # Kleinbuchstaben (bash 4+)
    case "$ans" in
        j|ja|y|yes) return 0 ;;
        *)           return 1 ;;
    esac
}

# ── Verzeichnis sicherstellen ─────────────────────────────────────
ensure_dir() {
    [[ -d "$1" ]] || mkdir -p -- "$1"
}

# ── Sicher mounten ────────────────────────────────────────────────
# safe_mount <quelle> <ziel> [mount-optionen …]
safe_mount() {
    local src="$1"
    local dst="$2"
    shift 2

    if mountpoint -q "$dst" 2>/dev/null; then
        warn "$dst ist bereits eingehängt – wird übersprungen."
        return 0
    fi

    ensure_dir "$dst"

    if mount "$@" -- "$src" "$dst"; then
        ok "Eingehängt: $src → $dst"
    else
        warn "Konnte nicht einhängen: $src → $dst"
        return 1
    fi
}

# ── Virtuelle Dateisysteme binden ─────────────────────────────────
bind_virtual_fs() {
    local base="$1"
    info "Binde virtuelle Dateisysteme …"

    safe_mount proc     "${base}/proc"    -t proc     -o nosuid,noexec,nodev
    safe_mount sys      "${base}/sys"     -t sysfs    -o nosuid,noexec,nodev,ro
    safe_mount devtmpfs "${base}/dev"     -t devtmpfs -o mode=0755,nosuid
    safe_mount devpts   "${base}/dev/pts" -t devpts   -o mode=0620,gid=5,nosuid,noexec
    safe_mount shm      "${base}/dev/shm" -t tmpfs    -o mode=1777,nosuid,nodev
    safe_mount run      "${base}/run"     -t tmpfs    -o nosuid,nodev,mode=0755
    safe_mount tmp      "${base}/tmp"     -t tmpfs    -o mode=1777,strictatime,nodev,nosuid

    # efivarfs – nur wenn EFI-Variablen im laufenden Kernel vorhanden
    local efipath="${base}/sys/firmware/efi/efivars"
    if [[ -d /sys/firmware/efi/efivars ]]; then
        ensure_dir "$efipath"
        if ! mountpoint -q "$efipath" 2>/dev/null; then
            if mount -t efivarfs efivarfs "$efipath"; then
                ok "efivarfs eingehängt: $efipath"
            else
                warn "efivarfs konnte nicht eingehängt werden (nicht kritisch)."
            fi
        fi
    fi

    ok "Virtuelle Dateisysteme bereit."
}

# ── DNS in chroot weiterleiten ────────────────────────────────────
setup_resolv() {
    local dst="${CHROOT_DIR}/etc/resolv.conf"
    if [[ -f /etc/resolv.conf ]]; then
        if cp -- /etc/resolv.conf "$dst" 2>/dev/null; then
            ok "resolv.conf übernommen → Netzwerk im chroot verfügbar."
        else
            warn "resolv.conf konnte nicht kopiert werden."
        fi
    fi
}

# ── Separate /boot-Partition aus fstab erkennen ───────────────────
# Unterstützt: UUID=, LABEL=, PARTUUID=, /dev/…
detect_boot_partition() {
    local fstab="${CHROOT_DIR}/etc/fstab"
    [[ -f "$fstab" ]] || return 0

    local spec mntpt _rest
    while read -r spec mntpt _rest; do
        # Kommentare & Leerzeilen überspringen
        [[ "$spec" =~ ^# ]] && continue
        [[ -z "$spec"     ]] && continue
        [[ "$mntpt" == "/boot" ]] || continue

        local dev=""
        case "$spec" in
            UUID=*)
                dev=$(blkid -U "${spec#UUID=}" 2>/dev/null) ;;
            LABEL=*)
                dev=$(blkid -L "${spec#LABEL=}" 2>/dev/null) ;;
            PARTUUID=*)
                dev=$(blkid --match-token "PARTUUID=${spec#PARTUUID=}" \
                            -o device 2>/dev/null | head -1) ;;
            /dev/*)
                dev="$spec" ;;
        esac

        if [[ -n "$dev" && "$dev" != "$MOUNT_ROOT" && -b "$dev" ]]; then
            info "Separate /boot-Partition erkannt: $dev"
            safe_mount "$dev" "${CHROOT_DIR}/boot"
        fi
        return 0   # erste /boot-Zeile auswerten, dann fertig

    done < "$fstab"
}

# ── Alle Dateisysteme unter CHROOT_DIR aushängen ─────────────────
umount_all() {
    if ! mountpoint -q "$CHROOT_DIR" 2>/dev/null; then
        info "Nichts eingehängt unter ${CHROOT_DIR}."
        MOUNTED_BY_US=false
        return 0
    fi

    info "Hänge alle Dateisysteme aus (${CHROOT_DIR}) …"

    # Lazy-Recursive-Unmount: zuverlässigste Methode für chroot-Bäume
    if umount -R --lazy "$CHROOT_DIR" 2>/dev/null; then
        ok "Alle Dateisysteme erfolgreich ausgehängt."
        MOUNTED_BY_US=false
    else
        warn "Einige Dateisysteme konnten nicht ausgehängt werden."
        warn "Manuell prüfen: findmnt | grep ${CHROOT_DIR}"
    fi
}

# ── Gemeinsames Mount-Setup ───────────────────────────────────────
# Kapselt den wiederholten Mount-Ablauf aus do_chroot / do_mount_only.
_do_mount_setup() {
    MOUNT_ROOT=""
    MOUNT_EFI=""

    printf "${WHT}─── Schritt 1 / 3  ·  Root-Partition ───${RST}\n"
    select_partition "Root-Partition (/) der Arch-Installation" MOUNT_ROOT false

    printf "\n${WHT}─── Schritt 2 / 3  ·  EFI-Partition ───${RST}\n"
    printf "${DIM}Wird unter /boot/efi eingehängt (optional).${RST}\n"
    select_partition "EFI-Systempartition" MOUNT_EFI true

    printf "\n${WHT}─── Schritt 3 / 3  ·  Mounten ───${RST}\n"

    info "Mounte Root: ${MOUNT_ROOT} → ${CHROOT_DIR}"
    if ! safe_mount "$MOUNT_ROOT" "$CHROOT_DIR"; then
        die "Root-Partition konnte nicht eingehängt werden. Abbruch."
    fi
    MOUNTED_BY_US=true

    detect_boot_partition

    if [[ -n "$MOUNT_EFI" ]]; then
        ensure_dir "${CHROOT_DIR}/boot/efi"
        safe_mount "$MOUNT_EFI" "${CHROOT_DIR}/boot/efi"
    fi

    bind_virtual_fs "$CHROOT_DIR"
    setup_resolv
}

# ================================================================
#  AKTIONEN
# ================================================================

# ── Vollständiger chroot-Ablauf ───────────────────────────────────
do_chroot() {
    print_banner
    _do_mount_setup

    printf "\n"
    printf "${GRN}╔══════════════════════════════════════════════╗${RST}\n"
    printf "${GRN}║  Bereit!  Wechsle in chroot …                ║${RST}\n"
    printf "${GRN}║  Beenden mit:  exit  oder  Strg+D            ║${RST}\n"
    printf "${GRN}╚══════════════════════════════════════════════╝${RST}\n\n"
    sleep 1

    # chroot – Exitcode festhalten, aber nicht zum Skriptabbruch nutzen
    local exit_code=0
    arch-chroot "$CHROOT_DIR" /bin/bash || exit_code=$?

    [[ $exit_code -ne 0 ]] && warn "chroot beendet mit Exitcode $exit_code."

    umount_all

    printf "\n"
    printf "${YLW}╔══════════════════════════════════════════════╗${RST}\n"
    printf "${YLW}║  chroot beendet.                             ║${RST}\n"
    printf "${YLW}╚══════════════════════════════════════════════╝${RST}\n\n"

    if confirm "System jetzt neu starten?"; then
        ok "System wird neu gestartet …"
        sleep 1
        reboot
    else
        info "Kein Neustart. Du bleibst in der Live-Umgebung."
        printf "  Neu starten:  ${CYN}reboot${RST}\n"
        printf "  Aushängen:    ${CYN}umount -R %s${RST}\n" "$CHROOT_DIR"
    fi
}

# ── Nur mounten (kein chroot) ─────────────────────────────────────
do_mount_only() {
    print_banner
    printf "${WHT}─── Nur mounten (kein chroot) ───${RST}\n"
    _do_mount_setup

    printf "\n"
    ok "Alles eingehängt unter ${CHROOT_DIR}. Kein chroot gestartet."
    printf "  Manuell chrooten: ${CYN}arch-chroot %s${RST}\n" "$CHROOT_DIR"
    printf "  Aushängen:        ${CYN}umount -R %s${RST}\n"   "$CHROOT_DIR"
    printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
    read -r _
}

# ── Einzelnen Befehl im chroot ausführen ──────────────────────────
do_run_command() {
    print_banner
    printf "${WHT}─── Befehl im chroot ausführen ───${RST}\n\n"

    if ! mountpoint -q "$CHROOT_DIR" 2>/dev/null; then
        warn "Nichts eingehängt unter ${CHROOT_DIR}."
        warn "Bitte zuerst Option 1 oder 2 verwenden."
        printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
        read -r _
        return 0
    fi

    printf "${YLW}Befehl eingeben (wird in chroot ausgeführt): ${RST}"
    local cmd=""
    read -r cmd

    if [[ -z "$cmd" ]]; then
        warn "Kein Befehl eingegeben."
        printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
        read -r _
        return 0
    fi

    printf "\n"
    info "Führe aus: ${cmd}"
    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"

    local exit_code=0
    arch-chroot "$CHROOT_DIR" /bin/bash -c "$cmd" || exit_code=$?

    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
    [[ $exit_code -eq 0 ]] && ok "Befehl erfolgreich (Exit 0)." \
                            || warn "Befehl beendet mit Exitcode $exit_code."

    printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
    read -r _
}

# ── Mount-Status anzeigen ─────────────────────────────────────────
show_status() {
    print_banner
    printf "${WHT}Eingehängte Dateisysteme unter %s:${RST}\n" "$CHROOT_DIR"
    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
    findmnt -R "$CHROOT_DIR" 2>/dev/null \
        || printf "${DIM}(nichts eingehängt unter %s)${RST}\n" "$CHROOT_DIR"
    printf "${DIM}%s${RST}\n\n" "────────────────────────────────────────────────────────────"

    printf "${WHT}Freier Speicherplatz (Geräte unter %s):${RST}\n" "$CHROOT_DIR"
    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
    df -h "$CHROOT_DIR" 2>/dev/null || printf "${DIM}(nicht verfügbar)${RST}\n"
    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"

    printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
    read -r _
}

# ── fstab anzeigen und neu generieren ────────────────────────────
do_fstab() {
    print_banner
    printf "${WHT}─── fstab verwalten ───${RST}\n\n"

    if ! mountpoint -q "$CHROOT_DIR" 2>/dev/null; then
        warn "Nichts eingehängt unter ${CHROOT_DIR}."
        warn "Bitte zuerst Option 1 oder 2 verwenden."
        printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
        read -r _
        return 0
    fi

    local fstab="${CHROOT_DIR}/etc/fstab"

    printf "  ${CYN}1)${RST} Aktuelle fstab anzeigen\n"
    printf "  ${CYN}2)${RST} fstab neu generieren (genfstab -U)\n"
    printf "  ${CYN}0)${RST} Zurück\n\n"
    printf "${YLW}Auswahl [0-2]: ${RST}"
    local sub=""
    read -r sub

    case "$sub" in
        1)
            printf "\n"
            if [[ -f "$fstab" ]]; then
                printf "${WHT}Inhalt von %s:${RST}\n" "$fstab"
                printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
                cat "$fstab"
                printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
            else
                warn "fstab nicht gefunden: $fstab"
            fi
            ;;
        2)
            if ! command -v genfstab &>/dev/null; then
                error "genfstab nicht gefunden. Paket arch-install-scripts installieren."
                printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
                read -r _
                return 0
            fi
            printf "\n"
            info "Generiere fstab-Vorschau …"
            printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
            genfstab -U "$CHROOT_DIR"
            printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
            printf "\n"
            if confirm "Vorschau in ${fstab} schreiben (ÜBERSCHREIBT bestehende Datei)?"; then
                genfstab -U "$CHROOT_DIR" > "$fstab" \
                    && ok "fstab geschrieben: $fstab" \
                    || error "Schreiben fehlgeschlagen."
            else
                info "fstab nicht verändert."
            fi
            ;;
        0) return 0 ;;
        *) warn "Ungültige Eingabe." ;;
    esac

    printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
    read -r _
}

# ── GRUB neu installieren (geführt) ──────────────────────────────
do_grub() {
    print_banner
    printf "${WHT}─── GRUB-Bootloader installieren ───${RST}\n\n"

    if ! mountpoint -q "$CHROOT_DIR" 2>/dev/null; then
        warn "Nichts eingehängt unter ${CHROOT_DIR}."
        warn "Bitte zuerst Option 1 oder 2 verwenden."
        printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
        read -r _
        return 0
    fi

    printf "${DIM}Verfügbare Laufwerke (keine Partitionen!):${RST}\n"
    lsblk -d -o NAME,SIZE,MODEL 2>/dev/null
    printf "\n"

    local disk=""
    printf "${YLW}Ziel-Laufwerk für GRUB (z.B. /dev/sda, /dev/nvme0n1): ${RST}"
    read -r disk
    disk="${disk// /}"

    if [[ -z "$disk" ]]; then
        warn "Kein Laufwerk angegeben. Abbruch."
        printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
        read -r _
        return 0
    fi

    if [[ ! -b "$disk" ]]; then
        error "'$disk' ist kein gültiges Blockgerät."
        printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
        read -r _
        return 0
    fi

    # EFI oder BIOS?
    local mode="bios"
    if [[ -d /sys/firmware/efi ]]; then
        printf "\n${DIM}EFI-System erkannt.${RST}\n"
        printf "  ${CYN}1)${RST} UEFI (grub-install --target=x86_64-efi)\n"
        printf "  ${CYN}2)${RST} BIOS/Legacy (grub-install --target=i386-pc)\n"
        printf "${YLW}Auswahl [1/2]: ${RST}"
        local msel=""
        read -r msel
        [[ "$msel" == "2" ]] || mode="efi"
    fi

    printf "\n"
    if [[ "$mode" == "efi" ]]; then
        info "GRUB (UEFI) wird installiert auf: $disk"
        if confirm "Fortfahren?"; then
            arch-chroot "$CHROOT_DIR" \
                grub-install --target=x86_64-efi \
                             --efi-directory=/boot/efi \
                             --bootloader-id=GRUB \
                             --recheck \
                && ok "grub-install erfolgreich." \
                || warn "grub-install beendet mit Fehler."
        fi
    else
        info "GRUB (BIOS) wird installiert auf: $disk"
        if confirm "Fortfahren?"; then
            arch-chroot "$CHROOT_DIR" \
                grub-install --target=i386-pc \
                             --recheck \
                             "$disk" \
                && ok "grub-install erfolgreich." \
                || warn "grub-install beendet mit Fehler."
        fi
    fi

    # Konfiguration generieren
    printf "\n"
    if confirm "grub.cfg jetzt generieren (grub-mkconfig)?"; then
        arch-chroot "$CHROOT_DIR" \
            grub-mkconfig -o /boot/grub/grub.cfg \
            && ok "grub.cfg generiert." \
            || warn "grub-mkconfig beendet mit Fehler."
    fi

    printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
    read -r _
}

# ── Passwort im chroot zurücksetzen ──────────────────────────────
do_passwd_reset() {
    print_banner
    printf "${WHT}─── Passwort im chroot zurücksetzen ───${RST}\n\n"

    if ! mountpoint -q "$CHROOT_DIR" 2>/dev/null; then
        warn "Nichts eingehängt unter ${CHROOT_DIR}."
        warn "Bitte zuerst Option 1 oder 2 verwenden."
        printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
        read -r _
        return 0
    fi

    # Bekannte Benutzer aus passwd anzeigen
    local passwd_file="${CHROOT_DIR}/etc/passwd"
    if [[ -f "$passwd_file" ]]; then
        printf "${DIM}Benutzer in der Installation:${RST}\n"
        awk -F: '$3 >= 1000 || $1 == "root" { printf "  %s (UID %s)\n", $1, $3 }' \
            "$passwd_file"
        printf "\n"
    fi

    local target_user=""
    printf "${YLW}Benutzername (Standard: root): ${RST}"
    read -r target_user
    target_user="${target_user:-root}"

    # Benutzer existiert?
    if ! grep -q "^${target_user}:" "$passwd_file" 2>/dev/null; then
        error "Benutzer '${target_user}' nicht in /etc/passwd gefunden."
        printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
        read -r _
        return 0
    fi

    printf "\n"
    info "Starte passwd für Benutzer '${target_user}' im chroot …"
    arch-chroot "$CHROOT_DIR" passwd "$target_user" \
        && ok "Passwort für '${target_user}' erfolgreich geändert." \
        || warn "passwd beendet mit Fehler."

    printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
    read -r _
}

# ── Aushängen ─────────────────────────────────────────────────────
do_umount() {
    print_banner
    umount_all
    printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
    read -r _
}

# ── Neustart direkt aus Menü ──────────────────────────────────────
do_reboot() {
    printf "\n"
    if confirm "${RED}Wirklich neu starten?${RST}"; then
        umount_all
        ok "System wird neu gestartet …"
        sleep 1
        reboot
    fi
}

# ================================================================
#  HAUPTMENÜ
# ================================================================
main_menu() {
    while true; do
        print_banner
        printf "  ${WHT}Was möchtest du tun?${RST}\n\n"
        printf "  ${CYN}1)${RST} Arch-Installation chrooten       ${GRN}← Empfohlen${RST}\n"
        printf "  ${CYN}2)${RST} Nur mounten (kein chroot)\n"
        printf "  ${CYN}3)${RST} Befehl im chroot ausführen\n"
        printf "  ${DIM}────────────────────────────────────${RST}\n"
        printf "  ${CYN}4)${RST} fstab anzeigen / neu generieren\n"
        printf "  ${CYN}5)${RST} GRUB-Bootloader installieren\n"
        printf "  ${CYN}6)${RST} Passwort zurücksetzen\n"
        printf "  ${DIM}────────────────────────────────────${RST}\n"
        printf "  ${CYN}7)${RST} Mount-Status anzeigen\n"
        printf "  ${CYN}8)${RST} Alles aushängen\n"
        printf "  ${CYN}9)${RST} System neu starten\n"
        printf "  ${CYN}0)${RST} Beenden\n\n"
        printf "${YLW}Auswahl [0-9]: ${RST}"

        local choice=""
        read -r choice

        case "$choice" in
            1) do_chroot        ;;
            2) do_mount_only    ;;
            3) do_run_command   ;;
            4) do_fstab         ;;
            5) do_grub          ;;
            6) do_passwd_reset  ;;
            7) show_status      ;;
            8) do_umount        ;;
            9) do_reboot        ;;
            0) info "Skript beendet."; exit 0 ;;
            *) warn "Ungültige Eingabe: '${choice}'"; sleep 1 ;;
        esac
    done
}

# ================================================================
#  EINSTIEGSPUNKT
# ================================================================
parse_args "$@"
require_root "$@"
main_menu
