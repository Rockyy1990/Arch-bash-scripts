#!/usr/bin/env bash
# ============================================================
#  PipeWire Audio Konfigurations-Tool für Arch Linux
#  Version 2.0 – Vollständig überarbeitet & erweitert
#  Getestet mit: PipeWire >= 1.0, WirePlumber >= 0.5
# ============================================================

# ── Farben ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[1;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Konfigurationspfade ──────────────────────────────────────
PW_CONF_DIR="$HOME/.config/pipewire"
PW_CONF_D="$PW_CONF_DIR/pipewire.conf.d"
CLIENT_CONF_D="$PW_CONF_DIR/client.conf.d"
WP_CONF_DIR="$HOME/.config/wireplumber"
WP_CONF_D="$WP_CONF_DIR/wireplumber.conf.d"

CLOCK_CONF="$PW_CONF_D/90-clock.conf"
QUANTUM_CONF="$PW_CONF_D/91-quantum.conf"
RESAMPLE_CONF="$CLIENT_CONF_D/90-resample.conf"
WP_ALSA_CONF="$WP_CONF_D/90-alsa-format.conf"
WP_BT_CONF="$WP_CONF_D/51-bluetooth.conf"
WP_SETTINGS_CONF="$WP_CONF_D/80-settings.conf"
AEC_CONF="$PW_CONF_D/99-echo-cancel.conf"

# ── Hilfsfunktionen ──────────────────────────────────────────
# BUGFIX: \$1 → "$1" in allen Echo-Funktionen (druckte wörtlich "$1")
print_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${BOLD}     🎵  PipeWire Audio Konfigurations-Tool  v2.0     ${RESET}${BLUE}║${RESET}"
    echo -e "${BLUE}║         Arch Linux  •  PipeWire / WirePlumber        ║${RESET}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_section() {
    echo -e "${CYAN}──────────────────────────────────────────────────────${RESET}"
    echo -e "${BOLD}  $1${RESET}"
    echo -e "${CYAN}──────────────────────────────────────────────────────${RESET}"
}

success() { echo -e "${GREEN}  ✔  $1${RESET}"; }
warn()    { echo -e "${YELLOW}  ⚠  $1${RESET}"; }
error()   { echo -e "${RED}  ✘  $1${RESET}"; }
info()    { echo -e "${CYAN}  ℹ  $1${RESET}"; }

press_enter() {
    echo ""
    read -rp "  [Enter] zum Fortfahren..."
}

ensure_dirs() {
    mkdir -p "$PW_CONF_D" "$CLIENT_CONF_D" "$WP_CONF_D"
}

# BUGFIX: check_pipewire war aufgerufen (Zeile 618 original) aber nie definiert
check_pipewire() {
    if ! command -v pw-cli &>/dev/null; then
        error "PipeWire (pw-cli) nicht gefunden. Bitte 'pipewire' installieren."
        exit 1
    fi
    if ! command -v wpctl &>/dev/null; then
        warn "wpctl nicht gefunden. Einige Funktionen eingeschränkt."
    fi
    if ! command -v pw-metadata &>/dev/null; then
        warn "pw-metadata nicht gefunden. Live-Einstellungen nicht verfügbar."
    fi
    if ! systemctl --user is-active --quiet pipewire.service 2>/dev/null; then
        warn "PipeWire-Dienst ist nicht aktiv. Starte ihn mit: systemctl --user start pipewire"
    fi
}

# BUGFIX: pipewire-pulse.service ergänzt; WirePlumber korrekt sequenziell neu starten
restart_pipewire() {
    echo ""
    info "Stoppe WirePlumber..."
    systemctl --user stop wireplumber.service 2>/dev/null || true
    info "Starte PipeWire-Dienste neu..."
    systemctl --user restart pipewire.service 2>/dev/null || true
    systemctl --user restart pipewire-pulse.service pipewire-pulse.socket 2>/dev/null || true
    sleep 1
    info "Starte WirePlumber..."
    systemctl --user start wireplumber.service 2>/dev/null || true
    sleep 1
    if systemctl --user is-active --quiet pipewire.service; then
        success "PipeWire erfolgreich neu gestartet."
    else
        error "PipeWire-Neustart fehlgeschlagen. Bitte manuell prüfen."
    fi
}

ask_restart() {
    echo ""
    read -rp "  PipeWire jetzt neu starten? (empfohlen) [j/N]: " ans
    [[ "$ans" =~ ^[jJyY]$ ]] && restart_pipewire
}

# ── 1. Abtastrate (Sample Rate) ──────────────────────────────
menu_samplerate() {
    while true; do
        print_header
        print_section "1. Abtastrate (Sample Rate)"
        echo ""
        info "Standard: 48000 Hz  |  Aktuell:"
        if [[ -f "$CLOCK_CONF" ]]; then
            grep "default.clock.rate" "$CLOCK_CONF" 2>/dev/null | grep -v "allowed" | head -1 \
                | sed 's/^/     /' || warn "Nicht konfiguriert"
        else
            warn "Keine benutzerdefinierte Konfiguration (Standard: 48000 Hz)"
        fi
        echo ""
        echo "  [1] 44100 Hz  (CD-Qualität)"
        echo "  [2] 48000 Hz  (Standard / DVD)"
        echo "  [3] 88200 Hz  (Hi-Res)"
        echo "  [4] 96000 Hz  (Hi-Res)"
        echo "  [5] 176400 Hz (Hi-Res)"
        echo "  [6] 192000 Hz (Hi-Res)"
        echo "  [7] 352800 Hz (DSD64-Äquivalent)"
        echo "  [8] 384000 Hz (Hi-Res Maximum)"
        echo "  [9] Eigene Rate eingeben"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        local rate=""
        case "$choice" in
            1) rate=44100 ;;
            2) rate=48000 ;;
            3) rate=88200 ;;
            4) rate=96000 ;;
            5) rate=176400 ;;
            6) rate=192000 ;;
            7) rate=352800 ;;
            8) rate=384000 ;;
            9)
                read -rp "  Eigene Rate (8000–768000 Hz): " rate
                if ! [[ "$rate" =~ ^[0-9]+$ ]] || (( rate < 8000 || rate > 768000 )); then
                    error "Ungültige Eingabe (8000–768000 Hz)."; press_enter; continue
                fi
                ;;
            0) return ;;
            *) warn "Ungültige Auswahl."; press_enter; continue ;;
        esac

        ensure_dirs
        # Bestehende allowed-rates übernehmen
        local allowed=""
        [[ -f "$CLOCK_CONF" ]] && allowed=$(grep "default.clock.allowed-rates" "$CLOCK_CONF" 2>/dev/null | head -1)
        [[ -z "$allowed" ]] && allowed="    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]"

        cat > "$CLOCK_CONF" <<EOF
