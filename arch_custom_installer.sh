#!/bin/bash
###############################################################################
#  ARCH LINUX CUSTOM INSTALLER v2.0
#  Basiert auf archinstall 4.1 (April 2026)
#  EFI | Plasma/GNOME/Server | LTS-Kernel | Limine/GRUB | Pipewire
#  Deutsche Mirrorlist, Sprache & Tastatur
###############################################################################

set -uo pipefail

# ─── Farben & Formatierung ───────────────────────────────────────────────────
readonly ROT='\033[1;31m'
readonly GRUEN='\033[1;32m'
readonly GELB='\033[1;33m'
readonly BLAU='\033[1;34m'
readonly CYAN='\033[1;36m'
readonly MAGENTA='\033[1;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly RESET='\033[0m'

# ─── Globale Variablen (Standardwerte) ──────────────────────────────────────
INSTALL_DISK=""
BOOTLOADER="grub"
DESKTOP="plasma"
KERNEL="linux-lts"
DATEISYSTEM="btrfs"
HOSTNAME_VAL="archlinux"
BENUTZERNAME=""
BENUTZER_PASSWORT=""
ROOT_PASSWORT=""
SWAP_AKTIV="true"
TASTATUR="de-latin1"
LOCALE="de_DE.UTF-8"
ZEITZONE="Europe/Berlin"
ZUSATZ_PAKETE=""
VERSCHLUESSELUNG="false"
VERSCHL_PASSWORT=""

# ─── Hilfsfunktionen ────────────────────────────────────────────────────────

banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
    ╔═════════════════════════════════════════════════════════════╗
    ║                       ARCH LINUX                            ║
    ║                   CUSTOM INSTALLER v2.0                     ║
    ║                                                             ║
    ║           Basiert auf archinstall 4.1 (April 2026)          ║
    ║           EFI • LTS-Kernel • Pipewire • Deutsch             ║
    ╚═════════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
}

info()    { echo -e "  ${BLAU}[INFO]${RESET}  $1"; }
erfolg()  { echo -e "  ${GRUEN}[  OK]${RESET}  $1"; }
warnung() { echo -e "  ${GELB}[WARN]${RESET}  $1"; }
fehler()  { echo -e "  ${ROT}[FAIL]${RESET}  $1"; }

linie() {
    echo -e "  ${DIM}──────────────────────────────────────────────────────${RESET}"
}

pause_msg() {
    echo ""
    echo -ne "  ${DIM}Weiter mit [Enter]...${RESET}"
    read -r
}

# ─── Prüfungen ───────────────────────────────────────────────────────────────

pruefe_voraussetzungen() {
    banner
    echo -e "  ${BOLD}Systemprüfung${RESET}"
    linie

    # Root?
    if [[ $EUID -ne 0 ]]; then
        fehler "Dieses Skript muss als root ausgeführt werden!"
        exit 1
    fi
    erfolg "Root-Rechte vorhanden"

    # EFI?
    if [[ ! -d /sys/firmware/efi ]]; then
        fehler "Kein EFI-System erkannt! Dieses Skript unterstützt nur EFI."
        exit 1
    fi
    erfolg "EFI-Modus erkannt"

    # Internet?
    if ping -c 1 -W 3 archlinux.org &>/dev/null; then
        erfolg "Internetverbindung vorhanden"
    else
        warnung "Keine Internetverbindung erkannt!"
        echo -e "  ${GELB}       Bitte Netzwerk einrichten (z.B. iwctl für WLAN)${RESET}"
        pause_msg
    fi

    # archinstall vorhanden?
    if command -v archinstall &>/dev/null; then
        local ai_version
        ai_version=$(archinstall --version 2>/dev/null || echo "unbekannt")
        erfolg "archinstall gefunden: ${ai_version}"
    else
        fehler "archinstall nicht gefunden! Bitte Arch Linux ISO verwenden."
        exit 1
    fi

    # Keyring aktualisieren
    info "Aktualisiere Keyring..."
    pacman -Sy --noconfirm archlinux-keyring &>/dev/null && \
        erfolg "Keyring aktualisiert" || \
        warnung "Keyring-Update fehlgeschlagen"

    pause_msg
}

