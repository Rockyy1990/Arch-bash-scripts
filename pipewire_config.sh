#!/usr/bin/env bash
# ============================================================
#  PipeWire Audio Konfigurations-Tool für Arch Linux
#  Autor: PipeWire-Tuner Script
#  Getestet mit: PipeWire >= 0.3, WirePlumber
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
RESAMPLE_CONF="$CLIENT_CONF_D/90-resample.conf"
WP_ALSA_CONF="$WP_CONF_D/90-alsa-format.conf"

# ── Hilfsfunktionen ──────────────────────────────────────────
print_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${BOLD}       🎵  PipeWire Audio Konfigurations-Tool         ${RESET}${BLUE}║${RESET}"
    echo -e "${BLUE}║         Arch Linux  •  PipeWire / WirePlumber        ║${RESET}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_section() {
    echo -e "${CYAN}──────────────────────────────────────────────────────${RESET}"
    echo -e "${BOLD}  \$1${RESET}"
    echo -e "${CYAN}──────────────────────────────────────────────────────${RESET}"
}

success() { echo -e "${GREEN}  ✔  \$1${RESET}"; }
warn()    { echo -e "${YELLOW}  ⚠  \$1${RESET}"; }
error()   { echo -e "${RED}  ✘  \$1${RESET}"; }
info()    { echo -e "${CYAN}  ℹ  \$1${RESET}"; }

press_enter() {
    echo ""
    read -rp "  [Enter] zum Fortfahren..."
}

ensure_dirs() {
    mkdir -p "$PW_CONF_D" "$CLIENT_CONF_D" "$WP_CONF_D"
}

restart_pipewire() {
    echo ""
    info "Starte PipeWire neu..."
    systemctl --user restart pipewire.service pipewire-pulse.socket wireplumber.service 2>/dev/null
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
            grep "default.clock.rate" "$CLOCK_CONF" 2>/dev/null | head -1 | sed 's/^/     /'
        else
            warn "Keine benutzerdefinierte Konfiguration gefunden (Standard: 48000 Hz)"
        fi
        echo ""
        echo "  [1] 44100 Hz  (CD-Qualität)"
        echo "  [2] 48000 Hz  (Standard / DVD)"
        echo "  [3] 88200 Hz  (Hi-Res)"
        echo "  [4] 96000 Hz  (Hi-Res)"
        echo "  [5] 176400 Hz (Hi-Res)"
        echo "  [6] 192000 Hz (Hi-Res)"
        echo "  [7] Eigene Rate eingeben"
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
            7)
                read -rp "  Eigene Rate (z.B. 384000): " rate
                if ! [[ "$rate" =~ ^[0-9]+$ ]]; then
                    error "Ungültige Eingabe."; press_enter; continue
                fi
                ;;
            0) return ;;
            *) warn "Ungültige Auswahl."; press_enter; continue ;;
        esac

        ensure_dirs
        # Bestehende Datei lesen und clock.rate ersetzen oder neu schreiben
        local allowed
        allowed=$(grep "default.clock.allowed-rates" "$CLOCK_CONF" 2>/dev/null | head -1)
        [[ -z "$allowed" ]] && allowed="    default.clock.allowed-rates = [ 44100 48000 88200 96000 176400 192000 ]"

        cat > "$CLOCK_CONF" <<EOF
# PipeWire Clock / Sample Rate Konfiguration
# Generiert von pipewire-tuner.sh
context.properties = {
    default.clock.rate = $rate
$allowed
}
EOF
        success "Abtastrate auf ${rate} Hz gesetzt → $CLOCK_CONF"
        ask_restart
        press_enter
    done
}