# PipeWire Clock / Sample Rate Konfiguration
# Generiert von pipewire_config.sh
context.properties = {
    default.clock.rate          = $rate
$allowed
}
EOF
        success "Abtastrate auf ${rate} Hz gesetzt → $CLOCK_CONF"
        ask_restart
        press_enter
    done
}

# ── 2. Erlaubte Abtastraten (Allowed Rates) ──────────────────
# BUGFIX: while true ergänzt (kein Loop bei Fehleingabe im Original)
menu_allowed_rates() {
    while true; do
        print_header
        print_section "2. Erlaubte Abtastraten (Allowed Rates)"
        echo ""
        info "Definiert, auf welche Raten PipeWire dynamisch wechseln darf."
        info "Aktuell:"
        if [[ -f "$CLOCK_CONF" ]]; then
            grep "allowed-rates" "$CLOCK_CONF" 2>/dev/null | sed 's/^/     /' || warn "Nicht konfiguriert"
        else
            warn "Keine Konfiguration gefunden"
        fi
        echo ""
        echo "  [1] Standard        (44100 48000)"
        echo "  [2] Erweitert       (44100 48000 88200 96000)"
        echo "  [3] Vollständig     (44100 48000 88200 96000 176400 192000)"
        echo "  [4] Nur CD-Familie  (44100 88200 176400 352800)"
        echo "  [5] Nur DVD-Familie (48000 96000 192000 384000)"
        echo "  [6] Hi-Res komplett (44100 48000 88200 96000 176400 192000 352800 384000)"
        echo "  [7] Eigene Liste eingeben"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        local rates=""
        case "$choice" in
            1) rates="44100 48000" ;;
            2) rates="44100 48000 88200 96000" ;;
            3) rates="44100 48000 88200 96000 176400 192000" ;;
            4) rates="44100 88200 176400 352800" ;;
            5) rates="48000 96000 192000 384000" ;;
            6) rates="44100 48000 88200 96000 176400 192000 352800 384000" ;;
            7)
                read -rp "  Raten (Leerzeichen-getrennt, z.B. 44100 48000 96000): " rates
                if [[ -z "$rates" ]]; then
                    error "Keine Eingabe."; press_enter; continue
                fi
                ;;
            0) return ;;
            *) warn "Ungültige Auswahl."; press_enter; continue ;;
        esac

        ensure_dirs
        local current_rate
        current_rate=$(grep "default\.clock\.rate " "$CLOCK_CONF" 2>/dev/null \
            | grep -v "allowed" | head -1 | grep -oP '\d+' | head -1)
        [[ -z "$current_rate" ]] && current_rate=48000

        cat > "$CLOCK_CONF" <<EOF
# PipeWire Clock / Sample Rate Konfiguration
# Generiert von pipewire_config.sh
context.properties = {
    default.clock.rate          = $current_rate
    default.clock.allowed-rates = [ $rates ]
}
EOF
        success "Erlaubte Raten gesetzt: [ $rates ]"
        ask_restart
        press_enter
    done
}

# ── 3. Resampling-Qualität ────────────────────────────────────
menu_resample_quality() {
    while true; do
        print_header
        print_section "3. Resampling-Qualität"
        echo ""
        info "Aktuell:"
        if [[ -f "$RESAMPLE_CONF" ]]; then
            grep "resample.quality" "$RESAMPLE_CONF" 2>/dev/null | sed 's/^/     /' || warn "Nicht konfiguriert"
        else
            warn "Keine Konfiguration (Standard: 4)"
        fi
        echo ""
        echo "  Skala: 0 (niedrigste) → 14 (höchste Qualität / mehr CPU)"
        echo ""
        echo "  [1] Qualität  0  – Minimal    (sehr geringe CPU-Last)"
        echo "  [2] Qualität  4  – Standard   (empfohlen für Desktop)"
        echo "  [3] Qualität  6  – Ausgewogen"
        echo "  [4] Qualität 10  – Hoch       (empfohlen für Audiophile)"
        echo "  [5] Qualität 14  – Maximum    (höchste CPU-Last)"
        echo "  [6] Eigenen Wert eingeben (0–14)"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        local quality=""
        case "$choice" in
            1) quality=0 ;;
            2) quality=4 ;;
            3) quality=6 ;;
            4) quality=10 ;;
            5) quality=14 ;;
            6)
                read -rp "  Qualitätsstufe (0–14): " quality
                if ! [[ "$quality" =~ ^[0-9]+$ ]] || (( quality > 14 )); then
                    error "Ungültige Eingabe (0–14)."; press_enter; continue
                fi
                ;;
            0) return ;;
            *) warn "Ungültige Auswahl."; press_enter; continue ;;
        esac

        ensure_dirs
        cat > "$RESAMPLE_CONF" <<EOF
# PipeWire Resampling-Qualität
# Generiert von pipewire_config.sh  |  Skala: 0 (niedrig) bis 14 (höchste Qualität)
stream.properties = {
    resample.quality = $quality
}
EOF
        success "Resampling-Qualität auf $quality gesetzt → $RESAMPLE_CONF"
        ask_restart
        press_enter
    done
}

# ── 4. Bit-Tiefe (Bit Depth) ──────────────────────────────────
# BUGFIX: while true ergänzt; UUOC (cat | grep) → grep direkt auf Datei
menu_bitdepth() {
    while true; do
        print_header
        print_section "4. Bit-Tiefe (Bit Depth) via WirePlumber"
        echo ""
        info "Setzt das Audio-Format für ALSA-Ausgabegeräte."
        info "Aktuell:"
        if [[ -f "$WP_ALSA_CONF" ]]; then
            grep "audio.format" "$WP_ALSA_CONF" | sed 's/^/     /' || warn "Nicht konfiguriert"
        else
            warn "Keine Konfiguration (Standard: S32LE intern)"
        fi
        echo ""
        echo "  [1] S16LE   – 16-Bit         (CD-Standard, maximale Kompatibilität)"
        echo "  [2] S24LE   – 24-Bit         (Hi-Res, für die meisten DACs empfohlen)"
        echo "  [3] S24_3LE – 24-Bit gepackt (manche DACs, z.B. ESS Sabre)"
        echo "  [4] S32LE   – 32-Bit Integer (maximale interne Präzision)"
        echo "  [5] F32LE   – 32-Bit Float   (für DSP / Filter-Chains)"
        echo "  [6] F64LE   – 64-Bit Float   (maximale Rechengenauigkeit)"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        local fmt=""
        case "$choice" in
            1) fmt="S16LE" ;;
            2) fmt="S24LE" ;;
            3) fmt="S24_3LE" ;;
            4) fmt="S32LE" ;;
            5) fmt="F32LE" ;;
            6) fmt="F64LE" ;;
            0) return ;;
            *) warn "Ungültige Auswahl."; press_enter; continue ;;
        esac

        ensure_dirs
        cat > "$WP_ALSA_CONF" <<EOF
