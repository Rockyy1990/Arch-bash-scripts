#!/bin/bash
# ==============================================================================
# arch_nfs_verwaltung.sh – NFS-Verwaltungsskript für Arch Linux
# Version: 2.0
# ==============================================================================

# ── Farben & Formatierung ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Log-Datei ──────────────────────────────────────────────────────────────────
LOG_FILE="/var/log/nfs_verwaltung.log"

# ── Hilfsfunktionen ────────────────────────────────────────────────────────────

log() {
    local level="$1"
    local msg="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $msg" | sudo tee -a "$LOG_FILE" > /dev/null
}

info()    { echo -e "${GREEN}[✔]${RESET} $*"; log "INFO"  "$*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; log "WARN"  "$*"; }
error()   { echo -e "${RED}[✘]${RESET} $*"; log "ERROR" "$*"; }
section() { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}"; }

# Prüft, ob eine Variable leer ist; bricht mit Fehlermeldung ab
require_input() {
    local value="$1"
    local label="$2"
    if [[ -z "$value" ]]; then
        error "Eingabe für '$label' darf nicht leer sein."
        return 1
    fi
}

# Einfache IPv4-Validierung (auch CIDR-Notation erlaubt)
validate_ip_or_cidr() {
    local input="$1"
    # Erlaubt: IP, IP/CIDR, Hostname, Wildcard *
    if [[ "$input" == "*" ]]; then return 0; fi
    if echo "$input" | grep -qP '^(\d{1,3}\.){3}\d{1,3}(/\d{1,2})?$'; then return 0; fi
    if echo "$input" | grep -qP '^[a-zA-Z0-9._-]+(/\d{1,2})?$'; then return 0; fi
    return 1
}

# Prüft, ob sudo verfügbar ist
check_sudo() {
    if ! sudo -v 2>/dev/null; then
        error "Sudo-Zugriff ist erforderlich. Bitte als berechtigter Benutzer ausführen."
        exit 1
    fi
}

# Trennlinie
separator() { echo -e "${CYAN}────────────────────────────────────────────────${RESET}"; }

# ── Funktion 1: nfs-utils prüfen / installieren ───────────────────────────────
check_install_nfs() {
    section "nfs-utils prüfen"
    if pacman -Qi nfs-utils > /dev/null 2>&1; then
        info "nfs-utils ist bereits installiert."
    else
        warn "nfs-utils ist nicht installiert. Installation wird gestartet..."
        if sudo pacman -Sy --noconfirm nfs-utils; then
            info "nfs-utils wurde erfolgreich installiert."
            log "INFO" "nfs-utils installiert."
        else
            error "Fehler bei der Installation von nfs-utils."
            return 1
        fi
    fi
}

# ── Funktion 2: NFS-Server einrichten ─────────────────────────────────────────
setup_server() {
    section "NFS Server einrichten"

    read -rp "Freizugebendes Verzeichnis (z.B. /mnt/nfs): " shared_dir
    require_input "$shared_dir" "Verzeichnis" || return 1

    if [[ ! -d "$shared_dir" ]]; then
        warn "Verzeichnis '$shared_dir' existiert nicht."
        read -rp "Soll es erstellt werden? (j/n): " create_dir
        if [[ "$create_dir" =~ ^[Jj]$ ]]; then
            sudo mkdir -p "$shared_dir" || { error "Erstellen fehlgeschlagen."; return 1; }
            info "Verzeichnis '$shared_dir' wurde erstellt."
        else
            warn "Abbruch durch Benutzer."
            return 0
        fi
    fi

    read -rp "Erlaubte Clients (z.B. 192.168.1.0/24 oder *): " clients
    require_input "$clients" "Clients" || return 1

    if ! validate_ip_or_cidr "$clients"; then
        error "Ungültiges Format für Clients: '$clients'"
        return 1
    fi

    read -rp "Export-Optionen [Standard: rw,sync,no_subtree_check]: " export_opts
    export_opts="${export_opts:-rw,sync,no_subtree_check}"

    # Sicherer Export-Eintrag via tee
    if ! grep -qE "^${shared_dir}[[:space:]]" /etc/exports 2>/dev/null; then
        echo "${shared_dir} ${clients}(${export_opts})" | sudo tee -a /etc/exports > /dev/null
        info "Eintrag in /etc/exports hinzugefügt."
        log "INFO" "Export hinzugefügt: ${shared_dir} ${clients}(${export_opts})"
    else
        warn "Ein Eintrag für '${shared_dir}' existiert bereits in /etc/exports."
    fi

    sudo exportfs -ra 2>/dev/null || true

    if sudo systemctl enable --now nfs-server 2>/dev/null; then
        info "NFS-Server wurde gestartet und aktiviert."
    else
        error "Fehler beim Starten des NFS-Servers."
        return 1
    fi

    echo ""
    info "Aktive Exports:"
    sudo exportfs -v
}

# ── Funktion 3: NFS-Client einrichten ─────────────────────────────────────────
setup_client() {
    section "NFS Client einrichten"

    read -rp "Mountpunkt (z.B. /mnt/nfs): " mount_point
    require_input "$mount_point" "Mountpunkt" || return 1

    read -rp "Server-IP oder Hostname: " server_ip
    require_input "$server_ip" "Server-IP" || return 1

    read -rp "Exportiertes Verzeichnis auf dem Server (z.B. /mnt/nfs): " remote_dir
    require_input "$remote_dir" "Remote-Verzeichnis" || return 1

    read -rp "NFS-Version [Standard: 4]: " nfs_version
    nfs_version="${nfs_version:-4}"

    read -rp "Mount-Optionen [Standard: defaults,_netdev]: " mount_opts
    mount_opts="${mount_opts:-defaults,_netdev}"

    # Mountpunkt anlegen
    if [[ ! -d "$mount_point" ]]; then
        sudo mkdir -p "$mount_point" || { error "Mountpunkt konnte nicht erstellt werden."; return 1; }
        info "Verzeichnis '$mount_point' wurde erstellt."
    fi

    # Verbindungstest vor dem Mounten
    info "Verbindung zum Server wird getestet..."
    if ! showmount -e "$server_ip" > /dev/null 2>&1; then
        warn "Server '$server_ip' antwortet nicht oder keine Exports sichtbar."
        read -rp "Trotzdem mounten versuchen? (j/n): " force_mount
        [[ "$force_mount" =~ ^[Jj]$ ]] || return 0
    fi

    # Mounten
    if sudo mount -t "nfs${nfs_version}" "${server_ip}:${remote_dir}" "$mount_point"; then
        info "NFS-Share erfolgreich eingebunden unter '$mount_point'."
        log "INFO" "Gemountet: ${server_ip}:${remote_dir} → ${mount_point}"
    else
        error "Fehler beim Mounten. Bitte Server und Pfad prüfen."
        return 1
    fi

    # fstab-Eintrag
    local fstab_entry="${server_ip}:${remote_dir} ${mount_point} nfs${nfs_version} ${mount_opts} 0 0"
    if ! grep -qF "${server_ip}:${remote_dir} ${mount_point}" /etc/fstab 2>/dev/null; then
        echo "$fstab_entry" | sudo tee -a /etc/fstab > /dev/null
        info "fstab-Eintrag wurde hinzugefügt (automatisches Mounten beim Boot)."
        log "INFO" "fstab-Eintrag: $fstab_entry"
    else
        warn "Eintrag für diesen Share existiert bereits in /etc/fstab."
    fi
}

# ── Funktion 4: NFS-Optimierungen ─────────────────────────────────────────────
optimize_nfs() {
    section "NFS Optimierungen"
    echo "Bitte wählen Sie eine Option:"
    echo "  1) Optimierung für viele kleine Dateien (mehr NFS-Threads)"
    echo "  2) Optimierung für große Dateien (Puffergrößen)"
    echo "  3) NFSv4 aktivieren"
    echo "  4) Zurück"
    read -rp "Ihre Wahl: " choice

    case "$choice" in
        1)
            info "Konfiguriere NFS für viele kleine Dateien (16 Threads)..."
            # Korrekte Konfiguration: nfs.conf statt /etc/environment
            sudo bash -c 'grep -q "^\[nfsd\]" /etc/nfs.conf 2>/dev/null || echo "[nfsd]" >> /etc/nfs.conf'
            if grep -q "^threads=" /etc/nfs.conf 2>/dev/null; then
                sudo sed -i 's/^threads=.*/threads=16/' /etc/nfs.conf
            else
                echo "threads=16" | sudo tee -a /etc/nfs.conf > /dev/null
            fi
            sudo systemctl restart nfs-server
            info "NFS-Server mit 16 Threads neugestartet."
            log "INFO" "Optimierung: 16 NFS-Threads gesetzt."
            ;;
        2)
            info "Optimiere Netzwerkpuffer für große Dateien..."
            # Kernel-Netzwerkpuffer erhöhen
            local sysctl_conf="/etc/sysctl.d/99-nfs-optimize.conf"
            {
                echo "net.core.rmem_max=16777216"
                echo "net.core.wmem_max=16777216"
                echo "net.core.rmem_default=524288"
                echo "net.core.wmem_default=524288"
            } | sudo tee "$sysctl_conf" > /dev/null
            sudo sysctl -p "$sysctl_conf" > /dev/null
            info "Kernel-Netzwerkpuffer angepasst (Konfiguration: $sysctl_conf)."
            log "INFO" "Optimierung: Netzwerkpuffer vergrößert."
            ;;
        3)
            info "Aktiviere NFSv4..."
            sudo bash -c 'grep -q "^\[nfsd\]" /etc/nfs.conf 2>/dev/null || echo "[nfsd]" >> /etc/nfs.conf'
            # vers4 aktivieren, vers2/vers3 deaktivieren für Sicherheit
            for ver in vers2 vers3 vers4; do
                if grep -q "^${ver}=" /etc/nfs.conf 2>/dev/null; then
                    sudo sed -i "s/^${ver}=.*/${ver}=y/" /etc/nfs.conf
                else
                    echo "${ver}=y" | sudo tee -a /etc/nfs.conf > /dev/null
                fi
            done
            sudo systemctl restart nfs-server
            info "NFSv4 wurde aktiviert."
            log "INFO" "NFSv4 aktiviert in /etc/nfs.conf."
            ;;
        4) return ;;
        *) error "Ungültige Wahl." ;;
    esac
}

