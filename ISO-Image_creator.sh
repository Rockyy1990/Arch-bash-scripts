#!/usr/bin/env bash
# ==============================================================================
#  ISO-Image_creator.sh — ISO-Erstellungs-Assistent (Erweitert)
#  Erstellt, verifiziert, extrahiert und verwaltet ISO-Dateien.
#
#  Abhängigkeiten: genisoimage oder xorriso (wird automatisch geprüft)
#  Optional:       md5sum, sha256sum, file, isoinfo, rsync, 7z
#  Getestet auf:   Debian/Ubuntu, Arch, Fedora, openSUSE
# ==============================================================================

set -euo pipefail

# ── Farben & Symbole ──────────────────────────────────────────────────────────
ROT='\033[0;31m'
GRUEN='\033[0;32m'
GELB='\033[1;33m'
BLAU='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
FETT='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

OK="  ${GRUEN}✔${RESET}"
FEHLER="  ${ROT}✘${RESET}"
INFO="  ${BLAU}ℹ${RESET}"
WARNUNG="  ${GELB}⚠${RESET}"
PFEIL="  ${CYAN}➜${RESET}"

# ── Globale Variablen ─────────────────────────────────────────────────────────
TOOL=""               # genisoimage oder xorriso
QUELLVERZ=""
ISO_ZIEL=""
ISO_NAME="ausgabe.iso"
VOLUMEN_NAME="MEIN_ISO"
LOG_VERZ="${HOME}/.iso_creator/logs"
KONFIG_VERZ="${HOME}/.iso_creator"
KONFIG_DATEI="${KONFIG_VERZ}/einstellungen.conf"
LOG_DATEI="${LOG_VERZ}/iso_erstellen_$(date +%Y%m%d_%H%M%S).log"
EXCLUDE_DATEI=""      # Datei mit Ausschlussmustern
VERSION="2.0.0"

# ── Konfigurations-Verzeichnis sicherstellen ─────────────────────────────────
mkdir -p "$LOG_VERZ"

# ── Signal-Handler / Cleanup ─────────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    # Temporäre Dateien aufräumen
    if [[ -n "${TEMP_DIR:-}" && -d "${TEMP_DIR:-}" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    if [[ $exit_code -ne 0 && $exit_code -ne 130 ]]; then
        echo
        echo -e "${FEHLER} ${ROT}Skript unerwartet beendet (Code: ${exit_code})${RESET}"
        echo -e "${INFO} Log: ${LOG_DATEI}"
    fi
}
trap cleanup EXIT

abbruch_handler() {
    echo
    echo
    meldung_warnung "Abbruch durch Benutzer (Ctrl+C)."
    echo
    exit 130
}
trap abbruch_handler INT TERM

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────

trennlinie() {
    echo -e "${BLAU}$(printf '─%.0s' {1..60})${RESET}"
}

trennlinie_duenn() {
    echo -e "${DIM}$(printf '·%.0s' {1..60})${RESET}"
}

kopfzeile() {
    clear
    echo
    trennlinie
    echo -e "  ${FETT}${CYAN}🗂  ISO-Erstellungs-Assistent${RESET}  ${DIM}v${VERSION}${RESET}"
    echo -e "  ${GELB}$(date '+%d.%m.%Y %H:%M:%S')${RESET}"
    trennlinie
    echo
}

warte() {
    echo
    read -rp "  Drücke [Enter] um fortzufahren..." _
}

meldung_ok()      { echo -e "${OK} ${GRUEN}${1}${RESET}"; }
meldung_fehler()  { echo -e "${FEHLER} ${ROT}${1}${RESET}"; }
meldung_info()    { echo -e "${INFO} ${1}"; }
meldung_warnung() { echo -e "${WARNUNG} ${GELB}${1}${RESET}"; }

# Eingabe mit Standardwert
eingabe_mit_standard() {
    local aufforderung="$1"
    local standard="$2"
    local eingabe
    read -rp "$(echo -e "  ${PFEIL} ${aufforderung} [${GELB}${standard}${RESET}]: ")" eingabe
    echo "${eingabe:-$standard}"
}

# Ja/Nein-Abfrage
ja_nein() {
    local frage="$1"
    local antwort
    while true; do
        read -rp "$(echo -e "  ${PFEIL} ${frage} [j/N]: ")" antwort
        case "${antwort,,}" in
            j|ja|yes|y) return 0 ;;
            n|nein|no|"") return 1 ;;
            *) meldung_warnung "Bitte 'j' oder 'n' eingeben." ;;
        esac
    done
}

# Menschenlesbare Dateigröße
menschliche_groesse() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif (( bytes >= 1048576 )); then
        echo "$(echo "scale=1; $bytes / 1048576" | bc) MB"
    elif (( bytes >= 1024 )); then
        echo "$(echo "scale=0; $bytes / 1024" | bc) KB"
    else
        echo "${bytes} B"
    fi
}

# Zeitdauer menschenlesbar formatieren
format_dauer() {
    local sekunden=$1
    if (( sekunden >= 3600 )); then
        printf '%dh %dm %ds' $((sekunden/3600)) $((sekunden%3600/60)) $((sekunden%60))
    elif (( sekunden >= 60 )); then
        printf '%dm %ds' $((sekunden/60)) $((sekunden%60))
    else
        printf '%ds' "$sekunden"
    fi
}

# ── Abhängigkeiten prüfen ─────────────────────────────────────────────────────

pruefe_abhaengigkeiten() {
    kopfzeile
    echo -e "  ${FETT}Systemprüfung${RESET}"
    echo
    trennlinie

    local fehler=0

    # xorriso bevorzugen (moderner), Fallback auf genisoimage
    if command -v xorriso &>/dev/null; then
        TOOL="xorriso"
        meldung_ok "xorriso gefunden: $(xorriso --version 2>&1 | head -1)"
    elif command -v genisoimage &>/dev/null; then
        TOOL="genisoimage"
        meldung_ok "genisoimage gefunden: $(genisoimage --version 2>&1 | head -1)"
    else
        meldung_fehler "Weder xorriso noch genisoimage gefunden!"
        echo
        echo -e "  Bitte installiere eines der folgenden Pakete:"
        echo -e "  ${GELB}Ubuntu/Debian:${RESET}  sudo apt install xorriso"
        echo -e "  ${GELB}Arch Linux:${RESET}     sudo pacman -S libisoburn"
        echo -e "  ${GELB}Fedora:${RESET}         sudo dnf install xorriso"
        echo -e "  ${GELB}openSUSE:${RESET}       sudo zypper install xorriso"
        fehler=1
    fi

    # mkisofs als Alias für genisoimage?
    if [[ -z "$TOOL" ]] && command -v mkisofs &>/dev/null; then
        TOOL="mkisofs"
        meldung_ok "mkisofs gefunden (Fallback)"
    fi

    # Optionale Werkzeuge prüfen
    echo
    trennlinie_duenn
    echo -e "  ${DIM}Optionale Werkzeuge:${RESET}"
    local optionale_tools=("du:Größenberechnung" "df:Speicherplatz" "md5sum:MD5-Prüfsummen"
        "sha256sum:SHA256-Prüfsummen" "file:Dateityp-Erkennung" "rsync:Verzeichnis-Sync"
        "7z:Archiv-Extraktion" "isoinfo:ISO-Metadaten")

    for eintrag in "${optionale_tools[@]}"; do
        local cmd="${eintrag%%:*}"
        local beschreibung="${eintrag##*:}"
        if command -v "$cmd" &>/dev/null; then
            meldung_ok "${cmd} (${beschreibung}) verfügbar"
        else
            meldung_warnung "${cmd} (${beschreibung}) nicht gefunden – Funktion eingeschränkt"
        fi
    done

    echo
    if [[ $fehler -eq 1 ]]; then
        meldung_fehler "Kritische Abhängigkeiten fehlen. Das Skript wird beendet."
        exit 1
    fi

    meldung_ok "Alle kritischen Abhängigkeiten erfüllt. Tool: ${FETT}${TOOL}${RESET}"
    warte
}

# ── Verzeichnis auswählen ─────────────────────────────────────────────────────

