#!/usr/bin/env bash
# ==============================================================================
#  iso_erstellen.sh — ISO-Erstellungs-Assistent
#  Erstellt normale und bootfähige (EFI) ISO-Dateien aus Verzeichnissen.
#
#  Abhängigkeiten: genisoimage oder xorriso (wird automatisch geprüft)
#  Getestet auf:   Debian/Ubuntu, Arch, Fedora, openSUSE
# ==============================================================================

set -euo pipefail

# ── Farben & Symbole ──────────────────────────────────────────────────────────
ROT='\033[0;31m'
GRUEN='\033[0;32m'
GELB='\033[1;33m'
BLAU='\033[0;34m'
CYAN='\033[0;36m'
FETT='\033[1m'
RESET='\033[0m'

OK="  ${GRUEN}✔${RESET}"
FEHLER="  ${ROT}✘${RESET}"
INFO="  ${BLAU}ℹ${RESET}"
WARNUNG="  ${GELB}⚠${RESET}"
PFEIL="  ${CYAN}➜${RESET}"

# ── Globale Variablen ─────────────────────────────────────────────────────────
TOOL=""          # genisoimage oder xorriso
QUELLVERZ=""
ISO_ZIEL=""
ISO_NAME="ausgabe.iso"
VOLUMEN_NAME="MEIN_ISO"
LOG_DATEI="/tmp/iso_erstellen_$(date +%Y%m%d_%H%M%S).log"

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────

trennlinie() {
    echo -e "${BLAU}$(printf '─%.0s' {1..60})${RESET}"
}

kopfzeile() {
    clear
    echo
    trennlinie
    echo -e "  ${FETT}${CYAN}🗂  ISO-Erstellungs-Assistent${RESET}"
    echo -e "  ${GELB}$(date '+%d.%m.%Y %H:%M:%S')${RESET}"
    trennlinie
    echo
}

pause() {
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

    # mkisofs als alias für genisoimage?
    if [[ "$TOOL" == "" ]] && command -v mkisofs &>/dev/null; then
        TOOL="mkisofs"
        meldung_ok "mkisofs gefunden (Fallback)"
    fi

    # du, df prüfen
    command -v du &>/dev/null && meldung_ok "du (Größenberechnung) verfügbar" \
        || meldung_warnung "du nicht gefunden – Größenangaben nicht möglich"
    command -v df &>/dev/null && meldung_ok "df (Speicherplatz) verfügbar" \
        || meldung_warnung "df nicht gefunden"

    echo
    if [[ $fehler -eq 1 ]]; then
        meldung_fehler "Kritische Abhängigkeiten fehlen. Das Skript wird beendet."
        exit 1
    fi

    meldung_ok "Alle Abhängigkeiten erfüllt. Tool: ${FETT}${TOOL}${RESET}"
    pause
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
            local groesse
            groesse=$(du -sh "$QUELLVERZ" 2>/dev/null | cut -f1 || echo "unbekannt")
            echo
            meldung_ok "Verzeichnis: ${FETT}${QUELLVERZ}${RESET}"
            meldung_info "Größe:       ${groesse}"
            meldung_info "Dateien:     $(find "$QUELLVERZ" -type f | wc -l) Dateien"
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
            pause
            return 1
        fi
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
            pause
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
    trennlinie
    echo
}

# ── Fortschrittsanzeige ───────────────────────────────────────────────────────

zeige_fortschritt() {
    local pid=$1
    local spin=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    echo -ne "  ${CYAN}"
    while kill -0 "$pid" 2>/dev/null; do
        echo -ne "\r  ${CYAN}${spin[$i]}${RESET} ISO wird erstellt... "
        i=$(( (i + 1) % 10 ))
        sleep 0.1
    done
    echo -ne "\r  ${GRUEN}✔${RESET} Vorgang abgeschlossen.        \n"
}