# ─── Menü-Hilfsfunktion ─────────────────────────────────────────────────────

waehle_option() {
    local titel="$1"
    shift
    local optionen=("$@")
    local auswahl=0
    local anzahl=${#optionen[@]}
    local taste=""

    # Anzahl Zeilen die pro Durchlauf gezeichnet werden:
    # 1 (Leerzeile von \n) + 1 (Titel) + 1 (Linie) + $anzahl (Optionen) + 1 (Linie) + 1 (Hinweis)
    local zeilen=$((anzahl + 5))

    # Erstes Zeichnen
    _zeichne_menue() {
        echo ""
        echo -e "  ${BOLD}${titel}${RESET}"
        linie
        for i in "${!optionen[@]}"; do
            if [[ $i -eq $auswahl ]]; then
                echo -e "  ${CYAN}▶ ${BOLD}${optionen[$i]}${RESET}"
            else
                echo -e "    ${optionen[$i]}"
            fi
        done
        linie
        echo -e "  ${DIM}[↑/↓] Navigieren  [Enter] Auswählen${RESET}"
    }

    _zeichne_menue

    while true; do
        # Tasteneingabe lesen
        IFS= read -rsn1 taste
        case "$taste" in
            $'\x1b')
                read -rsn2 taste
                case "$taste" in
                    '[A')  # Pfeil hoch
                        if [[ $auswahl -gt 0 ]]; then
                            auswahl=$((auswahl - 1))
                        fi
                        ;;
                    '[B')  # Pfeil runter
                        if [[ $auswahl -lt $((anzahl - 1)) ]]; then
                            auswahl=$((auswahl + 1))
                        fi
                        ;;
                esac
                ;;
            '')  # Enter
                break
                ;;
            *)
                continue
                ;;
        esac

        # Cursor zurücksetzen und Zeilen löschen
        local z
        for ((z = 0; z < zeilen; z++)); do
            echo -ne "\033[1A\033[2K"
        done

        _zeichne_menue
    done

    return "$auswahl"
}

# ─── Festplatte wählen ──────────────────────────────────────────────────────

waehle_festplatte() {
    banner
    echo -e "  ${BOLD}1/9 — Zielfestplatte${RESET}"
    linie

    mapfile -t disks < <(lsblk -dnpo NAME,SIZE,MODEL,TYPE | grep "disk" | awk '{print $1 " (" $2 ") " $3 " " $4}')

    if [[ ${#disks[@]} -eq 0 ]]; then
        fehler "Keine Festplatten gefunden!"
        exit 1
    fi

    echo ""
    echo -e "  ${GELB}⚠  ACHTUNG: Alle Daten auf der gewählten Festplatte werden gelöscht!${RESET}"

    waehle_option "Verfügbare Festplatten:" "${disks[@]}"
    local idx=$?
    INSTALL_DISK=$(echo "${disks[$idx]}" | awk '{print $1}')
    erfolg "Gewählt: ${INSTALL_DISK}"
    pause_msg
}

# ─── Bootloader wählen ──────────────────────────────────────────────────────

waehle_bootloader() {
    banner
    echo -e "  ${BOLD}2/9 — Bootloader${RESET}"

    local optionen=(
        "GRUB          — Klassiker, universell, Boot-Menü, Btrfs-Snapshots"
        "Limine        — Ultraschnell, modern, minimalistisch"
        "Systemd-boot  — Einfach, schnell, EFI-nativ"
    )

    waehle_option "Bootloader wählen:" "${optionen[@]}"
    case $? in
        0) BOOTLOADER="Grub"        ; erfolg "Bootloader: GRUB" ;;
        1) BOOTLOADER="Limine"      ; erfolg "Bootloader: Limine" ;;
        2) BOOTLOADER="Systemd-boot"; erfolg "Bootloader: Systemd-boot" ;;
    esac
    pause_msg
}

# ─── Desktop wählen ─────────────────────────────────────────────────────────