waehle_quellverzeichnis() {
    kopfzeile
    echo -e "  ${FETT}Quellverzeichnis wählen${RESET}"
    echo
    trennlinie

    while true; do
        echo -e "${INFO} Gib den Pfad zum Verzeichnis ein, das als ISO verpackt werden soll."
        echo -e "${INFO} Leer lassen = aktuelles Verzeichnis (${GELB}$(pwd)${RESET})"
        echo
        read -rp "$(echo -e "  ${PFEIL} Quellverzeichnis: ")" eingabe

        local verz="${eingabe:-$(pwd)}"

        # Tilde expandieren
        verz="${verz/#\~/$HOME}"

        if [[ -d "$verz" ]]; then
            QUELLVERZ="$(realpath "$verz")"

            # Prüfe ob Verzeichnis lesbar ist
            if [[ ! -r "$QUELLVERZ" ]]; then
                meldung_fehler "Verzeichnis '${QUELLVERZ}' ist nicht lesbar (fehlende Berechtigungen)."
                echo
                continue
            fi

            local groesse datei_anzahl verz_anzahl
            groesse=$(du -sh "$QUELLVERZ" 2>/dev/null | cut -f1 || echo "unbekannt")
            datei_anzahl=$(find "$QUELLVERZ" -type f 2>/dev/null | wc -l)
            verz_anzahl=$(find "$QUELLVERZ" -type d 2>/dev/null | wc -l)

            echo
            meldung_ok "Verzeichnis:      ${FETT}${QUELLVERZ}${RESET}"
            meldung_info "Größe:            ${groesse}"
            meldung_info "Dateien:          ${datei_anzahl} Dateien in ${verz_anzahl} Verzeichnissen"

            # Warnung bei großen Verzeichnissen (>4.7 GB ≈ DVD)
            local groesse_kb
            groesse_kb=$(du -sk "$QUELLVERZ" 2>/dev/null | cut -f1 || echo 0)
            if (( groesse_kb > 4700000 )); then
                echo
                meldung_warnung "Das Verzeichnis ist größer als eine DVD (4.7 GB)!"
                meldung_info "Für Blu-ray-Medien bis ca. 25 GB möglich."
            elif (( groesse_kb > 700000 )); then
                echo
                meldung_warnung "Das Verzeichnis ist größer als eine CD (700 MB)."
            fi

            # Warnung bei leeren Verzeichnissen
            if (( datei_anzahl == 0 )); then
                echo
                meldung_warnung "Das Verzeichnis enthält keine Dateien!"
                if ! ja_nein "Trotzdem fortfahren?"; then
                    continue
                fi
            fi
            echo
            break
        else
            meldung_fehler "Verzeichnis '${verz}' nicht gefunden. Bitte erneut eingeben."
            echo
        fi
    done
}

# ── ISO-Ausgabeziel wählen ────────────────────────────────────────────────────