# ── Funktion 5: NFS-Status anzeigen ───────────────────────────────────────────
show_status() {
    section "NFS Status"

    echo -e "${BOLD}── NFS-Server:${RESET}"
    if systemctl is-active --quiet nfs-server 2>/dev/null; then
        echo -e "  Status: ${GREEN}aktiv${RESET}"
        systemctl status nfs-server --no-pager -l | grep -E "Active:|Main PID:|Tasks:" | sed 's/^/  /'
    else
        echo -e "  Status: ${RED}inaktiv / nicht installiert${RESET}"
    fi

    separator

    echo -e "${BOLD}── Aktive Exports (/etc/exports):${RESET}"
    if [[ -f /etc/exports ]] && [[ -s /etc/exports ]]; then
        grep -v '^\s*#' /etc/exports | grep -v '^\s*$' | while read -r line; do
            echo -e "  ${CYAN}${line}${RESET}"
        done
    else
        echo "  (Keine Exports konfiguriert)"
    fi

    separator

    echo -e "${BOLD}── Eingebundene NFS-Shares (Client):${RESET}"
    if mount | grep -q " type nfs"; then
        mount | grep " type nfs" | awk '{printf "  %-35s → %s\n", $1, $3}'
    else
        echo "  (Keine NFS-Shares eingebunden)"
    fi

    separator

    echo -e "${BOLD}── nfs-utils Version:${RESET}"
    if pacman -Qi nfs-utils > /dev/null 2>&1; then
        pacman -Qi nfs-utils | grep "^Version" | sed 's/^/  /'
    else
        echo "  nfs-utils nicht installiert."
    fi
}

