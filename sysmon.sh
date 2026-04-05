#!/usr/bin/env bash
# ============================================================
#  SYSMON — Arch Linux System Monitor  v2.1
#  Kernel · CPU · GPU · Mainboard · Storage · Network · Procs
#
#  Bugfixes v2.1:
#   - set -e entfernt (pipefail + -u behalten)
#   - pacman -Qu Exit-Code korrekt behandelt
#   - who-Fallback über /proc/utmp / loginctl
#   - CPU_SOCKETS Fallback auf 1 wenn kein 'physical id'
#   - CPU_FREQ_CUR vollständig abgesichert
#   - LOAD_1M Leer-Guard
#   - declare -A toter Code entfernt
#   - pct_str numerisch validiert vor Arithmetik
#   - NVMe-Glob auf [0-9]* erweitert
#   - grep-Pipes mit || true korrekt abgesichert
#   - 'type' Variable → 'zone_type' (kein Builtin-Shadow)
#   - systemctl --failed via grep -c statt wc -l
#   - Dependency-Check Sektion am Start
# ============================================================

# ─── Shelloptionen ──────────────────────────────────────────
# Kein -e: in Monitoring-Scripts sind Non-0-Exits erwartet
# -u: Fehler bei ungesetzten Variablen
# pipefail: Pipe-Fehler nicht verschlucken → wird lokal behandelt

set -uo pipefail

# ─── Farben & Symbole ────────────────────────────────────────
RED='\033[1;31m'
YEL='\033[1;33m'
GRN='\033[1;32m'
CYN='\033[1;36m'
BLU='\033[1;34m'
MAG='\033[1;35m'
WHT='\033[1;37m'
DIM='\033[2m'
RST='\033[0m'
BOLD='\033[1m'

OK="  ${GRN}✔${RST}"
WARN="  ${YEL}⚠${RST}"
CRIT="  ${RED}✖${RST}"
INFO="  ${CYN}→${RST}"

# ─── Temperaturschwellen (°C) ────────────────────────────────
CPU_WARN=75
CPU_CRIT=90
GPU_WARN=80
GPU_CRIT=95
MB_WARN=50
MB_CRIT=65

# ─── Prozess-Schwellen ───────────────────────────────────────
ZOMBIE_WARN=1
BLOCKED_WARN=3
# Load-Average Warnschwelle — empfohlen: Anzahl logischer Kerne
LOAD_WARN=${LOAD_WARN:-$(nproc 2>/dev/null || echo 4)}

# ════════════════════════════════════════════════════════════
# HILFSFUNKTIONEN
# ════════════════════════════════════════════════════════════

hr() {
    local char="${1:-─}"
    local line="" i
    for ((i=0; i<72; i++)); do line+="$char"; done
    printf "${DIM}%s${RST}\n" "$line"
}

section() {
    echo
    hr "═"
    printf "  ${BOLD}${BLU}%-68s${RST}\n" "$1"
    hr "─"
}

field() {
    printf "  ${DIM}%-28s${RST} ${WHT}%s${RST}\n" "$1" "$2"
}

# Gibt eine farbige Temperaturzeile aus
# Verwendung: temp_status "Label" "65.0" WARN_THRESH CRIT_THRESH
temp_status() {
    local label="$1"
    local temp_raw="$2"
    local warn="$3"
    local crit="$4"

    # Milligrad → Grad (lm_sensors liefert manchmal millidegrees)
    if [[ "$temp_raw" =~ ^[0-9]{4,}$ ]]; then
        temp_raw=$(awk "BEGIN {printf \"%.1f\", $temp_raw/1000}")
    fi

    # Sicheres Runden auf Integer
    local temp_int=0
    temp_int=$(printf "%.0f" "$temp_raw" 2>/dev/null) || temp_int=0

    if   (( temp_int >= crit )); then
        printf "${CRIT} ${RED}%-28s %s°C  ← KRITISCH!${RST}\n" "$label" "$temp_raw"
    elif (( temp_int >= warn )); then
        printf "${WARN} ${YEL}%-28s %s°C  ← Warnung${RST}\n"   "$label" "$temp_raw"
    else
        printf "${OK} ${GRN}%-28s %s°C${RST}\n"                "$label" "$temp_raw"
    fi
}

# Balken erzeugen — FIX: pct wird numerisch validiert
make_bar() {
    local pct_raw="${1:-0}"
    local bar_len="${2:-30}"
    # Nur Ziffern behalten (schützt vor '-', '%', etc.)
    local pct="${pct_raw//[^0-9]/}"
    pct="${pct:-0}"
    (( pct > 100 )) && pct=100

    local filled=$(( pct * bar_len / 100 ))
    local bar="" b
    for ((b=0; b<filled; b++));          do bar+="█"; done
    for ((b=filled; b<bar_len; b++));    do bar+="░"; done
    printf "%s" "$bar"
}

bar_color() {
    local pct_raw="${1:-0}"
    local warn="${2:-70}"
    local crit="${3:-90}"
    local pct="${pct_raw//[^0-9]/}"
    pct="${pct:-0}"
    if   (( pct >= crit )); then printf "%s" "$RED"
    elif (( pct >= warn )); then printf "%s" "$YEL"
    else                         printf "%s" "$GRN"; fi
}

cmd_exists() { command -v "$1" &>/dev/null; }

# ════════════════════════════════════════════════════════════
# DEPENDENCY CHECK
# ════════════════════════════════════════════════════════════