waehle_ausgabe() {
    kopfzeile
    echo -e "  ${FETT}Ausgabe konfigurieren${RESET}"
    echo
    trennlinie

    # ISO-Name
    local standard_name
    standard_name="$(basename "$QUELLVERZ")_$(date +%Y%m%d).iso"
    ISO_NAME=$(eingabe_mit_standard "ISO-Dateiname" "$standard_name")
    [[ "$ISO_NAME" != *.iso ]] && ISO_NAME="${ISO_NAME}.iso"

    # Ungültige Zeichen im Dateinamen prüfen
    if [[ "$ISO_NAME" =~ [/\\:*?\"\<\>\|] ]]; then
        meldung_fehler "Der Dateiname enthält ungültige Zeichen: / \\ : * ? \" < > |"
        meldung_info "Bitte verwende nur gültige Zeichen im Dateinamen."
        warte
        return 1
    fi

    # Ausgabeverzeichnis
    echo
    meldung_info "Ausgabeverzeichnis (leer = ${GELB}$(pwd)${RESET})"
    read -rp "$(echo -e "  ${PFEIL} Ausgabeverzeichnis: ")" ausgabe_verz
    ausgabe_verz="${ausgabe_verz:-$(pwd)}"
    ausgabe_verz="${ausgabe_verz/#\~/$HOME}"

    if [[ ! -d "$ausgabe_verz" ]]; then
        if ja_nein "Verzeichnis '${ausgabe_verz}' existiert nicht. Erstellen?"; then
            mkdir -p "$ausgabe_verz"
            meldung_ok "Verzeichnis erstellt."
        else
            meldung_fehler "Ungültiges Ausgabeverzeichnis. Abbruch."
            warte
            return 1
        fi
    fi

    # Prüfe Schreibberechtigung
    if [[ ! -w "$ausgabe_verz" ]]; then
        meldung_fehler "Keine Schreibberechtigung im Verzeichnis '${ausgabe_verz}'."
        warte
        return 1
    fi

    ISO_ZIEL="${ausgabe_verz}/${ISO_NAME}"

    # Volumen-Label
    echo
    VOLUMEN_NAME=$(eingabe_mit_standard "Volumen-Label (max. 32 Zeichen)" \
        "$(basename "$QUELLVERZ" | tr '[:lower:]' '[:upper:]' | tr ' ' '_' | cut -c1-32)")
    VOLUMEN_NAME="${VOLUMEN_NAME:0:32}"

    # Überschreiben prüfen
    if [[ -f "$ISO_ZIEL" ]]; then
        meldung_warnung "Die Datei '${ISO_ZIEL}' existiert bereits!"
        if ! ja_nein "Überschreiben?"; then
            meldung_info "Abgebrochen."
            warte
            return 1
        fi
    fi

    # Speicherplatz prüfen
    local verfuegbar_kb
    verfuegbar_kb=$(df -k "$(dirname "$ISO_ZIEL")" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
    local benoetigt_kb
    benoetigt_kb=$(du -sk "$QUELLVERZ" 2>/dev/null | cut -f1 || echo 0)

    echo
    meldung_info "Benötigter Speicher:   ca. $(( benoetigt_kb / 1024 )) MB"
    meldung_info "Verfügbarer Speicher:  ca. $(( verfuegbar_kb / 1024 )) MB"

    if (( benoetigt_kb > verfuegbar_kb )); then
        meldung_warnung "Möglicherweise nicht genug Speicherplatz!"
        ja_nein "Trotzdem fortfahren?" || return 1
    fi

    echo
    meldung_ok "Ausgabe: ${FETT}${ISO_ZIEL}${RESET}"
}

# ── Zusammenfassung anzeigen ──────────────────────────────────────────────────

zeige_zusammenfassung() {
    local modus="$1"
    kopfzeile
    echo -e "  ${FETT}Zusammenfassung${RESET}"
    echo
    trennlinie
    echo -e "  ${FETT}Modus:${RESET}          ${CYAN}${modus}${RESET}"
    echo -e "  ${FETT}Tool:${RESET}           ${TOOL}"
    echo -e "  ${FETT}Quelle:${RESET}         ${QUELLVERZ}"
    echo -e "  ${FETT}Ausgabe:${RESET}        ${ISO_ZIEL}"
    echo -e "  ${FETT}Volumen-Label:${RESET}  ${VOLUMEN_NAME}"
    if [[ -n "$EXCLUDE_DATEI" && -f "$EXCLUDE_DATEI" ]]; then
        local anzahl_muster
        anzahl_muster=$(wc -l < "$EXCLUDE_DATEI")
        echo -e "  ${FETT}Ausschlüsse:${RESET}    ${anzahl_muster} Muster"
    fi
    trennlinie
    echo
}

# ── Fortschrittsanzeige ───────────────────────────────────────────────────────

zeige_fortschritt() {
    local pid=$1
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local start_zeit=$SECONDS
    echo -ne "  ${CYAN}"
    while kill -0 "$pid" 2>/dev/null; do
        local vergangen=$(( SECONDS - start_zeit ))
        local dauer_str
        dauer_str=$(format_dauer "$vergangen")
        echo -ne "\r  ${CYAN}${spin[$i]}${RESET} ISO wird erstellt... ${DIM}(${dauer_str})${RESET}    "
        i=$(( (i + 1) % 10 ))
        sleep 0.1
    done
    local gesamt=$(( SECONDS - start_zeit ))
    echo -ne "\r  ${GRUEN}✔${RESET} Vorgang abgeschlossen in $(format_dauer "$gesamt").        \n"
}

# ── Ausschluss-Muster konfigurieren ──────────────────────────────────────────

konfiguriere_ausschluesse() {
    kopfzeile
    echo -e "  ${FETT}Ausschluss-Muster konfigurieren${RESET}"
    echo
    trennlinie
    echo
    echo -e "${INFO} Bestimmte Dateien/Verzeichnisse können beim Erstellen"
    echo -e "${INFO} der ISO ausgeschlossen werden."
    echo
    echo -e "  ${FETT}Gängige Muster:${RESET}"
    echo -e "  ${DIM}  *.tmp          – Temporäre Dateien${RESET}"
    echo -e "  ${DIM}  *.log          – Log-Dateien${RESET}"
    echo -e "  ${DIM}  .git           – Git-Verzeichnisse${RESET}"
    echo -e "  ${DIM}  __pycache__    – Python-Cache${RESET}"
    echo -e "  ${DIM}  node_modules   – Node.js-Abhängigkeiten${RESET}"
    echo -e "  ${DIM}  .DS_Store      – macOS Metadaten${RESET}"
    echo -e "  ${DIM}  Thumbs.db      – Windows Thumbnails${RESET}"
    echo

    if ! ja_nein "Möchtest du Ausschluss-Muster definieren?"; then
        EXCLUDE_DATEI=""
        return
    fi

    TEMP_DIR=$(mktemp -d)
    EXCLUDE_DATEI="${TEMP_DIR}/exclude_patterns.txt"
    touch "$EXCLUDE_DATEI"

    echo
    if ja_nein "Standard-Ausschlüsse verwenden? (.git, .DS_Store, Thumbs.db, *.tmp)"; then
        cat >> "$EXCLUDE_DATEI" <<'EOF'
.git
.svn
.DS_Store
Thumbs.db
*.tmp
*.swp
*~
EOF
        meldung_ok "Standard-Ausschlüsse hinzugefügt."
    fi

    echo
    meldung_info "Gib zusätzliche Muster ein (eines pro Zeile, leer = fertig):"
    echo
    while true; do
        read -rp "$(echo -e "  ${PFEIL} Muster: ")" muster
        if [[ -z "$muster" ]]; then
            break
        fi
        echo "$muster" >> "$EXCLUDE_DATEI"
        meldung_ok "Hinzugefügt: ${muster}"
    done

    local anzahl
    anzahl=$(wc -l < "$EXCLUDE_DATEI")
    echo
    if (( anzahl > 0 )); then
        meldung_ok "Insgesamt ${FETT}${anzahl}${RESET}${GRUEN} Ausschluss-Muster definiert.${RESET}"
        echo
        echo -e "  ${FETT}Aktive Muster:${RESET}"
        while IFS= read -r zeile; do
            echo -e "    ${DIM}• ${zeile}${RESET}"
        done < "$EXCLUDE_DATEI"
    else
        meldung_info "Keine Ausschluss-Muster definiert."
        EXCLUDE_DATEI=""
    fi
    echo
}

# ── Exclude-Optionen für Tool bauen ──────────────────────────────────────────

baue_exclude_optionen() {
    local -n optionen_ref=$1
    if [[ -n "${EXCLUDE_DATEI:-}" && -f "${EXCLUDE_DATEI:-}" ]]; then
        while IFS= read -r muster; do
            [[ -z "$muster" || "$muster" == \#* ]] && continue
            if [[ "$TOOL" == "xorriso" ]]; then
                optionen_ref+=("--exclude" "$muster")
            else
                optionen_ref+=("-m" "$muster")
            fi
        done < "$EXCLUDE_DATEI"
    fi
}

# ── Normale ISO erstellen ─────────────────────────────────────────────────────

erstelle_normale_iso() {
    waehle_quellverzeichnis || return
    konfiguriere_ausschluesse
    waehle_ausgabe          || return
    zeige_zusammenfassung "Normale ISO (Rock Ridge + Joliet)"

    ja_nein "ISO jetzt erstellen?" || { meldung_info "Abgebrochen."; warte; return; }

    echo
    meldung_info "Erstelle ISO... (Log: ${LOG_DATEI})"
    echo

    local exit_code=0
    local -a exclude_opts=()
    baue_exclude_optionen exclude_opts

    if [[ "$TOOL" == "xorriso" ]]; then
        xorriso -as mkisofs \
            -o "$ISO_ZIEL" \
            -V "$VOLUMEN_NAME" \
            -r -J \
            -joliet-long \
            "${exclude_opts[@]}" \
            "$QUELLVERZ" \
            >> "$LOG_DATEI" 2>&1 &
    else
        "$TOOL" \
            -o "$ISO_ZIEL" \
            -V "$VOLUMEN_NAME" \
            -r -J \
            -joliet-long \
            "${exclude_opts[@]}" \
            "$QUELLVERZ" \
            >> "$LOG_DATEI" 2>&1 &
    fi

    local pid=$!
    zeige_fortschritt "$pid"
    wait "$pid" || exit_code=$?

    auswertung_erstellen "$exit_code"
}

# ── Bootfähige EFI ISO erstellen ──────────────────────────────────────────────

erstelle_efi_iso() {
    waehle_quellverzeichnis || return

    kopfzeile
    echo -e "  ${FETT}EFI-Boot Konfiguration${RESET}"
    echo
    trennlinie
    echo
    echo -e "${INFO} Für eine EFI-bootfähige ISO wird ein EFI-Boot-Image benötigt."
    echo -e "${INFO} Dieses liegt typischerweise unter:"
    echo -e "  ${GELB}  boot/grub/efi.img${RESET}     (Debian/Ubuntu)"
    echo -e "  ${GELB}  EFI/boot/bootx64.efi${RESET}  (allgemein)"
    echo -e "  ${GELB}  images/efiboot.img${RESET}     (Fedora/RHEL)"
    echo

    # EFI-Image suchen
    local efi_pfad=""
    local kandidaten=(
        "${QUELLVERZ}/boot/grub/efi.img"
        "${QUELLVERZ}/EFI/boot/efiboot.img"
        "${QUELLVERZ}/EFI/BOOT/efiboot.img"
        "${QUELLVERZ}/images/efiboot.img"
        "${QUELLVERZ}/isolinux/efiboot.img"
    )

    for kandidat in "${kandidaten[@]}"; do
        if [[ -f "$kandidat" ]]; then
            efi_pfad="$kandidat"
            meldung_ok "EFI-Boot-Image automatisch gefunden: ${FETT}${efi_pfad}${RESET}"
            break
        fi
    done

    if [[ -z "$efi_pfad" ]]; then
        meldung_warnung "Kein EFI-Boot-Image automatisch gefunden."
        echo
        read -rp "$(echo -e "  ${PFEIL} Pfad zum EFI-Boot-Image manuell eingeben: ")" efi_eingabe
        efi_eingabe="${efi_eingabe/#\~/$HOME}"

        if [[ -z "$efi_eingabe" ]]; then
            meldung_fehler "Kein EFI-Boot-Image angegeben. EFI-ISO kann nicht erstellt werden."
            echo
            meldung_info "Tipp: Für eine einfache EFI-Teststruktur kannst du zuerst Option 3 nutzen."
            warte
            return 1
        fi

        if [[ ! -f "$efi_eingabe" ]]; then
            meldung_fehler "Datei '${efi_eingabe}' nicht gefunden."
            warte
            return 1
        fi
        efi_pfad="$efi_eingabe"
        meldung_ok "EFI-Boot-Image: ${efi_pfad}"
    fi

    # Relativen Pfad zum EFI-Image berechnen
    local efi_relativ
    efi_relativ="${efi_pfad#"${QUELLVERZ}/"}"

    konfiguriere_ausschluesse
    waehle_ausgabe || return

    # BIOS-Kompatibilität (Legacy-Boot)?
    echo
    local legacy_boot=false
    local isolinux_pfad=""
    if ja_nein "Auch Legacy-BIOS-Boot (isolinux) einbinden, falls vorhanden?"; then
        for kandidat in \
            "${QUELLVERZ}/isolinux/isolinux.bin" \
            "${QUELLVERZ}/boot/isolinux/isolinux.bin"; do
            if [[ -f "$kandidat" ]]; then
                isolinux_pfad="$kandidat"
                legacy_boot=true
                meldung_ok "isolinux.bin gefunden: ${isolinux_pfad}"
                break
            fi
        done
        if [[ "$legacy_boot" == false ]]; then
            meldung_warnung "isolinux.bin nicht gefunden – nur EFI-Boot wird eingebunden."
        fi
    fi

    zeige_zusammenfassung "Bootfähige ISO (EFI$([ "$legacy_boot" == true ] && echo ' + BIOS'))"
    meldung_info "EFI-Image:  ${efi_relativ}"
    [[ "$legacy_boot" == true ]] && meldung_info "BIOS-Boot:  aktiviert"
    echo

    ja_nein "ISO jetzt erstellen?" || { meldung_info "Abgebrochen."; warte; return; }

    echo
    meldung_info "Erstelle EFI-bootfähige ISO... (Log: ${LOG_DATEI})"
    echo

    local exit_code=0
    local -a exclude_opts=()
    baue_exclude_optionen exclude_opts

    if [[ "$TOOL" == "xorriso" ]]; then
        if [[ "$legacy_boot" == true ]]; then
            local iso_rel="${isolinux_pfad#"${QUELLVERZ}/"}"
            local iso_dir
            iso_dir="$(dirname "$iso_rel")"
            xorriso -as mkisofs \
                -o "$ISO_ZIEL" \
                -V "$VOLUMEN_NAME" \
                -r -J -joliet-long \
                -b "${iso_rel}" \
                -c "${iso_dir}/boot.cat" \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -eltorito-alt-boot \
                -e "${efi_relativ}" \
                -no-emul-boot \
                -isohybrid-gpt-basdat \
                "${exclude_opts[@]}" \
                "$QUELLVERZ" \
                >> "$LOG_DATEI" 2>&1 &
        else
            xorriso -as mkisofs \
                -o "$ISO_ZIEL" \
                -V "$VOLUMEN_NAME" \
                -r -J -joliet-long \
                -e "${efi_relativ}" \
                -no-emul-boot \
                -isohybrid-gpt-basdat \
                "${exclude_opts[@]}" \
                "$QUELLVERZ" \
                >> "$LOG_DATEI" 2>&1 &
        fi
    else
        if [[ "$legacy_boot" == true ]]; then
            local iso_rel="${isolinux_pfad#"${QUELLVERZ}/"}"
            local iso_dir
            iso_dir="$(dirname "$iso_rel")"
            "$TOOL" \
                -o "$ISO_ZIEL" \
                -V "$VOLUMEN_NAME" \
                -r -J -joliet-long \
                -b "${iso_rel}" \
                -c "${iso_dir}/boot.cat" \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -eltorito-alt-boot \
                -e "${efi_relativ}" \
                -no-emul-boot \
                "${exclude_opts[@]}" \
                "$QUELLVERZ" \
                >> "$LOG_DATEI" 2>&1 &
        else
            "$TOOL" \
                -o "$ISO_ZIEL" \
                -V "$VOLUMEN_NAME" \
                -r -J -joliet-long \
                -e "${efi_relativ}" \
                -no-emul-boot \
                "${exclude_opts[@]}" \
                "$QUELLVERZ" \
                >> "$LOG_DATEI" 2>&1 &
        fi
    fi

    local pid=$!
    zeige_fortschritt "$pid"
    wait "$pid" || exit_code=$?

    auswertung_erstellen "$exit_code"
}

# ── Demo-Verzeichnisstruktur erstellen ────────────────────────────────────────

erstelle_demo_struktur() {
    kopfzeile
    echo -e "  ${FETT}Demo-Verzeichnisstruktur erstellen${RESET}"
    echo
    trennlinie
    echo
    meldung_info "Dies erstellt eine minimale EFI-Boot-Teststruktur zum Ausprobieren."
    echo
    local ziel
    ziel=$(eingabe_mit_standard "Wo soll die Demo-Struktur erstellt werden?" "/tmp/iso_demo")
    ziel="${ziel/#\~/$HOME}"

    if ja_nein "Struktur in '${ziel}' erstellen?"; then
        mkdir -p \
            "${ziel}/boot/grub" \
            "${ziel}/EFI/BOOT" \
            "${ziel}/dokumente" \
            "${ziel}/bilder"

        # Dummy-EFI-Image (16 KB Nullbytes als Platzhalter)
        dd if=/dev/zero of="${ziel}/boot/grub/efi.img" bs=1K count=16 2>/dev/null
        # Dummy-GRUB-Konfiguration
        cat > "${ziel}/boot/grub/grub.cfg" <<'GRUBCFG'
set default=0
set timeout=5
menuentry "Demo ISO" {
    echo "Booting Demo ISO..."
}
GRUBCFG
        # Dummy-Dateien
        echo "Hallo von der Demo ISO! $(date)" > "${ziel}/dokumente/readme.txt"
        echo "Weitere Infos unter: https://wiki.archlinux.org/title/Optical_disc_drive" \
            >> "${ziel}/dokumente/readme.txt"
        for i in 1 2 3; do
            dd if=/dev/urandom bs=1K count=64 2>/dev/null | base64 > "${ziel}/bilder/bild_${i}.txt"
        done

        echo
        meldung_ok "Demo-Struktur erstellt:"
        find "$ziel" | sed "s|${ziel}||" | sort | head -20 \
            | while read -r zeile; do
                echo -e "   ${CYAN}${zeile}${RESET}"
            done
        echo
        meldung_info "Das EFI-Boot-Image (${ziel}/boot/grub/efi.img) ist ein Platzhalter."
        meldung_info "Für echte Bootfähigkeit wird ein gültiges GRUB-EFI-Image benötigt."
        echo
        QUELLVERZ="$ziel"
        meldung_ok "Quellverzeichnis auf Demo-Struktur gesetzt: ${FETT}${ziel}${RESET}"
    fi
    warte
}

# ── ISO-Informationen anzeigen ────────────────────────────────────────────────

zeige_iso_info() {
    kopfzeile
    echo -e "  ${FETT}ISO-Datei-Informationen${RESET}"
    echo
    trennlinie
    echo

    read -rp "$(echo -e "  ${PFEIL} Pfad zur ISO-Datei: ")" iso_pfad
    iso_pfad="${iso_pfad/#\~/$HOME}"

    if [[ ! -f "$iso_pfad" ]]; then
        meldung_fehler "Datei '${iso_pfad}' nicht gefunden."
        warte
        return
    fi

    echo
    local groesse_bytes
    groesse_bytes=$(stat -c %s "$iso_pfad" 2>/dev/null || echo 0)
    meldung_info "Dateigröße: $(du -sh "$iso_pfad" | cut -f1) (${groesse_bytes} Bytes)"

    if command -v file &>/dev/null; then
        meldung_info "Dateityp:   $(file -b "$iso_pfad")"
    fi

    if [[ "$TOOL" == "xorriso" ]]; then
        echo
        echo -e "  ${FETT}ISO-Metadaten (xorriso):${RESET}"
        trennlinie_duenn
        xorriso -indev "$iso_pfad" -pvd_info 2>/dev/null \
            | while read -r zeile; do echo -e "   ${zeile}"; done
        echo
        echo -e "  ${FETT}ISO-Inhalt (Root, max. 30 Einträge):${RESET}"
        trennlinie_duenn
        xorriso -indev "$iso_pfad" -ls / 2>/dev/null | head -30 \
            | while read -r zeile; do echo -e "   ${zeile}"; done
    elif command -v isoinfo &>/dev/null; then
        echo
        echo -e "  ${FETT}ISO-Metadaten (isoinfo):${RESET}"
        trennlinie_duenn
        isoinfo -d -i "$iso_pfad" 2>/dev/null \
            | grep -E "^(Volume|Preparer|Publisher|System|Application|Creation|Block)" \
            | while read -r zeile; do echo -e "   ${CYAN}${zeile}${RESET}"; done
    else
        meldung_warnung "Kein Tool zur ISO-Inspektion gefunden (xorriso/isoinfo)."
    fi

    echo
    # Prüfsummen
    echo -e "  ${FETT}Prüfsummen:${RESET}"
    trennlinie_duenn
    if command -v md5sum &>/dev/null; then
        echo -ne "  ${DIM}MD5 wird berechnet...${RESET}\r"
        meldung_info "MD5:    $(md5sum "$iso_pfad" | awk '{print $1}')"
    fi
    if command -v sha256sum &>/dev/null; then
        echo -ne "  ${DIM}SHA256 wird berechnet...${RESET}\r"
        meldung_info "SHA256: $(sha256sum "$iso_pfad" | awk '{print $1}')"
    fi

    warte
}

# ── NEU: ISO-Integrität verifizieren ──────────────────────────────────────────

verifiziere_iso() {
    kopfzeile
    echo -e "  ${FETT}ISO-Integrität verifizieren${RESET}"
    echo
    trennlinie
    echo
    echo -e "${INFO} Prüft die Integrität einer ISO-Datei durch Checksummen-Vergleich"
    echo -e "${INFO} oder durch Lese-Test des gesamten Abbildes."
    echo

    read -rp "$(echo -e "  ${PFEIL} Pfad zur ISO-Datei: ")" iso_pfad
    iso_pfad="${iso_pfad/#\~/$HOME}"

    if [[ ! -f "$iso_pfad" ]]; then
        meldung_fehler "Datei '${iso_pfad}' nicht gefunden."
        warte
        return
    fi

    echo
    echo -e "  ${FETT}Verifikationsmethode:${RESET}"
    echo
    echo -e "  ${CYAN}1)${RESET}  Prüfsumme vergleichen (MD5/SHA256 gegen bekannten Wert)"
    echo -e "  ${CYAN}2)${RESET}  Lese-Test (prüft ob alle Sektoren lesbar sind)"
    echo -e "  ${CYAN}3)${RESET}  ISO-Struktur validieren (benötigt xorriso)"
    echo
    read -rp "$(echo -e "  ${PFEIL} Methode [1-3]: ")" methode

    case "$methode" in
        1)
            echo
            echo -e "  ${FETT}Welchen Algorithmus verwenden?${RESET}"
            echo -e "  ${CYAN}1)${RESET} MD5     ${CYAN}2)${RESET} SHA256"
            read -rp "$(echo -e "  ${PFEIL} Auswahl: ")" algo_wahl

            local algo_cmd="" algo_name=""
            case "$algo_wahl" in
                1) algo_cmd="md5sum"; algo_name="MD5" ;;
                2|*) algo_cmd="sha256sum"; algo_name="SHA256" ;;
            esac

            if ! command -v "$algo_cmd" &>/dev/null; then
                meldung_fehler "${algo_cmd} nicht verfügbar."
                warte
                return
            fi

            echo
            echo -ne "  ${DIM}Berechne ${algo_name}-Prüfsumme...${RESET}\r"
            local berechnete_summe
            berechnete_summe=$("$algo_cmd" "$iso_pfad" | awk '{print $1}')
            echo -e "  ${FETT}Berechnete ${algo_name}:${RESET}"
            echo -e "  ${CYAN}${berechnete_summe}${RESET}"
            echo

            read -rp "$(echo -e "  ${PFEIL} Erwartete Prüfsumme (oder leer zum Überspringen): ")" erwartet

            if [[ -n "$erwartet" ]]; then
                # Leerzeichen und Groß/Klein normalisieren
                erwartet=$(echo "$erwartet" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
                if [[ "$berechnete_summe" == "$erwartet" ]]; then
                    echo
                    meldung_ok "${FETT}Prüfsumme stimmt überein! ISO ist integer.${RESET}"
                else
                    echo
                    meldung_fehler "Prüfsumme stimmt NICHT überein!"
                    meldung_fehler "Erwartet:  ${erwartet}"
                    meldung_fehler "Berechnet: ${berechnete_summe}"
                    echo
                    meldung_warnung "Die Datei könnte beschädigt oder verändert sein."
                fi
            else
                meldung_info "Kein Vergleichswert angegeben. Prüfsumme oben zur manuellen Prüfung."
            fi
            ;;

        2)
            echo
            meldung_info "Starte Lese-Test (liest die gesamte ISO Sektor für Sektor)..."
            echo
            local start_zeit=$SECONDS
            if dd if="$iso_pfad" of=/dev/null bs=1M status=progress 2>&1; then
                local dauer=$(( SECONDS - start_zeit ))
                echo
                meldung_ok "Lese-Test erfolgreich! Alle Sektoren lesbar. (Dauer: $(format_dauer "$dauer"))"
            else
                echo
                meldung_fehler "Lese-Test fehlgeschlagen! Die ISO könnte beschädigt sein."
            fi
            ;;

        3)
            if [[ "$TOOL" != "xorriso" ]]; then
                meldung_fehler "ISO-Strukturvalidierung benötigt xorriso."
                warte
                return
            fi
            echo
            meldung_info "Validiere ISO-Struktur mit xorriso..."
            echo
            if xorriso -indev "$iso_pfad" -check_media 2>&1 | tee -a "$LOG_DATEI"; then
                echo
                meldung_ok "Strukturvalidierung abgeschlossen. Details oben."
            else
                echo
                meldung_fehler "Strukturvalidierung hat Probleme gefunden."
            fi
            ;;

        *)
            meldung_warnung "Ungültige Auswahl."
            ;;
    esac

    warte
}

# ── NEU: Dateien aus ISO extrahieren ──────────────────────────────────────────

extrahiere_aus_iso() {
    kopfzeile
    echo -e "  ${FETT}Dateien aus ISO extrahieren${RESET}"
    echo
    trennlinie
    echo
    echo -e "${INFO} Extrahiert den gesamten Inhalt einer ISO-Datei"
    echo -e "${INFO} in ein Zielverzeichnis."
    echo

    read -rp "$(echo -e "  ${PFEIL} Pfad zur ISO-Datei: ")" iso_pfad
    iso_pfad="${iso_pfad/#\~/$HOME}"

    if [[ ! -f "$iso_pfad" ]]; then
        meldung_fehler "Datei '${iso_pfad}' nicht gefunden."
        warte
        return
    fi

    local iso_name_kurz
    iso_name_kurz=$(basename "$iso_pfad" .iso)
    local standard_ziel
    standard_ziel="$(dirname "$iso_pfad")/${iso_name_kurz}_extrahiert"

    echo
    local ziel_verz
    ziel_verz=$(eingabe_mit_standard "Zielverzeichnis für Extraktion" "$standard_ziel")
    ziel_verz="${ziel_verz/#\~/$HOME}"

    if [[ -d "$ziel_verz" ]]; then
        meldung_warnung "Zielverzeichnis '${ziel_verz}' existiert bereits."
        if ! ja_nein "Inhalte zusammenführen / überschreiben?"; then
            warte
            return
        fi
    fi

    mkdir -p "$ziel_verz"
    echo

    # Extraktion mit verschiedenen Methoden
    local exit_code=0

    if [[ "$TOOL" == "xorriso" ]]; then
        meldung_info "Extrahiere mit xorriso..."
        echo
        xorriso -osirrox on -indev "$iso_pfad" -extract / "$ziel_verz" 2>&1 \
            | tee -a "$LOG_DATEI" &
        local pid=$!
        zeige_fortschritt "$pid"
        wait "$pid" || exit_code=$?
    elif command -v 7z &>/dev/null; then
        meldung_info "Extrahiere mit 7z..."
        echo
        7z x -o"$ziel_verz" "$iso_pfad" -y >> "$LOG_DATEI" 2>&1 &
        local pid=$!
        zeige_fortschritt "$pid"
        wait "$pid" || exit_code=$?
    elif command -v bsdtar &>/dev/null; then
        meldung_info "Extrahiere mit bsdtar..."
        echo
        bsdtar xf "$iso_pfad" -C "$ziel_verz" >> "$LOG_DATEI" 2>&1 &
        local pid=$!
        zeige_fortschritt "$pid"
        wait "$pid" || exit_code=$?
    else
        meldung_fehler "Kein Extraktions-Tool verfügbar (xorriso, 7z, bsdtar)."
        warte
        return
    fi

    echo
    if [[ $exit_code -eq 0 ]]; then
        local dateien_anzahl verz_groesse
        dateien_anzahl=$(find "$ziel_verz" -type f 2>/dev/null | wc -l)
        verz_groesse=$(du -sh "$ziel_verz" 2>/dev/null | cut -f1 || echo "?")
        meldung_ok "${FETT}Extraktion erfolgreich!${RESET}"
        meldung_info "Ziel:     ${ziel_verz}"
        meldung_info "Dateien:  ${dateien_anzahl}"
        meldung_info "Größe:    ${verz_groesse}"
    else
        meldung_fehler "Extraktion fehlgeschlagen (Exit-Code: ${exit_code})."
        meldung_info "Log: ${LOG_DATEI}"
    fi

    warte
}

# ── NEU: Zwei ISOs vergleichen ────────────────────────────────────────────────

vergleiche_isos() {
    kopfzeile
    echo -e "  ${FETT}Zwei ISO-Dateien vergleichen${RESET}"
    echo
    trennlinie
    echo
    echo -e "${INFO} Vergleicht Größe, Prüfsummen und Metadaten zweier ISO-Dateien."
    echo

    read -rp "$(echo -e "  ${PFEIL} Pfad zur ersten ISO:  ")" iso1
    iso1="${iso1/#\~/$HOME}"
    read -rp "$(echo -e "  ${PFEIL} Pfad zur zweiten ISO: ")" iso2
    iso2="${iso2/#\~/$HOME}"

    if [[ ! -f "$iso1" ]]; then
        meldung_fehler "Datei '${iso1}' nicht gefunden."
        warte
        return
    fi
    if [[ ! -f "$iso2" ]]; then
        meldung_fehler "Datei '${iso2}' nicht gefunden."
        warte
        return
    fi

    echo
    echo -e "  ${FETT}Vergleich:${RESET}"
    trennlinie

    # Größe
    local g1 g2
    g1=$(stat -c %s "$iso1" 2>/dev/null || echo 0)
    g2=$(stat -c %s "$iso2" 2>/dev/null || echo 0)
    echo -e "  ${FETT}Größe ISO 1:${RESET}  $(menschliche_groesse "$g1") (${g1} Bytes)"
    echo -e "  ${FETT}Größe ISO 2:${RESET}  $(menschliche_groesse "$g2") (${g2} Bytes)"

    if [[ "$g1" -eq "$g2" ]]; then
        meldung_ok "Dateigröße identisch."
    else
        local diff_bytes=$(( g1 > g2 ? g1 - g2 : g2 - g1 ))
        meldung_warnung "Dateigröße unterschiedlich (Differenz: $(menschliche_groesse "$diff_bytes"))."
    fi
    echo

    # Prüfsummen
    if command -v sha256sum &>/dev/null; then
        echo -ne "  ${DIM}Berechne SHA256 für beide Dateien...${RESET}\r"
        local s1 s2
        s1=$(sha256sum "$iso1" | awk '{print $1}')
        s2=$(sha256sum "$iso2" | awk '{print $1}')
        echo -e "  ${FETT}SHA256 ISO 1:${RESET}  ${DIM}${s1}${RESET}"
        echo -e "  ${FETT}SHA256 ISO 2:${RESET}  ${DIM}${s2}${RESET}"
        if [[ "$s1" == "$s2" ]]; then
            echo
            meldung_ok "${FETT}Die ISOs sind bitgenau identisch!${RESET}"
        else
            echo
            meldung_warnung "Die ISOs sind unterschiedlich."
        fi
    fi

    # Metadaten-Vergleich
    if [[ "$TOOL" == "xorriso" ]]; then
        echo
        echo -e "  ${FETT}Volumen-Labels:${RESET}"
        trennlinie_duenn
        local vol1 vol2
        vol1=$(xorriso -indev "$iso1" -pvd_info 2>/dev/null | grep -i "volume id" | head -1 || echo "unbekannt")
        vol2=$(xorriso -indev "$iso2" -pvd_info 2>/dev/null | grep -i "volume id" | head -1 || echo "unbekannt")
        echo -e "  ISO 1: ${CYAN}${vol1}${RESET}"
        echo -e "  ISO 2: ${CYAN}${vol2}${RESET}"
    fi

    warte
}

# ── NEU: ISO auf USB schreiben ────────────────────────────────────────────────

schreibe_auf_usb() {
    kopfzeile
    echo -e "  ${FETT}ISO auf USB-Stick schreiben${RESET}"
    echo
    trennlinie
    echo
    echo -e "${WARNUNG} ${GELB}${FETT}ACHTUNG: Dieser Vorgang löscht ALLE Daten${RESET}"
    echo -e "${WARNUNG} ${GELB}${FETT}auf dem gewählten Datenträger unwiderruflich!${RESET}"
    echo

    # Prüfe ob root
    if [[ $EUID -ne 0 ]]; then
        meldung_fehler "Dieser Vorgang erfordert Root-Rechte."
        meldung_info "Starte das Skript mit: ${GELB}sudo $0${RESET}"
        echo
        meldung_info "Alternativ kannst du den dd-Befehl manuell als root ausführen:"
        meldung_info "  ${GELB}sudo dd if=DATEI.iso of=/dev/sdX bs=4M status=progress conv=fsync${RESET}"
        warte
        return
    fi

    read -rp "$(echo -e "  ${PFEIL} Pfad zur ISO-Datei: ")" iso_pfad
    iso_pfad="${iso_pfad/#\~/$HOME}"

    if [[ ! -f "$iso_pfad" ]]; then
        meldung_fehler "Datei '${iso_pfad}' nicht gefunden."
        warte
        return
    fi

    echo
    echo -e "  ${FETT}Verfügbare Block-Geräte:${RESET}"
    trennlinie_duenn
    lsblk -d -o NAME,SIZE,TYPE,MODEL,TRAN 2>/dev/null | while read -r zeile; do
        echo -e "   ${zeile}"
    done

    echo
    meldung_warnung "Wähle NUR ein USB-Gerät (z.B. sdb, sdc)!"
    meldung_warnung "NIEMALS deine Systemplatte (meistens sda oder nvme0n1) wählen!"
    echo

    read -rp "$(echo -e "  ${PFEIL} Zielgerät (z.B. sdb): ")" geraet
    geraet="${geraet#/dev/}"
    local geraet_pfad="/dev/${geraet}"

    if [[ ! -b "$geraet_pfad" ]]; then
        meldung_fehler "Gerät '${geraet_pfad}' ist kein gültiges Block-Gerät."
        warte
        return
    fi

    # Sicherheitscheck: Nicht auf Systemplatte schreiben
    local mount_punkt
    mount_punkt=$(findmnt -n -o TARGET "${geraet_pfad}" 2>/dev/null || true)
    if [[ "$mount_punkt" == "/" || "$mount_punkt" == "/boot" || "$mount_punkt" == "/home" ]]; then
        meldung_fehler "ABBRUCH: ${geraet_pfad} ist als '${mount_punkt}' gemountet!"
        meldung_fehler "Das ist wahrscheinlich deine Systemplatte!"
        warte
        return
    fi

    # Prüfe Transport-Typ
    local transport
    transport=$(lsblk -n -d -o TRAN "$geraet_pfad" 2>/dev/null || true)
    if [[ "$transport" != "usb" && -n "$transport" ]]; then
        meldung_warnung "Das Gerät ist kein USB-Gerät (Transport: ${transport})."
        if ! ja_nein "WIRKLICH fortfahren?"; then
            warte
            return
        fi
    fi

    echo
    local geraet_groesse
    geraet_groesse=$(lsblk -n -d -o SIZE "$geraet_pfad" 2>/dev/null || echo "?")
    local iso_groesse
    iso_groesse=$(du -sh "$iso_pfad" | cut -f1)

    echo -e "  ${FETT}${ROT}══════════ LETZTE WARNUNG ══════════${RESET}"
    echo -e "  ${FETT}ISO:${RESET}     ${iso_pfad} (${iso_groesse})"
    echo -e "  ${FETT}Ziel:${RESET}    ${geraet_pfad} (${geraet_groesse})"
    echo -e "  ${FETT}${ROT}ALLE Daten auf ${geraet_pfad} werden gelöscht!${RESET}"
    echo -e "  ${FETT}${ROT}════════════════════════════════════${RESET}"
    echo

    # Doppelte Bestätigung
    if ! ja_nein "Bist du ABSOLUT sicher?"; then
        meldung_info "Abgebrochen. Keine Änderungen vorgenommen."
        warte
        return
    fi

    echo
    read -rp "$(echo -e "  ${PFEIL} Tippe '${ROT}JA WIRKLICH${RESET}' zur endgültigen Bestätigung: ")" bestaetigung
    if [[ "$bestaetigung" != "JA WIRKLICH" ]]; then
        meldung_info "Abgebrochen. Keine Änderungen vorgenommen."
        warte
        return
    fi

    echo
    # Unmount falls gemountet
    if findmnt "${geraet_pfad}"* &>/dev/null; then
        meldung_info "Mounte Partitionen ab..."
        umount "${geraet_pfad}"* 2>/dev/null || true
    fi

    meldung_info "Schreibe ISO auf ${geraet_pfad}..."
    echo
    local start_zeit=$SECONDS

    if dd if="$iso_pfad" of="$geraet_pfad" bs=4M status=progress conv=fsync 2>&1; then
        sync
        local dauer=$(( SECONDS - start_zeit ))
        echo
        meldung_ok "${FETT}ISO erfolgreich auf ${geraet_pfad} geschrieben!${RESET}"
        meldung_info "Dauer: $(format_dauer "$dauer")"
        echo
        meldung_info "Du kannst den USB-Stick jetzt sicher entfernen."
    else
        echo
        meldung_fehler "Fehler beim Schreiben auf ${geraet_pfad}!"
    fi

    warte
}

# ── NEU: Log-Verwaltung ──────────────────────────────────────────────────────

verwalte_logs() {
    kopfzeile
    echo -e "  ${FETT}Log-Dateien verwalten${RESET}"
    echo
    trennlinie
    echo

    local log_anzahl
    log_anzahl=$(find "$LOG_VERZ" -name "iso_erstellen_*.log" -type f 2>/dev/null | wc -l)
    local log_groesse
    log_groesse=$(du -sh "$LOG_VERZ" 2>/dev/null | cut -f1 || echo "0")

    meldung_info "Log-Verzeichnis: ${LOG_VERZ}"
    meldung_info "Anzahl Log-Dateien: ${log_anzahl}"
    meldung_info "Gesamtgröße: ${log_groesse}"
    echo

    if (( log_anzahl == 0 )); then
        meldung_info "Keine Log-Dateien vorhanden."
        warte
        return
    fi

    echo -e "  ${CYAN}1)${RESET}  Letzte Log-Datei anzeigen"
    echo -e "  ${CYAN}2)${RESET}  Alle Log-Dateien auflisten"
    echo -e "  ${CYAN}3)${RESET}  Logs älter als 30 Tage löschen"
    echo -e "  ${CYAN}4)${RESET}  Alle Logs löschen"
    echo -e "  ${CYAN}0)${RESET}  Zurück"
    echo
    read -rp "$(echo -e "  ${PFEIL} Auswahl: ")" auswahl

    case "$auswahl" in
        1)
            local letzte_log
            letzte_log=$(find "$LOG_VERZ" -name "iso_erstellen_*.log" -type f -printf '%T@ %p\n' 2>/dev/null \
                | sort -rn | head -1 | cut -d' ' -f2-)
            if [[ -n "$letzte_log" && -f "$letzte_log" ]]; then
                echo
                echo -e "  ${FETT}Letzte Log-Datei: ${letzte_log}${RESET}"
                trennlinie_duenn
                tail -50 "$letzte_log" | while read -r zeile; do
                    echo -e "   ${DIM}${zeile}${RESET}"
                done
            fi
            ;;
        2)
            echo
            echo -e "  ${FETT}Alle Log-Dateien:${RESET}"
            trennlinie_duenn
            find "$LOG_VERZ" -name "iso_erstellen_*.log" -type f -printf '%T+ %s %p\n' 2>/dev/null \
                | sort -r | while read -r datum groesse pfad; do
                    local name
                    name=$(basename "$pfad")
                    echo -e "   ${DIM}${datum:0:19}${RESET}  ${groesse} Bytes  ${CYAN}${name}${RESET}"
                done
            ;;
        3)
            local alte_logs
            alte_logs=$(find "$LOG_VERZ" -name "iso_erstellen_*.log" -type f -mtime +30 2>/dev/null | wc -l)
            if (( alte_logs > 0 )); then
                if ja_nein "${alte_logs} Logs älter als 30 Tage löschen?"; then
                    find "$LOG_VERZ" -name "iso_erstellen_*.log" -type f -mtime +30 -delete 2>/dev/null
                    meldung_ok "${alte_logs} alte Log-Dateien gelöscht."
                fi
            else
                meldung_info "Keine Logs älter als 30 Tage."
            fi
            ;;
        4)
            if ja_nein "Wirklich ALLE ${log_anzahl} Log-Dateien löschen?"; then
                find "$LOG_VERZ" -name "iso_erstellen_*.log" -type f -delete 2>/dev/null
                meldung_ok "Alle Log-Dateien gelöscht."
            fi
            ;;
        0|*) return ;;
    esac

    warte
}

