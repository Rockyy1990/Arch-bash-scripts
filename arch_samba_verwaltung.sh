#!/bin/bash
# ==============================================================================
# Samba Verwaltungsskript für Arch Linux
# Autor: optimiert & erweitert
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Farben & Hilfsfunktionen
# ------------------------------------------------------------------------------
ROT='\033[0;31m'
GRUEN='\033[0;32m'
GELB='\033[1;33m'
BLAU='\033[1;34m'
CYAN='\033[0;36m'
FETT='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BLAU}[INFO]${RESET}  $*"; }
erfolg() { echo -e "${GRUEN}[OK]${RESET}    $*"; }
warnung() { echo -e "${GELB}[WARN]${RESET}  $*"; }
fehler()  { echo -e "${ROT}[FEHLER]${RESET} $*" >&2; }

pause() { echo; read -rp "$(echo -e "${CYAN}Drücke Enter, um fortzufahren...${RESET}")" _; }

# Root-Check
root_check() {
    if [[ $EUID -ne 0 ]]; then
        fehler "Dieses Skript muss als root oder mit sudo ausgeführt werden."
        exit 1
    fi
}

# Prüfe ob ein Befehl verfügbar ist
befehl_vorhanden() {
    command -v "$1" &>/dev/null
}

# Dienste sicher neu starten
dienste_neustarten() {
    info "Starte Samba-Dienste neu..."
    local fehler_aufgetreten=0
    for dienst in smb nmb; do
        if systemctl is-enabled "$dienst" &>/dev/null || systemctl is-active "$dienst" &>/dev/null; then
            if systemctl restart "$dienst"; then
                erfolg "Dienst '$dienst' neu gestartet."
            else
                fehler "Dienst '$dienst' konnte nicht neu gestartet werden."
                fehler_aufgetreten=1
            fi
        else
            warnung "Dienst '$dienst' ist nicht aktiv/aktiviert – wird übersprungen."
        fi
    done
    return $fehler_aufgetreten
}

# Konfiguration mit testparm validieren
config_validieren() {
    info "Prüfe Samba-Konfiguration mit testparm..."
    if testparm -s /etc/samba/smb.conf &>/dev/null; then
        erfolg "Konfigurationssyntax ist korrekt."
        return 0
    else
        fehler "Fehler in der smb.conf! Bitte prüfen:"
        testparm -s /etc/samba/smb.conf 2>&1 | head -20
        return 1
    fi
}

# Prüfe ob ein Share-Name bereits in der Config existiert
share_existiert() {
    local name="$1"
    grep -q "^\[${name}\]" /etc/samba/smb.conf 2>/dev/null
}

# ------------------------------------------------------------------------------
# 1) Samba installieren / überprüfen
# ------------------------------------------------------------------------------
install_samba() {
    echo -e "\n${FETT}=== Samba Installation ===${RESET}"
    if pacman -Qs samba &>/dev/null; then
        erfolg "Samba ist bereits installiert."
        pacman -Qi samba | grep -E "^(Name|Version)" | awk '{print "    " $0}'
    else
        info "Samba ist nicht installiert. Starte Installation..."
        if pacman -S --noconfirm samba; then
            erfolg "Samba wurde erfolgreich installiert."
        else
            fehler "Installation fehlgeschlagen."
            return 1
        fi
    fi

    # smb.conf anlegen falls nicht vorhanden
    if [[ ! -f /etc/samba/smb.conf ]]; then
        warnung "Keine smb.conf gefunden. Erstelle Standard-Konfiguration..."
        mkdir -p /etc/samba
        cp /etc/samba/smb.conf.default /etc/samba/smb.conf 2>/dev/null \
            || touch /etc/samba/smb.conf
        erfolg "Leere smb.conf angelegt."
    fi

    # Dienste aktivieren
    info "Aktiviere und starte Samba-Dienste..."
    for dienst in smb nmb; do
        systemctl enable --now "$dienst" && erfolg "$dienst aktiviert." \
            || warnung "$dienst konnte nicht aktiviert werden."
    done
}

