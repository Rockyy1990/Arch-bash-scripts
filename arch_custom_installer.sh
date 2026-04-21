#!/usr/bin/env bash
###############################################################################
#  ARCH LINUX CUSTOM INSTALLER v2.2
#  Basiert auf archinstall 2.8.x / Release 4.2 (April 2026)
#  EFI | Plasma/GNOME/Server | LTS-Kernel | Grub/Limine/systemd-boot | Pipewire
#  Deutsche Mirrorlist, Sprache & Tastatur
#
#  Änderungen ggü. v2.1 (Produktionsreife-Fixes):
#   • NEU: --dry-run Flag — archinstall im Simulationsmodus (ohne Änderungen)
#   • Sichere lsblk-Auswertung via lsblk -J + python3 (kein eval mehr)
#   • Trap auf SIGINT/SIGTERM wird während archinstall deaktiviert
#     (verhindert Cleanup der Credentials während laufender Installation)
#   • Root-Passwort-Längencheck + Bestätigung (Parität zum Benutzer-PW)
#   • encryption_password nur bei aktivem LUKS in Creds schreiben
#   • Mindest-Plattengröße-Prüfung (8 GiB) vor Installation
#   • CONFIG_DIR via mktemp -d (unvorhersagbarer Pfad)
#   • pacman -Syy nach Mirror-Wechsel (konsistenter Start)
#   • Präzisere Mount-Erkennung via lsblk statt findmnt/grep
#
#  VERWENDUNG:
#    sudo ./arch_custom_installer.sh             # echte Installation
#    sudo ./arch_custom_installer.sh --dry-run   # nur Simulation (empfohlen für ersten Test)
#    sudo ./arch_custom_installer.sh --help      # Hilfe
#
#  Änderungen v2.0 → v2.1:
#   • bootloader_config-Objektstruktur (neues Schema)
#   • swap als Objekt {enabled, algorithm=zstd}
#   • Profile: "details": ["KDE Plasma"] statt "sub": "kde"
#   • Credentials: root_enc_password / users[enc_password] (SHA-512 gehasht)
#   • mirror_config: custom_servers statt custom_mirrors
#   • Partitionen überlappen nicht mehr (1 MiB..1025 MiB / 1025 MiB..100%)
#   • archinstall-language: "German" (lang-Feld)
#   • Arrays statt Word-Splitting
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
BOOTLOADER="Grub"                    # Grub | Limine | Systemd-boot
DESKTOP="plasma"                     # kde | gnome | server | none
KERNEL_LIST=("linux-lts")            # Array!
DATEISYSTEM="btrfs"                  # btrfs | ext4 | xfs
HOSTNAME_VAL="archlinux"
BENUTZERNAME=""
BENUTZER_PASSWORT=""
ROOT_PASSWORT=""
TASTATUR="de-latin1"
LOCALE="de_DE.UTF-8"
ZEITZONE="Europe/Berlin"
ZUSATZ_PAKETE=()                     # Array!
VERSCHLUESSELUNG="false"
VERSCHL_PASSWORT=""

# Ergebnis der Menü-Funktion (globale Variable statt return-code)
_MENU_RESULT=0

# Arbeitsverzeichnis für Konfiguration (wird in main() als mktemp initialisiert)
CONFIG_DIR=""

# Dry-Run-Modus: archinstall simuliert nur, modifiziert NICHTS
DRY_RUN=false

# ─── Cleanup-Trap ───────────────────────────────────────────────────────────
# Wird bei EXIT/INT/TERM ausgelöst. WICHTIG: Während archinstall läuft wird
# die Trap auf 'ignorieren' gesetzt (siehe starte_installation), damit ein
# Ctrl+C die Credentials-Datei nicht mitten in der Installation löscht und
# zu inkonsistentem Zustand der Zielplatte führt.
cleanup() {
    # Sensible Daten sicher löschen
    if [[ -n "${CONFIG_DIR:-}" && -d "$CONFIG_DIR" ]]; then
        if [[ -f "${CONFIG_DIR}/user_credentials.json" ]]; then
            shred -u "${CONFIG_DIR}/user_credentials.json" 2>/dev/null \
                || rm -f "${CONFIG_DIR}/user_credentials.json"
        fi
        # Leeres Verzeichnis aufräumen (nur wenn nichts drin)
        rmdir "$CONFIG_DIR" 2>/dev/null || true
    fi
    # Variablen mit Passwörtern leeren
    BENUTZER_PASSWORT=""
    ROOT_PASSWORT=""
    VERSCHL_PASSWORT=""
}
trap cleanup EXIT
trap 'echo ""; warnung "Abgebrochen."; exit 130' INT TERM

# ─── Hilfsfunktionen ────────────────────────────────────────────────────────

banner() {
    clear
    printf '%b' "${CYAN}"
    cat << 'EOF'
    ╔═════════════════════════════════════════════════════════════╗
    ║                       ARCH LINUX                            ║
    ║                   CUSTOM INSTALLER v2.2                     ║
    ║                                                             ║
    ║        Basiert auf archinstall 2.8.x / Release 4.2          ║
    ║           EFI • LTS-Kernel • Pipewire • Deutsch             ║
    ╚═════════════════════════════════════════════════════════════╝
EOF
    printf '%b' "${RESET}"
}

info()    { printf '  %b[INFO]%b  %s\n' "$BLAU"  "$RESET" "$1"; }
erfolg()  { printf '  %b[  OK]%b  %s\n' "$GRUEN" "$RESET" "$1"; }
warnung() { printf '  %b[WARN]%b  %s\n' "$GELB"  "$RESET" "$1"; }
fehler()  { printf '  %b[FAIL]%b  %s\n' "$ROT"   "$RESET" "$1"; }

linie() {
    printf '  %b──────────────────────────────────────────────────────%b\n' \
        "$DIM" "$RESET"
}

pause_msg() {
    echo ""
    printf '  %bWeiter mit [Enter]...%b' "$DIM" "$RESET"
    read -r
}

# Passwort-Hash (SHA-512, universell kompatibel via crypt(3))
hash_password() {
    local pw="$1"
    # openssl ist auf der Arch-ISO garantiert vorhanden
    openssl passwd -6 "$pw" 2>/dev/null
}

# JSON-String sicher escapen (nur einfache Fälle: \ und ")
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# ─── Hilfe & Start-Hinweise ─────────────────────────────────────────────────