# ── NEU: Verzeichnisstruktur einer ISO anzeigen (Baumansicht) ─────────────────

zeige_iso_baum() {
    kopfzeile
    echo -e "  ${FETT}ISO-Inhalt als Baumstruktur anzeigen${RESET}"
    echo
    trennlinie
    echo
    echo -e "${INFO} Zeigt die vollständige Verzeichnisstruktur innerhalb einer ISO."
    echo

    read -rp "$(echo -e "  ${PFEIL} Pfad zur ISO-Datei: ")" iso_pfad
    iso_pfad="${iso_pfad/#\~/$HOME}"

    if [[ ! -f "$iso_pfad" ]]; then
        meldung_fehler "Datei '${iso_pfad}' nicht gefunden."
        warte
        return
    fi

    echo
    local max_tiefe
    max_tiefe=$(eingabe_mit_standard "Maximale Anzeigetiefe" "3")

    echo
    echo -e "  ${FETT}Verzeichnisbaum von: $(basename "$iso_pfad")${RESET}"
    trennlinie

    if [[ "$TOOL" == "xorriso" ]]; then
        xorriso -indev "$iso_pfad" -find / -maxdepth "$max_tiefe" -exec report_lba 2>/dev/null \
            | head -100 \
            | while IFS= read -r zeile; do
                # Einrückung basierend auf Pfadtiefe
                local tiefe
                tiefe=$(echo "$zeile" | tr -cd '/' | wc -c)
                local einrueckung=""
                for ((i=0; i<tiefe; i++)); do einrueckung+="  "; done
                local name
                name=$(basename "$zeile" 2>/dev/null || echo "$zeile")
                if [[ "$zeile" == */ ]]; then
                    echo -e "   ${einrueckung}${CYAN}📁 ${name}${RESET}"
                else
                    echo -e "   ${einrueckung}${DIM}📄 ${name}${RESET}"
                fi
            done
    elif command -v isoinfo &>/dev/null; then
        isoinfo -l -i "$iso_pfad" 2>/dev/null | head -80 \
            | while IFS= read -r zeile; do
                if [[ "$zeile" == *"Directory listing"* ]]; then
                    echo -e "   ${CYAN}${FETT}${zeile}${RESET}"
                else
                    echo -e "   ${DIM}${zeile}${RESET}"
                fi
            done
    else
        meldung_fehler "Kein geeignetes Tool (xorriso, isoinfo) verfügbar."
    fi

    echo
    meldung_info "(Anzeige auf max. 100 Einträge begrenzt)"
    warte
}