waehle_desktop() {
    banner
    echo -e "  ${BOLD}3/9 — Desktop-Umgebung${RESET}"

    local optionen=(
        "KDE Plasma    — Modern, anpassbar, Wayland-ready"
        "GNOME         — Clean, touchfreundlich, Erweiterungen"
        "Server        — Headless, SSH, Firewall, Server-Pakete"
        "Ohne Desktop  — Nur Basissystem (Minimal)"
    )

    waehle_option "Desktop-Umgebung wählen:" "${optionen[@]}"
    case $? in
        0) DESKTOP="kde"    ; erfolg "Desktop: KDE Plasma" ;;
        1) DESKTOP="gnome"  ; erfolg "Desktop: GNOME" ;;
        2) DESKTOP="server" ; erfolg "Profil: Server (Headless)" ;;
        3) DESKTOP="none"   ; erfolg "Desktop: Keiner (Minimal)" ;;
    esac
    pause_msg
}

# ─── Kernel wählen ──────────────────────────────────────────────────────────

waehle_kernel() {
    banner
    echo -e "  ${BOLD}4/9 — Kernel${RESET}"

    local optionen=(
        "linux-lts     — Langzeitstabil, empfohlen für Produktivsysteme"
        "linux         — Standard-Kernel, neueste Features"
        "linux-zen     — Desktop-optimiert, bessere Latenz, Gaming"
        "linux-lts + linux  — Beide installieren (Fallback)"
    )

    waehle_option "Kernel wählen:" "${optionen[@]}"
    case $? in
        0) KERNEL="linux-lts"             ; erfolg "Kernel: linux-lts" ;;
        1) KERNEL="linux"                 ; erfolg "Kernel: linux" ;;
        2) KERNEL="linux-zen"             ; erfolg "Kernel: linux-zen" ;;
        3) KERNEL="linux-lts linux"       ; erfolg "Kernel: linux-lts + linux" ;;
    esac
    pause_msg
}

# ─── Dateisystem wählen ─────────────────────────────────────────────────────

waehle_dateisystem() {
    banner
    echo -e "  ${BOLD}5/9 — Dateisystem${RESET}"

    local optionen=(
        "Btrfs   — Snapshots, Kompression, CoW, empfohlen"
        "Ext4    — Bewährt, stabil, einfach"
        "XFS     — Performant bei großen Dateien"
    )

    waehle_option "Dateisystem wählen:" "${optionen[@]}"
    case $? in
        0) DATEISYSTEM="btrfs" ; erfolg "Dateisystem: Btrfs" ;;
        1) DATEISYSTEM="ext4"  ; erfolg "Dateisystem: Ext4" ;;
        2) DATEISYSTEM="xfs"   ; erfolg "Dateisystem: XFS" ;;
    esac
    pause_msg
}

# ─── Tastaturlayout wählen ──────────────────────────────────────────────────

waehle_tastatur() {
    banner
    echo -e "  ${BOLD}6/9 — Tastaturlayout${RESET}"

    local optionen=(
        "de-latin1          — Deutsch (Standard)"
        "de-latin1-nodeadkeys — Deutsch ohne Tottasten"
        "de-neo              — Neo-Tastaturlayout"
        "de                  — Deutsch (einfach)"
        "us                  — US-Amerikanisch"
        "ch-de               — Schweizerdeutsch"
        "at                  — Österreichisch"
    )

    waehle_option "Tastaturlayout wählen:" "${optionen[@]}"
    case $? in
        0) TASTATUR="de-latin1"           ;;
        1) TASTATUR="de-latin1-nodeadkeys";;
        2) TASTATUR="de-neo"              ;;
        3) TASTATUR="de"                  ;;
        4) TASTATUR="us"                  ;;
        5) TASTATUR="ch-de"               ;;
        6) TASTATUR="at"                  ;;
    esac
    erfolg "Tastatur: ${TASTATUR}"
    pause_msg
}

# ─── Benutzerdaten eingeben ─────────────────────────────────────────────────