zeige_hilfe() {
    cat << 'HELPEOF'
Arch Linux Custom Installer v2.2

VERWENDUNG:
    sudo ./arch_custom_installer.sh [OPTIONEN]

OPTIONEN:
    --dry-run    archinstall im Simulationsmodus ausführen. KEINE Änderungen
                 an der Zielplatte. Prüft die JSON-Konfiguration gegen die
                 installierte archinstall-Version. Empfohlen für den ersten
                 Test in einer VM.
    --help, -h   Diese Hilfe anzeigen.

BEISPIELE:
    # Echte Installation (modifiziert die Zielplatte!):
    sudo ./arch_custom_installer.sh

    # Testlauf in VM (keine Änderungen):
    sudo ./arch_custom_installer.sh --dry-run
HELPEOF
}

zeige_startinfo() {
    banner
    echo ""
    if $DRY_RUN; then
        printf '  %b%b┌─────────────────────────────────────────────────────────────┐%b\n' \
            "$GELB" "$BOLD" "$RESET"
        printf '  %b%b│   DRY-RUN-MODUS AKTIV — keine Änderungen an der Platte!     │%b\n' \
            "$GELB" "$BOLD" "$RESET"
        printf '  %b%b└─────────────────────────────────────────────────────────────┘%b\n' \
            "$GELB" "$BOLD" "$RESET"
        echo ""
        printf '  archinstall wird mit %b--dry-run%b ausgeführt: es simuliert die\n' \
            "$BOLD" "$RESET"
        printf '  Installation und validiert die JSON-Konfiguration, ohne die\n'
        printf '  Zielplatte zu verändern.\n'
    else
        printf '  %b%b┌─────────────────────────────────────────────────────────────┐%b\n' \
            "$CYAN" "$BOLD" "$RESET"
        printf '  %b%b│   TIPP: Vor echter Installation in VM testen!               │%b\n' \
            "$CYAN" "$BOLD" "$RESET"
        printf '  %b%b└─────────────────────────────────────────────────────────────┘%b\n' \
            "$CYAN" "$BOLD" "$RESET"
        echo ""
        printf '  Dieses Skript bietet einen %bDry-Run-Modus%b, der archinstall im\n' \
            "$BOLD" "$RESET"
        printf '  Simulationsmodus startet — %bkeine%b Änderungen an der Zielplatte,\n' \
            "$BOLD" "$RESET"
        printf '  nur Validierung der JSON-Konfiguration. Empfohlen für ersten Test:\n'
        echo ""
        # WICHTIG: Dieser Block wird ohne Farbcodes gerendert, damit er
        # per Maus-Markierung ohne ANSI-Escape-Sequenzen kopierbar ist.
        echo "      sudo ./arch_custom_installer.sh --dry-run"
        echo ""
        printf '  %bAktueller Start-Modus: echte Installation (Zielplatte wird gelöscht!)%b\n' \
            "$GELB" "$RESET"
    fi
    echo ""
    linie
    printf '  %bWeiter mit [Enter], Abbruch mit Strg+C...%b' "$DIM" "$RESET"
    read -r
}

# ─── Prüfungen ───────────────────────────────────────────────────────────────

pruefe_voraussetzungen() {
    banner
    printf '  %bSystemprüfung%b\n' "$BOLD" "$RESET"
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

    # Bash-Version (benötigt 4+ für ${var,,} und mapfile)
    if (( BASH_VERSINFO[0] < 4 )); then
        fehler "Bash 4+ wird benötigt (gefunden: ${BASH_VERSION})"
        exit 1
    fi

    # openssl für Passwort-Hashing
    if ! command -v openssl &>/dev/null; then
        fehler "openssl nicht gefunden - benötigt für Passwort-Hashing"
        exit 1
    fi

    # Internet? (kein -W, stattdessen timeout für Kompatibilität)
    if timeout 3 ping -c 1 archlinux.org &>/dev/null; then
        erfolg "Internetverbindung vorhanden"
    else
        warnung "Keine Internetverbindung erkannt!"
        printf '  %b       Bitte Netzwerk einrichten (z.B. iwctl für WLAN)%b\n' \
            "$GELB" "$RESET"
        pause_msg
    fi

    # archinstall vorhanden?
    if command -v archinstall &>/dev/null; then
        local ai_version
        ai_version=$(archinstall --version 2>/dev/null | head -n1 || echo "unbekannt")
        erfolg "archinstall gefunden: ${ai_version}"

        # Angebot: archinstall aktualisieren
        printf '\n  archinstall aktualisieren? [j/N]: '
        local upd
        read -r upd
        if [[ "${upd,,}" == "j" || "${upd,,}" == "ja" ]]; then
            info "Aktualisiere archinstall..."
            if pacman -Sy --noconfirm archinstall &>/dev/null; then
                erfolg "archinstall aktualisiert"
            else
                warnung "Update fehlgeschlagen (fahre mit vorhandener Version fort)"
            fi
        fi
    else
        fehler "archinstall nicht gefunden! Bitte Arch Linux ISO verwenden."
        exit 1
    fi

    # Keyring aktualisieren (explizites if/else statt && ||-Kette)
    info "Aktualisiere Keyring..."
    if pacman -Sy --noconfirm archlinux-keyring &>/dev/null; then
        erfolg "Keyring aktualisiert"
    else
        warnung "Keyring-Update fehlgeschlagen (unkritisch)"
    fi

    pause_msg
}

# ─── Menü-Hilfsfunktionen ───────────────────────────────────────────────────

_menue_zeichne() {
    local titel="$1"
    local auswahl="$2"
    shift 2
    local -a optionen=("$@")

    echo ""
    printf '  %b%s%b\n' "$BOLD" "$titel" "$RESET"
    linie
    local i
    for i in "${!optionen[@]}"; do
        if [[ $i -eq $auswahl ]]; then
            printf '  %b▶ %b%s%b\n' "$CYAN" "$BOLD" "${optionen[$i]}" "$RESET"
        else
            printf '    %s\n' "${optionen[$i]}"
        fi
    done
    linie
    printf '  %b[↑/↓] Navigieren  [Enter] Auswählen%b\n' "$DIM" "$RESET"
}