# ── NEU: Prüfsummen-Datei erzeugen ───────────────────────────────────────────

erzeuge_pruefsummen_datei() {
    kopfzeile
    echo -e "  ${FETT}Prüfsummen-Datei erzeugen${RESET}"
    echo
    trennlinie
    echo
    echo -e "${INFO} Erstellt eine .sha256- oder .md5-Datei neben der ISO."
    echo -e "${INFO} Diese Datei kann zur späteren Verifikation verwendet werden."
    echo

    read -rp "$(echo -e "  ${PFEIL} Pfad zur ISO-Datei: ")" iso_pfad
    iso_pfad="${iso_pfad/#\~/$HOME}"

    if [[ ! -f "$iso_pfad" ]]; then
        meldung_fehler "Datei '${iso_pfad}' nicht gefunden."
        warte
        return
    fi

    echo
    echo -e "  ${CYAN}1)${RESET}  SHA256 (empfohlen)"
    echo -e "  ${CYAN}2)${RESET}  MD5"
    echo -e "  ${CYAN}3)${RESET}  Beide"
    echo
    read -rp "$(echo -e "  ${PFEIL} Auswahl: ")" auswahl

    local algos=()
    case "$auswahl" in
        1)   algos=("sha256sum") ;;
        2)   algos=("md5sum") ;;
        3|*) algos=("sha256sum" "md5sum") ;;
    esac

    echo

    for algo in "${algos[@]}"; do
        if ! command -v "$algo" &>/dev/null; then
            meldung_fehler "${algo} nicht verfügbar."
            continue
        fi

        local ext
        case "$algo" in
            sha256sum) ext="sha256" ;;
            md5sum)    ext="md5" ;;
        esac

        local checksummen_datei="${iso_pfad}.${ext}"

        echo -ne "  ${DIM}Berechne ${ext^^}...${RESET}\r"
        (cd "$(dirname "$iso_pfad")" && "$algo" "$(basename "$iso_pfad")") > "$checksummen_datei"
        meldung_ok "${ext^^}-Datei erstellt: ${checksummen_datei}"
        echo -e "  ${DIM}Inhalt: $(cat "$checksummen_datei")${RESET}"
        echo
    done

    meldung_info "Die Prüfsummen-Datei(en) können mit '${GELB}sha256sum -c datei.sha256${RESET}' geprüft werden."

    warte
}

