#!/usr/bin/env bash

echo "
#==========================================================================
#                 CachyOS-Optimierungen fuer Arch Linux
#
# Version: 1.0
#
# Beschreibung: Wendet ausgewaehlte CachyOS-Performance-Tweaks auf ein
#               bestehendes Arch Linux System an.
#
# Quelle: https://github.com/CachyOS/CachyOS-Settings
# Lizenz: MIT
#==========================================================================
"

set -euo pipefail

#-------------------------------------
# Farben & Formatierung
#-------------------------------------
readonly ROT=$'\e[1;31m'
readonly GRUEN=$'\e[1;32m'
readonly GELB=$'\e[1;33m'
readonly BLAU=$'\e[1;34m'
readonly CYAN=$'\e[1;36m'
readonly MAGENTA=$'\e[1;35m'
readonly RESET=$'\e[0m'
readonly FETT=$'\e[1m'
readonly DIM=$'\e[2m'

#-------------------------------------
# Globale Variablen
#-------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly BACKUP_DIR="/root/.cachyos-tweaks-backup/$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="/var/log/cachyos-tweaks.log"
AENDERUNGEN=0
FEHLER=0

#-------------------------------------
# Hilfsfunktionen
#-------------------------------------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

info()    { echo "${BLAU}[INFO]${RESET}    $1"; log "INFO: $1"; }
erfolg()  { echo "${GRUEN}[OK]${RESET}      $1"; log "OK: $1"; }
warnung() { echo "${GELB}[WARNUNG]${RESET} $1"; log "WARNUNG: $1"; }
fehler()  { echo "${ROT}[FEHLER]${RESET}  $1"; log "FEHLER: $1"; ((++FEHLER)); }

trenner() {
    echo "${DIM}──────────────────────────────────────────────────────────${RESET}"
}

backup_datei() {
    local datei="$1"
    if [[ -f "$datei" ]]; then
        local ziel="${BACKUP_DIR}${datei}"
        mkdir -p "$(dirname "$ziel")"
        cp -a "$datei" "$ziel"
        log "Backup erstellt: $datei -> $ziel"
    fi
}

pruefen_root() {
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
        echo "Es werden root Rechte benötigt.."
        exec "$sudo_cmd" "$0" "$@"

    fi
}
pruefen_root "$@"

pruefen_arch() {
    if [[ ! -f /etc/arch-release ]]; then
        echo "${ROT}Fehler: Dieses Script ist nur fuer Arch Linux konzipiert.${RESET}"
        exit 1
    fi
}

bestaetigen() {
    local frage="$1"
    local antwort
    echo -n "${CYAN}${frage} [j/N]: ${RESET}"
    read -r antwort
    [[ "$antwort" =~ ^[jJyY]$ ]]
}

#-------------------------------------
# Banner
#-------------------------------------
banner() {
    clear
    cat << 'BANNER'

   ╔════════════════════════════════════════════════════════╗
   ║       CachyOS-Optimierungen fuer Arch Linux            ║
   ║       ─────────────────────────────────────            ║
   ║       Performance-Tweaks aus dem CachyOS-Projekt       ║
   ╚════════════════════════════════════════════════════════╝

BANNER
    echo "${DIM}  Basierend auf: github.com/CachyOS/CachyOS-Settings${RESET}"
    echo ""
}

#-------------------------------------
# Systeminformationen anzeigen
#-------------------------------------
system_info() {
    trenner
    echo "${FETT}  Systeminformationen:${RESET}"
    echo "    Kernel:   $(uname -a)"
    echo "    CPU:      $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'unbekannt')"
    echo "    RAM:      $(free -h | awk 'tolower($1) ~ /^speicher:$/ {print $2; exit}')"
    echo "    GPU:      $(lspci 2>/dev/null | grep -i 'vga\|3d' | head -1 | cut -d: -f3 | xargs || echo 'unbekannt')"

    # x86-64 Feature-Level erkennen
    local level="  v1"
    if grep -qE   'avx512' /proc/cpuinfo 2>/dev/null; then
        level="  v4"
    elif grep -qE 'avx2' /proc/cpuinfo 2>/dev/null; then
        level="  v3"
    elif grep -qE 'sse4_2' /proc/cpuinfo 2>/dev/null; then
        level="  v2"
    fi
    echo "x86-64:     ${level}"

    # GPU-Typ erkennen
    local gpu_typ="unbekannt"
    if lspci 2>/dev/null | grep -qi 'nvidia'; then
        gpu_typ="nvidia"
    elif lspci 2>/dev/null | grep -qi 'amd\|radeon'; then
        gpu_typ="amd"
    elif lspci 2>/dev/null | grep -qi 'intel.*graphics\|intel.*uhd\|intel.*iris'; then
        gpu_typ="intel"
    fi
    echo "  GPU-Typ:    ${gpu_typ}"

    # ZRAM pruefen
    if [[ -e /dev/zram0 ]]; then
        echo "  ZRAM:       ${GRUEN}aktiv${RESET}"
    else
        echo "  ZRAM:       ${GELB}inaktiv${RESET}"
    fi
    trenner
    echo ""
}