# WirePlumber ALSA Audio-Format (Bit-Tiefe)
# Generiert von pipewire_config.sh  |  WirePlumber >= 0.5 kompatibel
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~alsa_output.*" } ]
    actions = {
      update-props = {
        audio.format = "$fmt"
      }
    }
  }
]
EOF
        success "Bit-Tiefe auf $fmt gesetzt → $WP_ALSA_CONF"
        warn "Gilt für alle ALSA-Ausgabegeräte. Für spezifische Geräte manuell anpassen."
        ask_restart
        press_enter
    done
}

# ── 5. Puffergröße / Latenz (Quantum) ────────────────────────
# BUGFIX: awk \$4/\$6 → $4/$6 (in single-quoted awk-Programm kein Escape nötig/möglich)
# NEU: Option [p] für persistente Quantum-Konfiguration
menu_latency() {
    while true; do
        print_header
        print_section "5. Puffergröße / Latenz (Quantum)"
        echo ""
        info "Kleinere Werte = geringere Latenz, aber mehr CPU-Last & Xrun-Risiko"
        info "Größere Werte = stabiler, aber höhere Latenz"
        echo ""
        info "Live-Einstellungen (pw-metadata):"
        pw-metadata -n settings 2>/dev/null | grep -E "clock\.(force-)?(quantum|rate)" | \
            awk -F"'" '{print "     " $4 " = " $6}' || warn "pw-metadata nicht verfügbar"
        echo ""
        echo "  [1]   32 Samples  (~0.7 ms  @ 48kHz) – Pro Audio / extrem niedrige Latenz"
        echo "  [2]   64 Samples  (~1.3 ms  @ 48kHz) – Sehr niedrige Latenz"
        echo "  [3]  128 Samples  (~2.7 ms  @ 48kHz) – Niedrige Latenz"
        echo "  [4]  256 Samples  (~5.3 ms  @ 48kHz) – Ausgewogen (Standard, empfohlen)"
        echo "  [5]  512 Samples  (~10.7 ms @ 48kHz) – Stabil"
        echo "  [6] 1024 Samples  (~21.3 ms @ 48kHz) – Sehr stabil"
        echo "  [7] 2048 Samples  (~42.7 ms @ 48kHz) – Maximum Stabilität"
        echo "  [8] Eigenen Wert eingeben"
        echo "  [9] Erzwungene Werte zurücksetzen (Standardwerte)"
        echo "  [p] Quantum dauerhaft in Konfigurationsdatei speichern"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        local quantum=""
        case "$choice" in
            1) quantum=32 ;;
            2) quantum=64 ;;
            3) quantum=128 ;;
            4) quantum=256 ;;
            5) quantum=512 ;;
            6) quantum=1024 ;;
            7) quantum=2048 ;;
            8)
                read -rp "  Quantum (idealerweise Potenz von 2, z.B. 512): " quantum
                if ! [[ "$quantum" =~ ^[0-9]+$ ]]; then
                    error "Ungültige Eingabe."; press_enter; continue
                fi
                ;;
            9)
                pw-metadata -n settings 0 clock.force-quantum 0 2>/dev/null || true
                pw-metadata -n settings 0 clock.force-rate    0 2>/dev/null || true
                success "Erzwungene Werte zurückgesetzt (Standardwerte aktiv)."
                press_enter; continue
                ;;
            p|P) menu_quantum_persistent; continue ;;
            0) return ;;
            *) warn "Ungültige Auswahl."; press_enter; continue ;;
        esac

        # BUGFIX: direktes if statt [[ $? -eq 0 ]] anti-pattern
        if pw-metadata -n settings 0 clock.force-quantum "$quantum" 2>/dev/null; then
            success "Quantum live auf $quantum Samples gesetzt (kein Neustart nötig)."
        else
            error "Fehler beim Setzen. Ist PipeWire aktiv?"
        fi
        press_enter
    done
}

# ── 5b. Quantum dauerhaft speichern (NEU) ────────────────────
menu_quantum_persistent() {
    print_header
    print_section "5b. Quantum dauerhaft konfigurieren"
    echo ""
    info "Diese Werte werden beim PipeWire-Start geladen (persistent nach Reboot)."
    info "Aktuell ($QUANTUM_CONF):"
    if [[ -f "$QUANTUM_CONF" ]]; then
        grep -v "^#" "$QUANTUM_CONF" | grep -v "^$" | sed 's/^/     /'
    else
        warn "Keine persistente Quantum-Konfiguration vorhanden"
    fi
    echo ""
    read -rp "  Standard-Quantum  [256]:  " q
    read -rp "  Minimum-Quantum   [32]:   " qmin
    read -rp "  Maximum-Quantum   [8192]: " qmax
    [[ -z "$q"    ]] && q=256
    [[ -z "$qmin" ]] && qmin=32
    [[ -z "$qmax" ]] && qmax=8192

    if ! [[ "$q" =~ ^[0-9]+$ && "$qmin" =~ ^[0-9]+$ && "$qmax" =~ ^[0-9]+$ ]]; then
        error "Ungültige Eingabe."; press_enter; return
    fi
    if (( qmin > q || q > qmax )); then
        error "Ungültige Reihenfolge: min ($qmin) ≤ quantum ($q) ≤ max ($qmax) erforderlich."
        press_enter; return
    fi

    ensure_dirs
    cat > "$QUANTUM_CONF" <<EOF
# PipeWire Quantum (Puffergröße) – persistente Konfiguration
# Generiert von pipewire_config.sh
context.properties = {
    default.clock.quantum     = $q
    default.clock.min-quantum = $qmin
    default.clock.max-quantum = $qmax
}
EOF
    success "Persistente Quantum-Konfiguration gespeichert → $QUANTUM_CONF"
    ask_restart
    press_enter
}

