#!/usr/bin/env bash
# ================================================================
#  arch-chroot-menu.sh  –  v2.0
#  Interaktives Menü zum Chrooten in eine Arch Linux Installation
#  EFI  ·  Automount  ·  Reboot-Abfrage
#
#  Verwendung:  bash arch-chroot-menu.sh
#  Benötigt:    arch-install-scripts  (arch-chroot)
# ================================================================

# ── Shell-Optionen ───────────────────────────────────────────────
# kein set -e: interaktive Skripte brauchen explizite Fehlerbehandlung
set -uo pipefail

# ── Farben ───────────────────────────────────────────────────────
readonly RED='\033[1;31m'
readonly GRN='\033[1;32m'
readonly YLW='\033[1;33m'
readonly BLU='\033[1;34m'
readonly CYN='\033[1;36m'
readonly WHT='\033[1;37m'
readonly DIM='\033[2m'
readonly RST='\033[0m'

# ── Globale Variablen ────────────────────────────────────────────
CHROOT_DIR="/mnt"
MOUNT_ROOT=""
MOUNT_EFI=""

# ── Logging ──────────────────────────────────────────────────────
info()  { printf "${BLU}[INFO]${RST}   %s\n"   "$*"; }
ok()    { printf "${GRN}[OK]${RST}     %s\n"   "$*"; }
warn()  { printf "${YLW}[WARN]${RST}   %s\n"   "$*" >&2; }
error() { printf "${RED}[FEHLER]${RST} %s\n"   "$*" >&2; }
die()   { error "$*"; exit 1; }

# ── Sudo-Eskalation ──────────────────────────────────────────────
# Wird das Skript nicht als root ausgeführt, startet es sich selbst
# mit sudo neu → Passwortabfrage erscheint direkt beim Skriptstart.
require_root() {
    if [[ $EUID -ne 0 ]]; then
        printf "${YLW}Root-Rechte erforderlich – sudo wird angefragt …${RST}\n"
        exec sudo -- "$0" "$@"
        # exec ersetzt den Prozess; was folgt wird nie erreicht
        die "sudo konnte nicht ausgeführt werden."
    fi
}

# ── Banner ───────────────────────────────────────────────────────
print_banner() {
    clear
    printf "${CYN}"
    printf "  ╔══════════════════════════════════════════════════╗\n"
    printf "  ║      Arch Linux  ·  chroot  Helper  v2.0         ║\n"
    printf "  ║          EFI  ·  Automount  ·  Menü              ║\n"
    printf "  ╚══════════════════════════════════════════════════╝\n"
    printf "${RST}\n"
}

# ── Blockgeräte auflisten ────────────────────────────────────────
list_devices() {
    printf "${WHT}Verfügbare Blockgeräte:${RST}\n"
    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT 2>/dev/null \
        || lsblk 2>/dev/null \
        || printf "(lsblk nicht verfügbar)\n"
    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
}

# ── Partition interaktiv wählen ──────────────────────────────────
# Verwendung: select_partition "Prompt" varname [optional=true]
# Schreibt das Ergebnis sicher per printf -v (kein eval)
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
        [[ "$optional" == "true" ]] && printf ", Enter = überspringen"
        printf "): "
        read -r part

        # Leerzeichen trimmen
        part="${part// /}"

        if [[ -z "$part" ]]; then
            if [[ "$optional" == "true" ]]; then
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

# ── Verzeichnis sicherstellen ────────────────────────────────────
ensure_dir() {
    [[ -d "$1" ]] || mkdir -p -- "$1"
}

# ── Sicher mounten ───────────────────────────────────────────────
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

# ── Virtuelle Dateisysteme binden ────────────────────────────────
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

# ── DNS in chroot weiterleiten ───────────────────────────────────
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