#=============================================================================
# MODUL 1: Sysctl-Optimierungen
#=============================================================================
modul_sysctl() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 1] Sysctl-Optimierungen (Kernel-Parameter)${RESET}"
    trenner
    info "Erstellt /etc/sysctl.d/90-cachyos-tweaks.conf"
    info "Werte basierend auf CachyOS 70-cachyos-settings.conf"
    echo ""
    echo "  Aenderungen:"
    echo "    - vm.swappiness           = 100     (Standard: 60)"
    echo "    - vm.vfs_cache_pressure   = 50      (Standard: 100)"
    echo "    - vm.dirty_bytes          = 268435456 (256MB, statt Ratio)"
    echo "    - vm.dirty_background_bytes = 67108864 (64MB)"
    echo "    - vm.page-cluster         = 0       (Standard: 3)"
    echo "    - kernel.nmi_watchdog     = 0       (Deaktiviert)"
    echo "    - kernel.split_lock_mitigate = 0    (Gaming-Verbesserung)"
    echo "    - kernel.unprivileged_userns_clone = 1"
    echo "    - kernel.kptr_restrict    = 2"
    echo "    - kernel.printk           = 3 3 3 3 (Weniger Console-Spam)"
    echo "    - net.core.netdev_max_backlog = 16384"
    echo "    - fs.file-max             = 2097152"
    echo ""

    if ! bestaetigen "Sysctl-Optimierungen anwenden?"; then
        warnung "Sysctl-Modul uebersprungen."
        return
    fi

    backup_datei "/etc/sysctl.d/90-cachyos-tweaks.conf"

    cat > /etc/sysctl.d/90-cachyos-tweaks.conf << 'SYSCTL'
# ===========================================================================
# CachyOS Sysctl-Optimierungen fuer Arch Linux
# Quelle: github.com/CachyOS/CachyOS-Settings
# ===========================================================================

# --- Speicher & Swap ---
# Bei ZRAM-Nutzung ist ein hoher Wert (100-200) sinnvoll, da Daten im RAM
# komprimiert bleiben statt auf Disk geschrieben zu werden.
# Ohne ZRAM/Zswap ist 60 (Standard) oft besser.
vm.swappiness = 100

# VFS-Cache weniger aggressiv freigeben (Standard: 100)
vm.vfs_cache_pressure = 50

# Feste Byte-Werte statt Prozent vermeiden Thrashing bei hoher RAM-Auslastung
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864

# Dirty-Writeback alle 5 Sekunden (Standard-Aehnlich, aber explizit gesetzt)
vm.dirty_writeback_centisecs = 500

# Swap-Readahead deaktivieren - einzelne Pages sind effizienter
vm.page-cluster = 0

# Proaktive Speicher-Kompaktierung deaktivieren (reduziert CPU-Overhead)
vm.compaction_proactiveness = 0

# Watermark-Boost deaktivieren (reduziert unnoetige Speicherrueckforderung)
vm.watermark_boost_factor = 0

# Min watermark bei 1% setzen
vm.watermark_scale_factor = 125

# --- Kernel ---
# NMI-Watchdog deaktivieren (spart CPU-Zyklen & Strom)
kernel.nmi_watchdog = 0

# Split-Lock-Mitigation deaktivieren (verhindert Stutter in manchen Spielen)
kernel.split_lock_mitigate = 0

# Unprivilegierte User-Namespaces erlauben (Container, Flatpak etc.)
kernel.unprivileged_userns_clone = 1

# Kernel-Pointer verstecken (Sicherheit)
kernel.kptr_restrict = 2

# Kexec deaktivieren (Sicherheit)
kernel.kexec_load_disabled = 1

# Console-Log auf Fehler beschraenken
kernel.printk = 3 3 3 3

# --- Netzwerk ---
# Groessere Netzwerk-Backlog-Queue
net.core.netdev_max_backlog = 16384

# --- Dateisystem ---
# Maximale Anzahl offener Dateien erhoehen
fs.file-max = 2097152
SYSCTL

    sysctl --system > /dev/null 2>&1
    erfolg "Sysctl-Optimierungen angewandt."
    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 2: I/O-Scheduler Udev-Regeln
#=============================================================================
modul_io_scheduler() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 2] I/O-Scheduler Udev-Regeln${RESET}"
    trenner
    info "Erstellt /etc/udev/rules.d/60-cachyos-ioschedulers.rules"
    echo ""
    echo "  Zuweisung:"
    echo "    - NVMe SSDs:  none     (Kernel-intern, niedrigste Latenz)"
    echo "    - SATA SSDs:  mq-deadline (Gute Balance fuer SATA)"
    echo "    - HDDs:       bfq      (Fair Queueing, ideal fuer HDDs)"
    echo ""

    if ! bestaetigen "I/O-Scheduler Regeln anwenden?"; then
        warnung "I/O-Scheduler Modul uebersprungen."
        return
    fi

    backup_datei "/etc/udev/rules.d/60-cachyos-ioschedulers.rules"

    cat > /etc/udev/rules.d/60-cachyos-ioschedulers.rules << 'UDEV_IO'
# CachyOS I/O-Scheduler Udev-Regeln
# NVMe SSDs: none (Kernel-intern optimal)
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"

# SATA SSDs: mq-deadline
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# HDDs: bfq (Budget Fair Queueing)
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
UDEV_IO

    udevadm control --reload-rules 2>/dev/null
    udevadm trigger 2>/dev/null
    erfolg "I/O-Scheduler Regeln installiert."
    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 3: SATA-Performance & HDD-Tuning
#=============================================================================
modul_sata() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 3] SATA Link-Power-Management${RESET}"
    trenner
    info "Erstellt Udev-Regel fuer SATA max_performance"
    echo ""
    echo "  Aenderungen:"
    echo "    - SATA Link Power Management auf max_performance"
    echo "    - hdparm -B 254 -S 0 fuer rotierende Platten (kein Spindown)"
    echo ""

    if ! bestaetigen "SATA-Performance Regeln anwenden?"; then
        warnung "SATA-Modul uebersprungen."
        return
    fi

    backup_datei "/etc/udev/rules.d/61-cachyos-sata.rules"

    cat > /etc/udev/rules.d/61-cachyos-sata.rules << 'UDEV_SATA'
# CachyOS SATA Link-Power-Management
# Maximale Performance fuer SATA-Ports
ACTION=="add", SUBSYSTEM=="scsi_host", KERNEL=="host*", ATTR{link_power_management_policy}="max_performance"

# HDD APM & Spindown deaktivieren (nur fuer rotierende Laufwerke)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", RUN+="/usr/bin/hdparm -B 254 -S 0 /dev/%k"
UDEV_SATA

    udevadm control --reload-rules 2>/dev/null
    erfolg "SATA-Performance Regeln installiert."
    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 4: ZRAM-Konfiguration