# ── 6. Live Sample Rate erzwingen ─────────────────────────────
# BUGFIX: awk \$4/\$6 → $4/$6; direktes if statt [[ $? -eq 0 ]]
# NEU: 352800 und 384000 Hz ergänzt
menu_force_rate() {
    print_header
    print_section "6. Abtastrate live erzwingen (temporär)"
    echo ""
    info "Setzt die Rate sofort ohne Neustart (geht nach Reboot verloren)."
    info "Aktuell:"
    pw-metadata -n settings 2>/dev/null | grep "clock.force-rate" | \
        awk -F"'" '{print "     " $4 " = " $6}' || warn "Nicht gesetzt"
    echo ""
    echo "  [1]  44100 Hz    [2]  48000 Hz    [3]  88200 Hz"
    echo "  [4]  96000 Hz    [5] 176400 Hz    [6] 192000 Hz"
    echo "  [7] 352800 Hz    [8] 384000 Hz"
    echo "  [9] Eigene Rate  [10] Zurücksetzen (Standard)"
    echo "  [0] Zurück"
    echo ""
    read -rp "  Auswahl: " choice

    local rate=""
    case "$choice" in
        1)  rate=44100  ;;
        2)  rate=48000  ;;
        3)  rate=88200  ;;
        4)  rate=96000  ;;
        5)  rate=176400 ;;
        6)  rate=192000 ;;
        7)  rate=352800 ;;
        8)  rate=384000 ;;
        9)  read -rp "  Rate eingeben: " rate ;;
        10)
            pw-metadata -n settings 0 clock.force-rate 0 2>/dev/null || true
            success "Rate zurückgesetzt (Standard aktiv)."; press_enter; return
            ;;
        0) return ;;
        *) warn "Ungültige Auswahl."; press_enter; return ;;
    esac

    if pw-metadata -n settings 0 clock.force-rate "$rate" 2>/dev/null; then
        success "Rate live auf ${rate} Hz gesetzt."
    else
        error "Fehler. Ist PipeWire aktiv?"
    fi
    press_enter
}

# ── 7. Status & Diagnose ──────────────────────────────────────
# BUGFIX: awk \$4/\$6 → $4/$6; UUOC entfernt
# NEU: WirePlumber-Version, Xrun-Zähler, pw-top Schnellübersicht
menu_status() {
    print_header
    print_section "7. Status & Diagnose"
    echo ""

    echo -e "${BOLD}  ── PipeWire Dienste ──${RESET}"
    for svc in pipewire pipewire-pulse wireplumber; do
        if systemctl --user is-active --quiet "${svc}.service" 2>/dev/null; then
            echo -e "  ${GREEN}●${RESET} ${svc}: aktiv"
        else
            echo -e "  ${RED}●${RESET} ${svc}: inaktiv"
        fi
    done

    echo ""
    echo -e "${BOLD}  ── Versionen ──${RESET}"
    pw-cli --version 2>/dev/null | head -1 | sed 's/^/  PipeWire: /'    || warn "pw-cli nicht gefunden"
    wpctl --version 2>/dev/null  | head -1 | sed 's/^/  WirePlumber: /' || warn "wpctl nicht gefunden"

    echo ""
    echo -e "${BOLD}  ── Live Einstellungen (pw-metadata) ──${RESET}"
    pw-metadata -n settings 2>/dev/null | grep -E "clock\." | \
        awk -F"'" '{printf "  %-42s = %s\n", $4, $6}' || warn "Keine Daten verfügbar"

    echo ""
    echo -e "${BOLD}  ── Xrun-Zähler ──${RESET}"
    pw-metadata -n settings 2>/dev/null | grep "xrun" | \
        awk -F"'" '{printf "  %-42s = %s\n", $4, $6}' || info "Keine Xrun-Daten (gut!)"

    echo ""
    echo -e "${BOLD}  ── Audio Geräte (wpctl status) ──${RESET}"
    wpctl status 2>/dev/null | grep -A 40 "Audio" | head -45 | sed 's/^/  /' \
        || warn "wpctl nicht verfügbar"

    echo ""
    echo -e "${BOLD}  ── Aktive Konfigurationsdateien ──${RESET}"
    for f in "$CLOCK_CONF" "$QUANTUM_CONF" "$RESAMPLE_CONF" "$WP_ALSA_CONF" \
             "$WP_BT_CONF" "$WP_SETTINGS_CONF" "$AEC_CONF"; do
        if [[ -f "$f" ]]; then
            echo -e "  ${GREEN}✔${RESET} $f"
            # BUGFIX: UUOC entfernt (cat "$f" | grep → grep direkt)
            grep -v "^#" "$f" | grep -v "^$" | sed 's/^/      /'
        else
            echo -e "  ${YELLOW}–${RESET} $f (nicht vorhanden)"
        fi
    done

    echo ""
    echo -e "${BOLD}  ── Verbundene Nodes (pw-cli) ──${RESET}"
    pw-cli list-objects Node 2>/dev/null | grep -E "node\.name|media\.class" \
        | paste - - | awk '{print "  " $0}' | head -20 || warn "Keine Node-Daten"

    press_enter
}

# ── 8. Bluetooth Audio Qualität ───────────────────────────────
# BUGFIX: while true ergänzt; monitor.bluez.properties (veraltet) → monitor.bluez.rules (WP >= 0.5)
menu_bluetooth() {
    while true; do
        print_header
        print_section "8. Bluetooth Audio Qualität (WirePlumber >= 0.5)"
        echo ""
        info "Aktuell ($WP_BT_CONF):"
        if [[ -f "$WP_BT_CONF" ]]; then
            grep -v "^#" "$WP_BT_CONF" | grep -v "^$" | sed 's/^/     /'
        else
            warn "Keine benutzerdefinierte BT-Konfiguration"
        fi
        echo ""
        echo "  LDAC Qualitätsmodus:"
        echo "  [1] auto – Adaptiv         (Standard, empfohlen)"
        echo "  [2] hq   – High Quality    (990/909 kbps)"
        echo "  [3] sq   – Standard Quality (660/606 kbps)"
        echo "  [4] mq   – Mobile Quality  (330/303 kbps)"
        echo ""
        echo "  BT Sample Rate:"
        echo "  [5] 44100 Hz   [6] 48000 Hz   [7] 96000 Hz"
        echo ""
        echo "  Weitere Optionen:"
        echo "  [8] Auto-Wechsel zu Headset-Profil deaktivieren"
        echo "  [9] A2DP Dual-Channel-Modus erzwingen"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        ensure_dirs

        # Bestehende Werte lesen
        local ldac_quality bt_rate
        ldac_quality=$(grep "ldac.quality" "$WP_BT_CONF" 2>/dev/null \
            | grep -oP '"[^"]+"' | head -1 | tr -d '"')
        bt_rate=$(grep "bluez5.default.rate\|default\.rate" "$WP_BT_CONF" 2>/dev/null \
            | grep -oP '\d+' | head -1)
        [[ -z "$ldac_quality" ]] && ldac_quality="auto"
        [[ -z "$bt_rate"      ]] && bt_rate=48000

        case "$choice" in
            1) ldac_quality="auto" ;;
            2) ldac_quality="hq"   ;;
            3) ldac_quality="sq"   ;;
            4) ldac_quality="mq"   ;;
            5) bt_rate=44100 ;;
            6) bt_rate=48000 ;;
            7) bt_rate=96000 ;;
            8)
                cat >> "$WP_BT_CONF" <<'EOF'