# ── Auswertung nach der Erstellung ───────────────────────────────────────────

auswertung_erstellen() {
    local code=$1
    echo
    trennlinie

    if [[ $code -eq 0 ]] && [[ -f "$ISO_ZIEL" ]]; then
        local groesse
        groesse=$(du -sh "$ISO_ZIEL" 2>/dev/null | cut -f1 || echo "?")
        meldung_ok "${FETT}ISO erfolgreich erstellt!${RESET}"
        echo
        echo -e "  ${FETT}Pfad:${RESET}   ${ISO_ZIEL}"
        echo -e "  ${FETT}Größe:${RESET}  ${groesse}"
        echo

        if command -v sha256sum &>/dev/null; then
            meldung_info "SHA256: $(sha256sum "$ISO_ZIEL" | awk '{print $1}')"
        fi
        echo
        meldung_info "Log-Datei: ${LOG_DATEI}"

        # Nachfolge-Aktionen anbieten
        echo
        trennlinie_duenn
        echo -e "  ${FETT}Nächste Schritte:${RESET}"
        echo -e "  ${CYAN}1)${RESET}  Prüfsummen-Datei erzeugen"
        echo -e "  ${CYAN}2)${RESET}  ISO-Informationen anzeigen"
        echo -e "  ${CYAN}3)${RESET}  Zurück zum Hauptmenü"
        echo
        read -rp "$(echo -e "  ${PFEIL} Auswahl [3]: ")" folge_aktion
        case "${folge_aktion:-3}" in
            1)
                local temp_pfad="$iso_pfad"
                iso_pfad="$ISO_ZIEL"  # Für die Prüfsummen-Funktion
                # Inline SHA256
                local checksummen_datei="${ISO_ZIEL}.sha256"
                (cd "$(dirname "$ISO_ZIEL")" && sha256sum "$(basename "$ISO_ZIEL")") > "$checksummen_datei"
                meldung_ok "SHA256-Datei erstellt: ${checksummen_datei}"
                ;;
            2)
                local temp_iso_pfad="$ISO_ZIEL"
                # Zeige Infos inline
                echo
                if [[ "$TOOL" == "xorriso" ]]; then
                    xorriso -indev "$temp_iso_pfad" -ls / 2>/dev/null | head -20 \
                        | while read -r zeile; do echo -e "   ${zeile}"; done
                fi
                ;;
        esac
    else
        meldung_fehler "ISO-Erstellung fehlgeschlagen (Exit-Code: ${code})!"
        echo
        meldung_info "Letzte Log-Zeilen:"
        echo
        tail -20 "$LOG_DATEI" 2>/dev/null | while read -r zeile; do
            echo -e "   ${ROT}${zeile}${RESET}"
        done
        echo
        meldung_info "Vollständiges Log: ${LOG_DATEI}"

        # Hilfreiche Tipps bei Fehlern
        echo
        trennlinie_duenn
        echo -e "  ${FETT}Häufige Fehlerursachen:${RESET}"
        echo -e "  ${DIM}• Unzureichender Speicherplatz${RESET}"
        echo -e "  ${DIM}• Fehlende Berechtigungen im Quell- oder Zielverzeichnis${RESET}"
        echo -e "  ${DIM}• Zu lange Dateinamen (>255 Zeichen)${RESET}"
        echo -e "  ${DIM}• Symbolische Links, die ins Leere zeigen${RESET}"
        echo -e "  ${DIM}• Sonderzeichen in Dateinamen${RESET}"
    fi

    warte
}