eingabe_benutzer() {
    banner
    echo -e "  ${BOLD}7/9 — Benutzerkonfiguration${RESET}"
    linie

    # Hostname
    echo -ne "  ${BOLD}Hostname${RESET} [archlinux]: "
    read -r eingabe
    HOSTNAME_VAL="${eingabe:-archlinux}"
    erfolg "Hostname: ${HOSTNAME_VAL}"
    echo ""

    # Benutzername
    while [[ -z "$BENUTZERNAME" ]]; do
        echo -ne "  ${BOLD}Benutzername${RESET}: "
        read -r BENUTZERNAME
        if [[ -z "$BENUTZERNAME" ]]; then
            warnung "Benutzername darf nicht leer sein!"
        fi
    done
    erfolg "Benutzer: ${BENUTZERNAME}"
    echo ""

    # Benutzer-Passwort
    while true; do
        echo -ne "  ${BOLD}Passwort für ${BENUTZERNAME}${RESET}: "
        read -rs BENUTZER_PASSWORT
        echo ""
        echo -ne "  ${BOLD}Passwort bestätigen${RESET}: "
        read -rs pw_confirm
        echo ""
        if [[ "$BENUTZER_PASSWORT" == "$pw_confirm" && -n "$BENUTZER_PASSWORT" ]]; then
            erfolg "Benutzer-Passwort gesetzt"
            break
        else
            warnung "Passwörter stimmen nicht überein oder sind leer!"
        fi
    done
    echo ""

    # Root-Passwort
    echo -e "  ${DIM}Root-Passwort (leer = gleich wie Benutzer-Passwort):${RESET}"
    echo -ne "  ${BOLD}Root-Passwort${RESET}: "
    read -rs ROOT_PASSWORT
    echo ""
    if [[ -z "$ROOT_PASSWORT" ]]; then
        ROOT_PASSWORT="$BENUTZER_PASSWORT"
        info "Root-Passwort = Benutzer-Passwort"
    else
        erfolg "Separates Root-Passwort gesetzt"
    fi

    pause_msg
}

# ─── Zusatzoptionen ─────────────────────────────────────────────────────────

zusatzoptionen() {
    banner
    echo -e "  ${BOLD}8/9 — Zusatzoptionen${RESET}"
    linie

    # Verschlüsselung
    local optionen_crypt=("Nein  — Keine Verschlüsselung" "Ja    — LUKS-Vollverschlüsselung")
    waehle_option "Festplattenverschlüsselung (LUKS):" "${optionen_crypt[@]}"
    case $? in
        0) VERSCHLUESSELUNG="false" ;;
        1)
            VERSCHLUESSELUNG="true"
            echo ""
            while true; do
                echo -ne "  ${BOLD}Verschlüsselungs-Passwort${RESET}: "
                read -rs VERSCHL_PASSWORT
                echo ""
                echo -ne "  ${BOLD}Passwort bestätigen${RESET}: "
                read -rs pw_c
                echo ""
                if [[ "$VERSCHL_PASSWORT" == "$pw_c" && -n "$VERSCHL_PASSWORT" ]]; then
                    erfolg "Verschlüsselungs-Passwort gesetzt"
                    break
                else
                    warnung "Passwörter stimmen nicht überein!"
                fi
            done
            ;;
    esac

    echo ""

    # Zusätzliche Pakete
    echo -e "  ${BOLD}Zusätzliche Pakete${RESET} ${DIM}(Leerzeichen-getrennt, leer = keine):${RESET}"
    echo -e "  ${DIM}Beispiel: firefox vim htop neofetch${RESET}"
    echo -ne "  > "
    read -r ZUSATZ_PAKETE
    if [[ -n "$ZUSATZ_PAKETE" ]]; then
        erfolg "Zusatzpakete: ${ZUSATZ_PAKETE}"
    else
        info "Keine Zusatzpakete"
    fi

    pause_msg
}

# ─── Zusammenfassung & Bestätigung ──────────────────────────────────────────

