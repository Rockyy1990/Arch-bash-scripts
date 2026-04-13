#!/bin/bash

echo ""
read -p "Optimierte pacman.conf. Beliebige Taste drücken um zu starten..."
echo ""

# Installiere aria2 und reflector
sudo pacman -S --needed --noconfirm aria2 reflector
sudo reflector --country Germany --latest 14 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
sudo pacman -Sy
clear

update_pacman_conf() {
    local backup_dir="/etc/pacman.d/backups"
    local pacman_conf="/etc/pacman.conf"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    check_root() {
    if [[ $EUID -ne 0 ]]; then
        # Versuche sudo zu finden
        local sudo_cmd=""
        if [[ -x /usr/bin/sudo ]]; then
            sudo_cmd="/usr/bin/sudo"
        elif [[ -x /bin/sudo ]]; then
            sudo_cmd="/bin/sudo"
        else
            echo "Fehler: sudo nicht gefunden!"
            echo "Installiere sudo mit: pacman -S sudo"
            exit 1
        fi
        echo "Starte mit sudo neu..."
        exec "$sudo_cmd" "$0" "$@"

    fi
}
check_root "$@"

    # Erstelle Backup-Verzeichnis, falls es nicht existiert
    if [[ ! -d "$backup_dir" ]]; then
        mkdir -p "$backup_dir"
        echo "Backup-Verzeichnis erstellt: $backup_dir"
    fi

    # Erstelle Backup der aktuellen pacman.conf
    if [[ -f "$pacman_conf" ]]; then
        cp "$pacman_conf" "$backup_dir/pacman.conf.backup_$timestamp"
        echo "Backup erstellt: $backup_dir/pacman.conf.backup_$timestamp"
    else
        echo "Fehler: $pacman_conf nicht gefunden!"
        return 1
    fi

    # Schreibe die neue pacman.conf
    cat > "$pacman_conf" << 'EOF'
#
# /etc/pacman.conf - Optimierte Konfiguration
#
# ╔═════════════════════════════════════════════════════════════════════╗
# ║  OPTIMIERTE PACMAN.CONF MIT ARIA2-SUPPORT                           ║
# ║  Erstellt: April 2026 | Basiert auf pacman 7.x                      ║
# ║                                                                     ║
# ║  HINWEIS: Vor Nutzung sicherstellen, dass aria2 installiert ist:    ║
# ║           sudo pacman -S aria2                                      ║
# ╚═════════════════════════════════════════════════════════════════════╝
#
# ┌─────────────────────────────────────────────────────────────────────┐
# │ DOWNLOAD-MODI (NUR EINEN AKTIVIEREN!)                               │
# │                                                                     │
# │ MODUS A: aria2 (multi-connection pro Datei, sequentiell)            │
# │   → XferCommand aktiv, ParallelDownloads wird IGNORIERT             │
# │   → Vorteil: Einzelne große Pakete werden schneller geladen         │
# │                                                                     │
# │ MODUS B: Nativer pacman-Download (parallele Pakete gleichzeitig)    │
# │   → XferCommand auskommentiert, ParallelDownloads aktiv             │
# │   → Vorteil: Viele kleine Pakete werden gleichzeitig geladen        │
# │                                                                     │
# │ EMPFEHLUNG: Bei schneller Leitung (>100 Mbit) → Modus B             │
# │             Bei langsamer Leitung / schlechten Mirrors → Modus A    │
# └─────────────────────────────────────────────────────────────────────┘

# ==============================================================================
# ALLGEMEINE OPTIONEN
# ==============================================================================

[options]

# --- Grundlegende Paketsicherheit ---
# Verhindert versehentliches Entfernen kritischer Systempakete
HoldPkg      = pacman glibc

# CPU-Architektur (auto = automatische Erkennung via uname -m)
Architecture = auto

# --- Paket-Ausnahmen ---
# Pakete, die NICHT automatisch aktualisiert werden sollen
# Nützlich z.B. bei benutzerdefinierten Kernels oder Wine-Staging
#IgnorePkg   = linux linux-headers
#IgnoreGroup =

# --- Dateischutz ---
# Dateien, die bei Updates nicht überschrieben werden sollen
#NoUpgrade   = etc/pacman.d/mirrorlist
#NoExtract   =

# ==============================================================================
# DOWNLOAD-KONFIGURATION
# ==============================================================================

# ┌────────────────────────────────────────────────────────────────────────────┐
# │ MODUS A: aria2 als Download-Manager                                      │
# │                                                                          │
# │ Optionen erklärt:                                                        │
# │   --allow-overwrite=true    Vorhandene Dateien überschreiben             │
# │   --continue=true           Abgebrochene Downloads fortsetzen            │
# │   --file-allocation=none    Keine Vorab-Speicherreservierung             │
# │   --log-level=error         Nur Fehler loggen (weniger Ausgabe)          │
# │   --max-tries=3             Maximal 3 Versuche pro Download              │
# │   --max-connection-per-server=4  4 parallele Verbindungen pro Mirror     │
# │   --max-file-not-found=5   Toleranz für "Datei nicht gefunden"           │
# │   --min-split-size=1M       Ab 1 MB wird die Datei gesplittet            │
# │   --no-conf                 Keine externe aria2-Konfig laden             │
# │   --remote-time=true        Server-Zeitstempel beibehalten               │
# │   --summary-interval=0      Keine periodischen Zusammenfassungen         │
# │   --timeout=5               5 Sekunden Verbindungs-Timeout               │
# │   --dir=/ --out %o %u       Ausgabepfad und URL von pacman               │
# │                                                                          │
# │ AKTIVIEREN: Zeile unten einkommentieren + ParallelDownloads auskomm.     │
# └────────────────────────────────────────────────────────────────────────────┘
#XferCommand = /usr/bin/aria2c --allow-overwrite=true --continue=true --file-allocation=none --log-level=error --max-tries=3 --max-connection-per-server=4 --max-file-not-found=5 --min-split-size=1M --no-conf --remote-time=true --summary-interval=0 --timeout=5 --dir=/ --out %o %u

# ┌────────────────────────────────────────────────────────────────────────────┐
# │ MODUS B: Nativer paralleler Download                                     │
# │                                                                          │
# │ AKTIVIEREN: XferCommand oben auskommentieren + Zeile unten einkomm.      │
# │ Werte: 5 = Standard, 8-10 = schnelle Leitungen, >10 = kaum Vorteil      │
# └────────────────────────────────────────────────────────────────────────────┘
ParallelDownloads = 4

# ==============================================================================
# SICHERHEIT (pacman 7.x)
# ==============================================================================

# Sandboxed Downloads: Pakete werden mit eingeschränkten Rechten
# heruntergeladen (benötigt Landlock-Support im Kernel >= 6.6)
DownloadUser = alpm

# Sandbox deaktivieren (nur bei Problemen, z.B. in Containern/VMs
# ohne Landlock-Support)
#DisableSandbox

# ==============================================================================
# DARSTELLUNG & KOMFORT
# ==============================================================================

# Farbige Terminalausgabe
Color

# Pac-Man frisst Punkte statt langweiligem Fortschrittsbalken
ILoveCandy

# Detaillierte Paketlisten bei Upgrades (Repo, alte/neue Version, Größe)
VerbosePkgLists

# Fortschrittsanzeige nicht unterdrücken
#NoProgressBar

# ==============================================================================
# SYSTEMSCHUTZ
# ==============================================================================

# Speicherplatzprüfung vor Installation
CheckSpace

# Download-Timeout deaktivieren (verhindert Abbrüche bei langsamen Mirrors)
DisableDownloadTimeout

# ==============================================================================
# SIGNATURPRÜFUNG
# ==============================================================================

# Pakete: Signatur erforderlich | Datenbanken: Signatur optional
# (Standard seit pacman 7.1 - sollte NICHT abgeschwächt werden!)
SigLevel          = Required DatabaseOptional

# Lokale Pakete: Signaturprüfung optional (für selbst gebaute AUR-Pakete)
LocalFileSigLevel = Optional

#RemoteFileSigLevel = Required

# ==============================================================================
# REPOSITORIES
# ==============================================================================

# HINWEIS: Reihenfolge ist relevant! Pakete werden aus dem ERSTEN
# Repository installiert, das sie enthält.

# --- Offizielle Arch-Repos ---

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist


# --- 32-Bit Multilib (erforderlich für Wine, Steam, 32-Bit-Spiele) ---
[multilib]
Include = /etc/pacman.d/mirrorlist

# --- Testing-Repos (NUR für erfahrene Nutzer / Tester!) ---
# WARNUNG: Können instabile Pakete enthalten!
#[core-testing]
#Include = /etc/pacman.d/mirrorlist

#[extra-testing]
#Include = /etc/pacman.d/mirrorlist

#[multilib-testing]
#Include = /etc/pacman.d/mirrorlist

# ┌─────────────────────────────────────────────────────────────────────┐
# │ DRITTANBIETER-REPOS (Beispiele - nach Bedarf einkommentieren)       │
# │                                                                     │
# │ CachyOS (performance-optimierte Pakete):                            │
# │   Siehe: https://cachyos.org/                                       │
# │   Erfordert separaten Keyring + mirrorlist!                         │
# │                                                                     │
# │ Chaotic-AUR (vorkompilierte AUR-Pakete):                            │
# │   Siehe: https://aur.chaotic.cx/                                    │
# │   Erfordert separaten Keyring + mirrorlist!                         │
# └─────────────────────────────────────────────────────────────────────┘

#[cachyos]
#Include = /etc/pacman.d/cachyos-mirrorlist

#[chaotic-aur]
#Include = /etc/pacman.d/chaotic-mirrorlist
EOF

    # Überprüfe, ob die Datei erfolgreich geschrieben wurde
    if [[ $? -eq 0 ]]; then
        echo "✓ pacman.conf erfolgreich aktualisiert!"
        echo "✓ Alte Konfiguration gespeichert unter: $backup_dir/pacman.conf.backup_$timestamp"

        # Optional: Zeige Unterschiede
        echo ""
        echo "Unterschiede zur alten Konfiguration:"
        diff -u "$backup_dir/pacman.conf.backup_$timestamp" "$pacman_conf" || true

        return 0
    else
        echo "Fehler: pacman.conf konnte nicht geschrieben werden!"
        # Stelle das Backup wieder her
        cp "$backup_dir/pacman.conf.backup_$timestamp" "$pacman_conf"
        echo "Backup wurde wiederhergestellt."
        return 1
    fi
}

# Funktion aufrufen
update_pacman_conf