# ------------------------------------------------------------------------------
# 2) Backup erstellen
# ------------------------------------------------------------------------------
backup_config() {
    local backup_pfad="/etc/samba/smb.conf.bak_$(date +%F_%H-%M-%S)"
    if [[ ! -f /etc/samba/smb.conf ]]; then
        fehler "Keine smb.conf vorhanden – Backup nicht möglich."
        return 1
    fi
    if cp /etc/samba/smb.conf "$backup_pfad"; then
        erfolg "Backup erstellt: $backup_pfad"
    else
        fehler "Backup fehlgeschlagen."
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 3) Konfiguration optimieren
# ------------------------------------------------------------------------------
optimiere_config() {
    echo -e "\n${FETT}=== Konfiguration optimieren ===${RESET}"

    # Hostname für netbios name
    local hostname
    hostname=$(hostname)

    backup_config || return 1
    info "Schreibe optimierte smb.conf..."

    cat > /etc/samba/smb.conf <<EOL
[global]
    server string = Samba Server %v
    workgroup = WORKGROUP
    netbios name = ${hostname^^}
    security = user
    server role = standalone server
    map to guest = Bad User
    guest account = nobody
    dns proxy = no

    # Logging
    log file = /var/log/samba/log.%m
    max log size = 1000
    logging = file

    # Performance
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=131072 SO_SNDBUF=131072
    read raw = yes
    write raw = yes
    use sendfile = yes

    # Druckerfreigabe (CUPS)
    printing = cups
    printcap name = cups
    load printers = yes
    cups options = raw

# Eigene Freigaben werden unterhalb dieser Zeile ergänzt
EOL

    if config_validieren; then
        erfolg "smb.conf wurde erfolgreich aktualisiert."
        dienste_neustarten
    else
        fehler "Konfiguration enthält Fehler. Backup wird wiederhergestellt..."
        local letztes_backup
        letztes_backup=$(ls -t /etc/samba/smb.conf.bak_* 2>/dev/null | head -1)
        [[ -n "$letztes_backup" ]] && cp "$letztes_backup" /etc/samba/smb.conf \
            && warnung "Backup wiederhergestellt: $letztes_backup"
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 4) Freigabe mit Passwort erstellen
# ------------------------------------------------------------------------------
freigabe_mit_passwort() {
    echo -e "\n${FETT}=== Freigabe mit Passwort erstellen ===${RESET}"

    # Eingabe: Freigabename
    while true; do
        read -rp "Name der Freigabe (z.B. 'dokumente'): " freigabename
        [[ -n "$freigabename" ]] || { warnung "Name darf nicht leer sein."; continue; }
        if share_existiert "$freigabename"; then
            fehler "Eine Freigabe mit dem Namen '[$freigabename]' existiert bereits in der smb.conf."
            return 1
        fi
        break
    done

    # Eingabe: Pfad
    while true; do
        read -rp "Pfad zum Verzeichnis (z.B. '/srv/samba/dokumente'): " freigabepfad
        [[ "$freigabepfad" == /* ]] || { warnung "Bitte absoluten Pfad angeben (beginnt mit /)."; continue; }
        break
    done

    # Eingabe: Benutzer
    while true; do
        read -rp "Systembenutzer für diese Freigabe: " benutzer
        if ! id "$benutzer" &>/dev/null; then
            fehler "Systembenutzer '$benutzer' existiert nicht."
            continue
        fi
        break
    done

    # Eingabe: Schreibrecht
    read -rp "Schreibzugriff erlauben? [J/n]: " schreiben
    local readonly_wert="no"
    [[ "${schreiben,,}" == "n" ]] && readonly_wert="yes"

    # Verzeichnis erstellen und Rechte setzen
    mkdir -p "$freigabepfad"
    local gruppe
    gruppe=$(id -gn "$benutzer")
    chown -R "$benutzer":"$gruppe" "$freigabepfad"
    chmod 770 "$freigabepfad"
    erfolg "Verzeichnis '$freigabepfad' erstellt und Rechte gesetzt."

    # Samba-Benutzer anlegen/prüfen
    if ! pdbedit -L 2>/dev/null | grep -qw "^${benutzer}:"; then
        info "Samba-Passwort für Benutzer '$benutzer' festlegen:"
        smbpasswd -a "$benutzer" || { fehler "Samba-Benutzer konnte nicht angelegt werden."; return 1; }
    else
        info "Samba-Benutzer '$benutzer' ist bereits vorhanden."
    fi

    # Config ergänzen
    cat >> /etc/samba/smb.conf <<EOL

[$freigabename]
    comment = Freigabe $freigabename
    path = $freigabepfad
    valid users = $benutzer
    read only = $readonly_wert
    browseable = yes
    create mask = 0660
    directory mask = 0770
EOL

    if config_validieren; then
        dienste_neustarten
        erfolg "Freigabe '[$freigabename]' mit Passwort erfolgreich erstellt."
    else
        fehler "Konfigurationsfehler – Freigabe wurde nicht aktiviert."
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 5) Gast-Freigabe erstellen
# ------------------------------------------------------------------------------
freigabe_gast() {
    echo -e "\n${FETT}=== Gast-Freigabe erstellen ===${RESET}"

    while true; do
        read -rp "Name der Gast-Freigabe (z.B. 'oeffentlich'): " freigabename
        [[ -n "$freigabename" ]] || { warnung "Name darf nicht leer sein."; continue; }
        if share_existiert "$freigabename"; then
            fehler "Eine Freigabe '[$freigabename]' existiert bereits."
            return 1
        fi
        break
    done

    while true; do
        read -rp "Pfad zum Verzeichnis (z.B. '/srv/samba/gast'): " freigabepfad
        [[ "$freigabepfad" == /* ]] || { warnung "Bitte absoluten Pfad angeben."; continue; }
        break
    done

    read -rp "Schreibzugriff für Gäste erlauben? [J/n]: " schreiben
    local readonly_wert="no"
    [[ "${schreiben,,}" == "n" ]] && readonly_wert="yes"

    mkdir -p "$freigabepfad"
    chown -R nobody:nobody "$freigabepfad"
    chmod 775 "$freigabepfad"
    erfolg "Verzeichnis '$freigabepfad' erstellt."

    cat >> /etc/samba/smb.conf <<EOL

[$freigabename]
    comment = Oeffentliche Freigabe $freigabename
    path = $freigabepfad
    guest ok = yes
    read only = $readonly_wert
    browseable = yes
    create mask = 0664
    directory mask = 0775
EOL

    if config_validieren; then
        dienste_neustarten
        erfolg "Gast-Freigabe '[$freigabename]' erfolgreich erstellt."
    else
        fehler "Konfigurationsfehler – Freigabe wurde nicht aktiviert."
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 6) Freigabe entfernen
# ------------------------------------------------------------------------------
freigabe_entfernen() {
    echo -e "\n${FETT}=== Freigabe entfernen ===${RESET}"

    # Aktuelle Freigaben anzeigen
    info "Vorhandene Freigaben in smb.conf:"
    grep -E "^\[" /etc/samba/smb.conf | grep -v "^\[global\]" | sed 's/[][]//g' | nl
    echo

    read -rp "Name der zu entfernenden Freigabe: " freigabename
    [[ -n "$freigabename" ]] || { warnung "Kein Name eingegeben."; return 1; }

    if ! share_existiert "$freigabename"; then
        fehler "Freigabe '[$freigabename]' nicht in smb.conf gefunden."
        return 1
    fi

    read -rp "Freigabe '[$freigabename]' wirklich entfernen? [j/N]: " bestaetigung
    [[ "${bestaetigung,,}" == "j" ]] || { info "Abgebrochen."; return 0; }

    backup_config

    # Entferne den gesamten Share-Block aus der Config
    # Nutze Python für zuverlässiges Multi-Line-Removal
    python3 - "$freigabename" <<'PYEOF'
import sys, re, pathlib
name = sys.argv[1]
cfg = pathlib.Path('/etc/samba/smb.conf')
text = cfg.read_text()
pattern = rf'\n\[{re.escape(name)}\][^\[]*'
new_text = re.sub(pattern, '', text, flags=re.DOTALL)
cfg.write_text(new_text)
print(f"[OK]    Freigabe '[{name}]' aus smb.conf entfernt.")
PYEOF

    if config_validieren; then
        dienste_neustarten
        erfolg "Freigabe '[$freigabename]' wurde entfernt."
    else
        fehler "Konfigurationsfehler nach Entfernung. Backup wird wiederhergestellt."
        local letztes_backup
        letztes_backup=$(ls -t /etc/samba/smb.conf.bak_* 2>/dev/null | head -1)
        [[ -n "$letztes_backup" ]] && cp "$letztes_backup" /etc/samba/smb.conf
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 7) Druckerfreigabe aktivieren
# ------------------------------------------------------------------------------
drucker_freigabe() {
    echo -e "\n${FETT}=== Druckerfreigabe aktivieren ===${RESET}"

    if share_existiert "printers"; then
        warnung "Druckerfreigabe [printers] ist bereits in der smb.conf vorhanden."
        return 0
    fi

    info "Prüfe CUPS-Installation..."
    if ! pacman -Qs cups &>/dev/null; then
        info "Installiere CUPS..."
        pacman -S --noconfirm cups || { fehler "CUPS-Installation fehlgeschlagen."; return 1; }
    fi
    systemctl enable --now cups && erfolg "CUPS aktiviert." || warnung "CUPS-Dienst konnte nicht gestartet werden."

    mkdir -p /var/spool/samba
    chmod 1777 /var/spool/samba

    cat >> /etc/samba/smb.conf <<EOL

[printers]
    comment = Alle Drucker
    path = /var/spool/samba
    printable = yes
    guest ok = yes
    read only = yes
    browseable = no

[print$]
    comment = Druckertreiber
    path = /var/lib/samba/printers
    browseable = yes
    read only = yes
    guest ok = no
EOL

    mkdir -p /var/lib/samba/printers

    if config_validieren; then
        dienste_neustarten
        erfolg "Druckerfreigabe wurde aktiviert."
    else
        fehler "Konfigurationsfehler bei Druckerfreigabe."
        return 1
    fi
}

# ------------------------------------------------------------------------------
# 8) Benutzerverwaltung
# ------------------------------------------------------------------------------
benutzer_verwalten() {
    echo -e "\n${FETT}=== Samba-Benutzerverwaltung ===${RESET}"
    echo "  a) Samba-Benutzer anzeigen"
    echo "  b) Samba-Benutzer hinzufügen"
    echo "  c) Samba-Benutzer entfernen"
    echo "  d) Samba-Passwort ändern"
    echo "  e) Benutzer aktivieren/deaktivieren"
    echo "  z) Zurück"
    echo
    read -rp "Auswahl: " sub

    case "$sub" in
        a)
            echo -e "\n${FETT}Registrierte Samba-Benutzer:${RESET}"
            pdbedit -L -v 2>/dev/null | grep -E "^(Unix|Account)" | \
                awk -F': ' '{printf "  %-20s %s\n", $1, $2}' \
                || warnung "Keine Benutzer gefunden."
            ;;
        b)
            read -rp "Systembenutzer, der als Samba-Benutzer hinzugefügt werden soll: " benutzer
            if ! id "$benutzer" &>/dev/null; then
                fehler "Systembenutzer '$benutzer' existiert nicht."
                return 1
            fi
            smbpasswd -a "$benutzer" && erfolg "Benutzer '$benutzer' hinzugefügt." \
                || fehler "Konnte Benutzer nicht hinzufügen."
            ;;
        c)
            read -rp "Zu entfernender Samba-Benutzer: " benutzer
            read -rp "Wirklich entfernen? [j/N]: " best
            [[ "${best,,}" == "j" ]] || { info "Abgebrochen."; return 0; }
            smbpasswd -x "$benutzer" && erfolg "Benutzer '$benutzer' entfernt." \
                || fehler "Entfernen fehlgeschlagen."
            ;;
        d)
            read -rp "Samba-Passwort ändern für Benutzer: " benutzer
            smbpasswd "$benutzer" && erfolg "Passwort geändert." \
                || fehler "Passwortänderung fehlgeschlagen."
            ;;
        e)
            read -rp "Benutzer aktivieren (a) oder deaktivieren (d)? [a/d]: " aktion
            read -rp "Benutzername: " benutzer
            if [[ "${aktion,,}" == "a" ]]; then
                smbpasswd -e "$benutzer" && erfolg "Benutzer '$benutzer' aktiviert."
            else
                smbpasswd -d "$benutzer" && erfolg "Benutzer '$benutzer' deaktiviert."
            fi
            ;;
        z) return 0 ;;
        *) warnung "Ungültige Auswahl." ;;
    esac
}

# ------------------------------------------------------------------------------
# 9) Status & Übersicht anzeigen
# ------------------------------------------------------------------------------
status_anzeigen() {
    echo -e "\n${FETT}=== Samba Status ===${RESET}"

    for dienst in smb nmb; do
        if systemctl is-active "$dienst" &>/dev/null; then
            echo -e "  Dienst ${FETT}$dienst${RESET}: ${GRUEN}aktiv${RESET}"
        else
            echo -e "  Dienst ${FETT}$dienst${RESET}: ${ROT}inaktiv${RESET}"
        fi
    done

    echo
    echo -e "${FETT}Aktive Verbindungen:${RESET}"
    if befehl_vorhanden smbstatus; then
        smbstatus --shares 2>/dev/null || warnung "Keine aktiven Verbindungen oder kein Zugriff."
    else
        warnung "smbstatus nicht verfügbar."
    fi

    echo
    echo -e "${FETT}Freigaben in smb.conf:${RESET}"
    grep -E "^\[" /etc/samba/smb.conf 2>/dev/null \
        | sed 's/[][]//g' | awk '{printf "  - %s\n", $0}' \
        || warnung "smb.conf nicht lesbar."

    echo
    echo -e "${FETT}Samba-Benutzer:${RESET}"
    pdbedit -L 2>/dev/null | awk -F: '{printf "  - %s\n", $1}' \
        || warnung "Keine Benutzer oder kein Zugriff."
}

# ------------------------------------------------------------------------------
# 10) Logs anzeigen
# ------------------------------------------------------------------------------
logs_anzeigen() {
    echo -e "\n${FETT}=== Samba Logs ===${RESET}"
    echo "  a) systemd Journal (smb)"
    echo "  b) systemd Journal (nmb)"
    echo "  c) Samba Log-Dateien (/var/log/samba/)"
    echo "  z) Zurück"
    echo
    read -rp "Auswahl: " sub

    case "$sub" in
        a) journalctl -u smb --no-pager -n 50 ;;
        b) journalctl -u nmb --no-pager -n 50 ;;
        c)
            if [[ -d /var/log/samba ]]; then
                echo -e "${FETT}Verfügbare Log-Dateien:${RESET}"
                ls -lh /var/log/samba/ 2>/dev/null
                echo
                read -rp "Dateiname anzeigen (leer = log.smbd): " logdatei
                logdatei="${logdatei:-log.smbd}"
                tail -n 50 "/var/log/samba/$logdatei" 2>/dev/null \
                    || warnung "Datei nicht gefunden: /var/log/samba/$logdatei"
            else
                warnung "Log-Verzeichnis /var/log/samba/ nicht gefunden."
            fi
            ;;
        z) return 0 ;;
        *) warnung "Ungültige Auswahl." ;;
    esac
}

# ------------------------------------------------------------------------------
# 11) Konfiguration testen & anzeigen
# ------------------------------------------------------------------------------
config_testen() {
    echo -e "\n${FETT}=== Konfigurationstest ===${RESET}"
    info "Führe testparm aus..."
    echo
    testparm -s /etc/samba/smb.conf 2>&1
    echo
    config_validieren
}

# ------------------------------------------------------------------------------
# Hauptmenü
# ------------------------------------------------------------------------------
main() {
    root_check

    while true; do
        clear
        echo -e "${FETT}${BLAU}"
        echo "╔══════════════════════════════════════╗"
        echo "║      Samba Verwaltung – Arch Linux   ║"
        echo "╚══════════════════════════════════════╝${RESET}"
        echo
        echo -e "  ${FETT}Installation & Konfiguration${RESET}"
        echo "   1) Samba installieren / überprüfen"
        echo "   2) Konfiguration optimieren"
        echo "   3) Konfiguration testen (testparm)"
        echo "   4) Backup der smb.conf erstellen"
        echo
        echo -e "  ${FETT}Freigaben${RESET}"
        echo "   5) Freigabe mit Passwort erstellen"
        echo "   6) Gast-Freigabe erstellen"
        echo "   7) Freigabe entfernen"
        echo "   8) Druckerfreigabe aktivieren"
        echo
        echo -e "  ${FETT}Benutzer & Übersicht${RESET}"
        echo "   9) Benutzerverwaltung"
        echo "  10) Status & Verbindungen anzeigen"
        echo "  11) Logs anzeigen"
        echo
        echo "   0) Beenden"
        echo
        read -rp "$(echo -e "${CYAN}Auswahl [0-11]:${RESET} ")" auswahl

        case "$auswahl" in
            1)  install_samba;       pause ;;
            2)  optimiere_config;    pause ;;
            3)  config_testen;       pause ;;
            4)  backup_config;       pause ;;
            5)  freigabe_mit_passwort; pause ;;
            6)  freigabe_gast;       pause ;;
            7)  freigabe_entfernen;  pause ;;
            8)  drucker_freigabe;    pause ;;
            9)  benutzer_verwalten;  pause ;;
            10) status_anzeigen;     pause ;;
            11) logs_anzeigen;       pause ;;
            0)
                echo -e "\n${GRUEN}Auf Wiedersehen!${RESET}"
                exit 0
                ;;
            *)
                warnung "Ungültige Auswahl. Bitte eine Zahl zwischen 0 und 11 eingeben."
                sleep 1
                ;;
        esac
    done
}

main "$@"