zusammenfassung() {
    banner
    echo -e "  ${BOLD}9/9 — Zusammenfassung${RESET}"
    linie
    echo ""
    echo -e "  ${BOLD}Festplatte:${RESET}       ${INSTALL_DISK}"
    echo -e "  ${BOLD}Dateisystem:${RESET}      ${DATEISYSTEM}"
    echo -e "  ${BOLD}Bootloader:${RESET}       ${BOOTLOADER}"
    echo -e "  ${BOLD}Desktop:${RESET}          ${DESKTOP}"
    echo -e "  ${BOLD}Kernel:${RESET}           ${KERNEL}"
    echo -e "  ${BOLD}Tastatur:${RESET}         ${TASTATUR}"
    echo -e "  ${BOLD}Sprache:${RESET}          ${LOCALE}"
    echo -e "  ${BOLD}Zeitzone:${RESET}         ${ZEITZONE}"
    echo -e "  ${BOLD}Hostname:${RESET}         ${HOSTNAME_VAL}"
    echo -e "  ${BOLD}Benutzer:${RESET}         ${BENUTZERNAME} (sudo)"
    echo -e "  ${BOLD}Audio:${RESET}            Pipewire"
    echo -e "  ${BOLD}Swap:${RESET}             Zram (dynamisch)"
    echo -e "  ${BOLD}Verschlüsselung:${RESET}  ${VERSCHLUESSELUNG}"
    echo -e "  ${BOLD}Mirrorlist:${RESET}       Deutschland"
    [[ -n "$ZUSATZ_PAKETE" ]] && \
    echo -e "  ${BOLD}Zusatzpakete:${RESET}     ${ZUSATZ_PAKETE}"
    echo ""
    linie
    echo ""
    echo -e "  ${ROT}${BOLD}⚠  WARNUNG: Alle Daten auf ${INSTALL_DISK} werden UNWIDERRUFLICH gelöscht!${RESET}"
    echo ""
    echo -ne "  Installation starten? [j/N]: "
    read -r bestaetigung
    if [[ "${bestaetigung,,}" != "j" && "${bestaetigung,,}" != "ja" ]]; then
        info "Installation abgebrochen."
        exit 0
    fi
}

# ─── Deutsche Mirrorlist konfigurieren ──────────────────────────────────────

konfiguriere_mirrors() {
    info "Konfiguriere deutsche Mirrorlist..."

    # Reflector verwenden falls vorhanden
    if command -v reflector &>/dev/null; then
        reflector --country Germany --age 12 --protocol https \
                  --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null && \
            erfolg "Mirrorlist via Reflector aktualisiert (Deutschland)" && return
    fi

    # Fallback: Manuelle deutsche Mirrors
    cat > /etc/pacman.d/mirrorlist << 'MIRRORS'
## Deutschland — generiert von arch_custom_installer.sh
Server = https://ftp.fau.de/archlinux/$repo/os/$arch
Server = https://mirror.informatik.tu-freiberg.de/arch/$repo/os/$arch
Server = https://ftp.halifax.rwth-aachen.de/archlinux/$repo/os/$arch
Server = https://mirror.pseudoform.org/$repo/os/$arch
Server = https://ftp.gwdg.de/pub/linux/archlinux/$repo/os/$arch
Server = https://mirror.fra10.de.leaseweb.net/archlinux/$repo/os/$arch
Server = https://arch.mirror.far.fi/$repo/os/$arch
Server = https://ftp.spline.inf.fu-berlin.de/mirrors/archlinux/$repo/os/$arch
Server = https://packages.oth-regensburg.de/archlinux/$repo/os/$arch
Server = https://mirror.mikrogravitation.org/archlinux/$repo/os/$arch
MIRRORS
    erfolg "Deutsche Mirrorlist manuell konfiguriert"
}

# ─── JSON-Konfiguration generieren ──────────────────────────────────────────