# ── Über / Hilfe ──────────────────────────────────────────────────────────────

zeige_hilfe() {
    kopfzeile
    echo -e "  ${FETT}Hilfe & Informationen${RESET}"
    echo
    trennlinie
    cat <<HILFE

  ${FETT}NORMALE ISO${RESET}
  ──────────────────────────────────────────────────────────
  Erstellt eine ISO 9660-Datei (mit Rock Ridge und Joliet).
  • Rock Ridge: Lange Dateinamen, Unix-Berechtigungen
  • Joliet:     Windows-Kompatibilität (lange Namen)
  Geeignet für: Datensicherung, Software-Verteilung,
  virtuelle Maschinen.

  ${FETT}BOOTFÄHIGE EFI ISO${RESET}
  ──────────────────────────────────────────────────────────
  Erstellt eine EFI-bootfähige ISO (UEFI-Standard).
  Benötigt ein EFI-Boot-Image (efi.img / efiboot.img).
  Optional: Legacy-BIOS-Boot via isolinux.
  Geeignet für: Installations-Medien, Live-Systeme.

  ${FETT}ISO VERIFIZIEREN${RESET}
  ──────────────────────────────────────────────────────────
  Prüft die Integrität einer ISO-Datei:
  • Checksummen-Vergleich (MD5/SHA256)
  • Sektorweiser Lese-Test (findet defekte Blöcke)
  • Strukturvalidierung (prüft ISO-9660-Konformität)

  ${FETT}DATEIEN EXTRAHIEREN${RESET}
  ──────────────────────────────────────────────────────────
  Entpackt den Inhalt einer ISO in ein Verzeichnis.
  Nutzt xorriso, 7z oder bsdtar als Backend.

  ${FETT}ISO AUF USB SCHREIBEN${RESET}
  ──────────────────────────────────────────────────────────
  Schreibt eine ISO bitgenau auf einen USB-Stick.
  Inklusive Sicherheitsprüfungen gegen versehentliches
  Überschreiben der Systemplatte.
  Erfordert Root-Rechte (sudo).

  ${FETT}VORAUSSETZUNGEN${RESET}
  ──────────────────────────────────────────────────────────
  • xorriso   (empfohlen)  oder  genisoimage / mkisofs
  • Optional: 7z, isoinfo, rsync, md5sum, sha256sum

  ${FETT}TASTENKÜRZEL${RESET}
  ──────────────────────────────────────────────────────────
  • Ctrl+C    Aktuellen Vorgang abbrechen
  • 0, q, Q   Programm beenden
  • Enter     Standardwert übernehmen

  ${FETT}KONFIGURATION${RESET}
  ──────────────────────────────────────────────────────────
  • Logs:     ${LOG_VERZ}
  • Version:  ${VERSION}

HILFE
    trennlinie
    warte
}