#=============================================================================
modul_zram() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 4] ZRAM Swap-Konfiguration${RESET}"
    trenner
    info "Installiert & konfiguriert zram-generator"
    echo ""
    echo "  Konfiguration:"
    echo "    - Kompression:    zstd"
    echo "    - Groesse:        RAM-Groesse (1:1)"
    echo "    - Swap-Prioritaet: 100"
    echo "    - Swappiness wird auf 150 angepasst (Udev-Regel)"
    echo ""

    if ! bestaetigen "ZRAM-Konfiguration anwenden?"; then
        warnung "ZRAM-Modul uebersprungen."
        return
    fi

    # zram-generator installieren
    if ! pacman -Qi zram-generator &>/dev/null; then
        info "Installiere zram-generator..."
        pacman -S --noconfirm --needed zram-generator || {
            fehler "zram-generator konnte nicht installiert werden."
            return
        }
    fi

    backup_datei "/etc/systemd/zram-generator.conf"

    cat > /etc/systemd/zram-generator.conf << 'ZRAM'
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
ZRAM

    # ZRAM-spezifische Udev-Regel fuer hoehere Swappiness
    backup_datei "/etc/udev/rules.d/30-cachyos-zram.rules"

    cat > /etc/udev/rules.d/30-cachyos-zram.rules << 'UDEV_ZRAM'
# CachyOS ZRAM Udev-Regeln
# Bei ZRAM ist hohe Swappiness sinnvoll: anonyme Pages werden komprimiert
# im RAM gehalten statt auf Disk geschrieben.
ACTION=="add", KERNEL=="zram0", ATTR{comp_algorithm}="zstd", \
    RUN+="/usr/bin/sysctl vm.swappiness=150", \
    RUN+="/usr/bin/sysctl vm.watermark_boost_factor=0", \
    RUN+="/usr/bin/sysctl vm.watermark_scale_factor=125", \
    RUN+="/usr/bin/sysctl vm.page-cluster=0"
UDEV_ZRAM

    # Zswap deaktivieren (kollidiert mit ZRAM)
    local cmdline_param="zswap.enabled=0"
    if [[ -f /etc/kernel/cmdline ]]; then
        if ! grep -q "$cmdline_param" /etc/kernel/cmdline; then
            warnung "Empfehlung: '$cmdline_param' zur Kernel-Commandline hinzufuegen!"
            warnung "Datei: /etc/kernel/cmdline oder Bootloader-Konfiguration"
        fi
    fi

    udevadm control --reload-rules 2>/dev/null
    systemctl daemon-reload 2>/dev/null

    erfolg "ZRAM-Konfiguration installiert. Neustart erforderlich!"
    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 5: Modprobe-Konfiguration (Audio, GPU, Watchdog)
#=============================================================================
modul_modprobe() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 5] Modprobe-Konfigurationen${RESET}"
    trenner
    info "Konfiguriert Kernel-Module fuer Hardware-Optimierung"
    echo ""
    echo "  Aenderungen:"
    echo "    - Audio: snd-hda-intel Power-Save deaktiviert (Anti-Knacksen)"
    echo "    - Watchdog: iTCO_wdt & sp5100_tco blacklisted"

    # GPU erkennen
    local hat_nvidia=false
    local hat_amd=false
    if lspci 2>/dev/null | grep -qi 'nvidia'; then hat_nvidia=true; fi
    if lspci 2>/dev/null | grep -qi 'amd.*radeon\|radeon\|amd.*navi\|amd.*vega'; then hat_amd=true; fi

    if $hat_nvidia; then
        echo "    - NVIDIA: PAT, Speicher-Init, Frame-Pacing Optimierungen"
    fi
    if $hat_amd; then
        echo "    - AMD GPU: amdgpu-Treiber fuer GCN 1.0+ erzwungen"
    fi
    echo ""

    if ! bestaetigen "Modprobe-Konfigurationen anwenden?"; then
        warnung "Modprobe-Modul uebersprungen."
        return
    fi

    # --- Audio Power-Save deaktivieren ---
    backup_datei "/etc/modprobe.d/cachyos-audio.conf"
    cat > /etc/modprobe.d/cachyos-audio.conf << 'MODPROBE_AUDIO'
# CachyOS: Audio Power-Save deaktivieren (verhindert Knacksen/Knistern)
options snd-hda-intel power_save=0
MODPROBE_AUDIO
    erfolg "Audio Power-Save deaktiviert."

    # --- Watchdog blacklisten ---
    backup_datei "/etc/modprobe.d/cachyos-watchdog.conf"
    cat > /etc/modprobe.d/cachyos-watchdog.conf << 'MODPROBE_WD'
# CachyOS: Watchdog-Timer blacklisten (spart Ressourcen)
blacklist iTCO_wdt
blacklist sp5100_tco
MODPROBE_WD
    erfolg "Watchdog-Module blacklisted."

    # --- NVIDIA-Optimierungen ---
    if $hat_nvidia; then
        backup_datei "/etc/modprobe.d/cachyos-nvidia.conf"
        cat > /etc/modprobe.d/cachyos-nvidia.conf << 'MODPROBE_NV'
# CachyOS: NVIDIA-Treiber Optimierungen
# PAT (Page Attribute Table) fuer bessere CPU-Performance
options nvidia NVreg_UsePageAttributeTable=1
# GPU-Speicher nicht bei Allokation nullen (schnellere Allokation)
options nvidia NVreg_InitializeSystemMemoryAllocations=0
# Frame-Pacing verbessern
options nvidia NVreg_RegistryDwords=RMIntrLockingMode=1
# DRM Modesetting & Framebuffer
options nvidia_drm modeset=1
options nvidia_drm fbdev=1
MODPROBE_NV
        erfolg "NVIDIA-Optimierungen konfiguriert."
    fi

    # --- AMD GPU erzwingen ---
    if $hat_amd; then
        backup_datei "/etc/modprobe.d/cachyos-amdgpu.conf"
        cat > /etc/modprobe.d/cachyos-amdgpu.conf << 'MODPROBE_AMD'