# ── 2. Erlaubte Abtastraten (Allowed Rates) ──────────────────
menu_allowed_rates() {
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
    echo "  [1] Standard (44100 48000)"
    echo "  [2] Erweitert (44100 48000 88200 96000)"
    echo "  [3] Vollständig (44100 48000 88200 96000 176400 192000)"
    echo "  [4] Nur CD-Familie (44100 88200 176400)"
    echo "  [5] Nur DVD-Familie (48000 96000 192000)"
    echo "  [6] Eigene Liste eingeben"
    echo "  [0] Zurück"
    echo ""
    read -rp "  Auswahl: " choice

    local rates=""
    case "$choice" in
        1) rates="44100 48000" ;;
        2) rates="44100 48000 88200 96000" ;;
        3) rates="44100 48000 88200 96000 176400 192000" ;;
        4) rates="44100 88200 176400" ;;
        5) rates="48000 96000 192000" ;;
        6)
            read -rp "  Raten (Leerzeichen-getrennt, z.B. 44100 48000 96000): " rates
            ;;
        0) return ;;
        *) warn "Ungültige Auswahl."; press_enter; return ;;
    esac

    ensure_dirs
    local current_rate
    current_rate=$(grep "default.clock.rate " "$CLOCK_CONF" 2>/dev/null | grep -v "allowed" | head -1 | grep -oP '\d+')
    [[ -z "$current_rate" ]] && current_rate=48000

    cat > "$CLOCK_CONF" <<EOF
# PipeWire Clock / Sample Rate Konfiguration
# Generiert von pipewire-tuner.sh
context.properties = {
    default.clock.rate = $current_rate
    default.clock.allowed-rates = [ $rates ]
}
EOF
    success "Erlaubte Raten gesetzt: [ $rates ]"
    ask_restart
    press_enter
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
        echo "  Skala: 0 (niedrigste) → 14 (höchste Qualität)"
        echo "  Hinweis: Qualität 10→14 hat kaum Unterschied, aber 2-3x mehr CPU-Last"
        echo ""
        echo "  [1] Qualität  4  – Standard (niedrige CPU-Last)"
        echo "  [2] Qualität  6  – Ausgewogen"
        echo "  [3] Qualität 10  – Hoch (empfohlen für Audiophile)"
        echo "  [4] Qualität 14  – Maximum (hohe CPU-Last)"
        echo "  [5] Eigenen Wert eingeben (0–14)"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        local quality=""
        case "$choice" in
            1) quality=4 ;;
            2) quality=6 ;;
            3) quality=10 ;;
            4) quality=14 ;;
            5)
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
# Generiert von pipewire-tuner.sh
# Skala: 0 (niedrig) bis 14 (höchste Qualität)
stream.properties = {
    resample.quality = $quality
}
EOF
        success "Resampling-Qualität auf $quality gesetzt → $RESAMPLE_CONF"
        ask_restart
        press_enter
        return
    done
}

# ── 4. Bit-Tiefe (Bit Depth) ──────────────────────────────────
menu_bitdepth() {
    print_header
    print_section "4. Bit-Tiefe (Bit Depth) via WirePlumber"
    echo ""
    info "Setzt das Audio-Format für ALSA-Ausgabegeräte."
    info "Aktuell:"
    if [[ -f "$WP_ALSA_CONF" ]]; then
        cat "$WP_ALSA_CONF" | grep "audio.format" | sed 's/^/     /' || warn "Nicht konfiguriert"
    else
        warn "Keine Konfiguration (Standard: S32LE intern)"
    fi
    echo ""
    echo "  [1] S16LE  – 16-Bit (CD-Standard)"
    echo "  [2] S24LE  – 24-Bit (Hi-Res, empfohlen für DACs)"
    echo "  [3] S24_3LE– 24-Bit gepackt (manche DACs)"
    echo "  [4] S32LE  – 32-Bit (maximale interne Präzision)"
    echo "  [0] Zurück"
    echo ""
    read -rp "  Auswahl: " choice

    local fmt=""
    case "$choice" in
        1) fmt="S16LE" ;;
        2) fmt="S24LE" ;;
        3) fmt="S24_3LE" ;;
        4) fmt="S32LE" ;;
        0) return ;;
        *) warn "Ungültige Auswahl."; press_enter; return ;;
    esac

    ensure_dirs
    cat > "$WP_ALSA_CONF" <<EOF