# ── Funktion 6: Aktive Exports auflisten ──────────────────────────────────────
list_exports() {
    section "Aktive Exports"
    if ! systemctl is-active --quiet nfs-server 2>/dev/null; then
        warn "NFS-Server ist nicht aktiv."
        return 1
    fi
    echo -e "${BOLD}Exports (exportfs -v):${RESET}"
    sudo exportfs -v 2>/dev/null || warn "Keine Exports aktiv."
}

# ── Funktion 7: Eingebundene NFS-Shares auflisten ─────────────────────────────
list_mounts() {
    section "Eingebundene NFS-Shares"
    if mount | grep -q " type nfs"; then
        printf "  ${BOLD}%-40s %-30s %s${RESET}\n" "Quelle" "Mountpunkt" "Optionen"
        separator
        mount | grep " type nfs" | while read -r src _ mpt _ type opts _; do
            printf "  %-40s %-30s %s\n" "$src" "$mpt" "$opts"
        done
    else
        info "Keine NFS-Shares aktuell eingebunden."
    fi

    echo ""
    echo -e "${BOLD}fstab-Einträge (NFS):${RESET}"
    if grep -E "^\S+\s+\S+\s+nfs" /etc/fstab 2>/dev/null; then
        :
    else
        echo "  (Keine NFS-Einträge in /etc/fstab)"
    fi
}