# CachyOS: amdgpu-Treiber fuer aeltere GCN-Karten erzwingen
# GCN 1.0 (Southern Islands)
options amdgpu si_support=1
options radeon si_support=0
# GCN 2.0 (Sea Islands)
options amdgpu cik_support=1
options radeon cik_support=0
MODPROBE_AMD
        erfolg "AMD GPU amdgpu-Erzwingung konfiguriert."
    fi

    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 6: Systemd-Optimierungen
#=============================================================================
modul_systemd() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 6] Systemd-Optimierungen${RESET}"
    trenner
    info "Optimiert Systemd-Timeouts, Journal, File-Limits, NTP"
    echo ""
    echo "  Aenderungen:"
    echo "    - Service-Timeouts:        Start=15s, Stop=10s"
    echo "    - Journal-Groesse:         max. 50MB"
    echo "    - File-Descriptor-Limits:  System 2048:2097152, User 1024:1048576"
    echo "    - NTP-Server:              Cloudflare + Google"
    echo "    - Coredump-Bereinigung:    Aelter als 3 Tage loeschen"
    echo "    - User-Service Delegation: CPU, IO, Memory, Pids"
    echo ""

    if ! bestaetigen "Systemd-Optimierungen anwenden?"; then
        warnung "Systemd-Modul uebersprungen."
        return
    fi

    # --- Service-Timeouts ---
    local system_conf_dir="/etc/systemd/system.conf.d"
    mkdir -p "$system_conf_dir"
    backup_datei "${system_conf_dir}/cachyos-timeouts.conf"

    cat > "${system_conf_dir}/cachyos-timeouts.conf" << 'SYSD_TIMEOUT'
# CachyOS: Schnellere Service-Timeouts
[Manager]
DefaultTimeoutStartSec=15s
DefaultTimeoutStopSec=10s
DefaultLimitNOFILE=2048:2097152
SYSD_TIMEOUT
    erfolg "Systemd System-Timeouts konfiguriert."

    # --- User-Service Limits ---
    local user_conf_dir="/etc/systemd/user.conf.d"
    mkdir -p "$user_conf_dir"
    backup_datei "${user_conf_dir}/cachyos-limits.conf"

    cat > "${user_conf_dir}/cachyos-limits.conf" << 'SYSD_USER'
# CachyOS: User-Service File-Descriptor-Limits
[Manager]
DefaultLimitNOFILE=1024:1048576
SYSD_USER
    erfolg "Systemd User-Limits konfiguriert."

    # --- Journal-Groesse ---
    local journal_dir="/etc/systemd/journald.conf.d"
    mkdir -p "$journal_dir"
    backup_datei "${journal_dir}/cachyos-journal.conf"

    cat > "${journal_dir}/cachyos-journal.conf" << 'SYSD_JOURNAL'
# CachyOS: Journal-Groesse begrenzen
[Journal]
SystemMaxUse=50M
SYSD_JOURNAL
    erfolg "Journal-Limit auf 50MB gesetzt."

    # --- NTP-Server ---
    local timesyncd_dir="/etc/systemd/timesyncd.conf.d"
    mkdir -p "$timesyncd_dir"
    backup_datei "${timesyncd_dir}/cachyos-ntp.conf"

    cat > "${timesyncd_dir}/cachyos-ntp.conf" << 'SYSD_NTP'
# CachyOS: NTP-Server Konfiguration
[Time]
NTP=time.cloudflare.com
FallbackNTP=time.google.com time1.google.com time2.google.com time3.google.com time4.google.com
SYSD_NTP
    erfolg "NTP-Server konfiguriert (Cloudflare + Google)."

    # --- Coredump-Bereinigung ---
    backup_datei "/etc/tmpfiles.d/cachyos-coredump-cleanup.conf"
    cat > /etc/tmpfiles.d/cachyos-coredump-cleanup.conf << 'COREDUMP'
# CachyOS: Coredumps aelter als 3 Tage automatisch loeschen
d /var/lib/systemd/coredump 0755 root root 3d
COREDUMP
    erfolg "Coredump-Bereinigung eingerichtet (3 Tage)."

    # --- User-Service Resource Delegation ---
    local slice_dir="/etc/systemd/system/user@.service.d"
    mkdir -p "$slice_dir"
    backup_datei "${slice_dir}/cachyos-delegate.conf"

    cat > "${slice_dir}/cachyos-delegate.conf" << 'DELEGATE'
# CachyOS: CPU, IO, Memory & Pids Delegation an User-Services
[Service]
Delegate=cpu cpuset io memory pids
DELEGATE
    erfolg "User-Service Resource-Delegation aktiviert."

    systemctl daemon-reload 2>/dev/null
    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 7: Transparent Huge Pages (THP) Tuning
#=============================================================================
modul_thp() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 7] Transparent Huge Pages (THP) Tuning${RESET}"
    trenner
    info "Optimiert THP-Defragmentierung"
    echo ""
    echo "  Aenderungen:"
    echo "    - THP defrag:   defer+madvise (Standard: madvise)"
    echo "    - khugepaged/max_ptes_none Tuning (Kernel 6.12+)"
    echo ""

    if ! bestaetigen "THP-Tuning anwenden?"; then
        warnung "THP-Modul uebersprungen."
        return
    fi

    backup_datei "/etc/tmpfiles.d/cachyos-thp.conf"

    cat > /etc/tmpfiles.d/cachyos-thp.conf << 'THP'
# CachyOS: Transparent Huge Pages Defragmentierung
# defer+madvise: Hintergrund-Defrag + madvise-Unterstuetzung (z.B. tcmalloc)
w /sys/kernel/mm/transparent_hugepage/defrag - - - - defer+madvise