# WirePlumber ALSA Audio-Format (Bit-Tiefe)
# Generiert von pipewire-tuner.sh
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
}

# ── 5. Puffergröße / Latenz ───────────────────────────────────
menu_latency() {
    while true; do
        print_header
        print_section "5. Puffergröße / Latenz (Quantum)"
        echo ""
        info "Kleinere Werte = geringere Latenz, aber mehr CPU-Last & Knackser-Risiko"
        info "Größere Werte = stabiler, aber höhere Latenz"
        echo ""
        info "Aktuell (live):"
        pw-metadata -n settings 2>/dev/null | grep -E "clock\.(force-)?(quantum|rate)" | \
            awk -F"'" '{print "     " \$4 " = " \$6}' || warn "pw-metadata nicht verfügbar"
        echo ""
        echo "  [1]   64 Samples  (~1.3 ms  @ 48kHz) – Pro Audio / sehr niedrige Latenz"
        echo "  [2]  128 Samples  (~2.7 ms  @ 48kHz) – Niedrige Latenz"
        echo "  [3]  256 Samples  (~5.3 ms  @ 48kHz) – Ausgewogen (empfohlen)"
        echo "  [4]  512 Samples  (~10.7 ms @ 48kHz) – Stabil"
        echo "  [5] 1024 Samples  (~21.3 ms @ 48kHz) – Sehr stabil / Desktop"
        echo "  [6] 2048 Samples  (~42.7 ms @ 48kHz) – Maximum Stabilität"
        echo "  [7] Eigenen Wert eingeben"
        echo "  [8] Erzwungene Rate zurücksetzen (auf Standard)"
        echo "  [0] Zurück"
        echo ""
        read -rp "  Auswahl: " choice

        local quantum=""
        case "$choice" in
            1) quantum=64 ;;
            2) quantum=128 ;;
            3) quantum=256 ;;
            4) quantum=512 ;;
            5) quantum=1024 ;;
            6) quantum=2048 ;;
            7)
                read -rp "  Quantum (Potenz von 2, z.B. 512): " quantum
                if ! [[ "$quantum" =~ ^[0-9]+$ ]]; then
                    error "Ungültige Eingabe."; press_enter; continue
                fi
                ;;
            8)
                pw-metadata -n settings 0 clock.force-quantum 0 2>/dev/null
                pw-metadata -n settings 0 clock.force-rate 0 2>/dev/null
                success "Erzwungene Werte zurückgesetzt (Standard aktiv)."
                press_enter; return
                ;;
            0) return ;;
            *) warn "Ungültige Auswahl."; press_enter; continue ;;
        esac

        pw-metadata -n settings 0 clock.force-quantum "$quantum" 2>/dev/null
        if [[ $? -eq 0 ]]; then
            success "Quantum live auf $quantum gesetzt (kein Neustart nötig)."
        else
            error "Fehler beim Setzen. Ist PipeWire aktiv?"
        fi
        press_enter
    done
}

# ── 6. Live Sample Rate erzwingen ─────────────────────────────
menu_force_rate() {
    print_header
    print_section "6. Abtastrate live erzwingen (temporär)"
    echo ""
    info "Setzt die Rate sofort ohne Neustart (geht nach Reboot verloren)."
    echo ""
    echo "  [1] 44100 Hz"
    echo "  [2] 48000 Hz"
    echo "  [3] 88200 Hz"
    echo "  [4] 96000 Hz"
    echo "  [5] 176400 Hz"
    echo "  [6] 192000 Hz"
    echo "  [7] Eigene Rate"
    echo "  [8] Zurücksetzen (Standard)"
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
        7) read -rp "  Rate eingeben: " rate ;;
        8)
            pw-metadata -n settings 0 clock.force-rate 0 2>/dev/null
            success "Rate zurückgesetzt."; press_enter; return
            ;;
        0) return ;;
        *) warn "Ungültige Auswahl."; press_enter; return ;;
    esac

    pw-metadata -n settings 0 clock.force-rate "$rate" 2>/dev/null
    [[ $? -eq 0 ]] && success "Rate live auf ${rate} Hz gesetzt." || error "Fehler. Ist PipeWire aktiv?"
    press_enter
}