# ── Separate /boot-Partition aus fstab erkennen ──────────────────
# Unterstützt: UUID=, LABEL=, PARTUUID=, /dev/…
detect_boot_partition() {
    local fstab="${CHROOT_DIR}/etc/fstab"
    [[ -f "$fstab" ]] || return 0

    local spec mountpoint_field _rest
    while read -r spec mountpoint_field _rest; do
        # Kommentare & Leerzeilen überspringen
        [[ "$spec" =~ ^#  ]] && continue
        [[ -z "$spec"      ]] && continue

        [[ "$mountpoint_field" == "/boot" ]] || continue

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
        return 0  # erste /boot-Zeile auswerten, dann fertig

    done < "$fstab"
}

# ── Alle Dateisysteme unter CHROOT_DIR aushängen ─────────────────
umount_all() {
    if ! mountpoint -q "$CHROOT_DIR" 2>/dev/null; then
        info "Nichts eingehängt unter ${CHROOT_DIR}."
        return 0
    fi

    info "Hänge alle Dateisysteme aus (${CHROOT_DIR}) …"

    # Lazy-Recursive-Unmount: zuverlässigste Methode für chroot-Bäume
    if umount -R --lazy "$CHROOT_DIR" 2>/dev/null; then
        ok "Alle Dateisysteme erfolgreich ausgehängt."
    else
        warn "Einige Dateisysteme konnten nicht ausgehängt werden."
        warn "Manuell prüfen: findmnt | grep ${CHROOT_DIR}"
    fi
}

# ── Neustart-Abfrage ─────────────────────────────────────────────
ask_reboot() {
    printf "\n"
    printf "${YLW}╔══════════════════════════════════════════════╗${RST}\n"
    printf "${YLW}║  chroot beendet.                             ║${RST}\n"
    printf "${YLW}╚══════════════════════════════════════════════╝${RST}\n"
    printf "\n"
    printf "${WHT}System jetzt neu starten? [j/N]: ${RST}"
    local ans=""
    read -r ans
    ans="${ans,,}"   # Kleinbuchstaben (bash 4+)

    case "$ans" in
        j|ja|y|yes)
            ok "System wird neu gestartet …"
            sleep 1
            reboot
            ;;
        *)
            info "Kein Neustart. Du bleibst in der Live-Umgebung."
            printf "  Neu starten:  ${CYN}reboot${RST}\n"
            printf "  Aushängen:    ${CYN}umount -R %s${RST}\n" "$CHROOT_DIR"
            ;;
    esac
}

# ================================================================
#  AKTIONEN
# ================================================================

# ── Vollständiger chroot-Ablauf ──────────────────────────────────
do_chroot() {
    # Zustand zurücksetzen (ermöglicht Wiederholung im gleichen Lauf)
    MOUNT_ROOT=""
    MOUNT_EFI=""

    print_banner
    printf "${WHT}─── Schritt 1 / 3  ·  Root-Partition ───${RST}\n"
    select_partition "Root-Partition (/) der Arch-Installation" MOUNT_ROOT false

    printf "\n${WHT}─── Schritt 2 / 3  ·  EFI-Partition ───${RST}\n"
    printf "${DIM}Wird unter /boot/efi eingehängt.${RST}\n"
    select_partition "EFI-Systempartition" MOUNT_EFI true

    printf "\n${WHT}─── Schritt 3 / 3  ·  Mounten & chroot ───${RST}\n"

    # 1) Root einhängen
    info "Mounte Root: ${MOUNT_ROOT} → ${CHROOT_DIR}"
    if ! safe_mount "$MOUNT_ROOT" "$CHROOT_DIR"; then
        die "Root-Partition konnte nicht eingehängt werden. Abbruch."
    fi

    # 2) Separate /boot aus fstab der Installation erkennen
    detect_boot_partition

    # 3) EFI einhängen
    if [[ -n "$MOUNT_EFI" ]]; then
        ensure_dir "${CHROOT_DIR}/boot/efi"
        safe_mount "$MOUNT_EFI" "${CHROOT_DIR}/boot/efi"
    fi

    # 4) Virtuelle Dateisysteme
    bind_virtual_fs "$CHROOT_DIR"

    # 5) DNS
    setup_resolv

    printf "\n"
    printf "${GRN}╔══════════════════════════════════════════════╗${RST}\n"
    printf "${GRN}║  Bereit!  Wechsle in chroot …                ║${RST}\n"
    printf "${GRN}║  Beenden mit:  exit  oder  Strg+D            ║${RST}\n"
    printf "${GRN}╚══════════════════════════════════════════════╝${RST}\n"
    printf "\n"
    sleep 1

    # 6) chroot – Exitcode festhalten, aber nicht zum Abbruch nutzen
    local exit_code=0
    arch-chroot "$CHROOT_DIR" /bin/bash || exit_code=$?

    [[ $exit_code -ne 0 ]] && warn "chroot beendet mit Exitcode $exit_code."

    # 7) Aushängen (nur einmal, NICHT nochmal in ask_reboot)
    umount_all

    # 8) Neustart-Abfrage
    ask_reboot
}