# THP Shrinker (Kernel >= 6.12): aggressiveres Zusammenlegen
w /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none - - - - 0
THP

    # Sofort anwenden wenn moeglich
    if [[ -f /sys/kernel/mm/transparent_hugepage/defrag ]]; then
        echo "defer+madvise" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
    fi
    if [[ -f /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none ]]; then
        echo "0" > /sys/kernel/mm/transparent_hugepage/khugepaged/max_ptes_none 2>/dev/null || true
    fi

    erfolg "THP-Tuning angewandt."
    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 8: CachyOS Kernel installieren
#=============================================================================
modul_kernel() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 8] CachyOS Kernel installieren${RESET}"
    trenner
    info "Fuegt CachyOS-Repos hinzu und installiert den CachyOS-Kernel"
    echo ""
    echo "  Optionen:"
    echo "    - linux-cachyos       (BORE Scheduler, sched-ext)"
    echo "    - linux-cachyos-lto   (Zusaetzlich LTO-optimiert)"
    echo ""
    echo "${GELB}  HINWEIS: Dies fuegt CachyOS-Paketquellen hinzu!${RESET}"
    echo "${GELB}  Das Installationsscript von CachyOS wird heruntergeladen.${RESET}"
    echo ""

    if ! bestaetigen "CachyOS Kernel & Repos installieren?"; then
        warnung "Kernel-Modul uebersprungen."
        return
    fi

    # CachyOS Repo-Installer ausfuehren
    info "Lade CachyOS Repository-Installer herunter..."
    local tmp_dir
    tmp_dir="$(mktemp -d)"

    if command -v curl &>/dev/null; then
        curl -sL "https://github.com/CachyOS/CachyOS-PKGBUILDS/raw/master/cachyos-repo/cachyos-repo.tar.xz" -o "${tmp_dir}/cachyos-repo.tar.xz" || {
            fehler "Download des CachyOS Repo-Installers fehlgeschlagen."
            rm -rf "$tmp_dir"
            return
        }
    elif command -v wget &>/dev/null; then
        wget -q "https://github.com/CachyOS/CachyOS-PKGBUILDS/raw/master/cachyos-repo/cachyos-repo.tar.xz" -O "${tmp_dir}/cachyos-repo.tar.xz" || {
            fehler "Download des CachyOS Repo-Installers fehlgeschlagen."
            rm -rf "$tmp_dir"
            return
        }
    else
        fehler "Weder curl noch wget verfuegbar."
        rm -rf "$tmp_dir"
        return
    fi

    cd "$tmp_dir"
    tar xf cachyos-repo.tar.xz 2>/dev/null || {
        fehler "Entpacken des Repo-Installers fehlgeschlagen."
        rm -rf "$tmp_dir"
        return
    }

    cd cachyos-repo 2>/dev/null || {
        fehler "Verzeichnis cachyos-repo nicht gefunden."
        rm -rf "$tmp_dir"
        return
    }

    info "Starte CachyOS Repository-Installer..."
    echo "${GELB}  (Du wirst moeglicherweise nach Bestaetigungen gefragt)${RESET}"
    echo ""

    bash cachyos-repo.sh || {
        fehler "CachyOS Repo-Installation fehlgeschlagen."
        rm -rf "$tmp_dir"
        return
    }

    rm -rf "$tmp_dir"

    # Kernel installieren
    echo ""
    echo "  Welchen Kernel installieren?"
    echo "    1) linux-cachyos       (BORE, Standard)"
    echo "    2) linux-cachyos-lto   (BORE + LTO)"
    echo "    3) Keinen (nur Repos hinzugefuegt)"
    echo ""
    echo -n "${CYAN}  Auswahl [1/2/3]: ${RESET}"
    local kernel_wahl
    read -r kernel_wahl

    case "$kernel_wahl" in
        1)
            pacman -S --needed linux-cachyos linux-cachyos-headers || {
                fehler "Kernel-Installation fehlgeschlagen."
                return
            }
            erfolg "linux-cachyos Kernel installiert."
            ;;
        2)
            pacman -S --needed linux-cachyos-lto linux-cachyos-lto-headers || {
                fehler "Kernel-Installation fehlgeschlagen."
                return
            }
            erfolg "linux-cachyos-lto Kernel installiert."
            ;;
        *)
            info "Kein Kernel installiert. Repos wurden hinzugefuegt."
            ;;
    esac

    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 9: ananicy-cpp (Auto-Nice-Daemon)
#=============================================================================
modul_ananicy() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 9] ananicy-cpp (Prozess-Priorisierung)${RESET}"
    trenner
    info "Installiert ananicy-cpp + CachyOS-Regeln"
    echo ""
    echo "  Beschreibung:"
    echo "    ananicy-cpp setzt automatisch Nice-/IO-/CPU-Prioritaeten"
    echo "    fuer bekannte Prozesse (Spiele, Browser, Compiler etc.)"
    echo "    Die CachyOS-Regeln enthalten vordefinierte Profile."
    echo ""

    if ! bestaetigen "ananicy-cpp installieren?"; then
        warnung "ananicy-Modul uebersprungen."
        return
    fi

    # Pruefen ob CachyOS-Repos verfuegbar sind
    if pacman -Ss cachyos-ananicy-rules &>/dev/null; then
        pacman -S --needed --noconfirm ananicy-cpp cachyos-ananicy-rules || {
            fehler "ananicy-cpp Installation fehlgeschlagen."
            return
        }
    else
        # Fallback: nur ananicy-cpp aus Community/AUR
        if pacman -Ss ananicy-cpp &>/dev/null; then
            pacman -S --needed --noconfirm ananicy-cpp || {
                fehler "ananicy-cpp Installation fehlgeschlagen."
                return
            }
            warnung "cachyos-ananicy-rules nicht verfuegbar (CachyOS-Repos noetig)."
            warnung "Nur Basis-ananicy-cpp installiert."
        else
            warnung "ananicy-cpp nicht in Paketquellen gefunden."
            warnung "CachyOS-Repos (Modul 8) muessen zuerst hinzugefuegt werden,"
            warnung "oder manuell aus dem AUR installieren."
            return
        fi
    fi

    systemctl enable --now ananicy-cpp.service 2>/dev/null
    erfolg "ananicy-cpp installiert und aktiviert."
    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 10: PCI-Latency Tuning (Audio)