# ── Hauptmenü ─────────────────────────────────────────────────────────────────

hauptmenue() {
    while true; do
        kopfzeile
        echo -e "  ${FETT}Hauptmenü${RESET}"
        echo
        trennlinie
        echo
        echo -e "  ${MAGENTA}── ISO erstellen ──${RESET}"
        echo -e "  ${CYAN}1)${RESET}  ${FETT}Normale ISO erstellen${RESET}"
        echo -e "      Standard-ISO aus einem Verzeichnis (Rock Ridge + Joliet)"
        echo
        echo -e "  ${CYAN}2)${RESET}  ${FETT}Bootfähige ISO erstellen (EFI / UEFI)${RESET}"
        echo -e "      ISO mit EFI-Boot-Support, optional + Legacy-BIOS"
        echo
        echo -e "  ${MAGENTA}── ISO verwalten ──${RESET}"
        echo -e "  ${CYAN}3)${RESET}  ${FETT}ISO-Datei inspizieren${RESET}"
        echo -e "      Metadaten, Inhalt und Prüfsummen einer ISO anzeigen"
        echo
        echo -e "  ${CYAN}4)${RESET}  ${FETT}ISO-Inhalt als Baumstruktur${RESET}"
        echo -e "      Verzeichnisstruktur innerhalb einer ISO anzeigen"
        echo
        echo -e "  ${CYAN}5)${RESET}  ${FETT}ISO-Integrität verifizieren${RESET}"
        echo -e "      Checksummen prüfen, Lese-Test, Strukturvalidierung"
        echo
        echo -e "  ${CYAN}6)${RESET}  ${FETT}Zwei ISOs vergleichen${RESET}"
        echo -e "      Größe, Prüfsummen und Metadaten zweier ISOs vergleichen"
        echo
        echo -e "  ${MAGENTA}── Werkzeuge ──${RESET}"
        echo -e "  ${CYAN}7)${RESET}  ${FETT}Dateien aus ISO extrahieren${RESET}"
        echo -e "      Gesamten Inhalt einer ISO in ein Verzeichnis entpacken"
        echo
        echo -e "  ${CYAN}8)${RESET}  ${FETT}ISO auf USB-Stick schreiben${RESET}"
        echo -e "      Bootfähigen USB-Stick erstellen (erfordert Root)"
        echo
        echo -e "  ${CYAN}9)${RESET}  ${FETT}Prüfsummen-Datei erzeugen${RESET}"
        echo -e "      .sha256/.md5 Datei für sichere Weitergabe erstellen"
        echo
        echo -e "  ${MAGENTA}── System ──${RESET}"
        echo -e "  ${CYAN}d)${RESET}  ${FETT}Demo-Verzeichnisstruktur erstellen${RESET}"
        echo -e "      Teststruktur zum Ausprobieren generieren"
        echo
        echo -e "  ${CYAN}l)${RESET}  ${FETT}Log-Dateien verwalten${RESET}"
        echo -e "      Logs anzeigen, aufräumen, löschen"
        echo
        echo -e "  ${CYAN}h)${RESET}  ${FETT}Hilfe${RESET}"
        echo
        echo -e "  ${CYAN}0)${RESET}  ${ROT}Beenden${RESET}"
        echo
        trennlinie
        echo

        read -rp "$(echo -e "  ${PFEIL} Auswahl: ")" auswahl

        case "$auswahl" in
            1) erstelle_normale_iso ;;
            2) erstelle_efi_iso ;;
            3) zeige_iso_info ;;
            4) zeige_iso_baum ;;
            5) verifiziere_iso ;;
            6) vergleiche_isos ;;
            7) extrahiere_aus_iso ;;
            8) schreibe_auf_usb ;;
            9) erzeuge_pruefsummen_datei ;;
            d|D) erstelle_demo_struktur ;;
            l|L) verwalte_logs ;;
            h|H) zeige_hilfe ;;
            0|q|Q|exit|quit)
                echo
                meldung_ok "Auf Wiedersehen!"
                echo
                exit 0
                ;;
            *)
                meldung_warnung "Ungültige Eingabe: '${auswahl}'."
                sleep 1
                ;;
        esac
    done
}

# ── Einstiegspunkt ────────────────────────────────────────────────────────────

# Bash-Version prüfen
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Fehler: Bash 4.0 oder neuer wird benötigt (aktuell: $BASH_VERSION)."
    exit 1
fi

pruefe_abhaengigkeiten
hauptmenue