# ── Nur mounten (kein chroot) ────────────────────────────────────
do_mount_only() {
    MOUNT_ROOT=""
    MOUNT_EFI=""

    print_banner
    printf "${WHT}─── Nur mounten (kein chroot) ───${RST}\n"
    select_partition "Root-Partition" MOUNT_ROOT false
    select_partition "EFI-Partition (optional)" MOUNT_EFI true

    if ! safe_mount "$MOUNT_ROOT" "$CHROOT_DIR"; then
        die "Root-Partition konnte nicht eingehängt werden."
    fi

    detect_boot_partition

    if [[ -n "$MOUNT_EFI" ]]; then
        ensure_dir "${CHROOT_DIR}/boot/efi"
        safe_mount "$MOUNT_EFI" "${CHROOT_DIR}/boot/efi"
    fi

    bind_virtual_fs "$CHROOT_DIR"
    setup_resolv

    printf "\n"
    ok "Alles eingehängt unter ${CHROOT_DIR}. Kein chroot gestartet."
    printf "  Manuell chrooten: ${CYN}arch-chroot %s${RST}\n" "$CHROOT_DIR"
    printf "  Aushängen:        ${CYN}umount -R %s${RST}\n"   "$CHROOT_DIR"
    printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
    read -r _
}

# ── Mount-Status anzeigen ────────────────────────────────────────
show_status() {
    print_banner
    printf "${WHT}Eingehängte Dateisysteme unter %s:${RST}\n" "$CHROOT_DIR"
    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
    findmnt -R "$CHROOT_DIR" 2>/dev/null \
        || printf "${DIM}(nichts eingehängt unter %s)${RST}\n" "$CHROOT_DIR"
    printf "${DIM}%s${RST}\n" "────────────────────────────────────────────────────────────"
    printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
    read -r _
}

# ── Aushängen ────────────────────────────────────────────────────
do_umount() {
    print_banner
    umount_all
    printf "\n${YLW}[Enter] zurück zum Menü …${RST}"
    read -r _
}

# ── Neustart direkt aus Menü ─────────────────────────────────────
do_reboot() {
    printf "\n${RED}Wirklich neu starten? [j/N]: ${RST}"
    local ans=""
    read -r ans
    ans="${ans,,}"
    if [[ "$ans" == "j" || "$ans" == "ja" || "$ans" == "y" || "$ans" == "yes" ]]; then
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
        printf "  ${CYN}1)${RST} Arch-Installation chrooten  ${GRN}← Empfohlen${RST}\n"
        printf "  ${CYN}2)${RST} Nur mounten (kein chroot)\n"
        printf "  ${CYN}3)${RST} Mount-Status anzeigen\n"
        printf "  ${CYN}4)${RST} Alles aushängen\n"
        printf "  ${CYN}5)${RST} System neu starten\n"
        printf "  ${CYN}0)${RST} Beenden\n\n"
        printf "${YLW}Auswahl [0-5]: ${RST}"
        local choice=""
        read -r choice

        case "$choice" in
            1) do_chroot     ;;
            2) do_mount_only ;;
            3) show_status   ;;
            4) do_umount     ;;
            5) do_reboot     ;;
            0) info "Skript beendet."; exit 0 ;;
            *) warn "Ungültige Eingabe: '${choice}'"; sleep 1 ;;
        esac
    done
}

# ================================================================
#  EINSTIEGSPUNKT
# ================================================================
require_root "$@"
main_menu