#=============================================================================
modul_pci_latency() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 10] PCI-Latency Tuning (Audio-Geraete)${RESET}"
    trenner
    info "Setzt PCI-Latency-Timer fuer Soundkarten auf 80 Zyklen"
    echo ""
    echo "  Beschreibung:"
    echo "    Reduziert Audio-Latenz durch Anpassung des PCI-Timers"
    echo "    fuer erkannte Soundkarten-Geraete."
    echo ""

    if ! bestaetigen "PCI-Latency Tuning anwenden?"; then
        warnung "PCI-Latency Modul uebersprungen."
        return
    fi

    # setpci pruefen
    if ! command -v setpci &>/dev/null; then
        info "Installiere pciutils..."
        pacman -S --needed --noconfirm pciutils || {
            fehler "pciutils konnte nicht installiert werden."
            return
        }
    fi

    # Systemd-Service erstellen
    backup_datei "/etc/systemd/system/cachyos-pci-latency.service"

    cat > /usr/local/bin/cachyos-pci-latency.sh << 'PCI_SCRIPT'
#!/usr/bin/env bash
# CachyOS PCI-Latency fuer Audio-Geraete
# Setzt den Latency-Timer fuer Soundkarten auf 80

for dev in $(lspci -n 2>/dev/null | awk '/0403/{print $1}'); do
    setpci -s "$dev" latency_timer=80 2>/dev/null || true
done
PCI_SCRIPT
    chmod +x /usr/local/bin/cachyos-pci-latency.sh

    cat > /etc/systemd/system/cachyos-pci-latency.service << 'PCI_SERVICE'
[Unit]
Description=CachyOS PCI-Latency Tuning fuer Audio-Geraete
After=sound.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/cachyos-pci-latency.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
PCI_SERVICE

    systemctl daemon-reload 2>/dev/null
    systemctl enable --now cachyos-pci-latency.service 2>/dev/null
    erfolg "PCI-Latency Service installiert und aktiviert."
    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 11: Device-Permissions (Audio/Timer)
#=============================================================================
modul_device_perms() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 11] Device-Permissions (RTC, HPET)${RESET}"
    trenner
    info "Setzt Berechtigungen fuer Audio-relevante Geraete"
    echo ""
    echo "  Aenderungen:"
    echo "    - /dev/rtc0  -> Gruppe audio"
    echo "    - /dev/hpet  -> Gruppe audio"
    echo "    - /dev/cpu_dma_latency -> Gruppe audio (rw)"
    echo ""

    if ! bestaetigen "Device-Permissions anwenden?"; then
        warnung "Device-Permissions Modul uebersprungen."
        return
    fi

    backup_datei "/etc/udev/rules.d/62-cachyos-audio-devices.rules"

    cat > /etc/udev/rules.d/62-cachyos-audio-devices.rules << 'UDEV_PERM'
# CachyOS: Audio-Device Permissions
KERNEL=="rtc0", GROUP="audio"
KERNEL=="hpet", GROUP="audio"
# CPU DMA Latency Zugriff fuer Audio-Anwendungen
DEVPATH=="/devices/virtual/misc/cpu_dma_latency", OWNER="root", GROUP="audio", MODE="0660"
UDEV_PERM

    udevadm control --reload-rules 2>/dev/null
    erfolg "Device-Permissions gesetzt."
    ((++AENDERUNGEN))
}

#=============================================================================
# MODUL 12: Kernel-Boot-Parameter (nowatchdog)
#=============================================================================
modul_boot_params() {
    echo ""
    echo "${MAGENTA}${FETT}[Modul 12] Empfohlene Kernel-Boot-Parameter${RESET}"
    trenner
    info "Zeigt empfohlene Kernel-Commandline Parameter"
    echo ""
    echo "  Empfohlene Parameter:"
    echo "    ${FETT}nowatchdog${RESET}             - Watchdog komplett deaktivieren"
    echo "    ${FETT}zswap.enabled=0${RESET}        - Zswap deaktivieren (wenn ZRAM aktiv)"
    echo "    ${FETT}splash quiet${RESET}           - Weniger Boot-Meldungen"
    echo "    ${FETT}mitigations=off${RESET}        - CPU-Mitigations aus (UNSICHER, aber schneller)"
    echo ""
    echo "${GELB}  HINWEIS: Diese Parameter muessen manuell in der Bootloader-${RESET}"
    echo "${GELB}  Konfiguration eingetragen werden!${RESET}"
    echo ""

    # Bootloader erkennen
    if [[ -d /boot/loader ]]; then
        echo "  Erkannter Bootloader: ${FETT}systemd-boot${RESET}"
        echo "  Datei: /boot/loader/entries/*.conf -> 'options' Zeile"
    elif [[ -f /etc/default/grub ]]; then
        echo "  Erkannter Bootloader: ${FETT}GRUB${RESET}"
        echo "  Datei: /etc/default/grub -> GRUB_CMDLINE_LINUX_DEFAULT"
        echo "  Danach: grub-mkconfig -o /boot/grub/grub.cfg"
    elif [[ -f /boot/limine.conf ]] || [[ -f /etc/default/limine ]]; then
        echo "  Erkannter Bootloader: ${FETT}Limine${RESET}"
        echo "  Datei: /etc/default/limine -> KERNEL_CMDLINE"
    elif [[ -f /boot/refind_linux.conf ]]; then
        echo "  Erkannter Bootloader: ${FETT}rEFInd${RESET}"
        echo "  Datei: /boot/refind_linux.conf"
    else
        echo "  Bootloader: ${GELB}nicht erkannt${RESET}"
    fi
    echo ""

    if bestaetigen "Parameter-Vorschlag als Datei speichern?"; then
        cat > /root/cachyos-kernel-params.txt << 'PARAMS'
# =========================================================
# CachyOS empfohlene Kernel-Boot-Parameter
# =========================================================
# Fuer den Bootloader-Eintrag (options/cmdline):
#
# Sicher:
#   nowatchdog zswap.enabled=0 quiet splash
#
# Gaming (etwas riskanter, aber schneller):
#   nowatchdog zswap.enabled=0 quiet splash mitigations=off
#
# AMD P-State (fuer AMD Zen 2+):
#   amd_pstate=active
#
# NVIDIA (zusaetzlich zu modprobe):
#   nvidia_drm.modeset=1 nvidia_drm.fbdev=1
# =========================================================
PARAMS
        erfolg "Gespeichert unter /root/cachyos-kernel-params.txt"
    fi
}