waehle_option() {
    local titel="$1"
    shift
    local -a optionen=("$@")
    local auswahl=0
    local anzahl=${#optionen[@]}
    local taste rest
    # Zeilen pro Durchlauf: Leerzeile + Titel + Linie + $anzahl + Linie + Hinweis
    local zeilen=$((anzahl + 5))

    _menue_zeichne "$titel" "$auswahl" "${optionen[@]}"

    while true; do
        # Einzelnes Zeichen lesen (mit nohang-Verhalten für ESC-Sequenzen)
        IFS= read -rsn1 taste
        case "$taste" in
            $'\x1b')
                # ESC-Sequenz: kurzes Timeout, falls nur ESC alleine gedrückt
                if IFS= read -rsn2 -t 0.05 rest; then
                    case "$rest" in
                        '[A') ((auswahl > 0)) && ((auswahl--)) ;;
                        '[B') ((auswahl < anzahl - 1)) && ((auswahl++)) ;;
                    esac
                fi
                ;;
            '')   # Enter
                break
                ;;
            *)
                continue
                ;;
        esac

        # Cursor zurücksetzen & Zeilen löschen
        local z
        for ((z = 0; z < zeilen; z++)); do
            printf '\033[1A\033[2K'
        done
        _menue_zeichne "$titel" "$auswahl" "${optionen[@]}"
    done

    _MENU_RESULT=$auswahl
}

# ─── Festplatte wählen ──────────────────────────────────────────────────────

waehle_festplatte() {
    banner
    printf '  %b1/9 — Zielfestplatte%b\n' "$BOLD" "$RESET"
    linie

    # Sichere Disk-Erkennung via lsblk JSON + python3 (kein eval, kein
    # Code-Injection-Risiko bei Sonderzeichen in Modellnamen). python3 ist
    # auf der Arch-ISO garantiert vorhanden (archinstall ist Python).
    local -a disks=()
    local -a disk_paths=()
    local disk_data=""

    if command -v python3 &>/dev/null; then
        disk_data=$(lsblk -J -d -b -o NAME,PATH,SIZE,MODEL,TYPE,RO 2>/dev/null \
            | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for d in data.get("blockdevices", []):
    if d.get("type") != "disk":
        continue
    if d.get("ro"):   # Read-Only Medien (z.B. Install-ISO) überspringen
        continue
    path  = d.get("path") or ("/dev/" + d.get("name", ""))
    size  = d.get("size") or 0
    model = (d.get("model") or "unbekannt").strip()
    try:
        gib = float(size) / (1024**3)
        size_str = f"{gib:.1f} GiB"
    except Exception:
        size_str = str(size)
    # Tab-getrennt (Model darf Leerzeichen enthalten)
    print(f"{path}\t{size_str}\t{model}")
' 2>/dev/null) || disk_data=""
    fi

    if [[ -n "$disk_data" ]]; then
        local name size model
        while IFS=$'\t' read -r name size model; do
            [[ -z "$name" ]] && continue
            disk_paths+=("$name")
            disks+=("${name} (${size})  ${model}")
        done <<< "$disk_data"
    else
        # Fallback ohne python3 (JSON-Parsing): Tab-separierter lsblk-Output
        local name ttype size model
        while IFS=$'\t' read -r name ttype size model; do
            [[ "$ttype" != "disk" ]] && continue
            [[ -z "$name" ]] && continue
            disk_paths+=("$name")
            disks+=("${name} (${size})  ${model:-unbekannt}")
        done < <(lsblk -dnp -o NAME,TYPE,SIZE,MODEL 2>/dev/null \
                 | awk '{printf "%s\t%s\t%s\t", $1, $2, $3; for(i=4;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":"\n")}')
    fi

    if [[ ${#disks[@]} -eq 0 ]]; then
        fehler "Keine Festplatten gefunden!"
        exit 1
    fi

    echo ""
    printf '  %b⚠  ACHTUNG: Alle Daten auf der gewählten Festplatte werden gelöscht!%b\n' \
        "$GELB" "$RESET"

    waehle_option "Verfügbare Festplatten:" "${disks[@]}"
    INSTALL_DISK="${disk_paths[$_MENU_RESULT]}"

    # Mindest-Plattengröße: 8 GiB (archinstall bricht sonst kryptisch ab)
    local size_bytes
    size_bytes=$(lsblk -bdn -o SIZE "$INSTALL_DISK" 2>/dev/null || echo 0)
    if [[ "$size_bytes" =~ ^[0-9]+$ ]] && (( size_bytes > 0 )); then
        local min_bytes=$((8 * 1024 * 1024 * 1024))  # 8 GiB
        if (( size_bytes < min_bytes )); then
            local size_gib=$((size_bytes / 1024 / 1024 / 1024))
            fehler "Festplatte zu klein: ${size_gib} GiB (mind. 8 GiB benötigt)"
            exit 1
        fi
    fi

    # Warnung bei gemounteten Partitionen der gewählten Platte
    # Präzises Matching: /dev/sda1, /dev/sdap1, /dev/nvme0n1p1, aber nicht /dev/sdaa
    if lsblk -nrpo MOUNTPOINTS "$INSTALL_DISK" 2>/dev/null \
            | awk 'NF>0{exit 0} END{exit 1}'; then
        warnung "Achtung: Partitionen auf ${INSTALL_DISK} sind aktuell gemountet!"
        echo -n "  Trotzdem fortfahren? [j/N]: "
        local ans
        read -r ans
        if [[ "${ans,,}" != "j" && "${ans,,}" != "ja" ]]; then
            info "Abgebrochen."
            exit 0
        fi
    fi

    erfolg "Gewählt: ${INSTALL_DISK}"
    pause_msg
}

# ─── Bootloader wählen ──────────────────────────────────────────────────────

waehle_bootloader() {
    banner
    printf '  %b2/9 — Bootloader%b\n' "$BOLD" "$RESET"

    local -a optionen=(
        "GRUB          — Klassiker, universell, Btrfs-Snapshots"
        "Limine        — Ultraschnell, modern, minimalistisch"
        "Systemd-boot  — Einfach, schnell, EFI-nativ"
    )

    waehle_option "Bootloader wählen:" "${optionen[@]}"
    case $_MENU_RESULT in
        0) BOOTLOADER="Grub"         ; erfolg "Bootloader: GRUB" ;;
        1) BOOTLOADER="Limine"       ; erfolg "Bootloader: Limine" ;;
        2) BOOTLOADER="Systemd-boot" ; erfolg "Bootloader: systemd-boot" ;;
    esac
    pause_msg
}

# ─── Desktop wählen ─────────────────────────────────────────────────────────

waehle_desktop() {
    banner
    printf '  %b3/9 — Desktop-Umgebung%b\n' "$BOLD" "$RESET"

    local -a optionen=(
        "KDE Plasma    — Modern, anpassbar, Wayland-ready"
        "GNOME         — Clean, touchfreundlich, Erweiterungen"
        "Server        — Headless, SSH, Firewall, Server-Pakete"
        "Ohne Desktop  — Nur Basissystem (Minimal)"
    )

    waehle_option "Desktop-Umgebung wählen:" "${optionen[@]}"
    case $_MENU_RESULT in
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
    printf '  %b4/9 — Kernel%b\n' "$BOLD" "$RESET"

    local -a optionen=(
        "linux-lts          — Langzeitstabil, empfohlen für Produktivsysteme"
        "linux              — Standard-Kernel, neueste Features"
        "linux-zen          — Desktop-optimiert, bessere Latenz, Gaming"
        "linux-lts + linux  — Beide installieren (Fallback)"
    )

    waehle_option "Kernel wählen:" "${optionen[@]}"
    case $_MENU_RESULT in
        0) KERNEL_LIST=("linux-lts")           ; erfolg "Kernel: linux-lts" ;;
        1) KERNEL_LIST=("linux")               ; erfolg "Kernel: linux" ;;
        2) KERNEL_LIST=("linux-zen")           ; erfolg "Kernel: linux-zen" ;;
        3) KERNEL_LIST=("linux-lts" "linux")   ; erfolg "Kernel: linux-lts + linux" ;;
    esac
    pause_msg
}