# ── 7. Status & Diagnose ──────────────────────────────────────
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
    echo -e "${BOLD}  ── PipeWire Version ──${RESET}"
    pw-cli --version 2>/dev/null | head -1 | sed 's/^/  /' || warn "pw-cli nicht gefunden"

    echo ""
    echo -e "${BOLD}  ── Live Einstellungen (pw-metadata) ──${RESET}"
    pw-metadata -n settings 2>/dev/null | grep -E "clock\." | \
        awk -F"'" '{printf "  %-35s = %s
", \$4, \$6}' || warn "Keine Daten"

    echo ""
    echo -e "${BOLD}  ── Audio Geräte (wpctl) ──${RESET}"
    wpctl status 2>/dev/null | grep -A 30 "Audio" | head -35 | sed 's/^/  /' || warn "wpctl nicht verfügbar"

    echo ""
    echo -e "${BOLD}  ── Aktive Konfigurationsdateien ──${RESET}"
    for f in "$CLOCK_CONF" "$RESAMPLE_CONF" "$WP_ALSA_CONF"; do
        if [[ -f "$f" ]]; then
            echo -e "  ${GREEN}✔${RESET} $f"
            cat "$f" | grep -v "^#" | grep -v "^$" | sed 's/^/      /'
        else
            echo -e "  ${YELLOW}–${RESET} $f (nicht vorhanden)"
        fi
    done

    press_enter
}

# ── 8. Bluetooth Audio Qualität ───────────────────────────────
menu_bluetooth() {
    print_header
    print_section "8. Bluetooth Audio Qualität (WirePlumber)"
    echo ""
    info "Konfiguriert LDAC/A2DP Qualität für Bluetooth-Geräte."
    echo ""

    local BT_CONF="$WP_CONF_DIR/wireplumber.conf.d/51-bluetooth-quality.conf"

    echo "  LDAC Qualitätsmodus:"
    echo "  [1] auto – Adaptiv (Standard, empfohlen)"
    echo "  [2] hq   – High Quality (990/909 kbps)"
    echo "  [3] sq   – Standard Quality (660/606 kbps)"
    echo "  [4] mq   – Mobile Quality (330/303 kbps)"
    echo ""
    echo "  Bluetooth Sample Rate:"
    echo "  [5] 44100 Hz"
    echo "  [6] 48000 Hz"
    echo "  [7] 96000 Hz"
    echo "  [0] Zurück"
    echo ""
    read -rp "  Auswahl: " choice

    ensure_dirs
    mkdir -p "$WP_CONF_DIR/wireplumber.conf.d"

    local ldac_quality bt_rate
    # Bestehende Werte lesen
    ldac_quality=$(grep "ldac.quality" "$BT_CONF" 2>/dev/null | grep -oP '"[^"]+"' | head -1 | tr -d '"')
    bt_rate=$(grep "default.rate" "$BT_CONF" 2>/dev/null | grep -oP '\d+' | head -1)
    [[ -z "$ldac_quality" ]] && ldac_quality="auto"
    [[ -z "$bt_rate" ]] && bt_rate=48000

    case "$choice" in
        1) ldac_quality="auto" ;;
        2) ldac_quality="hq" ;;
        3) ldac_quality="sq" ;;
        4) ldac_quality="mq" ;;
        5) bt_rate=44100 ;;
        6) bt_rate=48000 ;;
        7) bt_rate=96000 ;;
        0) return ;;
        *) warn "Ungültige Auswahl."; press_enter; return ;;
    esac

    cat > "$BT_CONF" <<EOF