# ── Normale ISO erstellen ─────────────────────────────────────────────────────

erstelle_normale_iso() {
    waehle_quellverzeichnis || return
    waehle_ausgabe          || return
    zeige_zusammenfassung "Normale ISO (Rock Ridge + Joliet)"

    ja_nein "ISO jetzt erstellen?" || { meldung_info "Abgebrochen."; pause; return; }

    echo
    meldung_info "Erstelle ISO... (Log: ${LOG_DATEI})"
    echo

    local exit_code=0

    if [[ "$TOOL" == "xorriso" ]]; then
        xorriso -as mkisofs \
            -o "$ISO_ZIEL" \
            -V "$VOLUMEN_NAME" \
            -r -J \
            -joliet-long \
            "$QUELLVERZ" \
            >> "$LOG_DATEI" 2>&1 &
    else
        "$TOOL" \
            -o "$ISO_ZIEL" \
            -V "$VOLUMEN_NAME" \
            -r -J \
            -joliet-long \
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
            pause
            return 1
        fi

        if [[ ! -f "$efi_eingabe" ]]; then
            meldung_fehler "Datei '${efi_eingabe}' nicht gefunden."
            pause
            return 1
        fi
        efi_pfad="$efi_eingabe"
        meldung_ok "EFI-Boot-Image: ${efi_pfad}"
    fi

    # Relativen Pfad zum EFI-Image berechnen
    local efi_relativ
    efi_relativ="${efi_pfad#"${QUELLVERZ}/"}"

    waehle_ausgabe || return

    # BIOS-Kompatibilität (Legacy-Boot)?
    echo
    local legacy_boot=false
    local isolinux_pfad=""
    if ja_nein "Auch Legacy-BIOS-Boot (isolinux) einbinden, falls vorhanden?"; then
        # isolinux.bin suchen
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

    ja_nein "ISO jetzt erstellen?" || { meldung_info "Abgebrochen."; pause; return; }

    echo
    meldung_info "Erstelle EFI-bootfähige ISO... (Log: ${LOG_DATEI})"
    echo

    local exit_code=0

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
                "$QUELLVERZ" \
                >> "$LOG_DATEI" 2>&1 &
        fi
    else
        # genisoimage / mkisofs (kein isohybrid-gpt, nur Basis-EFI)
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
                "$QUELLVERZ" \
                >> "$LOG_DATEI" 2>&1 &
        else
            "$TOOL" \
                -o "$ISO_ZIEL" \
                -V "$VOLUMEN_NAME" \
                -r -J -joliet-long \
                -e "${efi_relativ}" \
                -no-emul-boot \
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
    pause
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
        pause
        return
    fi

    echo
    meldung_info "Dateigröße: $(du -sh "$iso_pfad" | cut -f1)"

    if command -v file &>/dev/null; then
        meldung_info "Dateityp:   $(file "$iso_pfad")"
    fi

    if [[ "$TOOL" == "xorriso" ]]; then
        echo
        echo -e "  ${FETT}ISO-Inhalt (xorriso):${RESET}"
        trennlinie
        xorriso -indev "$iso_pfad" -ls / 2>/dev/null | head -30 \
            | while read -r zeile; do echo -e "   ${zeile}"; done
    elif command -v isoinfo &>/dev/null; then
        echo
        echo -e "  ${FETT}ISO-Inhalt (isoinfo):${RESET}"
        trennlinie
        isoinfo -d -i "$iso_pfad" 2>/dev/null | grep -E "^(Volume|Preparer|Publisher|System)" \
            | while read -r zeile; do echo -e "   ${CYAN}${zeile}${RESET}"; done
    else
        meldung_warnung "Kein Tool zur ISO-Inspektion gefunden (xorriso/isoinfo)."
    fi

    echo
    # MD5-Prüfsumme
    if command -v md5sum &>/dev/null; then
        meldung_info "MD5:   $(md5sum "$iso_pfad" | awk '{print $1}')"
    fi
    if command -v sha256sum &>/dev/null; then
        meldung_info "SHA256: $(sha256sum "$iso_pfad" | awk '{print $1}')"
    fi

    pause
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
    fi

    pause
}