#=============================================================================
# Alle Module anwenden
#=============================================================================
alle_module() {
    modul_sysctl
    modul_io_scheduler
    modul_sata
    modul_zram
    modul_modprobe
    modul_systemd
    modul_thp
    modul_kernel
    modul_ananicy
    modul_pci_latency
    modul_device_perms
    modul_boot_params
}

#=============================================================================
# Aenderungen rueckgaengig machen
#=============================================================================
rueckgaengig() {
    echo ""
    echo "${MAGENTA}${FETT}Aenderungen rueckgaengig machen${RESET}"
    trenner

    # Alle Backups auflisten
    if [[ ! -d /root/.cachyos-tweaks-backup ]]; then
        warnung "Keine Backups gefunden."
        return
    fi

    echo "Verfuegbare Backups:"
    local -a backups
    mapfile -t backups < <(ls -1d /root/.cachyos-tweaks-backup/*/ 2>/dev/null)

    if [[ ${#backups[@]} -eq 0 ]]; then
        warnung "Keine Backups gefunden."
        return
    fi

    local i=1
    for b in "${backups[@]}"; do
        echo "  ${i}) $(basename "$b")"
        ((++i))
    done
    echo ""
    echo -n "${CYAN}Backup-Nummer auswaehlen (oder 'a' fuer Abbruch): ${RESET}"
    local wahl
    read -r wahl

    [[ "$wahl" == "a" ]] && return

    if [[ "$wahl" =~ ^[0-9]+$ ]] && (( wahl >= 1 && wahl <= ${#backups[@]} )); then
        local backup_pfad="${backups[$((wahl-1))]}"
        if bestaetigen "Backup '$(basename "$backup_pfad")' wiederherstellen?"; then
            # Dateien aus Backup wiederherstellen
            find "$backup_pfad" -type f | while read -r datei; do
                local ziel="${datei#"$backup_pfad"}"
                if [[ -n "$ziel" ]]; then
                    cp -a "$datei" "$ziel" 2>/dev/null && \
                        erfolg "Wiederhergestellt: $ziel" || \
                        fehler "Fehler bei: $ziel"
                fi
            done

            # Nicht im Backup enthaltene CachyOS-Dateien entfernen
            local cachyos_dateien=(
                "/etc/sysctl.d/90-cachyos-tweaks.conf"
                "/etc/udev/rules.d/60-cachyos-ioschedulers.rules"
                "/etc/udev/rules.d/61-cachyos-sata.rules"
                "/etc/udev/rules.d/30-cachyos-zram.rules"
                "/etc/udev/rules.d/62-cachyos-audio-devices.rules"
                "/etc/modprobe.d/cachyos-audio.conf"
                "/etc/modprobe.d/cachyos-watchdog.conf"
                "/etc/modprobe.d/cachyos-nvidia.conf"
                "/etc/modprobe.d/cachyos-amdgpu.conf"
                "/etc/systemd/system.conf.d/cachyos-timeouts.conf"
                "/etc/systemd/user.conf.d/cachyos-limits.conf"
                "/etc/systemd/journald.conf.d/cachyos-journal.conf"
                "/etc/systemd/timesyncd.conf.d/cachyos-ntp.conf"
                "/etc/tmpfiles.d/cachyos-coredump-cleanup.conf"
                "/etc/tmpfiles.d/cachyos-thp.conf"
                "/etc/systemd/system/user@.service.d/cachyos-delegate.conf"
                "/etc/systemd/system/cachyos-pci-latency.service"
                "/usr/local/bin/cachyos-pci-latency.sh"
            )

            for datei in "${cachyos_dateien[@]}"; do
                if [[ -f "$datei" ]] && [[ ! -f "${backup_pfad}${datei}" ]]; then
                    rm -f "$datei" 2>/dev/null && \
                        info "Entfernt (neu erstellt): $datei"
                fi
            done

            sysctl --system > /dev/null 2>&1
            udevadm control --reload-rules 2>/dev/null
            systemctl daemon-reload 2>/dev/null
            erfolg "Backup wiederhergestellt. Neustart empfohlen!"
        fi
    else
        fehler "Ungueltige Auswahl."
    fi
}

#=============================================================================
# Status anzeigen
#=============================================================================
status_anzeigen() {
    echo ""
    echo "${MAGENTA}${FETT}Aktueller Optimierungsstatus${RESET}"
    trenner

    local check="${GRUEN}✓${RESET}"
    local cross="${ROT}✗${RESET}"

    # Sysctl
    local sw
    sw=$(sysctl -n vm.swappiness 2>/dev/null)
    [[ "$sw" -ge 100 ]] && echo "  $check Swappiness: $sw" || echo "  $cross Swappiness: $sw (Standard: 60)"

    local vfs
    vfs=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null)
    [[ "$vfs" -eq 50 ]] && echo "  $check VFS Cache Pressure: $vfs" || echo "  $cross VFS Cache Pressure: $vfs (Standard: 100)"

    local nmi
    nmi=$(sysctl -n kernel.nmi_watchdog 2>/dev/null)
    [[ "$nmi" -eq 0 ]] && echo "  $check NMI Watchdog: deaktiviert" || echo "  $cross NMI Watchdog: aktiv"

    # I/O Scheduler
    echo ""
    echo "  I/O-Scheduler:"
    for disk in /sys/block/sd? /sys/block/nvme?n? /sys/block/mmcblk?; do
        [[ -f "${disk}/queue/scheduler" ]] || continue
        local name=$(basename "$disk")
        local sched=$(cat "${disk}/queue/scheduler" 2>/dev/null | grep -oP '\[\K[^\]]+')
        local rot=$(cat "${disk}/queue/rotational" 2>/dev/null)
        local typ="SSD"
        [[ "$rot" == "1" ]] && typ="HDD"
        [[ "$name" == nvme* ]] && typ="NVMe"
        echo "    $name ($typ): $sched"
    done

    # ZRAM
    echo ""
    if [[ -e /dev/zram0 ]]; then
        echo "  $check ZRAM aktiv"
        zramctl 2>/dev/null | head -5 || true
    else
        echo "  $cross ZRAM inaktiv"
    fi

    # Services
    echo ""
    systemctl is-active ananicy-cpp.service &>/dev/null && \
        echo "  $check ananicy-cpp: aktiv" || echo "  $cross ananicy-cpp: inaktiv"

    systemctl is-active cachyos-pci-latency.service &>/dev/null && \
        echo "  $check PCI-Latency Service: aktiv" || echo "  $cross PCI-Latency Service: inaktiv"

    # Konfigurationsdateien
    echo ""
    echo "  Installierte Konfigurationen:"
    local conf_dateien=(
        "/etc/sysctl.d/90-cachyos-tweaks.conf"
        "/etc/udev/rules.d/60-cachyos-ioschedulers.rules"
        "/etc/udev/rules.d/61-cachyos-sata.rules"
        "/etc/udev/rules.d/30-cachyos-zram.rules"
        "/etc/modprobe.d/cachyos-audio.conf"
        "/etc/modprobe.d/cachyos-nvidia.conf"
        "/etc/modprobe.d/cachyos-amdgpu.conf"
        "/etc/systemd/zram-generator.conf"
    )
    for datei in "${conf_dateien[@]}"; do
        if [[ -f "$datei" ]]; then
            echo "    $check $(basename "$datei")"
        fi
    done

    echo ""
    trenner
}

#=============================================================================
# Hauptmenue
#=============================================================================
hauptmenue() {
    while true; do
        echo ""
        echo "${FETT}  Hauptmenü - CachyOS Optimierungen${RESET}"
        trenner
        echo ""
        echo "  ${FETT}Einzelne Module:${RESET}"
        echo "   1)  Sysctl-Optimierungen         (VM, Kernel, Netzwerk)"
        echo "   2)  I/O-Scheduler Udev-Regeln    (NVMe/SSD/HDD)"
        echo "   3)  SATA Link-Power-Management   (Performance-Modus)"
        echo "   4)  ZRAM-Konfiguration           (Komprimierter Swap)"
        echo "   5)  Modprobe-Konfigurationen     (Audio, GPU, Watchdog)"
        echo "   6)  Systemd-Optimierungen        (Timeouts, Journal, NTP)"
        echo "   7)  THP Tuning                   (Transparent Huge Pages)"
        echo "   8)  CachyOS Kernel installieren  (BORE Scheduler)"
        echo "   9)  ananicy-cpp                  (Prozess-Priorisierung)"
        echo "  10)  PCI-Latency Tuning           (Audio-Latenz)"
        echo "  11)  Device-Permissions           (RTC, HPET, DMA)"
        echo "  12)  Kernel-Boot-Parameter        (Empfehlungen)"
        echo ""
        echo "  ${FETT}Aktionen:${RESET}"
        echo "   a)  ALLE Module anwenden"
        echo "   s)  Status anzeigen"
        echo "   r)  Aenderungen rueckgaengig machen"
        echo "   q)  Beenden"
        echo ""
        echo -n "${CYAN}  Auswahl [1-12/a/s/r/q]: ${RESET}"
        local wahl
        read -r wahl

        case "$wahl" in
            1)  modul_sysctl ;;
            2)  modul_io_scheduler ;;
            3)  modul_sata ;;
            4)  modul_zram ;;
            5)  modul_modprobe ;;
            6)  modul_systemd ;;
            7)  modul_thp ;;
            8)  modul_kernel ;;
            9)  modul_ananicy ;;
            10) modul_pci_latency ;;
            11) modul_device_perms ;;
            12) modul_boot_params ;;
            a|A) alle_module ;;
            s|S) status_anzeigen ;;
            r|R) rueckgaengig ;;
            q|Q)
                echo ""
                if (( AENDERUNGEN > 0 )); then
                    erfolg "${AENDERUNGEN} Modul(e) erfolgreich angewandt."
                    if (( FEHLER > 0 )); then
                        warnung "${FEHLER} Fehler aufgetreten."
                    fi
                    echo ""
                    warnung "Ein ${FETT}Neustart${RESET}${GELB} wird empfohlen damit alle Aenderungen wirksam werden!${RESET}"
                fi
                echo ""
                echo "${DIM}Backup-Verzeichnis: ${BACKUP_DIR}${RESET}"
                echo "${DIM}Log-Datei:          ${LOG_FILE}${RESET}"
                echo ""
                exit 0
                ;;
            *)
                fehler "Ungueltige Auswahl: '$wahl'"
                ;;
        esac

        echo ""
        echo "${DIM} Druecke Enter um fortzufahren...${RESET}"
        read -r
    done
}

#===============================================================================
# Hauptprogramm
#===============================================================================
main() {
    pruefen_root
    pruefen_arch
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    banner
    system_info
    hauptmenue
}

main "$@"