# WirePlumber Bluetooth Audio Qualität
# Generiert von pipewire-tuner.sh
monitor.bluez.properties = {
    bluez5.a2dp.ldac.quality = "$ldac_quality"
    bluez5.default.rate      = $bt_rate
}
EOF
    success "Bluetooth: LDAC=$ldac_quality, Rate=${bt_rate} Hz → $BT_CONF"
    ask_restart
    press_enter
}

# ── 9. Konfiguration sichern / wiederherstellen ───────────────
menu_backup() {
    print_header
    print_section "9. Konfiguration sichern / wiederherstellen"
    echo ""
    local BACKUP_DIR="$HOME/.config/pipewire-tuner-backup"
    echo "  [1] Aktuelle Konfiguration sichern → $BACKUP_DIR"
    echo "  [2] Backup wiederherstellen"
    echo "  [3] Alle Tuner-Einstellungen zurücksetzen (Dateien löschen)"
    echo "  [0] Zurück"
    echo ""
    read -rp "  Auswahl: " choice

    case "$choice" in
        1)
            local ts; ts=$(date +%Y%m%d_%H%M%S)
            local bdir="$BACKUP_DIR/$ts"
            mkdir -p "$bdir"
            for f in "$CLOCK_CONF" "$RESAMPLE_CONF" "$WP_ALSA_CONF"; do
                [[ -f "$f" ]] && cp "$f" "$bdir/" && info "Gesichert: $f"
            done
            success "Backup gespeichert in: $bdir"
            ;;
        2)
            if [[ ! -d "$BACKUP_DIR" ]]; then
                warn "Kein Backup-Verzeichnis gefunden."; press_enter; return
            fi
            echo ""
            info "Verfügbare Backups:"
            local backups=("$BACKUP_DIR"/*)
            local i=1
            for b in "${backups[@]}"; do
                echo "  [$i] $(basename "$b")"
                ((i++))
            done
            echo ""
            read -rp "  Nummer wählen: " bnum
            local selected="${backups[$((bnum-1))]}"
            if [[ -d "$selected" ]]; then
                cp "$selected"/* "$PW_CONF_D/" 2>/dev/null
                cp "$selected"/* "$CLIENT_CONF_D/" 2>/dev/null
                cp "$selected"/* "$WP_CONF_D/" 2>/dev/null
                success "Backup wiederhergestellt aus: $selected"
                ask_restart
            else
                error "Ungültige Auswahl."
            fi
            ;;
        3)
            read -rp "  Wirklich alle Tuner-Konfigurationen löschen? [j/N]: " ans
            if [[ "$ans" =~ ^[jJyY]$ ]]; then
                rm -f "$CLOCK_CONF" "$RESAMPLE_CONF" "$WP_ALSA_CONF"
                rm -f "$WP_CONF_DIR/wireplumber.conf.d/51-bluetooth-quality.conf"
                success "Alle Tuner-Einstellungen gelöscht. PipeWire-Standardwerte aktiv."
                ask_restart
            fi
            ;;
        0) return ;;
        *) warn "Ungültige Auswahl." ;;
    esac
    press_enter
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
        echo "  [9]  Konfiguration sichern / wiederherstellen"
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
            1) menu_samplerate ;;
            2) menu_allowed_rates ;;
            3) menu_resample_quality ;;
            4) menu_bitdepth ;;
            5) menu_latency ;;
            6) menu_force_rate ;;
            7) menu_status ;;
            8) menu_bluetooth ;;
            9) menu_backup ;;
            r|R) restart_pipewire; press_enter ;;
            0)
                echo -e "
  ${GREEN}Auf Wiedersehen!${RESET}
"
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
check_pipewire 2>/dev/null || true   # optionaler Check
main_menu