# ─── Dateisystem wählen ─────────────────────────────────────────────────────

waehle_dateisystem() {
    banner
    printf '  %b5/9 — Dateisystem%b\n' "$BOLD" "$RESET"

    local -a optionen=(
        "Btrfs   — Snapshots, Kompression, CoW, empfohlen"
        "Ext4    — Bewährt, stabil, einfach"
        "XFS     — Performant bei großen Dateien"
    )

    waehle_option "Dateisystem wählen:" "${optionen[@]}"
    case $_MENU_RESULT in
        0) DATEISYSTEM="btrfs" ; erfolg "Dateisystem: Btrfs" ;;
        1) DATEISYSTEM="ext4"  ; erfolg "Dateisystem: Ext4" ;;
        2) DATEISYSTEM="xfs"   ; erfolg "Dateisystem: XFS" ;;
    esac
    pause_msg
}

# ─── Tastaturlayout wählen ──────────────────────────────────────────────────

waehle_tastatur() {
    banner
    printf '  %b6/9 — Tastaturlayout%b\n' "$BOLD" "$RESET"

    local -a optionen=(
        "de-latin1            — Deutsch (Standard)"
        "de-latin1-nodeadkeys — Deutsch ohne Tottasten"
        "de-neo               — Neo-Tastaturlayout"
        "de                   — Deutsch (einfach)"
        "us                   — US-Amerikanisch"
        "ch-de                — Schweizerdeutsch"
        "at                   — Österreichisch"
    )

    waehle_option "Tastaturlayout wählen:" "${optionen[@]}"
    case $_MENU_RESULT in
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
    printf '  %b7/9 — Benutzerkonfiguration%b\n' "$BOLD" "$RESET"
    linie

    local eingabe pw_confirm

    # Hostname
    printf '  %bHostname%b [archlinux]: ' "$BOLD" "$RESET"
    read -r eingabe
    HOSTNAME_VAL="${eingabe:-archlinux}"
    # Minimale Validierung (RFC 1123: a-z0-9-)
    if [[ ! "$HOSTNAME_VAL" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$ ]]; then
        warnung "Hostname unüblich, verwende 'archlinux'"
        HOSTNAME_VAL="archlinux"
    fi
    erfolg "Hostname: ${HOSTNAME_VAL}"
    echo ""

    # Benutzername
    while [[ -z "$BENUTZERNAME" ]]; do
        printf '  %bBenutzername%b: ' "$BOLD" "$RESET"
        read -r BENUTZERNAME
        # POSIX-konform: klein, beginnt mit Buchstabe/_, max. 32 Zeichen
        if [[ ! "$BENUTZERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
            warnung "Ungültiger Benutzername (nur [a-z0-9_-], Start mit Buchstabe)"
            BENUTZERNAME=""
        fi
    done
    erfolg "Benutzer: ${BENUTZERNAME}"
    echo ""

    # Benutzer-Passwort
    while true; do
        printf '  %bPasswort für %s%b: ' "$BOLD" "$BENUTZERNAME" "$RESET"
        read -rs BENUTZER_PASSWORT
        echo ""
        printf '  %bPasswort bestätigen%b: ' "$BOLD" "$RESET"
        read -rs pw_confirm
        echo ""
        if [[ "$BENUTZER_PASSWORT" == "$pw_confirm" && -n "$BENUTZER_PASSWORT" ]]; then
            if (( ${#BENUTZER_PASSWORT} < 6 )); then
                warnung "Passwort sehr kurz (<6 Zeichen) — bitte länger wählen"
                continue
            fi
            erfolg "Benutzer-Passwort gesetzt"
            break
        else
            warnung "Passwörter stimmen nicht überein oder sind leer!"
        fi
    done
    echo ""

    # Root-Passwort
    printf '  %bRoot-Passwort (leer = gleich wie Benutzer-Passwort):%b\n' "$DIM" "$RESET"
    while true; do
        printf '  %bRoot-Passwort%b: ' "$BOLD" "$RESET"
        read -rs ROOT_PASSWORT
        echo ""
        if [[ -z "$ROOT_PASSWORT" ]]; then
            ROOT_PASSWORT="$BENUTZER_PASSWORT"
            info "Root-Passwort = Benutzer-Passwort"
            break
        fi
        if (( ${#ROOT_PASSWORT} < 6 )); then
            warnung "Root-Passwort sehr kurz (<6 Zeichen) — bitte länger wählen"
            ROOT_PASSWORT=""
            continue
        fi
        printf '  %bRoot-Passwort bestätigen%b: ' "$BOLD" "$RESET"
        read -rs pw_confirm
        echo ""
        if [[ "$ROOT_PASSWORT" != "$pw_confirm" ]]; then
            warnung "Passwörter stimmen nicht überein!"
            ROOT_PASSWORT=""
            continue
        fi
        erfolg "Separates Root-Passwort gesetzt"
        break
    done

    # Variable nach Verwendung sicher löschen (nur lokale Kopie)
    pw_confirm=""

    pause_msg
}

# ─── Zusatzoptionen ─────────────────────────────────────────────────────────

zusatzoptionen() {
    banner
    printf '  %b8/9 — Zusatzoptionen%b\n' "$BOLD" "$RESET"
    linie

    # Verschlüsselung
    local -a optionen_crypt=(
        "Nein  — Keine Verschlüsselung"
        "Ja    — LUKS-Vollverschlüsselung"
    )
    waehle_option "Festplattenverschlüsselung (LUKS):" "${optionen_crypt[@]}"
    case $_MENU_RESULT in
        0) VERSCHLUESSELUNG="false" ;;
        1)
            VERSCHLUESSELUNG="true"
            echo ""
            local pw_c
            while true; do
                printf '  %bVerschlüsselungs-Passwort%b: ' "$BOLD" "$RESET"
                read -rs VERSCHL_PASSWORT
                echo ""
                printf '  %bPasswort bestätigen%b: ' "$BOLD" "$RESET"
                read -rs pw_c
                echo ""
                if [[ "$VERSCHL_PASSWORT" == "$pw_c" && -n "$VERSCHL_PASSWORT" ]]; then
                    if (( ${#VERSCHL_PASSWORT} < 8 )); then
                        warnung "LUKS-Passwort sehr kurz (<8 Zeichen)"
                        continue
                    fi
                    erfolg "Verschlüsselungs-Passwort gesetzt"
                    break
                else
                    warnung "Passwörter stimmen nicht überein oder sind leer!"
                fi
            done
            pw_c=""
            ;;
    esac

    echo ""

    # Zusätzliche Pakete
    printf '  %bZusätzliche Pakete%b %b(Leerzeichen-getrennt, leer = keine):%b\n' \
        "$BOLD" "$RESET" "$DIM" "$RESET"
    printf '  %bBeispiel: firefox vim htop neofetch%b\n' "$DIM" "$RESET"
    printf '  > '
    local pakete_zeile
    read -r pakete_zeile
    # Word-Splitting nur hier, dann in Array speichern
    if [[ -n "$pakete_zeile" ]]; then
        # shellcheck disable=SC2206
        ZUSATZ_PAKETE=($pakete_zeile)
        erfolg "Zusatzpakete: ${ZUSATZ_PAKETE[*]}"
    else
        ZUSATZ_PAKETE=()
        info "Keine Zusatzpakete"
    fi

    pause_msg
}

# ─── Zusammenfassung & Bestätigung ──────────────────────────────────────────

zusammenfassung() {
    banner
    printf '  %b9/9 — Zusammenfassung%b\n' "$BOLD" "$RESET"
    linie
    echo ""
    printf '  %bFestplatte:%b       %s\n' "$BOLD" "$RESET" "$INSTALL_DISK"
    printf '  %bDateisystem:%b      %s\n' "$BOLD" "$RESET" "$DATEISYSTEM"
    printf '  %bBootloader:%b       %s\n' "$BOLD" "$RESET" "$BOOTLOADER"
    printf '  %bDesktop:%b          %s\n' "$BOLD" "$RESET" "$DESKTOP"
    printf '  %bKernel:%b           %s\n' "$BOLD" "$RESET" "${KERNEL_LIST[*]}"
    printf '  %bTastatur:%b         %s\n' "$BOLD" "$RESET" "$TASTATUR"
    printf '  %bSprache:%b          %s\n' "$BOLD" "$RESET" "$LOCALE"
    printf '  %bZeitzone:%b         %s\n' "$BOLD" "$RESET" "$ZEITZONE"
    printf '  %bHostname:%b         %s\n' "$BOLD" "$RESET" "$HOSTNAME_VAL"
    printf '  %bBenutzer:%b         %s (sudo)\n' "$BOLD" "$RESET" "$BENUTZERNAME"
    printf '  %bAudio:%b            Pipewire\n' "$BOLD" "$RESET"
    printf '  %bSwap:%b             Zram (zstd)\n' "$BOLD" "$RESET"
    printf '  %bVerschlüsselung:%b  %s\n' "$BOLD" "$RESET" "$VERSCHLUESSELUNG"
    printf '  %bMirrorlist:%b       Deutschland\n' "$BOLD" "$RESET"
    if [[ ${#ZUSATZ_PAKETE[@]} -gt 0 ]]; then
        printf '  %bZusatzpakete:%b     %s\n' "$BOLD" "$RESET" "${ZUSATZ_PAKETE[*]}"
    fi
    echo ""
    linie
    echo ""
    printf '  %b%b⚠  WARNUNG: Alle Daten auf %s werden UNWIDERRUFLICH gelöscht!%b\n' \
        "$ROT" "$BOLD" "$INSTALL_DISK" "$RESET"
    echo ""
    printf '  Installation starten? [j/N]: '
    local bestaetigung
    read -r bestaetigung
    if [[ "${bestaetigung,,}" != "j" && "${bestaetigung,,}" != "ja" ]]; then
        info "Installation abgebrochen."
        exit 0
    fi
}

# ─── Deutsche Mirrorlist konfigurieren ──────────────────────────────────────

konfiguriere_mirrors() {
    info "Konfiguriere deutsche Mirrorlist..."

    local mirrors_ok=1

    # Reflector verwenden falls vorhanden
    if command -v reflector &>/dev/null; then
        if reflector --country Germany --age 12 --protocol https \
                     --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null; then
            erfolg "Mirrorlist via Reflector aktualisiert (Deutschland)"
            mirrors_ok=0
        else
            warnung "Reflector fehlgeschlagen, verwende statische Mirrorlist"
        fi
    fi

    if (( mirrors_ok != 0 )); then
        # Fallback: Manuelle deutsche Mirrors (April 2026)
        cat > /etc/pacman.d/mirrorlist << 'MIRRORS'
## Deutschland — generiert von arch_custom_installer.sh
Server = https://ftp.fau.de/archlinux/$repo/os/$arch
Server = https://mirror.informatik.tu-freiberg.de/arch/$repo/os/$arch
Server = https://ftp.halifax.rwth-aachen.de/archlinux/$repo/os/$arch
Server = https://mirror.pseudoform.org/$repo/os/$arch
Server = https://ftp.gwdg.de/pub/linux/archlinux/$repo/os/$arch
Server = https://mirror.fra10.de.leaseweb.net/archlinux/$repo/os/$arch
Server = https://ftp.spline.inf.fu-berlin.de/mirrors/archlinux/$repo/os/$arch
Server = https://packages.oth-regensburg.de/archlinux/$repo/os/$arch
Server = https://mirror.mikrogravitation.org/archlinux/$repo/os/$arch
MIRRORS
        erfolg "Deutsche Mirrorlist manuell konfiguriert"
    fi

    # Paketdatenbank nach Mirror-Wechsel aktualisieren
    if pacman -Syy --noconfirm &>/dev/null; then
        erfolg "Paketdatenbank aktualisiert"
    else
        warnung "pacman -Syy fehlgeschlagen (archinstall versucht es erneut)"
    fi
}

# ─── JSON-Konfiguration generieren ──────────────────────────────────────────
# ACHTUNG: Schema für archinstall 2.8.x / Release 4.2 (April 2026):
#   • bootloader_config als Objekt
#   • swap als Objekt {enabled, algorithm}
#   • custom_servers statt custom_mirrors
#   • profile_config.profile.details als Klartext-Array (z.B. ["KDE Plasma"])
#   • Credentials: root_enc_password, users[enc_password] (alle Hashes)
# ---------------------------------------------------------------------------

generiere_config() {
    info "Generiere archinstall-Konfiguration..."

    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    # --- Kernel-Liste als JSON-Array ---
    local kernel_json=""
    local k
    for k in "${KERNEL_LIST[@]}"; do
        [[ -n "$kernel_json" ]] && kernel_json+=", "
        kernel_json+="\"$(json_escape "$k")\""
    done

    # --- Profil & Greeter ---
    local profil_json="null"
    local greeter_json="null"
    case "$DESKTOP" in
        kde)
            profil_json='{"details": ["KDE Plasma"], "main": "Desktop"}'
            greeter_json='"sddm"'
            ;;
        gnome)
            profil_json='{"details": ["GNOME"], "main": "Desktop"}'
            greeter_json='"gdm"'
            ;;
        server)
            profil_json='{"details": [], "main": "Server"}'
            ;;
        none)
            profil_json='{"details": [], "main": "Minimal"}'
            ;;
    esac

    # --- Mount-Options für Btrfs ---
    local mount_opts_json="[]"
    local btrfs_subvols="[]"
    if [[ "$DATEISYSTEM" == "btrfs" ]]; then
        mount_opts_json='["compress=zstd"]'
        # Standard-Subvolume-Layout für Snapshot-Fähigkeit
        btrfs_subvols='[
                        {"name": "@",       "mountpoint": "/"},
                        {"name": "@home",   "mountpoint": "/home"},
                        {"name": "@log",    "mountpoint": "/var/log"},
                        {"name": "@pkg",    "mountpoint": "/var/cache/pacman/pkg"}
                    ]'
    fi

    # --- Disk-Config (Partitionen ohne Überlappung!) ---
    # Boot:  1 MiB .. 1025 MiB (1 GiB Größe)
    # Root:  1025 MiB .. 100% (Rest)
    local disk_dev
    disk_dev=$(json_escape "$INSTALL_DISK")

    local disk_json
    disk_json=$(cat << DISKEOF
{
    "config_type": "default_layout",
    "device_modifications": [
        {
            "device": "${disk_dev}",
            "partitions": [
                {
                    "btrfs": [],
                    "flags": ["boot"],
                    "fs_type": "fat32",
                    "mount_options": [],
                    "mountpoint": "/boot",
                    "obj_id": "efi-part-001",
                    "size": {
                        "sector_size": null,
                        "unit": "MiB",
                        "value": 1024
                    },
                    "start": {
                        "sector_size": null,
                        "unit": "MiB",
                        "value": 1
                    },
                    "status": "create",
                    "type": "primary"
                },
                {
                    "btrfs": ${btrfs_subvols},
                    "flags": [],
                    "fs_type": "${DATEISYSTEM}",
                    "mount_options": ${mount_opts_json},
                    "mountpoint": "/",
                    "obj_id": "root-part-001",
                    "size": {
                        "sector_size": null,
                        "unit": "Percent",
                        "value": 100
                    },
                    "start": {
                        "sector_size": null,
                        "unit": "MiB",
                        "value": 1025
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
        encryption_json='{
        "encryption_type": "luks",
        "partitions": ["root-part-001"]
    }'
    fi

    # --- Paketliste (Array → JSON) ---
    local -a all_packages=()
    # Server-Profil: Server-Pakete automatisch hinzufügen
    if [[ "$DESKTOP" == "server" ]]; then
        all_packages+=(openssh ufw rsync htop tmux curl wget git nano vim bind-tools)
    fi
    # Nutzer-Zusatzpakete
    all_packages+=("${ZUSATZ_PAKETE[@]}")

    local pakete_json=""
    local p
    for p in "${all_packages[@]}"; do
        [[ -z "$p" ]] && continue
        [[ -n "$pakete_json" ]] && pakete_json+=", "
        pakete_json+="\"$(json_escape "$p")\""
    done

    # --- Tastatur-Mapping für X/Wayland ---
    local kb_layout="de"
    local kb_variant=""
    case "$TASTATUR" in
        de-latin1|de)         kb_layout="de" ; kb_variant="" ;;
        de-latin1-nodeadkeys) kb_layout="de" ; kb_variant="nodeadkeys" ;;
        de-neo)               kb_layout="de" ; kb_variant="neo" ;;
        us)                   kb_layout="us" ; kb_variant="" ;;
        ch-de)                kb_layout="ch" ; kb_variant="de" ;;
        at)                   kb_layout="at" ; kb_variant="" ;;
    esac

    # --- GFX-Driver & Custom-Commands ---
    local gfx_driver='"All open-source (default)"'
    local custom_commands_json=""
    if [[ "$DESKTOP" == "server" ]]; then
        # Auf Servern keinen Grafik-Treiber installieren
        gfx_driver="null"
        custom_commands_json=',
    "custom_commands": [
        "systemctl enable sshd",
        "systemctl enable ufw",
        "ufw default deny incoming",
        "ufw default allow outgoing",
        "ufw allow ssh",
        "ufw --force enable"
    ]'
    fi

    # --- profile_config zusammenbauen ---
    local profile_config_json
    if [[ "$profil_json" == "null" ]]; then
        profile_config_json="null"
    else
        profile_config_json="{
        \"gfx_driver\": ${gfx_driver},
        \"greeter\": ${greeter_json},
        \"profile\": ${profil_json}
    }"
    fi

    # === user_configuration.json ===
    cat > "${CONFIG_DIR}/user_configuration.json" << CONFIGEOF
{
    "additional-repositories": ["multilib"],
    "archinstall-language": "German",
    "audio_config": {
        "audio": "pipewire"
    },
    "bootloader_config": {
        "bootloader": "${BOOTLOADER}",
        "uki": false,
        "removable": false
    },
    "debug": false,
    "disk_config": ${disk_json},
    "disk_encryption": ${encryption_json},
    "hostname": "$(json_escape "$HOSTNAME_VAL")",
    "kernels": [${kernel_json}],
    "locale_config": {
        "kb_layout": "${kb_layout}",
        "kb_variant": "${kb_variant}",
        "sys_enc": "UTF-8",
        "sys_lang": "${LOCALE}"
    },
    "mirror_config": {
        "custom_servers": [],
        "custom_repositories": [],
        "mirror_regions": {
            "Germany": [
                "https://ftp.fau.de/archlinux/\$repo/os/\$arch",
                "https://ftp.halifax.rwth-aachen.de/archlinux/\$repo/os/\$arch",
                "https://ftp.gwdg.de/pub/linux/archlinux/\$repo/os/\$arch"
            ]
        },
        "optional_repositories": []
    },
    "network_config": {
        "type": "nm"
    },
    "no_pkg_lookups": false,
    "ntp": true,
    "offline": false,
    "packages": [${pakete_json}],
    "parallel_downloads": 5,
    "profile_config": ${profile_config_json},
    "script": "guided",
    "silent": true,
    "swap": {
        "enabled": true,
        "algorithm": "zstd"
    },
    "timezone": "${ZEITZONE}",
    "version": "2.8.6"${custom_commands_json}
}
CONFIGEOF

    # === user_credentials.json ===
    # Schema: root_enc_password (hash), users[{username, enc_password, sudo, groups}]
    # encryption_password MUSS Plaintext sein (wird zum Entsperren benötigt)
    local root_hash user_hash
    root_hash=$(hash_password "$ROOT_PASSWORT")
    user_hash=$(hash_password "$BENUTZER_PASSWORT")

    if [[ -z "$root_hash" || -z "$user_hash" ]]; then
        fehler "Passwort-Hashing fehlgeschlagen"
        exit 1
    fi

    # Escapen für JSON
    root_hash=$(json_escape "$root_hash")
    user_hash=$(json_escape "$user_hash")
    local user_name_esc
    user_name_esc=$(json_escape "$BENUTZERNAME")

    # encryption_password nur bei aktiver LUKS-Verschlüsselung schreiben
    local enc_pw_line=""
    if [[ "$VERSCHLUESSELUNG" == "true" ]]; then
        local verschl_pw_esc
        verschl_pw_esc=$(json_escape "$VERSCHL_PASSWORT")
        enc_pw_line="\"encryption_password\": \"${verschl_pw_esc}\","$'\n    '
    fi

    cat > "${CONFIG_DIR}/user_credentials.json" << CREDEOF
{
    ${enc_pw_line}"root_enc_password": "${root_hash}",
    "users": [
        {
            "enc_password": "${user_hash}",
            "groups": [],
            "sudo": true,
            "username": "${user_name_esc}"
        }
    ]
}
CREDEOF

    # Strikte Berechtigungen
    chmod 600 "${CONFIG_DIR}/user_configuration.json"
    chmod 600 "${CONFIG_DIR}/user_credentials.json"

    # Passwörter aus Speicher tilgen (Hashes bleiben in der Datei)
    BENUTZER_PASSWORT=""
    ROOT_PASSWORT=""
    VERSCHL_PASSWORT=""

    erfolg "Konfiguration generiert: ${CONFIG_DIR}/"
    printf '  %b  → user_configuration.json%b\n' "$DIM" "$RESET"
    printf '  %b  → user_credentials.json  (Mode 600)%b\n' "$DIM" "$RESET"

    # Optionale JSON-Validierung (falls python3 verfügbar)
    if command -v python3 &>/dev/null; then
        if ! python3 -c "import json, sys; json.load(open(sys.argv[1]))" \
                "${CONFIG_DIR}/user_configuration.json" 2>/dev/null; then
            fehler "user_configuration.json ist kein valides JSON!"
            exit 1
        fi
        if ! python3 -c "import json, sys; json.load(open(sys.argv[1]))" \
                "${CONFIG_DIR}/user_credentials.json" 2>/dev/null; then
            fehler "user_credentials.json ist kein valides JSON!"
            exit 1
        fi
        erfolg "JSON-Validierung bestanden"
    fi
}

# ─── Installation ausführen ─────────────────────────────────────────────────

starte_installation() {
    banner
    printf '  %b%bInstallation wird gestartet...%b\n' "$BOLD" "$GRUEN" "$RESET"
    linie
    echo ""

    # Tastatur setzen
    info "Setze Tastaturlayout: ${TASTATUR}"
    loadkeys "$TASTATUR" 2>/dev/null || true

    # NTP aktivieren
    info "Aktiviere Zeitsynchronisation..."
    timedatectl set-ntp true 2>/dev/null || true

    # Mirrors konfigurieren
    konfiguriere_mirrors

    echo ""
    if $DRY_RUN; then
        info "DRY-RUN-MODUS: archinstall simuliert nur, keine Änderungen!"
    else
        info "Starte archinstall mit generierter Konfiguration..."
    fi
    echo ""
    linie
    echo ""

    # WICHTIG: Während archinstall läuft Signale NICHT am Skript abfangen,
    # damit sie an archinstall selbst weitergereicht werden und die Cleanup-
    # Trap nicht mitten in der Installation die Credentials-Datei schreddert
    # (würde zu halb-installierter, unsauberer Zielplatte führen).
    local exit_code=0
    local -a archinstall_args=(
        --config "${CONFIG_DIR}/user_configuration.json"
        --creds  "${CONFIG_DIR}/user_credentials.json"
    )
    if $DRY_RUN; then
        archinstall_args+=(--dry-run)
    else
        archinstall_args+=(--silent)
    fi

    trap '' INT TERM
    archinstall "${archinstall_args[@]}" || exit_code=$?
    # Signal-Handler wiederherstellen (für die Postinstall-Phase)
    trap 'echo ""; warnung "Abgebrochen."; exit 130' INT TERM

    echo ""
    linie

    if [[ $exit_code -eq 0 ]]; then
        echo ""
        if $DRY_RUN; then
            printf '  %b%b╔══════════════════════════════════════════════════╗%b\n' \
                "$CYAN" "$BOLD" "$RESET"
            printf '  %b%b║  ✔ Dry-Run erfolgreich — Konfiguration OK       ║%b\n' \
                "$CYAN" "$BOLD" "$RESET"
            printf '  %b%b╚══════════════════════════════════════════════════╝%b\n' \
                "$CYAN" "$BOLD" "$RESET"
            echo ""
            echo "  Die JSON-Konfiguration wurde von archinstall akzeptiert."
            echo "  Keine Änderungen an der Zielplatte vorgenommen."
            echo ""
            printf '  %bNächster Schritt:%b Führe das Skript ohne --dry-run aus,\n' \
                "$BOLD" "$RESET"
            echo "  um die echte Installation zu starten:"
            echo ""
            echo "      sudo ./arch_custom_installer.sh"
            echo ""
        else
            printf '  %b%b╔══════════════════════════════════════════════════╗%b\n' \
                "$GRUEN" "$BOLD" "$RESET"
            printf '  %b%b║  ✔ Installation erfolgreich abgeschlossen!       ║%b\n' \
                "$GRUEN" "$BOLD" "$RESET"
            printf '  %b%b╚══════════════════════════════════════════════════╝%b\n' \
                "$GRUEN" "$BOLD" "$RESET"
            echo ""
            echo "  Konfiguration gespeichert unter:"
            printf '  %b%s/user_configuration.json%b\n' "$DIM" "$CONFIG_DIR" "$RESET"
            printf '  %b/var/log/archinstall/install.log%b\n' "$DIM" "$RESET"
            echo ""

            printf '  %bNächste Schritte:%b\n' "$BOLD" "$RESET"
            printf '  %b1.%b USB-Stick entfernen\n' "$CYAN" "$RESET"
            printf '  %b2.%b System neu starten: %breboot%b\n' "$CYAN" "$RESET" "$BOLD" "$RESET"
            printf '  %b3.%b Anmelden als: %b%s%b\n' \
                "$CYAN" "$RESET" "$BOLD" "$BENUTZERNAME" "$RESET"
            echo ""
        fi
    else
        echo ""
        if $DRY_RUN; then
            fehler "Dry-Run fehlgeschlagen — Konfiguration wurde von archinstall abgelehnt"
            printf '  %b(Exit-Code: %d)%b\n' "$DIM" "$exit_code" "$RESET"
        else
            fehler "Installation fehlgeschlagen! (Exit-Code: ${exit_code})"
        fi
        printf '  %bLogdatei: /var/log/archinstall/install.log%b\n' "$DIM" "$RESET"
        echo ""
        printf '  Logdatei anzeigen? [j/N]: '
        local show_log
        read -r show_log
        if [[ "${show_log,,}" == "j" ]]; then
            if command -v less &>/dev/null; then
                less /var/log/archinstall/install.log 2>/dev/null || true
            else
                cat /var/log/archinstall/install.log 2>/dev/null || true
            fi
        fi
    fi
}

# ─── Hauptmenü ──────────────────────────────────────────────────────────────

hauptmenue() {
    while true; do
        banner

        # Aktuelle Konfiguration anzeigen falls vorhanden
        if [[ -n "$INSTALL_DISK" ]]; then
            printf '  %bAktuelle Konfiguration:%b\n' "$DIM" "$RESET"
            printf '  %bDisk=%s Boot=%s DE=%s Kern=%s FS=%s KB=%s%b\n' \
                "$DIM" "$INSTALL_DISK" "$BOOTLOADER" "$DESKTOP" \
                "${KERNEL_LIST[*]}" "$DATEISYSTEM" "$TASTATUR" "$RESET"
            linie
        fi

        local -a optionen=(
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
        case $_MENU_RESULT in
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
            10) printf '\n  %bAuf Wiedersehen!%b\n\n' "$DIM" "$RESET" ; exit 0 ;;
        esac
    done
}

# ─── Einstiegspunkt ─────────────────────────────────────────────────────────

main() {
    # Kommandozeilen-Argumente parsen
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                zeige_hilfe
                exit 0
                ;;
            *)
                echo "Unbekannte Option: $1" >&2
                echo "Verwende --help für Hilfe." >&2
                exit 2
                ;;
        esac
    done

    # Sudo/Root-Prüfung mit Passwort-Abfrage
    if [[ $EUID -ne 0 ]]; then
        printf '%b%b' "$CYAN" "$BOLD"
        echo "  ┌──────────────────────────────────────────┐"
        echo "  │   ARCH LINUX CUSTOM INSTALLER v2.2       │"
        echo "  │   Root-Rechte werden benötigt.           │"
        echo "  └──────────────────────────────────────────┘"
        printf '%b' "$RESET"
        # Ursprüngliche Argumente (inkl. --dry-run) an sudo durchreichen
        if $DRY_RUN; then
            exec sudo -E "$0" --dry-run
        else
            exec sudo -E "$0"
        fi
        # unreachable
        exit 1
    fi

    # Sicheres temporäres Verzeichnis (unvorhersagbarer Name)
    CONFIG_DIR=$(mktemp -d /tmp/archinstall_custom.XXXXXX) || {
        echo "FEHLER: Konnte temporäres Verzeichnis nicht anlegen" >&2
        exit 1
    }
    chmod 700 "$CONFIG_DIR"

    # Start-Hinweis (Tipp zu --dry-run bzw. Dry-Run-Bestätigung)
    zeige_startinfo

    # Prüfungen
    pruefe_voraussetzungen

    # Hauptmenü starten
    hauptmenue
}

main "$@"
