#!/usr/bin/env bash
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_ARGS=("$@")
# =============================================================================
#  ArchLinux Kernel Manager
#  Version : 2.2
#  Lizenz  : MIT
# =============================================================================
# Benötigt: pacman, mkinitcpio, (optional) grub, limine
# Ausführen als root oder mit sudo-Rechten
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
#  FARBEN & SYMBOLE
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

OK="[${GREEN}✔${RESET}]"
FAIL="[${RED}✘${RESET}]"
INFO="[${CYAN}i${RESET}]"
WARN="[${YELLOW}!${RESET}]"
ARROW="[${BLUE}→${RESET}]"

# ─────────────────────────────────────────────────────────────────────────────
#  SIGNAL-HANDLER
# ─────────────────────────────────────────────────────────────────────────────

cleanup() {
    echo ""
    echo -e "  ${WARN} Abgebrochen durch Benutzer."
    # Cursor wieder sichtbar machen, falls versteckt
    tput cnorm 2>/dev/null || true
    exit 130
}

trap cleanup INT TERM

# ─────────────────────────────────────────────────────────────────────────────
#  HILFSFUNKTIONEN
# ─────────────────────────────────────────────────────────────────────────────

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        if command -v sudo &>/dev/null; then
            echo -e "  ${INFO} Root-Rechte erforderlich – starte mit sudo neu..."
            exec sudo bash "${SCRIPT_PATH}" "${SCRIPT_ARGS[@]}"
        else
            echo -e "  ${FAIL} Root-Rechte erforderlich und sudo nicht gefunden."
            exit 1
        fi
    fi
}

pause() {
    echo ""
    read -rp "$(echo -e "  ${DIM}Drücke [Enter] um fortzufahren...${RESET}")"
}

separator() {
    echo -e "${DIM}$(printf '─%.0s' {1..60})${RESET}"
}

print_ok()   { echo -e "  ${OK} ${1}"; }
print_fail() { echo -e "  ${FAIL} ${1}"; }
print_info() { echo -e "  ${INFO} ${1}"; }
print_warn() { echo -e "  ${WARN} ${1}"; }
print_step() { echo -e "  ${ARROW} ${BOLD}${1}${RESET}"; }

run_cmd() {
    local desc="${1}"
    shift
    print_step "${desc}"
    if "$@"; then
        print_ok "Erfolgreich: ${desc}"
    else
        print_fail "Fehler bei: ${desc}"
        return 1
    fi
}

confirm() {
    local msg="${1:-Fortfahren?}"
    local answer
    read -rp "$(echo -e "  ${YELLOW}?${RESET} ${msg} [j/N]: ")" answer
    [[ "${answer,,}" == "j" || "${answer,,}" == "ja" ]]
}

# Hilfsfunktion: Partitions-Disk und -Nummer aus einem Gerätepfad extrahieren
# Unterstützt sowohl /dev/sdX1 als auch /dev/nvme0n1p2
parse_disk_and_part() {
    local dev="${1}"
    if [[ "${dev}" =~ ^(/dev/.+[^0-9])([0-9]+)$ ]]; then
        # z.B. /dev/sda1 → /dev/sda + 1
        PARSED_DISK="${BASH_REMATCH[1]}"
        PARSED_PART="${BASH_REMATCH[2]}"
    elif [[ "${dev}" =~ ^(/dev/.+)p([0-9]+)$ ]]; then
        # z.B. /dev/nvme0n1p2 → /dev/nvme0n1 + 2
        PARSED_DISK="${BASH_REMATCH[1]}"
        PARSED_PART="${BASH_REMATCH[2]}"
    else
        PARSED_DISK=""
        PARSED_PART=""
        return 1
    fi
}

print_header() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║         ArchLinux Kernel Manager  v2.2              ║"
    echo "  ║      System · Kernel · Bootloader · Repair          ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo -e "  ${DIM}Kernel laufend: $(uname -r)   |   Arch: $(uname -m)   |   $(date '+%d.%m.%Y %H:%M')${RESET}"
    separator
}

# ─────────────────────────────────────────────────────────────────────────────
#  MODUL 1 – SYSTEMANALYSE
# ─────────────────────────────────────────────────────────────────────────────