# Auto-Wechsel zu Headset-Profil deaktivieren (bleibt bei A2DP)
wireplumber.settings = {
    bluetooth.autoswitch-to-headset-profile = false
}
EOF
                success "Auto-Headset-Profilwechsel deaktiviert."
                ask_restart; press_enter; continue
                ;;
            9)
                cat >> "$WP_BT_CONF" <<'EOF'

# A2DP Dual-Channel-Modus erzwingen
monitor.bluez.rules = [
  {
    matches = [ { device.name = "~bluez_card.*" } ]
    actions = {
      update-props = {
        bluez5.a2dp.ldac.quality  = "hq"
        bluez5.a2dp-source.volume = 127
      }
    }
  }
]
EOF
                success "A2DP Dual-Channel-Modus konfiguriert."
                ask_restart; press_enter; continue
                ;;
            0) return ;;
            *) warn "Ungültige Auswahl."; press_enter; continue ;;
        esac

        # WirePlumber >= 0.5: monitor.bluez.rules (nicht mehr monitor.bluez.properties)
        cat > "$WP_BT_CONF" <<EOF
# WirePlumber Bluetooth Audio Konfiguration
# Generiert von pipewire_config.sh  |  WirePlumber >= 0.5
monitor.bluez.rules = [
  {
    matches = [ { device.name = "~bluez_card.*" } ]
    actions = {
      update-props = {
        bluez5.a2dp.ldac.quality = "$ldac_quality"
        bluez5.default.rate      = $bt_rate
      }
    }
  }
]
EOF
        success "Bluetooth: LDAC=$ldac_quality, Rate=${bt_rate} Hz → $WP_BT_CONF"
        ask_restart
        press_enter
    done
}

# ── 9. Echo- & Rauschunterdrückung (AEC) (NEU) ───────────────
menu_aec() {
    while true; do
        print_header
        print_section "9. Echo- & Rauschunterdrückung (AEC / NR)"
        echo ""
        info "Verwendet PipeWires eingebautes echo-cancel Modul (WebRTC-basiert)."
        info "Paket: pipewire-audio (ggf. webrtc-audio-processing installieren)"
        echo ""
        if [[ -f "$AEC_CONF" ]]; then
            echo -e "  ${GREEN}● AEC ist aktuell AKTIV${RESET} ($AEC_CONF)"
        else
            echo -e "  ${YELLOW}● AEC ist aktuell INAKTIV${RESET}"
        fi
        echo ""
        echo "  [1] AEC aktivieren             (Standardeinstellungen)"
        echo "  [2] AEC + Automatic Gain Control"
        echo "  [3] AEC + Rauschunterdrückung"
        echo "  [4] AEC vollständig            (AEC + AGC + NR + Hochpassfilter + VAD)"
        echo "  [5] AEC deaktivieren           (Konfigurationsdatei löschen)"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        case "$choice" in
            5)
                rm -f "$AEC_CONF"
                success "AEC-Konfiguration entfernt."
                ask_restart; press_enter; continue
                ;;
            0) return ;;
        esac

        ensure_dirs

        local gain_ctrl="false"
        local noise_sup="false"
        local noise_lvl=1
        local hpf="false"
        local vad="false"

        case "$choice" in
            1) ;;
            2) gain_ctrl="true" ;;
            3) noise_sup="true"; noise_lvl=2 ;;
            4) gain_ctrl="true"; noise_sup="true"; noise_lvl=2; hpf="true"; vad="true" ;;
            *) warn "Ungültige Auswahl."; press_enter; continue ;;
        esac

        cat > "$AEC_CONF" <<EOF
# PipeWire Echo-Cancellation / Rauschunterdrückung
# Generiert von pipewire_config.sh
context.modules = [
  { name = libpipewire-module-echo-cancel
    args = {
      node.latency = 1024/48000
      aec.args = {
        webrtc.gain_control            = $gain_ctrl
        webrtc.noise_suppression       = $noise_sup
        webrtc.noise_suppression_level = $noise_lvl
        webrtc.high_pass_filter        = $hpf
        webrtc.voice_detection         = $vad
      }
    }
  }
]
EOF
        success "AEC-Konfiguration gespeichert → $AEC_CONF"
        warn "Ein neues virtuelles Mikrofon 'Echo-Cancel Source' wird erstellt."
        warn "Dieses als Eingabegerät in Anwendungen auswählen."
        ask_restart
        press_enter
    done
}