# Pakete: [Befehl]=Paketname
declare -A DEP_CORE=(
    [awk]="gawk"
    [grep]="grep"
    [ps]="procps-ng"
    [df]="coreutils"
    [ip]="iproute2"
    [uname]="coreutils"
    [sleep]="coreutils"
    [nproc]="coreutils"
)

declare -A DEP_OPTIONAL=(
    [sensors]="lm_sensors       → Temp CPU/MB"
    [dmidecode]="dmidecode       → Board/BIOS Info"
    [smartctl]="smartmontools    → Disk Temperaturen"
    [nvidia-smi]="nvidia-utils   → NVIDIA GPU"
    [rocm-smi]="rocm-smi-lib    → AMD GPU (ROCm)"
    [loginctl]="systemd          → Aktive Sessions"
    [systemctl]="systemd         → Systemd-Units"
)

dep_check() {
    local missing_core=() missing_opt=()

    for cmd in "${!DEP_CORE[@]}"; do
        cmd_exists "$cmd" || missing_core+=("${DEP_CORE[$cmd]}")
    done

    for cmd in "${!DEP_OPTIONAL[@]}"; do
        cmd_exists "$cmd" || missing_opt+=("$cmd|${DEP_OPTIONAL[$cmd]}")
    done

    if (( ${#missing_core[@]} > 0 )); then
        echo
        printf "${CRIT} ${RED}KRITISCH: Fehlende Kernpakete — Script kann nicht korrekt laufen!${RST}\n"
        for pkg in "${missing_core[@]}"; do
            printf "          ${RED}→ pacman -S %s${RST}\n" "$pkg"
        done
        echo
        read -r -t 10 -p "  Trotzdem fortfahren? [j/N] " REPLY || REPLY="n"
        [[ "${REPLY,,}" == "j" ]] || exit 1
    fi

    if (( ${#missing_opt[@]} > 0 )); then
        echo
        printf "${WARN} ${YEL}Optionale Tools fehlen (eingeschränkte Ausgabe):${RST}\n"
        for entry in "${missing_opt[@]}"; do
            local cmd="${entry%%|*}"
            local info="${entry##*|}"
            printf "  ${DIM}  %-14s → pacman -S %s${RST}\n" "$cmd" "$info"
        done
    fi
}

# ════════════════════════════════════════════════════════════
# HEADER
# ════════════════════════════════════════════════════════════
clear
echo
printf "${BOLD}${CYN}"
cat << 'EOF'
-----------------------------
   Bash MONITORING TOOL v2,1
-----------------------------
EOF
printf "${RST}"
printf "  ${DIM}Arch Linux  ·  %s${RST}\n" "$(date '+%A, %d. %B %Y  %H:%M:%S')"

# Dependency-Check läuft nach Header, vor den Sektionen
dep_check

# ════════════════════════════════════════════════════════════
# 1. KERNEL & SYSTEM
# ════════════════════════════════════════════════════════════
section "⬡  KERNEL & SYSTEM"

KERNEL=$(uname -r)
ARCH_VAL=$(uname -m)

# FIX: hostname via /proc (immer verfügbar), kein externer Befehl
HOSTNAME_VAL=$(cat /proc/sys/kernel/hostname 2>/dev/null || uname -n 2>/dev/null || echo "n/a")

UPTIME_VAL=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "n/a")

# FIX: pacman -Qu exits 1 wenn keine Updates → pipefail umgehen mit Subshell-Trick
PACMAN_UPDATES="n/a"
if cmd_exists pacman; then
    PACMAN_UPDATES=$(pacman -Qu 2>/dev/null | wc -l || true)
    PACMAN_UPDATES="${PACMAN_UPDATES:-0}"
fi

# FIX: 'who' ist optional (util-linux) → loginctl / /proc als Fallback
USERS_VAL=0
if cmd_exists loginctl; then
    USERS_VAL=$(loginctl list-sessions --no-legend 2>/dev/null | grep -c "." || true)
elif cmd_exists who; then
    USERS_VAL=$(who 2>/dev/null | wc -l || true)
else
    # Letzter Ausweg: Einträge in utmp zählen
    USERS_VAL=$(ls /proc/[0-9]*/loginuid 2>/dev/null | \
        xargs -r cat 2>/dev/null | sort -u | grep -vc "^4294967295$" || true)
fi

SHELL_VAL="${SHELL:-n/a}"

field "Kernel:"             "$KERNEL"
field "Architektur:"        "$ARCH_VAL"
field "Hostname:"           "$HOSTNAME_VAL"
field "Uptime:"             "$UPTIME_VAL"
field "Updates (Pacman):"   "${PACMAN_UPDATES} verfügbar"
field "Aktive Sessions:"    "${USERS_VAL} Benutzer"
field "Shell:"              "$SHELL_VAL"

# ════════════════════════════════════════════════════════════
# 2. MAINBOARD
# ════════════════════════════════════════════════════════════
section "⬡  MAINBOARD"

if cmd_exists dmidecode; then
    MB_VENDOR=$(dmidecode -s baseboard-manufacturer  2>/dev/null | head -1 || echo "n/a")
    MB_MODEL=$(dmidecode -s baseboard-product-name   2>/dev/null | head -1 || echo "n/a")
    MB_VERSION=$(dmidecode -s baseboard-version      2>/dev/null | head -1 || echo "n/a")
    BIOS_VENDOR=$(dmidecode -s bios-vendor           2>/dev/null | head -1 || echo "n/a")
    BIOS_VER=$(dmidecode -s bios-version             2>/dev/null | head -1 || echo "n/a")
    BIOS_DATE=$(dmidecode -s bios-release-date       2>/dev/null | head -1 || echo "n/a")
else
    # Fallback: sysfs — kein Root nötig, immer lesbar
    MB_VENDOR=$(cat /sys/class/dmi/id/board_vendor   2>/dev/null || echo "n/a")
    MB_MODEL=$(cat /sys/class/dmi/id/board_name      2>/dev/null || echo "n/a")
    MB_VERSION=$(cat /sys/class/dmi/id/board_version 2>/dev/null || echo "n/a")
    BIOS_VENDOR=$(cat /sys/class/dmi/id/bios_vendor  2>/dev/null || echo "n/a")
    BIOS_VER=$(cat /sys/class/dmi/id/bios_version    2>/dev/null || echo "n/a")
    BIOS_DATE=$(cat /sys/class/dmi/id/bios_date      2>/dev/null || echo "n/a")
fi

field "Hersteller:"      "$MB_VENDOR"
field "Modell:"          "$MB_MODEL"
field "Version:"         "$MB_VERSION"
field "BIOS Hersteller:" "$BIOS_VENDOR"
field "BIOS Version:"    "$BIOS_VER"
field "BIOS Datum:"      "$BIOS_DATE"

echo
echo "  ${DIM}── Mainboard Temperaturen ──────────────────────────────${RST}"

if cmd_exists sensors; then
    # ACPI / IT87 / NCT / Nuvoton Chips
    MB_TEMPS=$(sensors 2>/dev/null \
        | grep -E "(SYSTIN|System Temp|MB Temp|Board|Temp1|Temp2|PCH)" \
        | head -6 || true)
    if [[ -n "$MB_TEMPS" ]]; then
        while IFS= read -r line; do
            label=$(echo "$line" | awk -F':' '{print $1}' | xargs)
            # FIX: grep -oP Pipe mit || true absichern
            temp=$(echo "$line" | grep -oP '[+-]?\d+\.\d+(?=°C)' | head -1 || true)
            [[ -z "$temp" ]] && continue
            temp_status "$label" "$temp" "$MB_WARN" "$MB_CRIT"
        done <<< "$MB_TEMPS"
    else
        printf "${INFO} Keine Mainboard-Sensor-Labels gefunden\n"
        printf "  ${DIM}  Tipp: sudo sensors-detect --auto  und dann  modprobe <chip>${RST}\n"
    fi
else
    printf "${WARN} lm_sensors fehlt  ${DIM}→ pacman -S lm_sensors${RST}\n"
fi

# ════════════════════════════════════════════════════════════
# 3. CPU
# ════════════════════════════════════════════════════════════
section "⬡  CENTRAL PROCESSING UNIT (CPU)"

CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs || echo "n/a")
CPU_CORES=$(nproc --all 2>/dev/null || grep -c "^processor" /proc/cpuinfo || echo "?")
CPU_THREADS=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "?")

# FIX: 'physical id' kann auf VMs / Single-Socket-AMD fehlen → Fallback 1
CPU_SOCKETS=$(grep "physical id" /proc/cpuinfo 2>/dev/null | sort -u | wc -l || true)
(( CPU_SOCKETS == 0 )) && CPU_SOCKETS=1

# FIX: Jede Freq-Quelle einzeln mit Fallback absichern
CPU_FREQ_MIN="n/a"
CPU_FREQ_MAX="n/a"
CPU_FREQ_CUR="n/a"

_f=/sys/devices/system/cpu/cpu0/cpufreq
if [[ -r "${_f}/cpuinfo_min_freq" ]]; then
    CPU_FREQ_MIN=$(awk '{printf "%.0f", $1/1000}' "${_f}/cpuinfo_min_freq" 2>/dev/null || echo "n/a")
fi
if [[ -r "${_f}/cpuinfo_max_freq" ]]; then
    CPU_FREQ_MAX=$(awk '{printf "%.0f", $1/1000}' "${_f}/cpuinfo_max_freq" 2>/dev/null || echo "n/a")
fi
# FIX: Fallback-Kette ohne fehleranfällige Pipe
if [[ -r "${_f}/scaling_cur_freq" ]]; then
    CPU_FREQ_CUR=$(awk '{printf "%.0f", $1/1000}' "${_f}/scaling_cur_freq" 2>/dev/null || echo "n/a")
elif grep -q "cpu MHz" /proc/cpuinfo 2>/dev/null; then
    CPU_FREQ_CUR=$(grep -m1 "cpu MHz" /proc/cpuinfo | cut -d: -f2 | xargs | awk '{printf "%.0f", $1}' || echo "n/a")
fi

CPU_GOV=$(cat "${_f}/scaling_governor" 2>/dev/null || echo "n/a")
CPU_CACHE=$(grep -m1 "cache size" /proc/cpuinfo | cut -d: -f2 | xargs 2>/dev/null || echo "n/a")

# FIX: grep -oE Pipe mit || true absichern
CPU_FLAGS=$(grep -m1 "^flags" /proc/cpuinfo \
    | grep -oE "(avx512[a-z]*|avx2|avx|sse4_2|sse4_1|aes|vmx|svm|rdrand)" \
    | sort -u | tr '\n' ' ' || true)
CPU_FLAGS="${CPU_FLAGS:-n/a}"

# FIX: LOAD_AVG aus /proc/loadavg — sicheres Parsen
read -r LOAD_1M LOAD_5M LOAD_15M _rest < /proc/loadavg 2>/dev/null || \
    { LOAD_1M="0.00"; LOAD_5M="0.00"; LOAD_15M="0.00"; }

field "Modell:"              "$CPU_MODEL"
field "Sockets / Kerne / Threads:" "${CPU_SOCKETS} / ${CPU_CORES} / ${CPU_THREADS}"
field "Frequenz aktuell:"    "${CPU_FREQ_CUR} MHz"
field "Frequenz min / max:"  "${CPU_FREQ_MIN} / ${CPU_FREQ_MAX} MHz"
field "Governor:"            "$CPU_GOV"
field "Cache (L2/L3):"       "$CPU_CACHE"
field "CPU-Features:"        "$CPU_FLAGS"
field "Load Average:"        "${LOAD_1M}  ${LOAD_5M}  ${LOAD_15M}  (1m / 5m / 15m)"

# FIX: LOAD_1M Guard — awk nur aufrufen wenn LOAD_1M eine Zahl ist
if [[ "$LOAD_1M" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    if awk "BEGIN {exit !($LOAD_1M >= $LOAD_WARN)}"; then
        printf "${WARN} ${YEL}Load Average (1m) ${LOAD_1M} ist erhöht!  (Schwelle: ${LOAD_WARN})${RST}\n"
    fi
fi

echo
echo "  ${DIM}── CPU Temperaturen ─────────────────────────────────────${RST}"

if cmd_exists sensors; then
    # Coretemp (Intel) / k10temp (AMD Tdie, Tccd*)
    CPU_TEMP_LINES=$(sensors 2>/dev/null \
        | grep -E "(Core [0-9]+|Tdie|Tccd[0-9]*|Tctl|Package id [0-9]+)" \
        | head -24 || true)

    if [[ -n "$CPU_TEMP_LINES" ]]; then
        while IFS= read -r line; do
            label=$(echo "$line" | awk -F':' '{print $1}' | xargs)
            temp=$(echo "$line" | grep -oP '[+-]?\d+\.\d+(?=°C)' | head -1 || true)
            [[ -z "$temp" ]] && continue
            temp_status "$label" "$temp" "$CPU_WARN" "$CPU_CRIT"
        done <<< "$CPU_TEMP_LINES"
    else
        # Fallback: thermal_zone (ACPI / x86_pkg_temp)
        _found_zone=0
        for zone in /sys/class/thermal/thermal_zone*/; do
            # FIX: 'zone_type' statt 'type' — shadowed nicht das Builtin
            zone_type=$(cat "${zone}type" 2>/dev/null || echo "")
            [[ "$zone_type" =~ ^(acpitz|x86_pkg_temp|cpu-thermal)$ ]] || continue
            raw=$(cat "${zone}temp" 2>/dev/null || continue)
            [[ "$raw" =~ ^[0-9]+$ ]] || continue
            temp=$(awk "BEGIN {printf \"%.1f\", $raw/1000}")
            temp_status "$zone_type" "$temp" "$CPU_WARN" "$CPU_CRIT"
            _found_zone=1
        done
        (( _found_zone == 0 )) && printf "${INFO} Keine CPU-Temperaturquelle gefunden\n"
    fi
else
    printf "${WARN} lm_sensors fehlt  ${DIM}→ pacman -S lm_sensors${RST}\n"
fi

echo
echo "  ${DIM}── CPU Auslastung pro Kern ──────────────────────────────${RST}"

# FIX: declare -A cpu0 cpu1 entfernt (waren ungenutzte tote Variablen)
# Sampling via /proc/stat: zwei Messungen mit 0.5s Abstand
mapfile -t _stat0 < <(grep "^cpu[0-9]" /proc/stat 2>/dev/null || true)
sleep 0.5
mapfile -t _stat1 < <(grep "^cpu[0-9]" /proc/stat 2>/dev/null || true)

for i in "${!_stat0[@]}"; do
    [[ -z "${_stat1[$i]+x}" ]] && continue   # Index existiert in stat1?
    read -ra f0 <<< "${_stat0[$i]}"
    read -ra f1 <<< "${_stat1[$i]}"
    [[ ${#f0[@]} -lt 8 || ${#f1[@]} -lt 8 ]] && continue

    local_name="${f0[0]}"
    idle0="${f0[4]}"
    total0=$(( f0[1]+f0[2]+f0[3]+f0[4]+f0[5]+f0[6]+f0[7] ))
    idle1="${f1[4]}"
    total1=$(( f1[1]+f1[2]+f1[3]+f1[4]+f1[5]+f1[6]+f1[7] ))
    d_idle=$(( idle1 - idle0 ))
    d_total=$(( total1 - total0 ))

    pct=0
    (( d_total > 0 )) && pct=$(( (d_total - d_idle) * 100 / d_total ))

    bar=$(make_bar "$pct" 30)
    color=$(bar_color "$pct" 60 90)
    printf "  ${DIM}%-6s${RST} [${color}%s${RST}] ${color}%3d%%${RST}\n" "$local_name" "$bar" "$pct"
done

echo
echo "  ${DIM}── RAM & Swap ───────────────────────────────────────────${RST}"

MEM_TOTAL=$(awk '/MemTotal/{print $2}'     /proc/meminfo 2>/dev/null || echo 1)
MEM_AVAIL=$(awk '/MemAvailable/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
MEM_USED=$(( MEM_TOTAL - MEM_AVAIL ))
MEM_USED_MB=$(( MEM_USED / 1024 ))
MEM_TOTAL_MB=$(( MEM_TOTAL / 1024 ))
MEM_PCT=$(( MEM_TOTAL > 0 ? MEM_USED * 100 / MEM_TOTAL : 0 ))

SWP_TOTAL=$(awk '/SwapTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
SWP_FREE=$(awk '/SwapFree/{print $2}'   /proc/meminfo 2>/dev/null || echo 0)
SWP_USED=$(( SWP_TOTAL - SWP_FREE ))
SWP_USED_MB=$(( SWP_USED / 1024 ))
SWP_TOTAL_MB=$(( SWP_TOTAL / 1024 ))

mc=$(bar_color "$MEM_PCT" 70 90)
printf "  ${DIM}%-6s${RST} [${mc}%s${RST}] ${mc}%d%%${RST}  ${DIM}%d / %d MiB${RST}\n" \
    "RAM" "$(make_bar "$MEM_PCT" 30)" "$MEM_PCT" "$MEM_USED_MB" "$MEM_TOTAL_MB"

if (( SWP_TOTAL_MB > 0 )); then
    SWP_PCT=$(( SWP_TOTAL > 0 ? SWP_USED * 100 / SWP_TOTAL : 0 ))
    sc=$(bar_color "$SWP_PCT" 50 80)
    printf "  ${DIM}%-6s${RST} [${sc}%s${RST}] ${sc}%d%%${RST}  ${DIM}%d / %d MiB${RST}\n" \
        "Swap" "$(make_bar "$SWP_PCT" 30)" "$SWP_PCT" "$SWP_USED_MB" "$SWP_TOTAL_MB"
else
    printf "  ${DIM}Swap:   nicht konfiguriert${RST}\n"
fi

# ════════════════════════════════════════════════════════════
# 4. GPU
# ════════════════════════════════════════════════════════════
section "⬡  GRAPHICS PROCESSING UNIT (GPU)"

GPU_FOUND=0

# ── NVIDIA (nvidia-smi) ──────────────────────────────────────
# FIX: GPU_FOUND erst nach Datenvalidierung setzen — binary-Existenz allein reicht nicht.
# nvidia-smi kann installiert sein ohne NVIDIA-GPU (verwaistes Paket), gibt dann leere
# Ausgabe. In diesem Fall darf der AMD-Zweig nicht blockiert werden.
if cmd_exists nvidia-smi; then
    _NV_FIELDS="name,driver_version,vbios_version,memory.total,memory.used,memory.free"
    _NV_FIELDS+=",utilization.gpu,utilization.memory,temperature.gpu"
    _NV_FIELDS+=",power.draw,power.limit,fan.speed"
    _NV_FIELDS+=",pcie.link.gen.current,pcie.link.width.current"
    _NV_FIELDS+=",clocks.current.graphics,clocks.current.memory"

    NV_DATA=$(nvidia-smi \
        --query-gpu="$_NV_FIELDS" \
        --format=csv,noheader,nounits 2>/dev/null || true)

    if [[ -n "$NV_DATA" ]]; then
        GPU_FOUND=1
        echo "  ${MAG}[NVIDIA]${RST}"
    else
        printf "${INFO} ${DIM}nvidia-smi vorhanden, aber keine NVIDIA-GPU erkannt — übersprungen${RST}\n"
    fi

    GPU_IDX=0
    while [[ -n "$NV_DATA" ]] && IFS=',' read -r gname drv vbios mem_t mem_u mem_f \
                          util_g util_m temp_g \
                          pwr_d pwr_l fan \
                          pcie_g pcie_w clk_g clk_m; do
        # xargs zum Trimmen von Leerzeichen (nvidia-smi paddet)
        gname=$(echo  "$gname"  | xargs)
        drv=$(echo    "$drv"    | xargs)
        vbios=$(echo  "$vbios"  | xargs)
        mem_t=$(echo  "$mem_t"  | xargs)
        mem_u=$(echo  "$mem_u"  | xargs)
        mem_f=$(echo  "$mem_f"  | xargs)
        util_g=$(echo "$util_g" | xargs)
        util_m=$(echo "$util_m" | xargs)
        temp_g=$(echo "$temp_g" | xargs)
        pwr_d=$(echo  "$pwr_d"  | xargs)
        pwr_l=$(echo  "$pwr_l"  | xargs)
        fan=$(echo    "$fan"    | xargs)
        pcie_g=$(echo "$pcie_g" | xargs)
        pcie_w=$(echo "$pcie_w" | xargs)
        clk_g=$(echo  "$clk_g"  | xargs)
        clk_m=$(echo  "$clk_m"  | xargs)

        field "GPU #${GPU_IDX} Modell:"    "$gname"
        field "Treiber:"                   "$drv"
        field "VBIOS:"                     "$vbios"
        field "VRAM Gesamt:"               "${mem_t} MiB"
        field "VRAM Belegt / Frei:"        "${mem_u} / ${mem_f} MiB"
        field "GPU Auslastung:"            "${util_g} %"
        field "Speicher Auslastung:"       "${util_m} %"
        field "PCIe Gen / Breite:"         "Gen ${pcie_g} × ${pcie_w}"
        field "Takt GPU / VRAM:"           "${clk_g} / ${clk_m} MHz"
        field "Leistungsaufnahme:"         "${pwr_d} / ${pwr_l} W"
        field "Lüfter:"                    "${fan} %"
        echo
        echo "  ${DIM}── GPU #${GPU_IDX} Temperatur ─────────────────────────────────${RST}"
        temp_status "GPU #${GPU_IDX}" "$temp_g" "$GPU_WARN" "$GPU_CRIT"
        echo
        GPU_IDX=$(( GPU_IDX + 1 ))
    done <<< "$NV_DATA"
fi

# ── AMD ROCm ─────────────────────────────────────────────────
# FIX: Kein GPU_FOUND-Guard — AMD läuft unabhängig von NVIDIA-Ergebnis.
# So werden auch Hybrid-Systeme (z.B. Intel iGPU + AMD dGPU) korrekt erkannt.
if cmd_exists rocm-smi; then
    # Erst prüfen ob rocm-smi wirklich eine AMD-GPU sieht (nicht nur installiert ist)
    _amd_gpu_count=$(rocm-smi --showid 2>/dev/null | grep -c "GPU\[" || true)
    if [[ "${_amd_gpu_count:-0}" -gt 0 ]]; then
        GPU_FOUND=1
        echo "  ${RED}[AMD – ROCm]${RST}"
        AMD_DATA=$(rocm-smi --showid --showtemp --showmeminfo vram \
                            --showuse --showpower --showclocks 2>/dev/null || true)
        if [[ -n "$AMD_DATA" ]]; then
            echo "$AMD_DATA" | head -40 | while IFS= read -r line; do
                printf "  %s\n" "$line"
            done
            AMD_TEMP=$(rocm-smi --showtemp 2>/dev/null \
                | grep -oP '\d+\.\d+' | head -1 || true)
            if [[ -n "$AMD_TEMP" ]]; then
                echo
                echo "  ${DIM}── GPU Temperatur (ROCm) ────────────────────────────────${RST}"
                temp_status "AMD GPU Edge" "$AMD_TEMP" "$GPU_WARN" "$GPU_CRIT"
            fi
        fi
    else
        printf "${INFO} ${DIM}rocm-smi vorhanden, aber keine AMD-GPU erkannt — übersprungen${RST}\n"
    fi
fi

# ── Fallback: hwmon sysfs (AMD/Intel ohne ROCm / nvidia-smi) ─
if [[ $GPU_FOUND -eq 0 ]]; then
    for hwmon in /sys/class/hwmon/hwmon*/; do
        [[ -d "$hwmon" ]] || continue
        hwname=$(cat "${hwmon}name" 2>/dev/null || echo "")
        [[ "$hwname" =~ ^(amdgpu|radeon|i915|nouveau)$ ]] || continue
        GPU_FOUND=1
        echo "  ${YEL}[${hwname^^} – sysfs Fallback]${RST}"
        field "hwmon Pfad:" "$hwmon"

        # Temperaturen
        _shown_gpu_header=0
        for tempfile in "${hwmon}"temp*_input; do
            [[ -f "$tempfile" ]] || continue
            label_file="${tempfile/_input/_label}"
            temp_label=$(cat "$label_file" 2>/dev/null || basename "$tempfile" _input)
            raw=$(cat "$tempfile" 2>/dev/null || continue)
            [[ "$raw" =~ ^[0-9]+$ ]] || continue
            temp=$(awk "BEGIN {printf \"%.1f\", $raw/1000}")
            if (( _shown_gpu_header == 0 )); then
                echo
                echo "  ${DIM}── GPU Temperatur ───────────────────────────────────────${RST}"
                _shown_gpu_header=1
            fi
            temp_status "$temp_label" "$temp" "$GPU_WARN" "$GPU_CRIT"
        done

        # Takt
        for freq_file in "${hwmon}"freq1_input; do
            [[ -f "$freq_file" ]] || continue
            freq=$(awk '{printf "%.0f", $1/1000000}' "$freq_file" 2>/dev/null || echo "n/a")
            field "Aktueller GPU-Takt:" "${freq} MHz"
        done

        # VRAM (amdgpu/radeon)
        for card in /sys/class/drm/card[0-9]*/; do
            vt_file="${card}device/mem_info_vram_total"
            vu_file="${card}device/mem_info_vram_used"
            [[ -r "$vt_file" && -r "$vu_file" ]] || continue
            vt=$(awk '{printf "%.0f", $1/1048576}' "$vt_file" 2>/dev/null || echo "?")
            vu=$(awk '{printf "%.0f", $1/1048576}' "$vu_file" 2>/dev/null || echo "?")
            field "VRAM Gesamt / Belegt:" "${vt} MiB / ${vu} MiB"
            break
        done
        break
    done
fi

if (( GPU_FOUND == 0 )); then
    printf "${INFO} Kein unterstütztes GPU-Tool oder -Gerät gefunden\n"
    printf "  ${DIM}  NVIDIA → pacman -S nvidia-utils${RST}\n"
    printf "  ${DIM}  AMD    → pacman -S rocm-smi-lib${RST}\n"
fi

# ════════════════════════════════════════════════════════════
# 5. STORAGE
# ════════════════════════════════════════════════════════════
section "⬡  STORAGE"

echo "  ${DIM}── Disk Nutzung ─────────────────────────────────────────${RST}"

# FIX: -x statt --exclude-type (kürzere Syntax, breiter kompatibel)
#      pct_str wird numerisch validiert in make_bar / bar_color
df -h -x tmpfs -x devtmpfs -x squashfs -x overlay \
   --output=target,pcent,size,used,avail 2>/dev/null \
   | tail -n +2 \
   | while IFS= read -r line; do
    mountpoint=$(echo "$line" | awk '{print $1}')
    pct_str=$(echo "$line"    | awk '{print $2}' | tr -d '%')
    size=$(echo "$line"       | awk '{print $3}')
    used_d=$(echo "$line"     | awk '{print $4}')
    avail=$(echo "$line"      | awk '{print $5}')

    # FIX: Numerisch validieren — '-' oder leere Strings ergeben 0
    pct_clean="${pct_str//[^0-9]/}"
    pct="${pct_clean:-0}"

    color=$(bar_color "$pct" 75 90)
    printf "  ${DIM}%-22s${RST} [${color}%s${RST}] ${color}%3d%%${RST}  ${DIM}%s / %s  (frei: %s)${RST}\n" \
        "$mountpoint" "$(make_bar "$pct" 25)" "$pct" "$used_d" "$size" "$avail"
done

echo
echo "  ${DIM}── Disk Temperaturen (SMART) ────────────────────────────${RST}"

if cmd_exists smartctl; then
    # FIX: NVMe-Glob auf [0-9]* erweitert → erkennt nvme0..nvme9, nvme10, …
    _disk_found=0
    for dev in /dev/sd[a-z] /dev/sd[a-z][a-z] /dev/nvme[0-9]* /dev/vd[a-z]; do
        # Nur Block-Devices, Partitionen überspringen
        [[ -b "$dev" ]] || continue
        [[ "$dev" =~ [0-9]$ && ! "$dev" =~ nvme ]] && continue  # sd-Partitionen skippen

        _disk_found=1
        if [[ "$dev" =~ nvme ]]; then
            nvme_temp=$(smartctl -A "$dev" 2>/dev/null \
                | grep -i "^Temperature" | awk '{print $2}' | head -1 || true)
            [[ -n "$nvme_temp" && "$nvme_temp" =~ ^[0-9]+$ ]] || continue
            temp_status "NVMe ${dev##*/}" "$nvme_temp" 65 80
        else
            hdd_temp=$(smartctl -A "$dev" 2>/dev/null \
                | grep -i "Temperature_Celsius" | awk '{print $10}' | head -1 || true)
            [[ -n "$hdd_temp" && "$hdd_temp" =~ ^[0-9]+$ ]] || continue
            temp_status "${dev##*/}" "$hdd_temp" 50 60
        fi
    done
    (( _disk_found == 0 )) && printf "${INFO} Keine Block-Devices gefunden\n"
else
    printf "${INFO} smartctl fehlt  ${DIM}→ pacman -S smartmontools${RST}\n"
fi

# ════════════════════════════════════════════════════════════
# 6. NETZWERK
# ════════════════════════════════════════════════════════════
section "⬡  NETZWERK"

for iface in /sys/class/net/*/; do
    name=$(basename "$iface")
    [[ "$name" == "lo" ]] && continue

    state=$(cat "${iface}operstate" 2>/dev/null || echo "unknown")
    rx=$(cat "${iface}statistics/rx_bytes" 2>/dev/null || echo 0)
    tx=$(cat "${iface}statistics/tx_bytes" 2>/dev/null || echo 0)
    rx_mb=$(awk "BEGIN {printf \"%.1f\", $rx/1048576}")
    tx_mb=$(awk "BEGIN {printf \"%.1f\", $tx/1048576}")
    speed=$(cat "${iface}speed" 2>/dev/null || echo "?")

    # FIX: grep -oP Pipe mit || true absichern (no match → exit 1 mit pipefail)
    ip_addr=$(ip -4 addr show "$name" 2>/dev/null \
        | grep -oP '(?<=inet )\S+' | head -1 || true)
    ip6_addr=$(ip -6 addr show "$name" 2>/dev/null \
        | grep -oP '(?<=inet6 )\S+' | grep -v "^fe80" | head -1 || true)
    mac=$(cat "${iface}address" 2>/dev/null || echo "—")

    if [[ "$state" == "up" ]]; then
        state_col="${GRN}UP${RST}"
    else
        state_col="${DIM}down${RST}"
    fi

    printf "  ${BOLD}${WHT}%-16s${RST}  Status: %b   MAC: ${DIM}%s${RST}\n" \
        "$name" "$state_col" "$mac"
    printf "  ${DIM}%16s${RST}  IPv4:   ${CYN}%-22s${RST}  Speed: %s Mb/s\n" \
        "" "${ip_addr:-—}" "$speed"
    [[ -n "$ip6_addr" ]] && \
    printf "  ${DIM}%16s${RST}  IPv6:   ${CYN}%s${RST}\n" "" "$ip6_addr"
    printf "  ${DIM}%16s${RST}  RX: %-12s MiB   TX: %s MiB\n" \
        "" "$rx_mb" "$tx_mb"
    echo
done

# ════════════════════════════════════════════════════════════
# 7. PROZESSE & SYSTEMWARNUNGEN
# ════════════════════════════════════════════════════════════
section "⬡  PROZESSE & SYSTEMWARNUNGEN"

# FIX: --no-headers (dokumentierte Schreibweise in procps-ng)
TOTAL_PROC=$(ps aux --no-headers 2>/dev/null | wc -l || true)
ZOMBIE_PROC=$(ps aux --no-headers 2>/dev/null | awk '$8=="Z"' | wc -l || true)
BLOCKED_PROC=$(ps aux --no-headers 2>/dev/null | awk '$8=="D"' | wc -l || true)
RUNNING_PROC=$(ps aux --no-headers 2>/dev/null | awk '$8=="R"' | wc -l || true)
SLEEP_PROC=$(ps aux --no-headers 2>/dev/null | awk '$8=="S" || $8=="s"' | wc -l || true)

field "Prozesse gesamt:"   "${TOTAL_PROC:-0}"
field "Laufend (R):"       "${RUNNING_PROC:-0}"
field "Schlafend (S):"     "${SLEEP_PROC:-0}"
field "Blockiert D-State:" "${BLOCKED_PROC:-0}"
field "Zombie (Z):"        "${ZOMBIE_PROC:-0}"

echo

# Zombie-Warnung
if (( ${ZOMBIE_PROC:-0} >= ZOMBIE_WARN )); then
    printf "${WARN} ${YEL}%d Zombie-Prozess(e) gefunden!${RST}\n" "$ZOMBIE_PROC"
    ps aux --no-headers 2>/dev/null \
        | awk '$8=="Z" {printf "      PID %-8s PPID %-8s CMD: %s\n", $2, $3, $11}' \
        | head -5
    echo
fi

# D-State (hängende I/O) Warnung
if (( ${BLOCKED_PROC:-0} >= BLOCKED_WARN )); then
    printf "${CRIT} ${RED}%d Prozesse im D-State – mögliches I/O-Problem!${RST}\n" "$BLOCKED_PROC"
    ps aux --no-headers 2>/dev/null \
        | awk '$8=="D" {printf "      PID %-8s USER %-10s CMD: %s\n", $2, $1, $11}' \
        | head -5
    echo
fi

echo "  ${DIM}── Top 10 Prozesse (CPU) ────────────────────────────────${RST}"
printf "  ${DIM}%-8s %-12s %6s %6s  %s${RST}\n" "PID" "USER" "%CPU" "%MEM" "COMMAND"

ps aux --sort=-%cpu --no-headers 2>/dev/null | head -10 \
| while read -r _user pid cpu mem _vsz _rss _tty _stat _start _time cmd _rest; do
    # FIX: _rest mit Unterstrich — Konvention für ungenutzte Variablen
    c_col=$(bar_color "${cpu%%.*}" 50 80)
    printf "  %-8s %-12s ${c_col}%6s${RST} %6s  %s\n" \
        "$pid" "$_user" "${cpu}%" "${mem}%" "$cmd"
done

echo
echo "  ${DIM}── Top 5 Prozesse (RAM) ─────────────────────────────────${RST}"
printf "  ${DIM}%-8s %-12s %6s %6s  %s${RST}\n" "PID" "USER" "%CPU" "%MEM" "COMMAND"

ps aux --sort=-%mem --no-headers 2>/dev/null | head -5 \
| while read -r _user pid cpu mem _vsz _rss _tty _stat _start _time cmd _rest; do
    m_col=$(bar_color "${mem%%.*}" 15 30)
    printf "  %-8s %-12s %6s ${m_col}%6s${RST}  %s\n" \
        "$pid" "$_user" "${cpu}%" "${mem}%" "$cmd"
done

# Fehlgeschlagene Systemd-Units
if cmd_exists systemctl; then
    echo
    echo "  ${DIM}── Fehlgeschlagene Systemd-Units ───────────────────────${RST}"

    # FIX: grep -c statt wc -l → zählt keine Leerzeilen
    FAILED_UNITS=$(systemctl --failed --no-legend 2>/dev/null \
        | grep -c "." || true)

    if (( ${FAILED_UNITS:-0} > 0 )); then
        printf "${CRIT} ${RED}%d fehlgeschlagene Unit(s):${RST}\n" "$FAILED_UNITS"
        systemctl --failed --no-legend 2>/dev/null | head -10 \
            | while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                printf "      ${RED}%s${RST}\n" "$line"
            done
    else
        printf "${OK} ${GRN}Alle Systemd-Units laufen fehlerfrei${RST}\n"
    fi

    # Journal-Fehler der letzten Stunde
    if cmd_exists journalctl; then
        echo
        echo "  ${DIM}── Kritische Journald-Einträge (letzte Stunde) ─────────${RST}"
        JOURNAL_CRIT=$(journalctl -p err -S "1 hour ago" --no-pager -q 2>/dev/null \
            | grep -v "^$" | wc -l || true)
        if (( ${JOURNAL_CRIT:-0} > 0 )); then
            printf "${WARN} ${YEL}%d Fehler-Einträge im Journal:${RST}\n" "$JOURNAL_CRIT"
            journalctl -p err -S "1 hour ago" --no-pager -q 2>/dev/null \
                | tail -5 | while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    printf "  ${DIM}%s${RST}\n" "$line"
                done
        else
            printf "${OK} ${GRN}Keine Fehler im Journal (letzte Stunde)${RST}\n"
        fi
    fi
fi

# ─── FOOTER ─────────────────────────────────────────────────
echo
hr "═"
printf "  ${DIM}Generiert: %s  ·  Host: %s  ·  Kernel: %s${RST}\n" \
    "$(date '+%d.%m.%Y %H:%M:%S')" "$HOSTNAME_VAL" "$KERNEL"
hr "═"
echo