generiere_config() {
    info "Generiere archinstall-Konfiguration..."

    local config_dir="/tmp/archinstall_custom"
    mkdir -p "$config_dir"

    # --- Kernel-Liste ---
    local kernel_json=""
    for k in $KERNEL; do
        [[ -n "$kernel_json" ]] && kernel_json+=","
        kernel_json+="\"$k\""
    done

    # --- Profil (Desktop) ---
    local profil_json=""
    case "$DESKTOP" in
        kde)
            profil_json='{
                "details": ["kde"],
                "main": "Desktop",
                "sub": "kde"
            }'
            ;;
        gnome)
            profil_json='{
                "details": ["gnome"],
                "main": "Desktop",
                "sub": "gnome"
            }'
            ;;
        none)
            profil_json='{
                "main": "Minimal"
            }'
            ;;
        server)
            profil_json='{
                "main": "Server"
            }'
            ;;
    esac

    # --- Disk-Config ---
    local mount_opts=""
    [[ "$DATEISYSTEM" == "btrfs" ]] && mount_opts='"compress=zstd"'

    local disk_json
    disk_json=$(cat << DISKEOF
{
    "config_type": "default_layout",
    "device_modifications": [
        {
            "device": "${INSTALL_DISK}",
            "partitions": [
                {
                    "btrfs": [],
                    "dev_path": null,
                    "flags": ["Boot", "ESP"],
                    "fs_type": "fat32",
                    "mount_options": [],
                    "mountpoint": "/boot",
                    "obj_id": "efi-part-001",
                    "size": {
                        "sector_size": {"unit": "B", "value": 512},
                        "unit": "GiB",
                        "value": 1
                    },
                    "start": {
                        "sector_size": {"unit": "B", "value": 512},
                        "unit": "MiB",
                        "value": 1
                    },
                    "status": "create",
                    "type": "primary"
                },
                {
                    "btrfs": [],
                    "dev_path": null,
                    "flags": [],
                    "fs_type": "${DATEISYSTEM}",
                    "mount_options": [${mount_opts}],
                    "mountpoint": "/",
                    "obj_id": "root-part-001",
                    "size": {
                        "sector_size": {"unit": "B", "value": 512},
                        "unit": "Percent",
                        "value": 100
                    },
                    "start": {
                        "sector_size": {"unit": "B", "value": 512},
                        "unit": "GiB",
                        "value": 1
                    },
                    "status": "create",
                    "type": "primary"
                }
            ],
            "wipe": true
        }
    ]
}
DISKEOF
    )

    # --- Verschlüsselung ---
    local encryption_json="null"
    if [[ "$VERSCHLUESSELUNG" == "true" ]]; then
        encryption_json="{
            \"encryption_type\": \"luks\",
            \"partitions\": [\"root-part-001\"]
        }"
    fi

    # --- Zusatzpakete ---
    local pakete_json=""

    # Server-Profil: automatisch Server-Pakete hinzufügen
    if [[ "$DESKTOP" == "server" ]]; then
        local server_pkgs="openssh ufw rsync htop tmux curl wget git nano vim bind-tools"
        for pkg in $server_pkgs; do
            [[ -n "$pakete_json" ]] && pakete_json+=","
            pakete_json+="\"$pkg\""
        done
    fi

    if [[ -n "$ZUSATZ_PAKETE" ]]; then
        for pkg in $ZUSATZ_PAKETE; do
            [[ -n "$pakete_json" ]] && pakete_json+=","
            pakete_json+="\"$pkg\""
        done
    fi

    # --- Tastatur-Mapping für X/Wayland ---
    local kb_layout="de"
    local kb_variant=""
    case "$TASTATUR" in
        de-latin1)            kb_layout="de" ; kb_variant="" ;;
        de-latin1-nodeadkeys) kb_layout="de" ; kb_variant="nodeadkeys" ;;
        de-neo)               kb_layout="de" ; kb_variant="neo" ;;
        de)                   kb_layout="de" ; kb_variant="" ;;
        us)                   kb_layout="us" ; kb_variant="" ;;
        ch-de)                kb_layout="ch" ; kb_variant="de" ;;
        at)                   kb_layout="at" ; kb_variant="" ;;
    esac

    # --- GFX-Driver & Custom-Commands ---
    local gfx_driver='"All open-source"'
    local custom_commands=""
    if [[ "$DESKTOP" == "server" ]]; then
        gfx_driver="null"
        custom_commands=',
    "custom-commands": [
        "systemctl enable sshd",
        "systemctl enable ufw",
        "ufw default deny incoming",
        "ufw default allow outgoing",
        "ufw allow ssh",
        "ufw enable"
    ]'
    fi

    # === user_configuration.json ===
    cat > "${config_dir}/user_configuration.json" << CONFIGEOF
{
    "additional-repositories": ["multilib"],
    "archinstall-language": "Deutsch",
    "audio_config": {
        "audio": "pipewire"
    },
    "bootloader": "${BOOTLOADER}",
    "config_version": "4.1",
    "debug": false,
    "disk_config": ${disk_json},
    "disk_encryption": ${encryption_json},
    "hostname": "${HOSTNAME_VAL}",
    "kernels": [${kernel_json}],
    "locale_config": {
        "kb_layout": "${kb_layout}",
        "kb_variant": "${kb_variant}",
        "sys_enc": "UTF-8",
        "sys_lang": "${LOCALE}"
    },
    "mirror_config": {
        "custom_mirrors": [],
        "mirror_regions": {
            "Germany": [
                "https://ftp.fau.de/archlinux/\$repo/os/\$arch",
                "https://ftp.halifax.rwth-aachen.de/archlinux/\$repo/os/\$arch",
                "https://ftp.gwdg.de/pub/linux/archlinux/\$repo/os/\$arch"
            ]
        }
    },
    "network_config": {
        "type": "nm"
    },
    "no_pkg_lookups": false,
    "ntp": true,
    "packages": [${pakete_json}],
    "parallel_downloads": 5,
    "profile_config": {
        "gfx_driver": ${gfx_driver},
        "profile": ${profil_json}
    },
    "swap": true,
    "timezone": "${ZEITZONE}",
    "version": "4.1"${custom_commands}
}
CONFIGEOF

    # === user_credentials.json ===
    cat > "${config_dir}/user_credentials.json" << CREDEOF
{
    "!root-password": "${ROOT_PASSWORT}",
    "!users": [
        {
            "!password": "${BENUTZER_PASSWORT}",
            "sudo": true,
            "username": "${BENUTZERNAME}"
        }
    ]
}
CREDEOF

    # Berechtigungen setzen
    chmod 600 "${config_dir}/user_credentials.json"

    erfolg "Konfiguration generiert: ${config_dir}/"
    echo -e "  ${DIM}  → user_configuration.json${RESET}"
    echo -e "  ${DIM}  → user_credentials.json${RESET}"
}