# ── 10. Standard-Audiogerät setzen (NEU) ─────────────────────
menu_default_device() {
    while true; do
        print_header
        print_section "10. Standard-Audiogerät setzen (wpctl)"
        echo ""
        info "Verfügbare Audio-Geräte:"
        echo ""
        wpctl status 2>/dev/null | head -50 | sed 's/^/  /' || warn "wpctl nicht verfügbar"
        echo ""
        echo "  [1] Standard-Ausgabe setzen  (Sink)   – ID aus obiger Liste"
        echo "  [2] Standard-Eingabe setzen  (Source) – ID aus obiger Liste"
        echo "  [3] Lautstärke setzen        (Standard-Ausgabe)"
        echo "  [4] Lautstärke in %          (z.B. 80% statt 0.8)"
        echo "  [5] Stummschalten umschalten (Toggle Mute)"
        echo "  [6] Geräteprofil wechseln"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        case "$choice" in
            1)
                read -rp "  Geräte-ID eingeben: " dev_id
                if wpctl set-default "$dev_id" 2>/dev/null; then
                    success "Standard-Ausgabe auf ID $dev_id gesetzt."
                else
                    error "Fehler. Bitte korrekte ID aus wpctl status verwenden."
                fi
                ;;
            2)
                read -rp "  Geräte-ID eingeben: " dev_id
                if wpctl set-default "$dev_id" 2>/dev/null; then
                    success "Standard-Eingabe auf ID $dev_id gesetzt."
                else
                    error "Fehler. Bitte korrekte ID aus wpctl status verwenden."
                fi
                ;;
            3)
                read -rp "  Lautstärke (0.0–1.5, z.B. 1.0 = 100%): " vol
                if wpctl set-volume @DEFAULT_AUDIO_SINK@ "$vol" 2>/dev/null; then
                    success "Lautstärke auf $vol gesetzt."
                else
                    error "Fehler beim Setzen der Lautstärke."
                fi
                ;;
            4)
                read -rp "  Lautstärke in Prozent (z.B. 80): " pct
                if [[ "$pct" =~ ^[0-9]+$ ]]; then
                    local vol; vol=$(echo "scale=2; $pct/100" | bc 2>/dev/null || echo "0.$pct")
                    if wpctl set-volume @DEFAULT_AUDIO_SINK@ "${pct}%" 2>/dev/null; then
                        success "Lautstärke auf ${pct}% gesetzt."
                    else
                        error "Fehler beim Setzen der Lautstärke."
                    fi
                else
                    error "Ungültige Eingabe."
                fi
                ;;
            5)
                if wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle 2>/dev/null; then
                    success "Stummschaltung umgeschaltet."
                else
                    error "Fehler beim Umschalten."
                fi
                ;;
            6)
                read -rp "  Geräte-ID: " dev_id
                info "Verfügbare Profile für Gerät $dev_id:"
                wpctl inspect "$dev_id" 2>/dev/null | grep "profile" | sed 's/^/  /' || true
                read -rp "  Profil-Name eingeben: " prof
                if wpctl set-profile "$dev_id" "$prof" 2>/dev/null; then
                    success "Profil '$prof' gesetzt."
                else
                    error "Fehler beim Setzen des Profils."
                fi
                ;;
            0) return ;;
            *) warn "Ungültige Auswahl." ;;
        esac
        press_enter
    done
}

# ── 11. Pro-Audio / Gaming Schnellprofile (NEU) ───────────────
menu_pro_audio() {
    print_header
    print_section "11. Pro-Audio / Gaming Schnellprofile"
    echo ""
    info "Wendet vordefinierte Einstellungssätze auf alle Konfigurationsdateien an."
    echo ""
    echo "  [1] 🎛️  Pro-Audio Low-Latency"
    echo "      64 Samples | 48kHz | Qualität 10 | S32LE"
    echo ""
    echo "  [2] 🎮  Gaming"
    echo "      256 Samples | 48kHz | Qualität 4 | S16LE"
    echo ""
    echo "  [3] 🎵  Hi-Fi Audiophile"
    echo "      512 Samples | 96kHz | Qualität 14 | S32LE"
    echo ""
    echo "  [4] 💻  Desktop Standard"
    echo "      256 Samples | 48kHz | Qualität 4 | S16LE"
    echo ""
    echo "  [5] 🎙️  Podcast / Streaming"
    echo "      1024 Samples | 48kHz | Qualität 6 | S32LE + AEC"
    echo ""
    echo "  [6] 🎧  Balanced Hi-Res"
    echo "      512 Samples | 192kHz | Qualität 10 | S32LE"
    echo ""
    echo "  [0] Zurück"
    echo ""
    read -rp "  Auswahl: " choice

    local profile_name quantum rate quality fmt with_aec=0
    case "$choice" in
        1) profile_name="Pro-Audio Low-Latency"; quantum=64;   rate=48000;  quality=10; fmt="S32LE" ;;
        2) profile_name="Gaming";                quantum=256;  rate=48000;  quality=4;  fmt="S16LE" ;;
        3) profile_name="Hi-Fi Audiophile";      quantum=512;  rate=96000;  quality=14; fmt="S32LE" ;;
        4) profile_name="Desktop Standard";      quantum=256;  rate=48000;  quality=4;  fmt="S16LE" ;;
        5) profile_name="Podcast/Streaming";     quantum=1024; rate=48000;  quality=6;  fmt="S32LE"; with_aec=1 ;;
        6) profile_name="Balanced Hi-Res";       quantum=512;  rate=192000; quality=10; fmt="S32LE" ;;
        0) return ;;
        *) warn "Ungültige Auswahl."; press_enter; return ;;
    esac

    echo ""
    info "Profil '${profile_name}' wird angewendet..."
    ensure_dirs

    cat > "$CLOCK_CONF" <<EOF
# PipeWire Clock – Profil: $profile_name
# Generiert von pipewire_config.sh
context.properties = {
    default.clock.rate          = $rate
    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]
}
EOF

    cat > "$QUANTUM_CONF" <<EOF
# PipeWire Quantum – Profil: $profile_name
# Generiert von pipewire_config.sh
context.properties = {
    default.clock.quantum     = $quantum
    default.clock.min-quantum = 32
    default.clock.max-quantum = 8192
}
EOF

    cat > "$RESAMPLE_CONF" <<EOF
# PipeWire Resampling – Profil: $profile_name
# Generiert von pipewire_config.sh
stream.properties = {
    resample.quality = $quality
}
EOF

    cat > "$WP_ALSA_CONF" <<EOF
# WirePlumber ALSA Format – Profil: $profile_name
# Generiert von pipewire_config.sh
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~alsa_output.*" } ]
    actions = {
      update-props = {
        audio.format = "$fmt"
        audio.rate   = $rate
      }
    }
  }
]
EOF

    if (( with_aec )); then
        cat > "$AEC_CONF" <<'EOF'
# PipeWire AEC – Podcast/Streaming Profil
context.modules = [
  { name = libpipewire-module-echo-cancel
    args = {
      node.latency = 1024/48000
      aec.args = {
        webrtc.gain_control      = true
        webrtc.noise_suppression = true
        webrtc.high_pass_filter  = true
        webrtc.voice_detection   = true
      }
    }
  }
]
EOF
        success "AEC für Podcast-Profil aktiviert."
    fi

    echo ""
    success "Profil '${profile_name}' erfolgreich angewendet!"
    info "  Quantum: $quantum Samples | Rate: ${rate} Hz | Qualität: $quality | Format: $fmt"
    ask_restart
    press_enter
}