system_info() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ SYSTEMANALYSE ]${RESET}"
    separator

    echo -e "\n  ${BOLD}── Kernel & OS ──────────────────────────────────────${RESET}"
    echo -e "  Kernel Version  : $(uname -r)"
    echo -e "  Kernel Build    : $(uname -v)"
    echo -e "  Architektur     : $(uname -m)"
    echo -e "  Hostname        : $(hostname)"
    echo -e "  Betriebssystem  : $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"

    echo -e "\n  ${BOLD}── Installierte Kernel ──────────────────────────────${RESET}"
    local kernels
    kernels=$(pacman -Qq | grep -E '^linux(-lts|-zen|-hardened|-rt)?$' 2>/dev/null || true)
    if [[ -n "${kernels}" ]]; then
        while IFS= read -r k; do
            local ver
            ver=$(pacman -Qi "${k}" 2>/dev/null | grep '^Version' | awk '{print $3}')
            echo -e "  ${GREEN}●${RESET} ${k}  ${DIM}(${ver})${RESET}"
        done <<< "${kernels}"
    else
        print_warn "Keine Standard-Kernel gefunden."
    fi

    echo -e "\n  ${BOLD}── Boot-Verzeichnis (/boot) ──────────────────────────${RESET}"
    if [[ -d /boot ]]; then
        ls -lh /boot/*.img /boot/vmlinuz* 2>/dev/null | awk '{print "  " $0}' || \
            print_warn "Keine Kernel-Images in /boot gefunden."
    fi

    echo -e "\n  ${BOLD}── Bootloader-Erkennung ─────────────────────────────${RESET}"
    if command -v grub-mkconfig &>/dev/null; then
        print_info "GRUB ist installiert."
    fi
    if command -v limine &>/dev/null; then
        local lver
        lver=$(limine --version 2>&1 | head -1 | awk '{print $2}')
        print_info "Limine ist installiert (Version: ${lver})."
    fi
    if [[ -d /sys/firmware/efi ]]; then
        print_info "System bootet im ${GREEN}UEFI${RESET}-Modus."
    else
        print_info "System bootet im ${YELLOW}BIOS/Legacy${RESET}-Modus."
    fi

    echo -e "\n  ${BOLD}── Speicherplatz ────────────────────────────────────${RESET}"
    df -h / /boot 2>/dev/null | awk '{print "  " $0}'

    echo -e "\n  ${BOLD}── RAM & CPU ────────────────────────────────────────${RESET}"
    echo -e "  CPU   : $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    echo -e "  Kerne : $(nproc)"
    free -h | awk '{print "  " $0}'

    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  MODUL 2 – KERNEL MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

kernel_menu() {
    while true; do
        print_header
        echo -e "  ${BOLD}${CYAN}[ KERNEL MANAGEMENT ]${RESET}"
        separator
        echo ""
        echo -e "  ${BOLD}1)${RESET}  Kernel installieren"
        echo -e "  ${BOLD}2)${RESET}  Kernel entfernen"
        echo -e "  ${BOLD}3)${RESET}  Alle Kernel aktualisieren"
        echo -e "  ${BOLD}4)${RESET}  Installierte Kernel anzeigen"
        echo -e "  ${BOLD}5)${RESET}  Kernel-Module anzeigen"
        echo -e "  ${BOLD}6)${RESET}  Kernel downgraden (aus Cache)"
        echo -e "  ${BOLD}0)${RESET}  ${DIM}Zurück${RESET}"
        echo ""
        separator
        read -rp "$(echo -e "  ${BOLD}Auswahl: ${RESET}")" choice

        case "${choice}" in
            1) kernel_install ;;
            2) kernel_remove ;;
            3) kernel_update_all ;;
            4) kernel_list ;;
            5) kernel_modules ;;
            6) kernel_downgrade ;;
            0) return ;;
            *) print_warn "Ungültige Auswahl." ; sleep 1 ;;
        esac
    done
}

kernel_install() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ KERNEL INSTALLIEREN ]${RESET}"
    separator
    echo ""
    echo -e "  Verfügbare Kernel-Pakete:"
    echo -e "  ${BOLD}1)${RESET}  linux          ${DIM}(Stable)${RESET}"
    echo -e "  ${BOLD}2)${RESET}  linux-lts      ${DIM}(Long Term Support)${RESET}"
    echo -e "  ${BOLD}3)${RESET}  linux-zen      ${DIM}(Zen / Desktop optimiert)${RESET}"
    echo -e "  ${BOLD}4)${RESET}  linux-hardened ${DIM}(Sicherheits-Kernel)${RESET}"
    echo -e "  ${BOLD}5)${RESET}  Eigenes Paket eingeben"
    echo ""
    read -rp "$(echo -e "  ${BOLD}Auswahl: ${RESET}")" sel

    local pkg=""
    case "${sel}" in
        1) pkg="linux linux-headers" ;;
        2) pkg="linux-lts linux-lts-headers" ;;
        3) pkg="linux-zen linux-zen-headers" ;;
        4) pkg="linux-hardened linux-hardened-headers" ;;
        5)
            read -rp "$(echo -e "  Paketname eingeben: ")" pkg
            ;;
        *) print_warn "Ungültige Auswahl." ; pause ; return ;;
    esac

    if [[ -z "${pkg}" ]]; then
        print_warn "Kein Paket angegeben." ; pause ; return
    fi

    if confirm "Paket(e) '${pkg}' installieren?"; then
        # shellcheck disable=SC2086
        run_cmd "Installiere ${pkg}" pacman -S --needed ${pkg}
        print_ok "Kernel installiert. Initramfs wird neu generiert..."
        run_cmd "Generiere Initramfs (alle Presets)" mkinitcpio -P
    fi
    pause
}

kernel_remove() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ KERNEL ENTFERNEN ]${RESET}"
    separator
    echo ""
    print_warn "Installierte Kernel:"
    pacman -Qq | grep -E '^linux(-lts|-zen|-hardened|-rt)?$' 2>/dev/null | \
        nl -w3 -s ') ' | awk '{print "  " $0}'
    echo ""
    read -rp "$(echo -e "  Paketname zum Entfernen: ")" pkg

    if [[ -z "${pkg}" ]]; then
        print_warn "Kein Paket angegeben." ; pause ; return
    fi

    local count
    count=$(pacman -Qq | grep -cE '^linux(-lts|-zen|-hardened|-rt)?$' 2>/dev/null || echo 0)
    if [[ "${count}" -le 1 ]]; then
        print_fail "Nur ein Kernel installiert – Entfernen abgebrochen!"
        pause ; return
    fi

    if confirm "Kernel '${pkg}' und zugehörige Headers entfernen?"; then
        run_cmd "Entferne ${pkg}" pacman -Rns "${pkg}" "${pkg}-headers" 2>/dev/null || \
            run_cmd "Entferne ${pkg} (ohne Headers)" pacman -Rns "${pkg}"
    fi
    pause
}

kernel_update_all() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ KERNEL AKTUALISIEREN ]${RESET}"
    separator
    echo ""
    if confirm "Vollständiges System-Update durchführen (pacman -Syu)?"; then
        run_cmd "System-Update" pacman -Syu
        print_ok "Update abgeschlossen."
    fi
    pause
}

kernel_list() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ INSTALLIERTE KERNEL ]${RESET}"
    separator
    echo ""
    pacman -Qi linux linux-lts linux-zen linux-hardened 2>/dev/null | \
        grep -E '^(Name|Version|Installationsdatum|Installierte Größe)' | \
        awk '{print "  " $0}' || print_warn "Keine Kernel-Infos verfügbar."
    echo ""
    echo -e "  ${BOLD}── Boot-Images ──────────────────────────────────────${RESET}"
    ls -lh /boot/vmlinuz* /boot/initramfs-*.img 2>/dev/null | \
        awk '{print "  " $0}' || print_warn "Keine Boot-Images gefunden."
    pause
}

kernel_modules() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ KERNEL MODULE ]${RESET}"
    separator
    echo ""
    echo -e "  ${BOLD}Geladene Module (Top 20):${RESET}"
    lsmod | head -21 | awk '{print "  " $0}'
    echo ""
    echo -e "  ${BOLD}Kernel-Modul-Verzeichnisse:${RESET}"
    ls /lib/modules/ 2>/dev/null | awk '{print "  ● " $0}'
    pause
}

kernel_downgrade() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ KERNEL DOWNGRADE ]${RESET}"
    separator
    echo ""
    print_info "Verfügbare Kernel-Pakete im Pacman-Cache:"
    ls /var/cache/pacman/pkg/linux-[0-9]*.pkg.tar.* 2>/dev/null | \
        nl -w3 -s ') ' | awk '{print "  " $0}' || \
        print_warn "Keine Kernel-Pakete im Cache gefunden."
    echo ""
    read -rp "$(echo -e "  Vollständigen Pfad zum Paket eingeben: ")" pkgpath

    if [[ -f "${pkgpath}" ]]; then
        if confirm "Kernel aus '${pkgpath}' installieren?"; then
            run_cmd "Downgrade Kernel" pacman -U "${pkgpath}"
            run_cmd "Regeneriere Initramfs" mkinitcpio -P
        fi
    else
        print_fail "Datei nicht gefunden: ${pkgpath}"
    fi
    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  MODUL 3 – INITRAMFS / MKINITCPIO
# ─────────────────────────────────────────────────────────────────────────────

initramfs_menu() {
    while true; do
        print_header
        echo -e "  ${BOLD}${CYAN}[ INITRAMFS / MKINITCPIO ]${RESET}"
        separator
        echo ""
        echo -e "  ${BOLD}1)${RESET}  Alle Initramfs neu generieren  ${DIM}(mkinitcpio -P)${RESET}"
        echo -e "  ${BOLD}2)${RESET}  Einzelnes Preset neu generieren"
        echo -e "  ${BOLD}3)${RESET}  Verfügbare Presets anzeigen"
        echo -e "  ${BOLD}4)${RESET}  mkinitcpio.conf anzeigen"
        echo -e "  ${BOLD}5)${RESET}  mkinitcpio.conf bearbeiten"
        echo -e "  ${BOLD}6)${RESET}  Autodetect-Module anzeigen"
        echo -e "  ${BOLD}0)${RESET}  ${DIM}Zurück${RESET}"
        echo ""
        separator
        read -rp "$(echo -e "  ${BOLD}Auswahl: ${RESET}")" choice

        case "${choice}" in
            1) initramfs_all ;;
            2) initramfs_single ;;
            3) initramfs_presets ;;
            4) initramfs_show_conf ;;
            5) initramfs_edit_conf ;;
            6) initramfs_autodetect ;;
            0) return ;;
            *) print_warn "Ungültige Auswahl." ; sleep 1 ;;
        esac
    done
}

initramfs_all() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ ALLE INITRAMFS GENERIEREN ]${RESET}"
    separator
    echo ""
    if confirm "Alle Initramfs-Images neu generieren?"; then
        run_cmd "Generiere alle Initramfs-Presets" mkinitcpio -P
    fi
    pause
}

initramfs_single() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ EINZELNES PRESET GENERIEREN ]${RESET}"
    separator
    echo ""
    echo -e "  Verfügbare Presets:"
    ls /etc/mkinitcpio.d/*.preset 2>/dev/null | \
        xargs -I{} basename {} .preset | \
        nl -w3 -s ') ' | awk '{print "  " $0}'
    echo ""
    read -rp "$(echo -e "  Preset-Name (z.B. linux, linux-lts): ")" preset

    if [[ -f "/etc/mkinitcpio.d/${preset}.preset" ]]; then
        run_cmd "Generiere Initramfs für Preset '${preset}'" mkinitcpio -p "${preset}"
    else
        print_fail "Preset '${preset}' nicht gefunden."
    fi
    pause
}

initramfs_presets() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ VERFÜGBARE PRESETS ]${RESET}"
    separator
    echo ""
    for f in /etc/mkinitcpio.d/*.preset; do
        [[ -e "${f}" ]] || { print_warn "Keine Presets gefunden." ; break ; }
        echo -e "  ${GREEN}●${RESET} $(basename "${f}")"
        grep -E '^(ALL_kver|default_image|fallback_image)' "${f}" 2>/dev/null | \
            awk '{print "    " $0}'
        echo ""
    done
    pause
}

initramfs_show_conf() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ MKINITCPIO.CONF ]${RESET}"
    separator
    echo ""
    if [[ -f /etc/mkinitcpio.conf ]]; then
        awk '{print "  " $0}' /etc/mkinitcpio.conf
    else
        print_fail "/etc/mkinitcpio.conf nicht gefunden."
    fi
    pause
}

initramfs_edit_conf() {
    local editor="${EDITOR:-nano}"
    print_step "Öffne /etc/mkinitcpio.conf mit ${editor}..."
    "${editor}" /etc/mkinitcpio.conf
}

initramfs_autodetect() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ AUTODETECT MODULE ]${RESET}"
    separator
    echo ""
    print_step "Erkenne Module für aktuellen Kernel..."
    mkinitcpio -M 2>/dev/null | awk '{print "  " $0}' || \
        print_warn "Autodetect nicht verfügbar."
    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  MODUL 4 – GRUB BOOTLOADER
# ─────────────────────────────────────────────────────────────────────────────

grub_menu() {
    if ! command -v grub-mkconfig &>/dev/null; then
        print_header
        print_warn "GRUB ist nicht installiert."
        print_info "Installieren mit: pacman -S grub"
        pause ; return
    fi

    while true; do
        print_header
        echo -e "  ${BOLD}${CYAN}[ GRUB BOOTLOADER ]${RESET}"
        separator
        echo ""
        echo -e "  ${BOLD}1)${RESET}  GRUB-Konfiguration neu generieren  ${DIM}(grub-mkconfig)${RESET}"
        echo -e "  ${BOLD}2)${RESET}  GRUB auf Disk installieren"
        echo -e "  ${BOLD}3)${RESET}  GRUB-Konfiguration anzeigen"
        echo -e "  ${BOLD}4)${RESET}  GRUB-Konfiguration bearbeiten  ${DIM}(/etc/default/grub)${RESET}"
        echo -e "  ${BOLD}5)${RESET}  GRUB-Version anzeigen"
        echo -e "  ${BOLD}6)${RESET}  EFI-Booteinträge anzeigen  ${DIM}(efibootmgr)${RESET}"
        echo -e "  ${BOLD}0)${RESET}  ${DIM}Zurück${RESET}"
        echo ""
        separator
        read -rp "$(echo -e "  ${BOLD}Auswahl: ${RESET}")" choice

        case "${choice}" in
            1) grub_mkconfig_run ;;
            2) grub_install_disk ;;
            3) grub_show_config ;;
            4) grub_edit_default ;;
            5) grub_version ;;
            6) efi_entries ;;
            0) return ;;
            *) print_warn "Ungültige Auswahl." ; sleep 1 ;;
        esac
    done
}

grub_mkconfig_run() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ GRUB KONFIGURATION GENERIEREN ]${RESET}"
    separator
    echo ""
    local cfg="/boot/grub/grub.cfg"
    print_info "Zieldatei: ${cfg}"
    echo ""
    if confirm "GRUB-Konfiguration neu generieren?"; then
        run_cmd "Generiere grub.cfg" grub-mkconfig -o "${cfg}"
    fi
    pause
}

grub_install_disk() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ GRUB AUF DISK INSTALLIEREN ]${RESET}"
    separator
    echo ""
    echo -e "  Verfügbare Blockgeräte:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null | awk '{print "  " $0}'
    echo ""

    if [[ -d /sys/firmware/efi ]]; then
        print_info "UEFI-System erkannt."
        read -rp "$(echo -e "  EFI-Verzeichnis [/boot]: ")" efidir
        efidir="${efidir:-/boot}"
        if confirm "GRUB für UEFI installieren (--target=x86_64-efi)?"; then
            run_cmd "Installiere GRUB (UEFI)" \
                grub-install --target=x86_64-efi \
                             --efi-directory="${efidir}" \
                             --bootloader-id=GRUB \
                             --recheck
            run_cmd "Generiere grub.cfg" grub-mkconfig -o /boot/grub/grub.cfg
        fi
    else
        print_info "BIOS/Legacy-System erkannt."
        read -rp "$(echo -e "  Ziel-Disk (z.B. /dev/sda): ")" disk
        if [[ -b "${disk}" ]]; then
            if confirm "GRUB auf '${disk}' installieren (BIOS)?"; then
                run_cmd "Installiere GRUB (BIOS)" \
                    grub-install --target=i386-pc \
                                 --recheck \
                                 "${disk}"
                run_cmd "Generiere grub.cfg" grub-mkconfig -o /boot/grub/grub.cfg
            fi
        else
            print_fail "Gerät '${disk}' nicht gefunden."
        fi
    fi
    pause
}

grub_show_config() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ GRUB KONFIGURATION ]${RESET}"
    separator
    echo ""
    if [[ -f /boot/grub/grub.cfg ]]; then
        head -60 /boot/grub/grub.cfg | awk '{print "  " $0}'
        echo -e "\n  ${DIM}... (nur erste 60 Zeilen angezeigt)${RESET}"
    else
        print_warn "/boot/grub/grub.cfg nicht gefunden."
    fi
    pause
}

grub_edit_default() {
    local editor="${EDITOR:-nano}"
    print_step "Öffne /etc/default/grub mit ${editor}..."
    "${editor}" /etc/default/grub
    if confirm "GRUB-Konfiguration jetzt neu generieren?"; then
        run_cmd "Generiere grub.cfg" grub-mkconfig -o /boot/grub/grub.cfg
    fi
}

grub_version() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ GRUB VERSION ]${RESET}"
    separator
    echo ""
    grub-install --version 2>/dev/null | awk '{print "  " $0}'
    pacman -Qi grub 2>/dev/null | grep -E '^(Name|Version)' | awk '{print "  " $0}'
    pause
}

efi_entries() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ EFI BOOTEINTRÄGE ]${RESET}"
    separator
    echo ""
    if command -v efibootmgr &>/dev/null; then
        efibootmgr 2>/dev/null | awk '{print "  " $0}'
    else
        print_warn "efibootmgr nicht installiert."
        print_info "Installieren mit: pacman -S efibootmgr"
    fi
    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  MODUL 5 – LIMINE BOOTLOADER
# ─────────────────────────────────────────────────────────────────────────────

limine_menu() {
    if ! command -v limine &>/dev/null; then
        print_header
        print_warn "Limine ist nicht installiert."
        print_info "Installieren mit: pacman -S limine"
        pause ; return
    fi

    while true; do
        print_header
        echo -e "  ${BOLD}${CYAN}[ LIMINE BOOTLOADER ]${RESET}"
        separator
        echo ""
        echo -e "  ${BOLD}1)${RESET}  Limine EFI-Dateien aktualisieren  ${DIM}(UEFI)${RESET}"
        echo -e "  ${BOLD}2)${RESET}  Limine BIOS installieren/aktualisieren"
        echo -e "  ${BOLD}3)${RESET}  Limine-Konfiguration anzeigen"
        echo -e "  ${BOLD}4)${RESET}  Limine-Konfiguration bearbeiten"
        echo -e "  ${BOLD}5)${RESET}  Limine-Version anzeigen"
        echo -e "  ${BOLD}6)${RESET}  EFI-Booteinträge anzeigen  ${DIM}(efibootmgr)${RESET}"
        echo -e "  ${BOLD}7)${RESET}  Limine EFI-Eintrag registrieren"
        echo -e "  ${BOLD}0)${RESET}  ${DIM}Zurück${RESET}"
        echo ""
        separator
        read -rp "$(echo -e "  ${BOLD}Auswahl: ${RESET}")" choice

        case "${choice}" in
            1) limine_update_uefi ;;
            2) limine_install_bios ;;
            3) limine_show_config ;;
            4) limine_edit_config ;;
            5) limine_version ;;
            6) efi_entries ;;
            7) limine_register_efi ;;
            0) return ;;
            *) print_warn "Ungültige Auswahl." ; sleep 1 ;;
        esac
    done
}

limine_update_uefi() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ LIMINE UEFI AKTUALISIEREN ]${RESET}"
    separator
    echo ""

    local esp_path=""
    if command -v bootctl &>/dev/null; then
        esp_path=$(bootctl --print-esp-path 2>/dev/null || echo "")
    fi
    [[ -z "${esp_path}" ]] && esp_path="/boot"

    print_info "Erkannter ESP-Pfad: ${esp_path}"
    read -rp "$(echo -e "  ESP-Pfad bestätigen oder ändern [${esp_path}]: ")" input
    [[ -n "${input}" ]] && esp_path="${input}"

    local limine_efi_dir="${esp_path}/EFI/limine"
    local limine_data_dir
    limine_data_dir=$(limine --print-datadir 2>/dev/null || echo "/usr/share/limine")

    print_info "Limine-Datenpfad: ${limine_data_dir}"
    print_info "Zielverzeichnis : ${limine_efi_dir}"
    echo ""

    if confirm "Limine EFI-Dateien nach '${limine_efi_dir}' kopieren?"; then
        mkdir -p "${limine_efi_dir}"
        run_cmd "Kopiere BOOTX64.EFI" \
            cp "${limine_data_dir}/BOOTX64.EFI" "${limine_efi_dir}/BOOTX64.EFI"
        run_cmd "Kopiere limine-uefi-cd.bin" \
            cp "${limine_data_dir}/limine-uefi-cd.bin" "${limine_efi_dir}/" 2>/dev/null || true
        print_ok "Limine EFI-Dateien erfolgreich aktualisiert."
    fi
    pause
}

limine_install_bios() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ LIMINE BIOS INSTALLIEREN ]${RESET}"
    separator
    echo ""
    echo -e "  Verfügbare Blockgeräte:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null | awk '{print "  " $0}'
    echo ""
    read -rp "$(echo -e "  Ziel-Disk (z.B. /dev/sda): ")" disk

    if [[ ! -b "${disk}" ]]; then
        print_fail "Gerät '${disk}' nicht gefunden."
        pause ; return
    fi

    local limine_data_dir
    limine_data_dir=$(limine --print-datadir 2>/dev/null || echo "/usr/share/limine")

    print_info "Limine-Datenpfad: ${limine_data_dir}"
    print_warn "Dies schreibt den Limine-Bootsektor auf '${disk}'!"
    echo ""

    if confirm "Limine BIOS auf '${disk}' installieren?"; then
        run_cmd "Installiere Limine BIOS-Stage" \
            limine bios-install "${disk}"
        run_cmd "Kopiere limine-bios.sys" \
            cp "${limine_data_dir}/limine-bios.sys" /boot/limine-bios.sys 2>/dev/null || true
        print_ok "Limine BIOS erfolgreich installiert."
    fi
    pause
}

limine_show_config() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ LIMINE KONFIGURATION ]${RESET}"
    separator
    echo ""

    local cfg_paths=(
        "/boot/limine.cfg"
        "/boot/limine/limine.cfg"
        "/boot/EFI/limine/limine.cfg"
        "/efi/limine.cfg"
    )

    local found=false
    for cfg in "${cfg_paths[@]}"; do
        if [[ -f "${cfg}" ]]; then
            print_info "Konfigurationsdatei: ${cfg}"
            echo ""
            awk '{print "  " $0}' "${cfg}"
            found=true
            break
        fi
    done

    if [[ "${found}" == false ]]; then
        print_warn "Keine limine.cfg gefunden."
        print_info "Gesuchte Pfade:"
        for p in "${cfg_paths[@]}"; do
            echo -e "    ${DIM}${p}${RESET}"
        done
    fi
    pause
}

limine_edit_config() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ LIMINE KONFIGURATION BEARBEITEN ]${RESET}"
    separator
    echo ""

    local cfg_paths=(
        "/boot/limine.cfg"
        "/boot/limine/limine.cfg"
        "/boot/EFI/limine/limine.cfg"
        "/efi/limine.cfg"
    )

    local cfg_file=""
    for cfg in "${cfg_paths[@]}"; do
        if [[ -f "${cfg}" ]]; then
            cfg_file="${cfg}"
            break
        fi
    done

    if [[ -z "${cfg_file}" ]]; then
        print_warn "Keine limine.cfg gefunden."
        read -rp "$(echo -e "  Pfad zur Konfigurationsdatei angeben: ")" cfg_file
        if [[ -z "${cfg_file}" ]]; then
            print_fail "Kein Pfad angegeben." ; pause ; return
        fi
    fi

    print_info "Bearbeite: ${cfg_file}"
    local editor="${EDITOR:-nano}"
    "${editor}" "${cfg_file}"
    print_ok "Konfiguration gespeichert."
    pause
}

limine_version() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ LIMINE VERSION ]${RESET}"
    separator
    echo ""
    limine --version 2>/dev/null | awk '{print "  " $0}'
    echo ""
    pacman -Qi limine 2>/dev/null | \
        grep -E '^(Name|Version|Installationsdatum|Installierte Größe)' | \
        awk '{print "  " $0}'
    pause
}

limine_register_efi() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ LIMINE EFI-EINTRAG REGISTRIEREN ]${RESET}"
    separator
    echo ""

    if ! command -v efibootmgr &>/dev/null; then
        print_warn "efibootmgr nicht installiert."
        print_info "Installieren mit: pacman -S efibootmgr"
        pause ; return
    fi

    local esp_path=""
    if command -v bootctl &>/dev/null; then
        esp_path=$(bootctl --print-esp-path 2>/dev/null || echo "")
    fi
    [[ -z "${esp_path}" ]] && esp_path="/boot"

    read -rp "$(echo -e "  ESP-Pfad [${esp_path}]: ")" input
    [[ -n "${input}" ]] && esp_path="${input}"

    local esp_dev
    esp_dev=$(findmnt -n -o SOURCE "${esp_path}" 2>/dev/null || echo "")

    if [[ -z "${esp_dev}" ]]; then
        print_warn "ESP-Partition konnte nicht automatisch erkannt werden."
        read -rp "$(echo -e "  ESP-Partition (z.B. /dev/sda1): ")" esp_dev
    fi

    if [[ -z "${esp_dev}" ]]; then
        print_fail "Keine ESP-Partition angegeben." ; pause ; return
    fi

    local disk="" part_num=""
    if parse_disk_and_part "${esp_dev}"; then
        disk="${PARSED_DISK}"
        part_num="${PARSED_PART}"
    else
        print_fail "Konnte Disk/Partition aus '${esp_dev}' nicht ermitteln."
        read -rp "$(echo -e "  Disk manuell eingeben (z.B. /dev/sda): ")" disk
        read -rp "$(echo -e "  Partitionsnummer (z.B. 1): ")" part_num
    fi

    print_info "ESP-Gerät    : ${esp_dev}"
    print_info "Disk         : ${disk}"
    print_info "Partition Nr.: ${part_num}"
    echo ""

    if confirm "Limine EFI-Eintrag in NVRAM registrieren?"; then
        run_cmd "Registriere Limine EFI-Eintrag" \
            efibootmgr --create \
                       --disk "${disk}" \
                       --part "${part_num}" \
                       --label "Limine" \
                       --loader "\\EFI\\limine\\BOOTX64.EFI" \
                       --unicode
        print_ok "EFI-Eintrag erfolgreich registriert."
    fi
    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  MODUL 6 – SYSTEM REPARATUR
# ─────────────────────────────────────────────────────────────────────────────

repair_menu() {
    while true; do
        print_header
        echo -e "  ${BOLD}${CYAN}[ SYSTEM REPARATUR ]${RESET}"
        separator
        echo ""
        echo -e "  ${BOLD}1)${RESET}  Paketdatenbank reparieren  ${DIM}(pacman -Syy)${RESET}"
        echo -e "  ${BOLD}2)${RESET}  Beschädigte Pakete prüfen  ${DIM}(pacman -Qk)${RESET}"
        echo -e "  ${BOLD}3)${RESET}  Verwaiste Pakete anzeigen  ${DIM}(pacman -Qdt)${RESET}"
        echo -e "  ${BOLD}4)${RESET}  Verwaiste Pakete entfernen"
        echo -e "  ${BOLD}5)${RESET}  Pacman-Schlüsselring reparieren"
        echo -e "  ${BOLD}6)${RESET}  Pacman-Cache leeren"
        echo -e "  ${BOLD}7)${RESET}  Systemd-Journal Fehler anzeigen"
        echo -e "  ${BOLD}8)${RESET}  Fehlgeschlagene Systemd-Dienste"
        echo -e "  ${BOLD}9)${RESET}  Dateisystem-Check (fsck) vorbereiten"
        echo -e "  ${BOLD}a)${RESET}  Paket-Integrität prüfen  ${DIM}(pacman -Qkk)${RESET}"
        echo -e "  ${BOLD}b)${RESET}  Verlorene Pakete neu installieren"
        echo -e "  ${BOLD}0)${RESET}  ${DIM}Zurück${RESET}"
        echo ""
        separator
        read -rp "$(echo -e "  ${BOLD}Auswahl: ${RESET}")" choice

        case "${choice}" in
            1) repair_pacman_db ;;
            2) repair_check_pkgs ;;
            3) repair_orphans_list ;;
            4) repair_orphans_remove ;;
            5) repair_keyring ;;
            6) repair_cache ;;
            7) repair_journal_errors ;;
            8) repair_failed_services ;;
            9) repair_fsck ;;
            a|A) repair_pkg_integrity ;;
            b|B) repair_reinstall_broken ;;
            0) return ;;
            *) print_warn "Ungültige Auswahl." ; sleep 1 ;;
        esac
    done
}

repair_pacman_db() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ PAKETDATENBANK REPARIEREN ]${RESET}"
    separator
    echo ""
    run_cmd "Synchronisiere Paketdatenbank (erzwungen)" pacman -Syy
    pause
}

repair_check_pkgs() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ BESCHÄDIGTE PAKETE PRÜFEN ]${RESET}"
    separator
    echo ""
    print_step "Prüfe Paket-Dateien (pacman -Qk)..."
    local result
    result=$(pacman -Qk 2>&1 | grep -v -E ': 0 (fehlende|missing)' | head -50 || true)
    if [[ -n "${result}" ]]; then
        echo "${result}" | awk '{print "  " $0}'
    else
        print_ok "Keine offensichtlich beschädigten Pakete gefunden."
    fi
    pause
}

repair_orphans_list() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ VERWAISTE PAKETE ]${RESET}"
    separator
    echo ""
    local orphans
    orphans=$(pacman -Qdt 2>/dev/null || true)
    if [[ -n "${orphans}" ]]; then
        print_warn "Folgende verwaiste Pakete gefunden:"
        echo "${orphans}" | awk '{print "  ● " $0}'
    else
        print_ok "Keine verwaisten Pakete gefunden."
    fi
    pause
}

repair_orphans_remove() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ VERWAISTE PAKETE ENTFERNEN ]${RESET}"
    separator
    echo ""
    local orphans
    orphans=$(pacman -Qdtq 2>/dev/null || true)
    if [[ -z "${orphans}" ]]; then
        print_ok "Keine verwaisten Pakete vorhanden."
        pause ; return
    fi
    print_warn "Zu entfernende Pakete:"
    echo "${orphans}" | awk '{print "  ● " $0}'
    echo ""
    if confirm "Alle verwaisten Pakete entfernen?"; then
        # shellcheck disable=SC2086
        run_cmd "Entferne verwaiste Pakete" pacman -Rns ${orphans}
    fi
    pause
}

repair_keyring() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ PACMAN SCHLÜSSELRING REPARIEREN ]${RESET}"
    separator
    echo ""
    print_warn "Dies initialisiert den Schlüsselring neu und lädt Arch-Schlüssel."
    print_warn "Der Schritt 'refresh-keys' kann mehrere Minuten dauern!"
    echo ""
    if confirm "Schlüsselring reparieren?"; then
        run_cmd "Initialisiere Schlüsselring" pacman-key --init
        run_cmd "Lade Arch-Schlüssel"         pacman-key --populate archlinux
        if confirm "Schlüssel online aktualisieren (kann langsam sein)?"; then
            run_cmd "Aktualisiere Schlüsselring"  pacman-key --refresh-keys
        fi
    fi
    pause
}

repair_cache() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ PACMAN CACHE LEEREN ]${RESET}"
    separator
    echo ""
    local cache_size
    cache_size=$(du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)
    print_info "Aktuelle Cache-Größe: ${cache_size}"
    echo ""
    echo -e "  ${BOLD}1)${RESET}  Nur veraltete Pakete entfernen  ${DIM}(paccache -r)${RESET}"
    echo -e "  ${BOLD}2)${RESET}  Gesamten Cache leeren  ${DIM}(pacman -Scc)${RESET}"
    echo ""
    read -rp "$(echo -e "  ${BOLD}Auswahl: ${RESET}")" sel
    case "${sel}" in
        1)
            if command -v paccache &>/dev/null; then
                run_cmd "Bereinige Cache (behalte 3 Versionen)" paccache -r
            else
                print_warn "paccache nicht gefunden. Installiere pacman-contrib."
            fi
            ;;
        2)
            if confirm "Gesamten Paket-Cache leeren?"; then
                run_cmd "Leere Pacman-Cache" pacman -Scc --noconfirm
            fi
            ;;
        *) print_warn "Ungültige Auswahl." ;;
    esac
    pause
}

repair_journal_errors() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ SYSTEMD JOURNAL FEHLER ]${RESET}"
    separator
    echo ""
    print_step "Letzte 30 Fehler/Warnungen aus dem Journal:"
    echo ""
    journalctl -p 3 -xn 30 --no-pager 2>/dev/null | awk '{print "  " $0}' || \
        print_warn "Journal nicht verfügbar."
    pause
}

repair_failed_services() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ FEHLGESCHLAGENE DIENSTE ]${RESET}"
    separator
    echo ""
    local failed
    failed=$(systemctl --failed --no-legend 2>/dev/null || true)
    if [[ -n "${failed}" ]]; then
        print_warn "Fehlgeschlagene Dienste:"
        echo "${failed}" | awk '{print "  ● " $0}'
        echo ""
        read -rp "$(echo -e "  Dienst-Name zum Neustart eingeben (leer = überspringen): ")" svc
        if [[ -n "${svc}" ]]; then
            if confirm "Dienst '${svc}' neu starten?"; then
                run_cmd "Starte Dienst neu: ${svc}" systemctl restart "${svc}"
            fi
        fi
    else
        print_ok "Keine fehlgeschlagenen Dienste gefunden."
    fi
    pause
}

repair_fsck() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ DATEISYSTEM-CHECK VORBEREITEN ]${RESET}"
    separator
    echo ""
    print_warn "Ein fsck kann nur auf nicht eingehängten Partitionen durchgeführt werden."
    print_info "Für Root-Partition: Kernel-Parameter 'fsck.mode=force' beim Boot setzen."
    echo ""
    echo -e "  ${BOLD}1)${RESET}  fsck beim nächsten Boot erzwingen  ${DIM}(Kernel-Parameter)${RESET}"
    echo -e "  ${BOLD}2)${RESET}  fsck auf separater Partition ausführen"
    echo ""
    read -rp "$(echo -e "  ${BOLD}Auswahl: ${RESET}")" sel
    case "${sel}" in
        1)
            print_info "Für systemd-basierte Systeme gibt es zwei Methoden:"
            echo ""
            echo -e "  ${BOLD}a)${RESET}  Kernel-Parameter 'fsck.mode=force' einmalig in GRUB setzen"
            echo -e "  ${BOLD}b)${RESET}  Legacy: /forcefsck erstellen (nur für initramfs mit fsck-Hook)"
            echo ""
            read -rp "$(echo -e "  ${BOLD}Methode: ${RESET}")" method
            case "${method}" in
                a|A)
                    print_info "Beim nächsten Boot in GRUB die Kernel-Zeile bearbeiten"
                    print_info "und 'fsck.mode=force' an die Kernel-Parameter anhängen."
                    print_info "Alternativ: Temporär in /etc/default/grub setzen und"
                    print_info "grub-mkconfig neu ausführen."
                    ;;
                b|B)
                    if confirm "fsck beim nächsten Boot erzwingen (Legacy-Methode)?"; then
                        touch /forcefsck
                        print_ok "/forcefsck erstellt – fsck wird beim nächsten Boot ausgeführt."
                    fi
                    ;;
                *) print_warn "Ungültige Auswahl." ;;
            esac
            ;;
        2)
            echo -e "\n  Eingehängte Partitionen:"
            lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | awk '{print "  " $0}'
            echo ""
            read -rp "$(echo -e "  Partition (z.B. /dev/sdb1): ")" part
            if [[ -b "${part}" ]]; then
                # Prüfen ob eingehängt
                if findmnt "${part}" &>/dev/null; then
                    print_fail "Partition '${part}' ist noch eingehängt!"
                    print_info "Bitte zuerst aushängen: umount ${part}"
                elif confirm "fsck auf '${part}' ausführen?"; then
                    run_cmd "Führe fsck aus auf ${part}" fsck -f "${part}"
                fi
            else
                print_fail "Gerät '${part}' nicht gefunden."
            fi
            ;;
        *) print_warn "Ungültige Auswahl." ;;
    esac
    pause
}

repair_pkg_integrity() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ PAKET-INTEGRITÄT PRÜFEN ]${RESET}"
    separator
    echo ""
    print_step "Vollständige Paket-Integritätsprüfung (pacman -Qkk)..."
    print_warn "Dies kann einige Minuten dauern..."
    echo ""
    pacman -Qkk 2>&1 | grep -v -E ': 0 (fehlende|missing)' | \
        awk '{print "  " $0}' | head -80
    print_ok "Prüfung abgeschlossen."
    pause
}

repair_reinstall_broken() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ BESCHÄDIGTE PAKETE NEU INSTALLIEREN ]${RESET}"
    separator
    echo ""
    print_step "Suche nach Paketen mit fehlenden Dateien..."
    local broken
    broken=$(pacman -Qk 2>/dev/null | grep -v ': 0' | awk -F: '{print $1}' || true)

    if [[ -z "${broken}" ]]; then
        print_ok "Keine beschädigten Pakete gefunden."
        pause ; return
    fi

    print_warn "Beschädigte Pakete:"
    echo "${broken}" | awk '{print "  ● " $0}'
    echo ""
    if confirm "Alle beschädigten Pakete neu installieren?"; then
        # shellcheck disable=SC2086
        run_cmd "Reinstalliere beschädigte Pakete" pacman -S --noconfirm ${broken}
    fi
    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  MODUL 7 – ERWEITERTE DIAGNOSE
# ─────────────────────────────────────────────────────────────────────────────

diagnostics_menu() {
    while true; do
        print_header
        echo -e "  ${BOLD}${CYAN}[ ERWEITERTE DIAGNOSE ]${RESET}"
        separator
        echo ""
        echo -e "  ${BOLD}1)${RESET}  Hardware-Informationen"
        echo -e "  ${BOLD}2)${RESET}  PCI-Geräte anzeigen"
        echo -e "  ${BOLD}3)${RESET}  USB-Geräte anzeigen"
        echo -e "  ${BOLD}4)${RESET}  Dmesg – Kernel-Meldungen"
        echo -e "  ${BOLD}5)${RESET}  Dmesg – Nur Fehler"
        echo -e "  ${BOLD}6)${RESET}  Netzwerk-Interfaces"
        echo -e "  ${BOLD}7)${RESET}  Festplatten-SMART-Status"
        echo -e "  ${BOLD}8)${RESET}  Systemd-Boot-Analyse"
        echo -e "  ${BOLD}9)${RESET}  Speichernutzung (Top-Prozesse)"
        echo -e "  ${BOLD}0)${RESET}  ${DIM}Zurück${RESET}"
        echo ""
        separator
        read -rp "$(echo -e "  ${BOLD}Auswahl: ${RESET}")" choice

        case "${choice}" in
            1) diag_hardware ;;
            2) diag_pci ;;
            3) diag_usb ;;
            4) diag_dmesg ;;
            5) diag_dmesg_errors ;;
            6) diag_network ;;
            7) diag_smart ;;
            8) diag_boot_analyze ;;
            9) diag_memory ;;
            0) return ;;
            *) print_warn "Ungültige Auswahl." ; sleep 1 ;;
        esac
    done
}

diag_hardware() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ HARDWARE-INFORMATIONEN ]${RESET}"
    separator
    echo ""
    if command -v inxi &>/dev/null; then
        inxi -Fxz 2>/dev/null | awk '{print "  " $0}'
    else
        print_warn "inxi nicht installiert. Zeige Basis-Infos:"
        echo ""
        echo -e "  ${BOLD}CPU:${RESET}"
        lscpu 2>/dev/null | grep -E '^(Architektur|CPU|Thread|Kern|Socket|Modell)' | \
            awk '{print "  " $0}'
        echo -e "\n  ${BOLD}RAM:${RESET}"
        free -h | awk '{print "  " $0}'
        echo -e "\n  ${BOLD}Blockgeräte:${RESET}"
        lsblk | awk '{print "  " $0}'
    fi
    pause
}

diag_pci() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ PCI-GERÄTE ]${RESET}"
    separator
    echo ""
    lspci 2>/dev/null | awk '{print "  " $0}' || \
        print_warn "lspci nicht verfügbar (pciutils installieren)."
    pause
}

diag_usb() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ USB-GERÄTE ]${RESET}"
    separator
    echo ""
    lsusb 2>/dev/null | awk '{print "  " $0}' || \
        print_warn "lsusb nicht verfügbar (usbutils installieren)."
    pause
}

diag_dmesg() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ KERNEL-MELDUNGEN (DMESG) ]${RESET}"
    separator
    echo ""
    dmesg --color=always -T 2>/dev/null | tail -50 | awk '{print "  " $0}'
    pause
}

diag_dmesg_errors() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ DMESG – NUR FEHLER ]${RESET}"
    separator
    echo ""
    local errors
    errors=$(dmesg -T --level=err,crit,alert,emerg 2>/dev/null || true)
    if [[ -n "${errors}" ]]; then
        echo "${errors}" | awk '{print "  " $0}'
    else
        print_ok "Keine kritischen Kernel-Fehler gefunden."
    fi
    pause
}

diag_network() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ NETZWERK-INTERFACES ]${RESET}"
    separator
    echo ""
    ip addr show 2>/dev/null | awk '{print "  " $0}'
    echo ""
    echo -e "  ${BOLD}── Routing-Tabelle ──────────────────────────────────${RESET}"
    ip route 2>/dev/null | awk '{print "  " $0}'
    pause
}

diag_smart() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ FESTPLATTEN SMART-STATUS ]${RESET}"
    separator
    echo ""
    if ! command -v smartctl &>/dev/null; then
        print_warn "smartmontools nicht installiert."
        print_info "Installieren mit: pacman -S smartmontools"
        pause ; return
    fi
    echo -e "  Verfügbare Festplatten:"
    lsblk -d -o NAME,SIZE,TYPE,MODEL | grep disk | awk '{print "  " $0}'
    echo ""
    read -rp "$(echo -e "  Festplatte prüfen (z.B. /dev/sda): ")" disk
    if [[ -b "${disk}" ]]; then
        run_cmd "SMART-Kurztest für ${disk}" smartctl -H "${disk}"
        echo ""
        smartctl -A "${disk}" 2>/dev/null | awk '{print "  " $0}'
    else
        print_fail "Gerät '${disk}' nicht gefunden."
    fi
    pause
}

diag_boot_analyze() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ SYSTEMD BOOT-ANALYSE ]${RESET}"
    separator
    echo ""
    systemd-analyze 2>/dev/null | awk '{print "  " $0}'
    echo ""
    echo -e "  ${BOLD}── Langsamste Dienste (Top 10) ──────────────────────${RESET}"
    systemd-analyze blame 2>/dev/null | head -10 | awk '{print "  " $0}'
    pause
}

diag_memory() {
    print_header
    echo -e "  ${BOLD}${CYAN}[ SPEICHERNUTZUNG ]${RESET}"
    separator
    echo ""
    echo -e "  ${BOLD}── RAM-Übersicht ─────────────────────────────────────${RESET}"
    free -h | awk '{print "  " $0}'
    echo ""
    echo -e "  ${BOLD}── Top 10 Prozesse nach RAM-Nutzung ─────────────────${RESET}"
    ps aux --sort=-%mem 2>/dev/null | head -11 | awk '{print "  " $0}'
    echo ""
    echo -e "  ${BOLD}── Top 10 Prozesse nach CPU-Nutzung ─────────────────${RESET}"
    ps aux --sort=-%cpu 2>/dev/null | head -11 | awk '{print "  " $0}'
    pause
}

# ─────────────────────────────────────────────────────────────────────────────
#  HAUPTMENÜ
# ─────────────────────────────────────────────────────────────────────────────

main_menu() {
    while true; do
        print_header
        echo -e "  ${BOLD}${CYAN}[ HAUPTMENÜ ]${RESET}"
        separator
        echo ""
        echo -e "  ${BOLD}${GREEN}1)${RESET}  Systemanalyse"
        echo -e "  ${BOLD}${GREEN}2)${RESET}  Kernel Management"
        echo -e "  ${BOLD}${GREEN}3)${RESET}  Initramfs / mkinitcpio"
        echo -e "  ${BOLD}${GREEN}4)${RESET}  GRUB Bootloader"
        echo -e "  ${BOLD}${GREEN}5)${RESET}  Limine Bootloader"
        echo -e "  ${BOLD}${GREEN}6)${RESET}  System Reparatur"
        echo -e "  ${BOLD}${GREEN}7)${RESET}  Erweiterte Diagnose"
        echo ""
        echo -e "  ${BOLD}${RED}0)${RESET}  ${DIM}Beenden${RESET}"
        echo ""
        separator
        echo -e "  ${DIM}Tipp: Script benötigt Root-Rechte für alle Funktionen.${RESET}"
        echo ""
        read -rp "$(echo -e "  ${BOLD}Auswahl: ${RESET}")" choice

        case "${choice}" in
            1) system_info ;;
            2) kernel_menu ;;
            3) initramfs_menu ;;
            4) grub_menu ;;
            5) limine_menu ;;
            6) repair_menu ;;
            7) diagnostics_menu ;;
            0)
                echo ""
                echo -e "  ${GREEN}Auf Wiedersehen!${RESET}"
                echo ""
                exit 0
                ;;
            *)
                print_warn "Ungültige Auswahl."
                sleep 1
                ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
#  EINSTIEGSPUNKT
# ─────────────────────────────────────────────────────────────────────────────

main() {
    check_root "$@"
    main_menu
}

main "$@"