# ─── Installation ausführen ─────────────────────────────────────────────────

starte_installation() {
    banner
    echo -e "  ${BOLD}${GRUEN}Installation wird gestartet...${RESET}"
    linie
    echo ""

    local config_dir="/tmp/archinstall_custom"

    # Tastatur setzen
    info "Setze Tastaturlayout: ${TASTATUR}"
    loadkeys "$TASTATUR" 2>/dev/null || true

    # NTP aktivieren
    info "Aktiviere Zeitsynchronisation..."
    timedatectl set-ntp true 2>/dev/null || true

    # Mirrors konfigurieren
    konfiguriere_mirrors

    echo ""
    info "Starte archinstall mit generierter Konfiguration..."
    echo ""
    linie
    echo ""

    # archinstall ausführen
    archinstall \
        --config "${config_dir}/user_configuration.json" \
        --creds "${config_dir}/user_credentials.json" \
        --silent

    local exit_code=$?

    echo ""
    linie

    if [[ $exit_code -eq 0 ]]; then
        echo ""
        echo -e "  ${GRUEN}${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
        echo -e "  ${GRUEN}${BOLD}║  ✔ Installation erfolgreich abgeschlossen!      ║${RESET}"
        echo -e "  ${GRUEN}${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo -e "  Konfiguration gespeichert unter:"
        echo -e "  ${DIM}${config_dir}/user_configuration.json${RESET}"
        echo -e "  ${DIM}/var/log/archinstall/install.log${RESET}"
        echo ""

        # Post-Install Hinweise
        echo -e "  ${BOLD}Nächste Schritte:${RESET}"
        echo -e "  ${CYAN}1.${RESET} USB-Stick entfernen"
        echo -e "  ${CYAN}2.${RESET} System neu starten: ${BOLD}reboot${RESET}"
        echo -e "  ${CYAN}3.${RESET} Anmelden als: ${BOLD}${BENUTZERNAME}${RESET}"
        echo ""
    else
        echo ""
        fehler "Installation fehlgeschlagen! (Exit-Code: ${exit_code})"
        echo -e "  ${DIM}Logdatei: /var/log/archinstall/install.log${RESET}"
        echo ""
        echo -ne "  Logdatei anzeigen? [j/N]: "
        read -r show_log
        if [[ "${show_log,,}" == "j" ]]; then
            less /var/log/archinstall/install.log 2>/dev/null || \
                cat /var/log/archinstall/install.log 2>/dev/null
        fi
    fi
}