# ── 12. WirePlumber Erweiterte Einstellungen (NEU) ────────────
menu_wireplumber() {
    while true; do
        print_header
        print_section "12. WirePlumber Erweiterte Einstellungen"
        echo ""
        info "Aktuell ($WP_SETTINGS_CONF):"
        if [[ -f "$WP_SETTINGS_CONF" ]]; then
            grep -v "^#" "$WP_SETTINGS_CONF" | grep -v "^$" | sed 's/^/     /'
        else
            warn "Keine benutzerdefinierten WirePlumber-Einstellungen"
        fi
        echo ""
        echo "  [1] ALSA-Gerät: Abtastrate für spezifisches Gerät setzen"
        echo "  [2] ALSA-Gerät: Puffergröße setzen (period-size)"
        echo "  [3] ALSA-Gerät: Headroom konfigurieren"
        echo "  [4] Automatische Profil-Auswahl deaktivieren"
        echo "  [5] Lautstärke & Standardziel persistieren"
        echo "  [6] ALSA-Rategrenzen lockern (alle erlaubten Raten)"
        echo "  [7] Node-Suspend deaktivieren (immer aktiv halten)"
        echo "  [8] WP-Einstellungsdatei anzeigen"
        echo "  [9] WP-Einstellungen zurücksetzen"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        ensure_dirs

        case "$choice" in
            1)
                echo ""
                info "Verfügbare ALSA-Geräte (wpctl):"
                wpctl status 2>/dev/null | grep -i "alsa" | head -10 | sed 's/^/  /' || true
                echo ""
                read -rp "  Gerätemuster (z.B. alsa_output.pci-0000_00_1f.3): " dev_pattern
                read -rp "  Ziel-Rate (z.B. 96000): " target_rate
                if ! [[ "$target_rate" =~ ^[0-9]+$ ]]; then
                    error "Ungültige Rate."; press_enter; continue
                fi
                cat >> "$WP_SETTINGS_CONF" <<EOF

# ALSA-Geräterate – generiert von pipewire_config.sh
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~${dev_pattern}.*" } ]
    actions = {
      update-props = {
        audio.rate = $target_rate
      }
    }
  }
]
EOF
                success "Geräterate-Regel für '${dev_pattern}' → ${target_rate} Hz gespeichert."
                ;;
            2)
                echo ""
                read -rp "  Gerätemuster: " dev_pattern
                read -rp "  Period-Size in Samples (z.B. 256): " buf_size
                cat >> "$WP_SETTINGS_CONF" <<EOF

# ALSA-Gerät Puffergröße – generiert von pipewire_config.sh
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~${dev_pattern}.*" } ]
    actions = {
      update-props = {
        api.alsa.period-size = $buf_size
      }
    }
  }
]
EOF
                success "ALSA Period-Size für '${dev_pattern}' auf $buf_size gesetzt."
                ;;
            3)
                echo ""
                read -rp "  Gerätemuster: " dev_pattern
                read -rp "  Headroom in Samples (0 = minimal, 8 = sicherer): " headroom
                cat >> "$WP_SETTINGS_CONF" <<EOF

# ALSA-Gerät Headroom – generiert von pipewire_config.sh
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~${dev_pattern}.*" } ]
    actions = {
      update-props = {
        api.alsa.headroom = $headroom
      }
    }
  }
]
EOF
                success "Headroom für '${dev_pattern}' auf $headroom Samples gesetzt."
                ;;
            4)
                cat >> "$WP_SETTINGS_CONF" <<'EOF'

# Automatische Profil-Auswahl deaktivieren
wireplumber.settings = {
    device.profile.auto-select = false
}
EOF
                success "Auto-Profilauswahl deaktiviert."
                ;;
            5)
                cat >> "$WP_SETTINGS_CONF" <<'EOF'

# Lautstärke und Standardziele beim Neustart wiederherstellen
wireplumber.settings = {
    restore-props               = true
    restore-default-targets     = true
}
EOF
                success "Persistente Lautstärke / Standardziele aktiviert."
                ;;
            6)
                cat >> "$WP_SETTINGS_CONF" <<'EOF'

# ALSA-Rategrenzen lockern (alle Standardraten erlauben)
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~alsa_output.*" } ]
    actions = {
      update-props = {
        audio.allowed-rates = [ 44100 48000 88200 96000 176400 192000 352800 384000 ]
      }
    }
  }
]
EOF
                success "ALSA-Rategrenzen gelockert."
                ;;
            7)
                cat >> "$WP_SETTINGS_CONF" <<'EOF'

# Nodes immer aktiv halten (kein automatisches Suspend nach Inaktivität)
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~alsa.*" } ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
EOF
                success "Node-Suspend deaktiviert (Geräte bleiben aktiv)."
                ;;
            8)
                echo ""
                if [[ -f "$WP_SETTINGS_CONF" ]]; then
                    info "Inhalt von $WP_SETTINGS_CONF:"
                    cat "$WP_SETTINGS_CONF" | sed 's/^/  /'
                else
                    warn "Datei nicht vorhanden."
                fi
                press_enter; continue
                ;;
            9)
                read -rp "  WirePlumber-Einstellungen wirklich löschen? [j/N]: " ans
                if [[ "$ans" =~ ^[jJyY]$ ]]; then
                    rm -f "$WP_SETTINGS_CONF"
                    success "WirePlumber-Einstellungen zurückgesetzt."
                fi
                ;;
            0) return ;;
            *) warn "Ungültige Auswahl."; press_enter; continue ;;
        esac

        ask_restart
        press_enter
    done
}