# ── Über / Hilfe ──────────────────────────────────────────────────────────────

zeige_hilfe() {
    kopfzeile
    echo -e "  ${FETT}Hilfe & Informationen${RESET}"
    echo
    trennlinie
    cat <<'HILFE'

  NORMALE ISO
  ──────────────────────────────────────────────────────────
  Erstellt eine ISO 9660-Datei (mit Rock Ridge und Joliet).
  • Rock Ridge: Lange Dateinamen, Unix-Berechtigungen
  • Joliet:     Windows-Kompatibilität (lange Namen)
  Geeignet für: Datensicherung, Software-Verteilung,
  virtuelle Maschinen.

  BOOTFÄHIGE EFI ISO
  ──────────────────────────────────────────────────────────
  Erstellt eine EFI-bootfähige ISO (UEFI-Standard).
  Benötigt ein EFI-Boot-Image (efi.img / efiboot.img).
  Optional: Legacy-BIOS-Boot via isolinux.
  Geeignet für: Installations-Medien, Live-Systeme.

  VORAUSSETZUNGEN
  ──────────────────────────────────────────────────────────
  • xorriso   (empfohlen)
  • genisoimage / mkisofs (Alternative)

  HINWEISE
  ──────────────────────────────────────────────────────────
  • Das EFI-Boot-Image muss im Quellverzeichnis liegen.
  • Für echte Boot-Medien wird ein gültiger Bootloader
    (z. B. GRUB, systemd-boot) benötigt.
  • ISO-Dateien können mit 'dd' oder Balena Etcher auf
    USB-Sticks geschrieben werden.

HILFE
    trennlinie
    pause
}

# ── Hauptmenü ─────────────────────────────────────────────────────────────────

hauptmenue() {
    while true; do
        kopfzeile
        echo -e "  ${FETT}Hauptmenü${RESET}"
        echo
        trennlinie
        echo
        echo -e "  ${CYAN}1)${RESET}  ${FETT}Normale ISO erstellen${RESET}"
        echo -e "      Standard-ISO aus einem Verzeichnis (Rock Ridge + Joliet)"
        echo
        echo -e "  ${CYAN}2)${RESET}  ${FETT}Bootfähige ISO erstellen (EFI / UEFI)${RESET}"
        echo -e "      ISO mit EFI-Boot-Support, optional + Legacy-BIOS"
        echo
        echo -e "  ${CYAN}3)${RESET}  ${FETT}Demo-Verzeichnisstruktur erstellen${RESET}"
        echo -e "      Teststruktur zum Ausprobieren generieren"
        echo
        echo -e "  ${CYAN}4)${RESET}  ${FETT}ISO-Datei inspizieren${RESET}"
        echo -e "      Informationen, Inhalt und Prüfsummen einer ISO anzeigen"
        echo
        echo -e "  ${CYAN}5)${RESET}  ${FETT}Hilfe${RESET}"
        echo
        echo -e "  ${CYAN}0)${RESET}  ${ROT}Beenden${RESET}"
        echo
        trennlinie
        echo

        read -rp "$(echo -e "  ${PFEIL} Auswahl: ")" auswahl

        case "$auswahl" in
            1) erstelle_normale_iso ;;
            2) erstelle_efi_iso ;;
            3) erstelle_demo_struktur ;;
            4) zeige_iso_info ;;
            5) zeige_hilfe ;;
            0|q|Q|exit|quit)
                echo
                meldung_ok "Auf Wiedersehen!"
                echo
                exit 0
                ;;
            *)
                meldung_warnung "Ungültige Eingabe: '${auswahl}'. Bitte 0–5 eingeben."
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