# ── Funktion 8: NFS-Share aushängen ───────────────────────────────────────────
unmount_share() {
    section "NFS-Share aushängen"

    # Aktuelle NFS-Mounts anzeigen
    local mounts
    mounts=$(mount | grep " type nfs" | awk '{print $3}')
    if [[ -z "$mounts" ]]; then
        info "Keine NFS-Shares eingebunden."
        return 0
    fi

    echo "Aktuell eingebundene NFS-Shares:"
    local i=1
    while IFS= read -r mpt; do
        printf "  %d) %s\n" "$i" "$mpt"
        ((i++))
    done <<< "$mounts"

    read -rp "Mountpunkt zum Aushängen (Pfad eingeben): " mount_point
    require_input "$mount_point" "Mountpunkt" || return 1

    if ! mount | grep -q " on ${mount_point} type nfs"; then
        error "'${mount_point}' ist nicht als NFS-Share eingebunden."
        return 1
    fi

    if sudo umount "$mount_point"; then
        info "'${mount_point}' erfolgreich ausgehängt."
        log "INFO" "Ausgehängt: $mount_point"
    else
        error "Fehler beim Aushängen. Prüfen Sie, ob das Verzeichnis noch benutzt wird."
        return 1
    fi

    read -rp "fstab-Eintrag für '${mount_point}' ebenfalls entfernen? (j/n): " remove_fstab
    if [[ "$remove_fstab" =~ ^[Jj]$ ]]; then
        sudo sed -i "\| ${mount_point} |d" /etc/fstab
        info "fstab-Eintrag entfernt."
        log "INFO" "fstab-Eintrag für $mount_point entfernt."
    fi
}

# ── Funktion 9: Export entfernen ──────────────────────────────────────────────
remove_export() {
    section "Export entfernen"

    if [[ ! -f /etc/exports ]] || [[ ! -s /etc/exports ]]; then
        info "Keine Exports in /etc/exports vorhanden."
        return 0
    fi

    echo "Aktuell konfigurierte Exports:"
    grep -v '^\s*#' /etc/exports | grep -v '^\s*$' | nl -ba

    read -rp "Zu entfernendes Verzeichnis (vollständiger Pfad): " export_dir
    require_input "$export_dir" "Verzeichnis" || return 1

    if ! grep -qE "^${export_dir}[[:space:]]" /etc/exports; then
        error "Kein Export für '${export_dir}' gefunden."
        return 1
    fi

    # Backup anlegen
    sudo cp /etc/exports /etc/exports.bak
    info "Backup: /etc/exports.bak"

    sudo sed -i "\|^${export_dir}[[:space:]]|d" /etc/exports
    sudo exportfs -ra
    info "Export '${export_dir}' entfernt und Exports neu geladen."
    log "INFO" "Export entfernt: $export_dir"
}