# ── 13. Konfiguration sichern / wiederherstellen ──────────────
# BUGFIX: Backup-Restore kopierte blind in alle Dirs → jetzt korrekte Unterverzeichnisse
menu_backup() {
    while true; do
        print_header
        print_section "13. Konfiguration sichern / wiederherstellen"
        echo ""
        local BACKUP_DIR="$HOME/.config/pipewire-tuner-backup"
        echo "  [1] Aktuelle Konfiguration sichern  → $BACKUP_DIR"
        echo "  [2] Backup wiederherstellen"
        echo "  [3] Alle Tuner-Einstellungen zurücksetzen"
        echo "  [4] Backups auflisten / anzeigen"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        case "$choice" in
            1)
                local ts; ts=$(date +%Y%m%d_%H%M%S)
                local bdir="$BACKUP_DIR/$ts"
                mkdir -p "$bdir/pipewire.conf.d" "$bdir/client.conf.d" "$bdir/wireplumber.conf.d"
                local count=0
                for f in "$CLOCK_CONF" "$QUANTUM_CONF" "$AEC_CONF"; do
                    [[ -f "$f" ]] && cp "$f" "$bdir/pipewire.conf.d/" && info "Gesichert: $(basename "$f")" && ((count++)) || true
                done
                for f in "$RESAMPLE_CONF"; do
                    [[ -f "$f" ]] && cp "$f" "$bdir/client.conf.d/" && info "Gesichert: $(basename "$f")" && ((count++)) || true
                done
                for f in "$WP_ALSA_CONF" "$WP_BT_CONF" "$WP_SETTINGS_CONF"; do
                    [[ -f "$f" ]] && cp "$f" "$bdir/wireplumber.conf.d/" && info "Gesichert: $(basename "$f")" && ((count++)) || true
                done
                if (( count > 0 )); then
                    success "Backup ($count Datei(en)) gespeichert → $bdir"
                else
                    warn "Keine Konfigurationsdateien vorhanden – nichts gesichert."
                fi
                ;;
            2)
                if [[ ! -d "$BACKUP_DIR" ]]; then
                    warn "Kein Backup-Verzeichnis gefunden."; press_enter; continue
                fi
                local backups=()
                while IFS= read -r -d '' d; do
                    backups+=("$d")
                done < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
                if [[ ${#backups[@]} -eq 0 ]]; then
                    warn "Keine Backups vorhanden."; press_enter; continue
                fi
                echo ""
                info "Verfügbare Backups:"
                local i=1
                for b in "${backups[@]}"; do
                    local cnt; cnt=$(find "$b" -type f | wc -l)
                    echo "  [$i] $(basename "$b")  ($cnt Datei(en))"
                    ((i++))
                done
                echo ""
                read -rp "  Nummer wählen: " bnum
                if ! [[ "$bnum" =~ ^[0-9]+$ ]] || (( bnum < 1 || bnum > ${#backups[@]} )); then
                    error "Ungültige Auswahl."; press_enter; continue
                fi
                local selected="${backups[$((bnum-1))]}"
                ensure_dirs
                # BUGFIX: Dateien in korrekte Zielverzeichnisse kopieren
                [[ -d "$selected/pipewire.conf.d"   ]] && cp "$selected/pipewire.conf.d/"*   "$PW_CONF_D/"     2>/dev/null || true
                [[ -d "$selected/client.conf.d"     ]] && cp "$selected/client.conf.d/"*     "$CLIENT_CONF_D/" 2>/dev/null || true
                [[ -d "$selected/wireplumber.conf.d" ]] && cp "$selected/wireplumber.conf.d/"* "$WP_CONF_D/"   2>/dev/null || true
                success "Backup '$(basename "$selected")' wiederhergestellt."
                ask_restart
                ;;
            3)
                read -rp "  Wirklich alle Tuner-Konfigurationen löschen? [j/N]: " ans
                if [[ "$ans" =~ ^[jJyY]$ ]]; then
                    rm -f "$CLOCK_CONF" "$QUANTUM_CONF" "$RESAMPLE_CONF" \
                          "$WP_ALSA_CONF" "$WP_BT_CONF" "$WP_SETTINGS_CONF" "$AEC_CONF"
                    success "Alle Tuner-Einstellungen gelöscht. PipeWire-Standardwerte aktiv."
                    ask_restart
                fi
                ;;
            4)
                echo ""
                if [[ -d "$BACKUP_DIR" ]]; then
                    info "Backups in $BACKUP_DIR:"
                    while IFS= read -r bpath; do
                        local cnt; cnt=$(find "$bpath" -type f | wc -l)
                        echo -e "  ${CYAN}📦${RESET} $(basename "$bpath")  ($cnt Datei(en))"
                        find "$bpath" -type f | sed 's|.*/||' | sed 's/^/       /'
                    done < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
                else
                    warn "Noch keine Backups vorhanden."
                fi
                ;;
            0) return ;;
            *) warn "Ungültige Auswahl." ;;
        esac
        press_enter
    done
}

# ── Hauptmenü ─────────────────────────────────────────────────
main_menu() {
    while true; do
        print_header
        echo -e "  ${BOLD}Hauptmenü${RESET}"
        echo ""
        echo "  [1]  Abtastrate (Sample Rate) setzen"
        echo "  [2]  Erlaubte Abtastraten konfigurieren"
        echo "  [3]  Resampling-Qualität einstellen"
        echo "  [4]  Bit-Tiefe (Bit Depth) setzen"
        echo "  [5]  Puffergröße / Latenz (Quantum)"
        echo "  [6]  Abtastrate live erzwingen (temporär)"
        echo "  [7]  Status & Diagnose anzeigen"
        echo "  [8]  Bluetooth Audio Qualität"
        echo "  [9]  Echo- & Rauschunterdrückung (AEC)"
        echo " [10]  Standard-Audiogerät setzen"
        echo " [11]  Pro-Audio / Gaming Schnellprofile"
        echo " [12]  WirePlumber Erweiterte Einstellungen"
        echo " [13]  Konfiguration sichern / wiederherstellen"
        echo "  [r]  PipeWire neu starten"
        echo "  [0]  Beenden"
        echo ""
        echo -e "  ${CYAN}Konfigurationspfade:${RESET}"
        echo -e "  ${CYAN}  PipeWire:    $PW_CONF_D${RESET}"
        echo -e "  ${CYAN}  Client:      $CLIENT_CONF_D${RESET}"
        echo -e "  ${CYAN}  WirePlumber: $WP_CONF_D${RESET}"
        echo ""
        read -rp "  Auswahl: " choice

        case "$choice" in
            1)  menu_samplerate ;;
            2)  menu_allowed_rates ;;
            3)  menu_resample_quality ;;
            4)  menu_bitdepth ;;
            5)  menu_latency ;;
            6)  menu_force_rate ;;
            7)  menu_status ;;
            8)  menu_bluetooth ;;
            9)  menu_aec ;;
            10) menu_default_device ;;
            11) menu_pro_audio ;;
            12) menu_wireplumber ;;
            13) menu_backup ;;
            r|R) restart_pipewire; press_enter ;;
            0)
                echo -e "\n  ${GREEN}Auf Wiedersehen!${RESET}\n"
                exit 0
                ;;
            *)
                warn "Ungültige Auswahl."
                press_enter
                ;;
        esac
    done
}

# ── Einstiegspunkt ────────────────────────────────────────────
check_pipewire
main_menu