# ─── Hauptmenü ──────────────────────────────────────────────────────────────

hauptmenue() {
    while true; do
        banner

        # Aktuelle Konfiguration anzeigen falls vorhanden
        if [[ -n "$INSTALL_DISK" ]]; then
            echo -e "  ${DIM}Aktuelle Konfiguration:${RESET}"
            echo -e "  ${DIM}Disk=${INSTALL_DISK} Boot=${BOOTLOADER} DE=${DESKTOP} Kern=${KERNEL} FS=${DATEISYSTEM} KB=${TASTATUR}${RESET}"
            linie
        fi

        local optionen=(
            "▸ Schnellinstallation   — Alle Schritte nacheinander"
            "▸ Festplatte wählen     — Zieldatenträger auswählen"
            "▸ Bootloader wählen     — GRUB / Limine / Systemd-boot"
            "▸ Desktop wählen        — KDE Plasma / GNOME / Server / Minimal"
            "▸ Kernel wählen         — LTS / Standard / Zen"
            "▸ Dateisystem wählen    — Btrfs / Ext4 / XFS"
            "▸ Tastatur wählen       — Tastaturlayout konfigurieren"
            "▸ Benutzer einrichten   — Hostname, Benutzer, Passwörter"
            "▸ Zusatzoptionen        — Verschlüsselung, Pakete"
            "▸ Zusammenfassung       — Prüfen & Installation starten"
            "▸ Beenden"
        )

        waehle_option "Hauptmenü — Arch Linux Installer" "${optionen[@]}"
        case $? in
            0)  # Schnellinstallation
                waehle_festplatte
                waehle_bootloader
                waehle_desktop
                waehle_kernel
                waehle_dateisystem
                waehle_tastatur
                eingabe_benutzer
                zusatzoptionen
                zusammenfassung
                generiere_config
                starte_installation
                exit 0
                ;;
            1)  waehle_festplatte ;;
            2)  waehle_bootloader ;;
            3)  waehle_desktop ;;
            4)  waehle_kernel ;;
            5)  waehle_dateisystem ;;
            6)  waehle_tastatur ;;
            7)  eingabe_benutzer ;;
            8)  zusatzoptionen ;;
            9)
                if [[ -z "$INSTALL_DISK" || -z "$BENUTZERNAME" ]]; then
                    warnung "Bitte zuerst Festplatte und Benutzer konfigurieren!"
                    pause_msg
                else
                    zusammenfassung
                    generiere_config
                    starte_installation
                    exit 0
                fi
                ;;
            10) echo -e "\n  ${DIM}Auf Wiedersehen!${RESET}\n" ; exit 0 ;;
        esac
    done
}

# ─── Einstiegspunkt ─────────────────────────────────────────────────────────

main() {
    # Sudo/Root-Prüfung mit Passwort-Abfrage
    if [[ $EUID -ne 0 ]]; then
        echo -e "${CYAN}${BOLD}"
        echo "  ┌──────────────────────────────────────────┐"
        echo "  │   ARCH LINUX CUSTOM INSTALLER v2.0       │"
        echo "  │   Root-Rechte werden benötigt.           │"
        echo "  └──────────────────────────────────────────┘"
        echo -e "${RESET}"
        exec sudo -E "$0" "$@"
        exit 1
    fi

    # Prüfungen
    pruefe_voraussetzungen

    # Hauptmenü starten
    hauptmenue
}

main "$@"