# ── Funktion 10: Verbindungstest ──────────────────────────────────────────────
test_connection() {
    section "NFS-Verbindungstest"

    read -rp "Server-IP oder Hostname: " server_ip
    require_input "$server_ip" "Server-IP" || return 1

    echo ""
    echo -e "${BOLD}1) Erreichbarkeit (ping):${RESET}"
    if ping -c 2 -W 2 "$server_ip" > /dev/null 2>&1; then
        info "Server '${server_ip}' ist erreichbar."
    else
        error "Server '${server_ip}' antwortet nicht auf Ping."
    fi

    separator

    echo -e "${BOLD}2) NFS-Port 2049 (TCP):${RESET}"
    if timeout 3 bash -c "echo > /dev/tcp/${server_ip}/2049" 2>/dev/null; then
        info "Port 2049 (NFS) ist offen."
    else
        error "Port 2049 ist nicht erreichbar. Firewall oder NFS-Server prüfen."
    fi

    separator

    echo -e "${BOLD}3) Verfügbare Exports (showmount):${RESET}"
    if showmount -e "$server_ip" 2>/dev/null; then
        :
    else
        error "Keine Exports sichtbar. RPC/NFS-Dienst auf Server prüfen."
    fi

    separator

    echo -e "${BOLD}4) RPC-Dienste (rpcinfo):${RESET}"
    if rpcinfo -p "$server_ip" 2>/dev/null | grep -E "nfs|mountd"; then
        :
    else
        warn "rpcinfo lieferte keine NFS-Dienste."
    fi
}

# ── Funktion 11: NFS-Logs anzeigen ────────────────────────────────────────────
show_logs() {
    section "NFS-Logs"
    echo "  1) Systemd-Journal (NFS-Server, letzte 50 Zeilen)"
    echo "  2) Systemd-Journal (NFS-Mount-Events)"
    echo "  3) Skript-Logdatei ($LOG_FILE)"
    read -rp "Ihre Wahl: " choice

    case "$choice" in
        1)
            sudo journalctl -u nfs-server -n 50 --no-pager
            ;;
        2)
            sudo journalctl -k -n 100 --no-pager | grep -i nfs || info "Keine NFS-Kernel-Events gefunden."
            ;;
        3)
            if [[ -f "$LOG_FILE" ]]; then
                sudo tail -50 "$LOG_FILE"
            else
                info "Logdatei '$LOG_FILE' noch nicht vorhanden."
            fi
            ;;
        *)
            error "Ungültige Wahl."
            ;;
    esac
}

# ── Hauptmenü ─────────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        echo ""
        echo -e "${BOLD}${CYAN}╔══════════════════════════════════╗${RESET}"
        echo -e "${BOLD}${CYAN}║     NFS Verwaltung – Arch Linux  ║${RESET}"
        echo -e "${BOLD}${CYAN}╚══════════════════════════════════╝${RESET}"
        echo ""
        echo -e "  ${GREEN}1)${RESET} nfs-utils prüfen / installieren"
        echo -e "  ${GREEN}2)${RESET} NFS-Server einrichten"
        echo -e "  ${GREEN}3)${RESET} NFS-Client einrichten"
        echo -e "  ${GREEN}4)${RESET} NFS optimieren"
        echo -e "  ${CYAN}5)${RESET} NFS-Status anzeigen"
        echo -e "  ${CYAN}6)${RESET} Aktive Exports auflisten"
        echo -e "  ${CYAN}7)${RESET} Eingebundene Shares auflisten"
        echo -e "  ${CYAN}8)${RESET} NFS-Share aushängen"
        echo -e "  ${CYAN}9)${RESET} Export entfernen"
        echo -e " ${CYAN}10)${RESET} Verbindungstest"
        echo -e " ${CYAN}11)${RESET} Logs anzeigen"
        echo -e "  ${RED}12)${RESET} Beenden"
        echo ""
        read -rp "$(echo -e "${BOLD}Ihre Wahl: ${RESET}")" option

        case "$option" in
            1)  check_install_nfs ;;
            2)  check_install_nfs && setup_server ;;
            3)  check_install_nfs && setup_client ;;
            4)  check_install_nfs && optimize_nfs ;;
            5)  show_status ;;
            6)  list_exports ;;
            7)  list_mounts ;;
            8)  unmount_share ;;
            9)  remove_export ;;
            10) test_connection ;;
            11) show_logs ;;
            12) echo -e "${GREEN}Auf Wiedersehen!${RESET}"; exit 0 ;;
            *)  error "Ungültige Eingabe. Bitte eine Zahl zwischen 1 und 12 wählen." ;;
        esac
    done
}

# ── Einstiegspunkt ─────────────────────────────────────────────────────────────
check_sudo
main_menu
