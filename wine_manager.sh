#!/usr/bin/env bash
# ==============================================================================
# Wine Manager CLI Tool (Bash 5+) - Interaktive & stabile Edition
# Zuverlässige und strukturierte Verwaltung von Wine-Versionen und Präfixen.
# ==============================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Farbedefinitionen & UI-Vorgaben ---
readonly COLOR_RED=$'\033[0;31m'
readonly COLOR_GREEN=$'\033[0;32m'
readonly COLOR_YELLOW=$'\033[0;33m'
readonly COLOR_BLUE=$'\033[0;34m'
readonly COLOR_CYAN=$'\033[0;36m'
readonly COLOR_RESET=$'\033[0m'

# --- Pfade & Standardkonfiguration ---
readonly BASE_DIR="${HOME}/wine-manager"
readonly CONFIG_DIR="${BASE_DIR}/config"
readonly CONFIG_FILE="${CONFIG_DIR}/config.yaml"
readonly METADATA_FILE="${CONFIG_DIR}/prefixes.json"
readonly LOCK_FILE="/tmp/wine-manager.lock"

# Dynamische Standardwerte (werden durch load_config überschrieben)
DEFAULT_WINE_DIR="${BASE_DIR}/wine-versions"
DEFAULT_PREFIX_DIR="${BASE_DIR}/wine-prefixes"
DEFAULT_LOG_FILE="${BASE_DIR}/logs/wine-manager.log"

# --- Statusvariablen ---
DRY_RUN=false
ASSUME_YES=false
VERBOSE=false
LOG_FILE=""
LOCK_FD=""
HAS_LOCK=false

# --- Statische Ausweich-URLs (Fallbacks) ---
declare -A WINE_URLS=(
    ["kron4ek-v11.9"]="https://github.com/Kron4ek/Wine-Builds/releases/download/11.9/wine-11.9-staging-amd64.tar.xz"
    ["steam-proton"]="https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-4/GE-Proton9-4.tar.xz"
    ["cachyos-wine"]="https://github.com/CachyOS/proton-cachyos/releases/download/11.0-20260521/proton-cachyos-11.0-20260521-slr-x86_64_v3.tar.xz"
)

declare -A WINE_SHAS=(
    ["kron4ek-v11.9"]="bb1122ea19b9c7ce2ac25048d62aaa3d29e0500699ece82857b736ff94f09f67"
    ["steam-proton"]="a3d7e8f192b45cd2a90ee928a3915cc8a213e8e2c0e86b24f5728a3811f583bb2a8e4cb3"
    ["cachyos-wine"]="856919fb6daf6bd21cc7c0c48fcd24de564877f8effc44f15e607c51dc08cfa5"
)

# --- Protokollierungsfunktionen ---
log_info() {
    echo "${COLOR_GREEN}[OK]${COLOR_RESET} $1"
    log_to_file "INFO: $1"
}

log_warn() {
    echo "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
    log_to_file "WARN: $1"
}

log_error() {
    echo "${COLOR_RED}[ERR]${COLOR_RESET} $1" >&2
    log_to_file "ERROR: $1"
}

log_verbose() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo "${COLOR_BLUE}[DEBUG]${COLOR_RESET} $1"
    fi
    log_to_file "DEBUG: $1"
}

log_to_file() {
    [[ -z "${LOG_FILE:-}" ]] && return 0
    local parent_dir
    parent_dir=$(dirname "${LOG_FILE}")
    if [[ ! -d "${parent_dir}" ]]; then
        mkdir -p "${parent_dir}"
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}"
}

# --- Cleanup & Sicherheits-Traps ---
cleanup() {
    local exit_code=$?
    log_verbose "Exit aufgerufen. Code: ${exit_code}"

    # Sperrdatei nur entfernen, wenn diese Instanz sie gesperrt hat
    if [[ "${HAS_LOCK}" == "true" ]]; then
        if [[ -n "${LOCK_FD:-}" ]]; then
            flock -u "${LOCK_FD}" || true
        fi
        rm -f "${LOCK_FILE}"
        log_verbose "Sperrdatei freigegeben."
    fi

    if [[ -n "${LOG_FILE:-}" && -f "${LOG_FILE}" ]]; then
        local max_size=$((1024 * 1024)) # 1MB
        local current_size
        current_size=$(wc -c < "${LOG_FILE}" || echo 0)
        if (( current_size > max_size )); then
            mv "${LOG_FILE}" "${LOG_FILE}.old"
            log_verbose "Protokolldatei rotatiert."
        fi
    fi

    exit "${exit_code}"
}

trap cleanup EXIT INT TERM

# --- Dateisperre (Locking) ---
acquire_lock() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    exec {LOCK_FD}>> "${LOCK_FILE}"
    if ! flock -n "${LOCK_FD}"; then
        LOCK_FD="" # Verhindert Löschen der Sperre durch fremde Instanz im Cleanup
        log_error "Eine andere Instanz von wine-manager läuft bereits."
        exit 1
    fi
    HAS_LOCK=true
}

# --- Initialisierung & Validierung ---
load_config() {
    if [[ -s "${CONFIG_FILE}" ]]; then
        local line key val
        while IFS= read -r line; do
            [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
            if [[ "${line}" =~ ^([a-zA-Z0-9_]+):[[:space:]]*(.*)$ ]]; then
                key="${BASH_REMATCH[1]}"
                val="${BASH_REMATCH[2]}"
                # Anführungszeichen entfernen
                val="${val#\"}"
                val="${val%\"}"
                val="${val#\'}"
                val="${val%\'}"
                case "${key}" in
                    wine_install_path) DEFAULT_WINE_DIR="${val}" ;;
                    prefix_path) DEFAULT_PREFIX_DIR="${val}" ;;
                    log_file) DEFAULT_LOG_FILE="${val}" ;;
                esac
            fi
        done < "${CONFIG_FILE}"
    fi
    LOG_FILE="${DEFAULT_LOG_FILE}"
}

init_directories() {
    log_verbose "Initialisiere Verzeichnisse..."
    mkdir -p "${CONFIG_DIR}"
    mkdir -p "${DEFAULT_WINE_DIR}"
    mkdir -p "${DEFAULT_PREFIX_DIR}"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat <<EOF > "${CONFIG_FILE}"
wine_install_path: "${DEFAULT_WINE_DIR}"
prefix_path: "${DEFAULT_PREFIX_DIR}"
log_file: "${DEFAULT_LOG_FILE}"
EOF
    fi

    # Neuinitialisierung auch bei beschädigten/leeren Metadaten (Größe 0)
    if [[ ! -s "${METADATA_FILE}" ]]; then
        echo '{"prefixes":{},"custom_wines":{}}' > "${METADATA_FILE}"
    fi
}

# --- Betriebssystem- & Abhängigkeitsprüfung ---
detect_os() {
    if [[ -f /etc/os-release ]]; then
        (
            # shellcheck disable=SC1091
            source /etc/os-release
            echo "${ID:-unknown}:${ID_LIKE:-}"
        )
    else
        echo "unknown:"
    fi
}

run_with_sudo() {
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo &>/dev/null; then
        sudo "$@"
    elif command -v doas &>/dev/null; then
        doas "$@"
    else
        log_error "Root-Rechte erforderlich, aber weder 'sudo' noch 'doas' gefunden."
        return 1
    fi
}

install_missing_deps() {
    local missing=("$@")
    local os_info
    os_info=$(detect_os)
    local os_id="${os_info%%:*}"
    local os_like="${os_info#*:}"

    log_warn "Automatische Installation wird vorbereitet für: ${missing[*]}"

    local install_cmd=()
    if [[ "${os_id}" =~ ^(debian|ubuntu|pop|mint|kali)$ ]] || [[ "${os_like}" =~ debian ]]; then
        if ! confirm_action "Möchtest du die fehlenden Abhängigkeiten (${missing[*]}) via apt installieren?"; then
            return 1
        fi
        log_info "Aktualisiere Paketquellen..."
        run_with_sudo apt-get update -y
        install_cmd=(apt-get install -y)
    elif [[ "${os_id}" =~ ^(arch|manjaro|endeavouros)$ ]] || [[ "${os_like}" =~ arch ]]; then
        if ! confirm_action "Möchtest du die fehlenden Abhängigkeiten (${missing[*]}) via pacman installieren?"; then
            return 1
        fi
        install_cmd=(pacman -S --noconfirm)
    else
        if command -v apt-get &>/dev/null; then
            if ! confirm_action "Möchtest du die fehlenden Abhängigkeiten (${missing[*]}) via apt installieren?"; then
                return 1
            fi
            log_info "Aktualisiere Paketquellen..."
            run_with_sudo apt-get update -y
            install_cmd=(apt-get install -y)
        elif command -v pacman &>/dev/null; then
            if ! confirm_action "Möchtest du die fehlenden Abhängigkeiten (${missing[*]}) via pacman installieren?"; then
                return 1
            fi
            install_cmd=(pacman -S --noconfirm)
        else
            log_error "Nicht unterstützte Distribution zur automatischen Installation. Bitte installiere manuell: ${missing[*]}"
            return 1
        fi
    fi

    run_with_sudo "${install_cmd[@]}" "${missing[@]}"
}

validate_dependencies() {
    # zstd hinzugefügt zur fehlerfreien Dekomprimierung von CachyOS Archiven
    local deps=(jq tar unzip winetricks curl file zstd)
    local missing=()
    for cmd in "${deps[@]}"; do
        if ! command -v "${cmd}" &>/dev/null; then
            missing+=("${cmd}")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        log_warn "Fehlende Abhängigkeiten gefunden: ${missing[*]}"
        if ! install_missing_deps "${missing[@]}"; then
            log_error "Abhängigkeiten konnten nicht installiert werden. Skript bricht ab."
            exit 1
        fi

        local verify_failed=()
        for cmd in "${missing[@]}"; do
            if ! command -v "${cmd}" &>/dev/null; then
                verify_failed+=("${cmd}")
            fi
        done
        if (( ${#verify_failed[@]} > 0 )); then
            log_error "Einige Abhängigkeiten fehlen weiterhin nach der Installation: ${verify_failed[*]}"
            exit 1
        fi
    fi
}

# --- Hilfsfunktionen ---
confirm_action() {
    if [[ "${ASSUME_YES}" == "true" ]]; then
        return 0
    fi
    read -rp "$1 [y/N]: " resp < /dev/tty
    if [[ ! "${resp}" =~ ^[Yy]$ ]]; then
        log_info "Aktion abgebrochen."
        return 1
    fi
    return 0
}

safe_delete_dir() {
    local dir="$1"
    if [[ ! -d "${dir}" ]]; then
        return 0
    fi
    if command -v trash-put &>/dev/null; then
        trash-put "${dir}"
    else
        rm -rf "${dir}"
    fi
}

# --- Architektur- & Multilib-Erkennung ---
detect_exe_arch() {
    local exe="${1:-}"
    if [[ -z "${exe}" || ! -f "${exe}" ]]; then
        echo "win64"
        return 0
    fi
    local file_info
    file_info=$(file -b "${exe}" 2>/dev/null || echo "")
    if [[ "${file_info}" == *"PE32+"* ]]; then
        echo "win64"
    elif [[ "${file_info}" == *"PE32"* ]]; then
        echo "win32"
    else
        echo "win64"
    fi
}

verify_multilib_support() {
    local os_info
    os_info=$(detect_os)
    local os_id="${os_info%%:*}"
    local os_like="${os_info#*:}"

    log_warn "Überprüfe 32-Bit-Systemunterstützung (Multiarch)..."

    if [[ "${os_id}" =~ ^(debian|ubuntu|pop|mint|kali)$ ]] || [[ "${os_like}" =~ debian ]]; then
        if ! dpkg --print-foreign-architectures | grep -q "i386"; then
            log_warn "i386-Architektur ist nicht im System aktiviert!"
            if confirm_action "Möchtest du i386-Multiarch jetzt aktivieren?"; then
                run_with_sudo dpkg --add-architecture i386
                run_with_sudo apt-get update -y
            fi
        fi
        if ! dpkg -l | grep -q -E "libc6:i386"; then
            log_warn "Grundlegende 32-Bit-Bibliotheken (libc6:i386) fehlen."
            if confirm_action "Möchtest du libc6:i386 und libgl1:i386 installieren?"; then
                run_with_sudo apt-get install -y libc6:i386 libgl1:i386
            fi
        fi
    elif [[ "${os_id}" =~ ^(arch|manjaro|endeavouros)$ ]] || [[ "${os_like}" =~ arch ]]; then
        if ! grep -E -q '^\[multilib\]' /etc/pacman.conf; then
            log_warn "[multilib] Repository ist in /etc/pacman.conf nicht aktiv!"
            log_warn "Bitte aktiviere [multilib] manuell und installiere 'lib32-glibc'."
        else
            if ! pacman -Qi lib32-glibc &>/dev/null; then
                log_warn "lib32-glibc ist nicht installiert."
                if confirm_action "Möchtest du lib32-glibc jetzt installieren?"; then
                    run_with_sudo pacman -S --noconfirm lib32-glibc
                fi
            fi
        fi
    fi
}

# --- Dynamische Programm-Erkennung in Präfixen ---
detect_installed_programs() {
    local prefix_path="$1"
    if [[ ! -d "${prefix_path}/drive_c" ]]; then
        return 0
    fi
    # Sucht ausführbare Dateien und schließt System-Utilities von Wine/Windows aus
    find "${prefix_path}/drive_c" -type f -name "*.exe" \
        ! -path "*/[wW]indows/*" \
        ! -path "*/[cC]ommon [fF]iles/*" \
        ! -path "*/Common Files/*" \
        ! -name "unins*.exe" \
        ! -name "[uU]ninstall*.exe" \
        ! -name "wineboot.exe" \
        ! -name "winecfg.exe" \
        ! -name "control.exe" \
        ! -name "notepad.exe" \
        ! -name "regedit.exe" \
        ! -name "winemine.exe" \
        ! -name "uninstaller.exe" \
        2>/dev/null || true
}

# --- Desktop-Verknüpfungen generieren ---
generate_desktop_shortcut() {
    local prefix_name="$1"
    local exe_path="$2"
    local app_name="$3"

    local app_clean
    app_clean=$(basename "${exe_path}" .exe)

    local shortcut_file="${HOME}/.local/share/applications/wine-manager-${prefix_name}-${app_clean//[^a-zA-Z0-9_-]/_}.desktop"

    local script_path
    script_path=$(realpath "$0" 2>/dev/null || echo "")
    if [[ -z "${script_path}" || ! -f "${script_path}" ]]; then
        log_error "Konnte den absoluten Pfad des Skripts nicht ermitteln."
        return 1
    fi

    log_info "Erstelle Desktop-Verknüpfung..."
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY] Erstelle ${shortcut_file}"
        return 0
    fi

    mkdir -p "$(dirname "${shortcut_file}")"

    cat <<EOF > "${shortcut_file}"
[Desktop Entry]
Name=${app_name} (${prefix_name})
Comment=Gestartet über Wine Manager
Exec="${script_path}" run "${prefix_name}" "${exe_path}"
Icon=wine
Terminal=false
Type=Application
Categories=Game;Wine;
EOF

    chmod +x "${shortcut_file}"
    log_info "Verknüpfung erfolgreich erstellt unter: ${shortcut_file}"
}

# --- Pfad-Resolver ---
resolve_wine_path() {
    local version="${1:-}"
    if [[ -z "${version}" ]]; then
        echo ""
        return 0
    fi

    local custom_path
    custom_path=$(jq -r --arg ver "${version}" '.custom_wines[$ver] // empty' "${METADATA_FILE}")
    if [[ -n "${custom_path}" ]]; then
        echo "${custom_path}"
        return 0
    fi

    echo "${DEFAULT_WINE_DIR}/${version}"
}

resolve_wine_binary() {
    local path="$1"
    if [[ -z "${path}" ]]; then
        echo ""
        return 0
    fi
    if [[ -f "${path}/bin/wine" ]]; then
        echo "${path}/bin/wine"
    elif [[ -f "${path}/files/bin/wine" ]]; then
        echo "${path}/files/bin/wine"
    elif [[ -x "${path}" && ! -d "${path}" ]]; then
        echo "${path}"
    else
        echo ""
    fi
}

resolve_wineserver_binary() {
    local wine_path="$1"
    if [[ -z "${wine_path}" ]]; then
        echo "/usr/bin/wineserver"
        return 0
    fi
    if [[ -f "${wine_path}/bin/wineserver" ]]; then
        echo "${wine_path}/bin/wineserver"
    elif [[ -f "${wine_path}/files/bin/wineserver" ]]; then
        echo "${wine_path}/files/bin/wineserver"
    else
        echo "/usr/bin/wineserver"
    fi
}

# --- Metadaten-Datenbankzugriffe ---
update_prefix_metadata() {
    local name="$1"
    local json_payload="$2"

    if [[ "${DRY_RUN}" == "true" ]]; then return 0; fi

    local temp_meta
    temp_meta=$(mktemp)
    jq --arg name "${name}" --argjson payload "${json_payload}" \
       '.prefixes[$name] = $payload' "${METADATA_FILE}" > "${temp_meta}"
    mv "${temp_meta}" "${METADATA_FILE}"
}

remove_prefix_metadata() {
    local name="$1"
    if [[ "${DRY_RUN}" == "true" ]]; then return 0; fi

    local temp_meta
    temp_meta=$(mktemp)
    jq --arg name "${name}" 'del(.prefixes[$name])' "${METADATA_FILE}" > "${temp_meta}"
    mv "${temp_meta}" "${METADATA_FILE}"
}

register_custom_wine_metadata() {
    local name="$1"
    local path="$2"

    local temp_meta
    temp_meta=$(mktemp)
    jq --arg name "${name}" --arg path "${path}" \
       '.custom_wines[$name] = $path' "${METADATA_FILE}" > "${temp_meta}"
    mv "${temp_meta}" "${METADATA_FILE}"
    log_info "Lokale Wine-Version '${name}' wurde registriert (${path})."
}

# --- Wine Downloads & GitHub API ---
fetch_github_releases() {
    local repo="$1"
    local cache_file="/tmp/wine_manager_releases_${repo//\//_}.json"
    local cache_time=0

    if [[ -f "${cache_file}" ]]; then
        cache_time=$(date -r "${cache_file}" +%s 2>/dev/null || stat -c %Y "${cache_file}" 2>/dev/null || echo 0)
    fi

    # Lokaler Cache schützt vor GitHub API-Rate-Limits (Gültigkeit: 1 Stunde)
    if [[ ! -f "${cache_file}" ]] || (( $(date +%s) - cache_time > 3600 )); then
        log_info "Hole aktuelle Releases von GitHub für ${repo}..."
        local temp_file
        temp_file=$(mktemp)
        if ! curl -fsL -H "User-Agent: Wine-Manager-CLI" "https://api.github.com/repos/${repo}/releases" > "${temp_file}"; then
            log_warn "Fehler beim Abrufen von GitHub. Verwende vorhandenen Cache."
            rm -f "${temp_file}"
        else
            if jq -e 'if type == "array" then true else false end' "${temp_file}" &>/dev/null; then
                mv "${temp_file}" "${cache_file}"
            else
                log_warn "GitHub-Limit erreicht oder ungültige API-Antwort. Verwende lokalen Cache."
                rm -f "${temp_file}"
            fi
        fi
    fi

    if [[ ! -f "${cache_file}" ]]; then
        echo "[]"
        return 1
    fi

    cat "${cache_file}"
}

download_and_verify() {
    local version="${1:-}"
    local url="${2:-}"
    local checksum_url="${3:-}"
    local archive_filename="${4:-}"

    if [[ -z "${version}" ]]; then
        log_error "Fehler: Keine Wine-Version zum Download angegeben."
        return 1
    fi

    if [[ -z "${url}" ]]; then
        url="${WINE_URLS[${version}]:-}"
        if [[ -z "${url}" ]]; then
            log_error "Ungültige oder nicht unterstützte Version: ${version}"
            return 1
        fi
    fi

    local expected_sha=""
    local target_dir="${DEFAULT_WINE_DIR}/${version}"

    if [[ -d "${target_dir}" ]]; then
        log_info "Wine-Version '${version}' ist bereits installiert."
        return 0
    fi

    log_info "Lade ${version} herunter..."
    local ext="${url##*.}"
    local temp_file
    temp_file=$(mktemp --suffix=".${ext}" "/tmp/wine_${version}_XXXXXX")

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY] curl -L -o ${temp_file} ${url}"
        return 0
    fi

    if ! curl -L -o "${temp_file}" "${url}"; then
        log_error "Download fehlgeschlagen."
        rm -f "${temp_file}"
        return 1
    fi

    if [[ -n "${checksum_url}" ]]; then
        log_info "Lade Prüfsumme von GitHub herunter..."
        local temp_checksum
        temp_checksum=$(mktemp)
        if curl -sL -o "${temp_checksum}" "${checksum_url}"; then
            if [[ -n "${archive_filename}" ]] && grep -F "${archive_filename}" "${temp_checksum}" &>/dev/null; then
                expected_sha=$(grep -F "${archive_filename}" "${temp_checksum}" | awk '{print $1}')
                log_verbose "Gefundene Prüfsumme für ${archive_filename}: ${expected_sha}"
            else
                expected_sha=$(awk '{print $1}' "${temp_checksum}")
            fi
            rm -f "${temp_checksum}"
        else
            log_warn "Prüfsumme konnte nicht geladen werden. Überspringe Verifizierung."
        fi
    elif [[ -n "${WINE_SHAS[${version}]:-}" ]]; then
        expected_sha="${WINE_SHAS[${version}]}"
    fi

    if [[ -n "${expected_sha}" ]]; then
        local actual_sha=""
        if (( ${#expected_sha} == 128 )); then
            log_verbose "Verwende SHA512..."
            actual_sha=$(sha512sum "${temp_file}" | awk '{print $1}')
        else
            log_verbose "Verwende SHA256..."
            actual_sha=$(sha256sum "${temp_file}" | awk '{print $1}')
        fi

        if [[ "${actual_sha}" != "${expected_sha}" ]]; then
            log_error "SHA-Prüfsummenfehler! Erwartet: ${expected_sha}, erhalten: ${actual_sha}"
            rm -f "${temp_file}"
            return 1
        fi
        log_info "Prüfsumme erfolgreich verifiziert."
    else
        log_warn "Keine Prüfsumme zur Verifizierung verfügbar."
    fi

    mkdir -p "${target_dir}"
    if [[ "${url}" == *.tar.xz || "${url}" == *.tar.zst || "${url}" == *.tar.gz ]]; then
        tar -xf "${temp_file}" -C "${target_dir}" --strip-components=1
    elif [[ "${url}" == *.zip ]]; then
        unzip -q "${temp_file}" -d "${target_dir}"
    fi

    rm -f "${temp_file}"
    log_info "Erfolgreich installiert: '${version}'."
}

remove_wine() {
    local version="${1:-}"
    if [[ -z "${version}" ]]; then
        log_error "Fehler: Keine Wine-Version zum Löschen angegeben."
        return 1
    fi

    local target_dir
    target_dir=$(resolve_wine_path "${version}")

    if [[ -z "${target_dir}" || ! -d "${target_dir}" ]]; then
        log_warn "Wine-Version '${version}' ist nicht installiert."
        return 0
    fi

    if ! confirm_action "Möchtest du Wine-Version '${version}' wirklich löschen?"; then
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY] rm -rf ${target_dir}"
        return 0
    fi

    rm -rf "${target_dir}"
    local temp_meta
    temp_meta=$(mktemp)
    jq --arg name "${version}" 'del(.custom_wines[$name])' "${METADATA_FILE}" > "${temp_meta}"
    mv "${temp_meta}" "${METADATA_FILE}"

    log_info "Wine-Version '${version}' gelöscht."
}

list_wine() {
    echo -e "${COLOR_CYAN}--- Installierte Wine-Versionen ---${COLOR_RESET}"
    local local_found=false
    if [[ -d "${DEFAULT_WINE_DIR}" ]]; then
        for dir in "${DEFAULT_WINE_DIR}"/*; do
            if [[ -d "${dir}" ]]; then
                local_found=true
                printf "  %-30s [%s]\n" "$(basename "${dir}")" "${COLOR_GREEN}Installiert${COLOR_RESET}"
            fi
        done
    fi
    [[ "${local_found}" == "false" ]] && echo "  Keine installierten Versionen gefunden."

    local customs
    mapfile -t customs < <(jq -r '.custom_wines | keys[]' "${METADATA_FILE}" 2>/dev/null || true)
    if (( ${#customs[@]} > 0 )); then
        echo -e "\n${COLOR_CYAN}--- Registrierte lokale Versionen ---${COLOR_RESET}"
        for key in "${customs[@]}"; do
            local path
            path=$(jq -r --arg k "${key}" '.custom_wines[$k]' "${METADATA_FILE}")
            printf "  %-30s [%s] (%s)\n" "${key}" "${COLOR_GREEN}Registriert${COLOR_RESET}" "${path}"
        done
    fi
}

# --- Core-Präfixverwaltung ---
create_prefix() {
    local name="${1:-}"
    local version="${2:-}"
    local type="${3:-gaming}"
    local exe_arch_path="${4:-}"

    if [[ -z "${name}" || -z "${version}" ]]; then
        log_error "Fehler: Name und Wine-Version müssen angegeben werden."
        return 1
    fi

    local prefix_path="${DEFAULT_PREFIX_DIR}/${name}"
    local wine_path
    wine_path=$(resolve_wine_path "${version}")

    local wine_bin
    wine_bin=$(resolve_wine_binary "${wine_path}")

    if [[ -z "${wine_bin}" ]]; then
        log_error "Wine Binary für Version '${version}' konnte unter '${wine_path}' nicht gefunden werden."
        return 1
    fi

    if [[ -d "${prefix_path}" ]]; then
        log_warn "Prefix '${name}' existiert bereits unter: ${prefix_path}"
        return 0
    fi

    local arch="win64"
    if [[ -n "${exe_arch_path}" ]]; then
        arch=$(detect_exe_arch "${exe_arch_path}")
        log_info "Erkannte Anwendungsarchitektur: ${arch}"
    fi

    if [[ "${arch}" == "win32" ]]; then
        verify_multilib_support
    fi

    log_info "Erstelle Prefix '${name}' [Typ: ${type}, Arch: ${arch}] mit '${version}'..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY] Initialisiere WINEPREFIX=${prefix_path} WINEARCH=${arch}"
        return 0
    fi

    export WINEPREFIX="${prefix_path}"
    export WINEARCH="${arch}"
    export WINEDEBUG=-all
    export WINE="${wine_bin}"
    export WINESERVER
    WINESERVER=$(resolve_wineserver_binary "${wine_path}")

    mkdir -p "${prefix_path}"
    "${wine_bin}boot" -u

    local esync=1
    local fsync=1
    local dxvk=0
    local vkd3d=0

    log_info "Installiere Standard-Komponenten via Winetricks (corefonts, vcrun2019)..."
    winetricks -q corefonts vcrun2019 || log_warn "Einige Winetricks-Komponenten konnten nicht geladen werden."

    if [[ "${type}" == "gaming" ]]; then
        log_info "Aktiviere Gaming-Optimierungen (DXVK, VKD3D)..."
        winetricks -q dxvk vkd3d || log_warn "DXVK/VKD3D Installation unvollständig."
        dxvk=1
        vkd3d=1
        "${wine_bin}" reg add 'HKCU\Software\Wine\DllOverrides' /v 'd3d11' /t REG_SZ /d 'native,builtin' /f
        "${wine_bin}" reg add 'HKCU\Software\Wine\DllOverrides' /v 'dxgi' /t REG_SZ /d 'native,builtin' /f
    else
        log_info "Deaktiviere ungenutzte Desktopintegrationen..."
        "${wine_bin}" reg add 'HKCU\Software\Wine\DllOverrides' /v 'winemenubuilder.exe' /t REG_SZ /d '' /f
    fi

    local metadata
    metadata=$(jq -n \
        --arg path "${prefix_path}" \
        --arg ver "${version}" \
        --arg t "${type}" \
        --arg arch "${arch}" \
        --argjson e "${esync}" \
        --argjson f "${fsync}" \
        --argjson d "${dxvk}" \
        --argjson v "${vkd3d}" \
        '{path: $path, wine_version: $ver, type: $t, arch: $arch, esync: $e, fsync: $f, dxvk: $d, vkd3d: $v}')

    update_prefix_metadata "${name}" "${metadata}"
    log_info "Prefix '${name}' erfolgreich erstellt."
}

# --- Prozess- & Startmanagement ---
run_exe_in_prefix() {
    local name="${1:-}"
    local exe_path="${2:-}"
    if [[ -z "${name}" || -z "${exe_path}" ]]; then
        log_error "Fehler: Name und Pfad zur EXE müssen übergeben werden."
        return 1
    fi
    shift 2 || shift $#

    if [[ ! -f "${exe_path}" ]]; then
        log_error "Ausführbare Datei '${exe_path}' existiert nicht."
        return 1
    fi

    local metadata
    metadata=$(jq -r --arg n "${name}" '.prefixes[$n] // empty' "${METADATA_FILE}")
    if [[ -z "${metadata}" ]]; then
        log_error "Prefix '${name}' ist nicht registriert."
        return 1
    fi

    local p_path
    local p_ver
    local p_esync
    local p_fsync
    local p_arch

    p_path=$(echo "${metadata}" | jq -r '.path')
    p_ver=$(echo "${metadata}" | jq -r '.wine_version')
    p_esync=$(echo "${metadata}" | jq -r '.esync')
    p_fsync=$(echo "${metadata}" | jq -r '.fsync')
    p_arch=$(echo "${metadata}" | jq -r '.arch // "win64"')

    local wine_path
    wine_path=$(resolve_wine_path "${p_ver}")
    local wine_bin
    wine_bin=$(resolve_wine_binary "${wine_path}")

    if [[ -z "${wine_bin}" ]]; then
        log_error "Wine-Binary für '${p_ver}' nicht gefunden."
        return 1
    fi

    log_info "Starte '${exe_path}' in Prefix '${name}'..."

    export WINEPREFIX="${p_path}"
    export WINEARCH="${p_arch}"
    export WINEESYNC="${p_esync}"
    export WINEFSYNC="${p_fsync}"
    export WINEDEBUG=-all
    export WINESERVER
    WINESERVER=$(resolve_wineserver_binary "${wine_path}")

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY] WINEPREFIX=${p_path} WINEARCH=${p_arch} WINEESYNC=${p_esync} WINEFSYNC=${p_fsync} ${wine_bin} '${exe_path}'"
        return 0
    fi

    "${wine_bin}" "${exe_path}" "$@" &
    local pid=$!
    log_info "Prozess im Hintergrund gestartet (PID: ${pid})."
}

kill_prefix_processes() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then
        log_error "Fehler: Kein Prefix-Name angegeben."
        return 1
    fi

    local metadata
    metadata=$(jq -r --arg n "${name}" '.prefixes[$n] // empty' "${METADATA_FILE}")
    if [[ -z "${metadata}" ]]; then
        log_error "Prefix '${name}' nicht gefunden."
        return 1
    fi

    local p_path
    p_path=$(echo "${metadata}" | jq -r '.path')
    local p_ver
    p_ver=$(echo "${metadata}" | jq -r '.wine_version')

    local wine_path
    wine_path=$(resolve_wine_path "${p_ver}")
    local server_bin
    server_bin=$(resolve_wineserver_binary "${wine_path}")

    log_info "Sende Beendigungs-Signal an alle Prozesse im Prefix '${name}'..."
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY] WINEPREFIX=${p_path} ${server_bin} -k"
        return 0
    fi

    if [[ -x "${server_bin}" ]]; then
        WINEPREFIX="${p_path}" "${server_bin}" -k || true
        log_info "Prozesse für '${name}' beendet."
    else
        log_warn "wineserver nicht gefunden oder nicht ausführbar unter ${server_bin}."
    fi
}

# --- Präfix-Einstellungen ändern ---
configure_prefix() {
    local name="${1:-}"
    local setting="${2:-}"
    local value="${3:-}"

    if [[ -z "${name}" || -z "${setting}" ]]; then
        log_error "Fehler: Name und Einstellung müssen angegeben werden."
        return 1
    fi

    local metadata
    metadata=$(jq -r --arg n "${name}" '.prefixes[$n] // empty' "${METADATA_FILE}")
    if [[ -z "${metadata}" ]]; then
        log_error "Prefix '${name}' existiert nicht."
        return 1
    fi

    local new_meta
    if [[ "${setting}" == "wine_version" ]]; then
        local target_path
        target_path=$(resolve_wine_path "${value}")
        if [[ ! -d "${target_path}" ]]; then
            log_error "Target Wine-Version '${value}' ist nicht installiert."
            return 1
        fi
        new_meta=$(echo "${metadata}" | jq --arg val "${value}" '.wine_version = $val')
    else
        new_meta=$(echo "${metadata}" | jq --arg sec "${setting}" --argjson val "${value}" '.[$sec] = $val')
    fi

    update_prefix_metadata "${name}" "${new_meta}"
    log_info "Einstellung '${setting}' für '${name}' auf '${value}' gesetzt."
}

# --- TUI-Hilfsfunktionen ---
paged_selector() {
    local -n all_items=$1
    local prompt=$2

    local filtered_items=()
    local filtered_indices=()
    local search_query=""

    local start=0
    local limit=10

    while true; do
        filtered_items=()
        filtered_indices=()
        for i in "${!all_items[@]}"; do
            local item_lower="${all_items[i],,}"
            local query_lower="${search_query,,}"
            if [[ -z "${search_query}" ]] || [[ "${item_lower}" == *"${query_lower}"* ]]; then
                filtered_items+=("${all_items[i]}")
                filtered_indices+=("${i}")
            fi
        done

        local total=${#filtered_items[@]}

        if (( start >= total && total > 0 )); then
            start=$(( (total - 1) / limit * limit ))
        fi
        if (( start < 0 )); then start=0; fi

        clear >&2
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}" >&2
        echo "   ${COLOR_GREEN}${prompt}${COLOR_RESET}" >&2
        if [[ -n "${search_query}" ]]; then
            echo "   Filter: ${COLOR_YELLOW}'${search_query}'${COLOR_RESET} (${total} Treffer)" >&2
        else
            echo "   Gesamteinträge: ${total}" >&2
        fi
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}" >&2

        local end=$((start + limit))
        (( end > total )) && end=total

        if (( total == 0 )); then
            echo "  ${COLOR_RED}Keine passenden Einträge gefunden.${COLOR_RESET}" >&2
        else
            for ((i=start; i<end; i++)); do
                printf "  %2d) %s\n" $((i - start + 1)) "${filtered_items[i]}" >&2
            done
        fi

        echo "${COLOR_CYAN}-----------------------------------------------${COLOR_RESET}" >&2
        local current_page=$((total == 0 ? 0 : start / limit + 1))
        local total_pages=$(((total + limit - 1) / limit))
        printf " Seite %d/%d | [n] Weiter | [p] Zurück | [f] Filtern | [c] Filter leeren | [q] Abbrechen\n" \
            "${current_page}" "${total_pages}" >&2
        echo "${COLOR_CYAN}-----------------------------------------------${COLOR_RESET}" >&2

        local input
        read -rp "Auswahl (1-$((end - start))) oder Befehl: " input < /dev/tty

        case "${input}" in
            n|N)
                if (( start + limit < total )); then
                    start=$((start + limit))
                fi
                ;;
            p|P)
                if (( start - limit >= 0 )); then
                    start=$((start - limit))
                fi
                ;;
            f|F)
                read -rp "Suchbegriff eingeben: " search_query < /dev/tty
                start=0
                ;;
            c|C)
                search_query=""
                start=0
                ;;
            q|Q)
                echo "255"
                return 0
                ;;
            *)
                if [[ "${input}" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= (end - start) )); then
                    local selected_filtered_idx=$((start + input - 1))
                    local original_idx=${filtered_indices[selected_filtered_idx]}
                    echo "${original_idx}"
                    return 0
                fi
                ;;
        esac
    done
}

menu_download_scrollable() {
    clear
    echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
    echo "       ${COLOR_GREEN}Wine Manager - Download-Familie wählen${COLOR_RESET}   "
    echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
    echo "1) Kron4ek-Builds (Kron4ek/Wine-Builds)"
    echo "2) Steam-Proton (GloriousEggroll/proton-ge-custom)"
    echo "3) CachyOS-Wine (CachyOS/proton-cachyos)"
    echo "4) Abbrechen"
    echo ""
    read -rp "Auswahl [1-4]: " fam_opt

    local repo=""
    local name_prefix=""
    case "${fam_opt}" in
        1) repo="Kron4ek/Wine-Builds"; name_prefix="kron4ek" ;;
        2) repo="GloriousEggroll/proton-ge-custom"; name_prefix="steam-proton" ;;
        3) repo="CachyOS/proton-cachyos"; name_prefix="cachyos-wine" ;;
        *) return 0 ;;
    esac

    local releases_json
    releases_json=$(fetch_github_releases "${repo}") || {
        log_error "Fehler beim Abrufen der Releases."
        sleep 2
        return 1
    }

    local tags=()
    local urls=()
    local checksums_list=()
    local asset_names=()

    local parser_filter='
        .[] | select(.assets != null) | .tag_name as $tag |
        ([.assets[] | select(.name? | (endswith(".sha512sum") or endswith(".sha256sum") or endswith(".sha256") or endswith(".sha512") or endswith("sums.txt"))) | .browser_download_url] | join(",")) as $checksums |
        .assets[] | select(.name? | (endswith(".tar.xz") or endswith(".tar.zst") or endswith(".tar.gz") or endswith(".zip")) and (test("arm|aarch64"; "i") | not)) |
        "\($tag) [\(.name)]\t\(.browser_download_url)\t\($checksums)\t\(.name)"
    '

    local r_tag_asset r_url r_checksums r_asset_name
    while IFS=$'\t' read -r r_tag_asset r_url r_checksums r_asset_name; do
        if [[ -n "${r_tag_asset}" ]]; then
            tags+=("${r_tag_asset}")
            urls+=("${r_url}")
            checksums_list+=("${r_checksums}")
            asset_names+=("${r_asset_name}")
        fi
    done < <(echo "${releases_json}" | jq -r "${parser_filter}" 2>/dev/null || true)

    if (( ${#tags[@]} == 0 )); then
        log_error "Keine kompatiblen x86_64 Releases (.tar.xz/.tar.zst/.zip) auf GitHub gefunden."
        sleep 2
        return 1
    fi

    local selected_idx
    selected_idx=$(paged_selector tags "Wähle Version zum Download")

    if [[ ! "${selected_idx}" =~ ^[0-9]+$ ]] || [[ "${selected_idx}" == "255" ]]; then
        log_info "Download abgebrochen."
        sleep 1
        return 0
    fi

    local target_tag_asset="${tags[selected_idx]}"
    local target_url="${urls[selected_idx]}"
    local target_checksums="${checksums_list[selected_idx]}"
    local target_asset_name="${asset_names[selected_idx]}"

    local best_checksum=""
    if [[ -n "${target_checksums}" ]]; then
        IFS=',' read -r -a cs_array <<< "${target_checksums}"
        for cs in "${cs_array[@]}"; do
            if [[ "${cs}" == *"${target_asset_name}"* ]]; then
                best_checksum="${cs}"
                break
            fi
        done
        if [[ -z "${best_checksum}" && ${#cs_array[@]} -gt 0 ]]; then
            for cs in "${cs_array[@]}"; do
                if [[ "${cs}" == *"sums.txt"* || "${cs}" == *"sum"* ]]; then
                    best_checksum="${cs}"
                    break
                fi
            done
            [[ -z "${best_checksum}" ]] && best_checksum="${cs_array[0]}"
        fi
    fi

    local archive_name="${target_asset_name}"
    archive_name="${archive_name%.tar.xz}"
    archive_name="${archive_name%.tar.zst}"
    archive_name="${archive_name%.tar.gz}"
    archive_name="${archive_name%.zip}"

    local custom_version_name="${name_prefix}-${archive_name}"

    download_and_verify "${custom_version_name}" "${target_url}" "${best_checksum}" "${target_asset_name}"
    sleep 2
}

# --- TUI-Menüstrukturen ---
menu_wine_versions() {
    while true; do
        clear
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        echo "         ${COLOR_GREEN}Wine Manager - Wine-Versionen${COLOR_RESET}         "
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        list_wine
        echo ""
        echo "1) Neue Version aus GitHub-Releases herunterladen"
        echo "2) Lokales Wine-Verzeichnis registrieren"
        echo "3) Wine-Version löschen"
        echo "4) Zurück zum Hauptmenü"
        echo ""
        read -rp "Auswahl [1-4]: " opt
        case "${opt}" in
            1)
                menu_download_scrollable
                ;;
            2)
                read -rp "Name für die eigene Version: " custom_name
                read -e -rp "Absoluter Pfad zum Root-Ordner (z.B. /usr oder ~/.local/share/lutris/runners/wine/...): " -i "${HOME}/" custom_path
                if [[ -d "${custom_path}" ]]; then
                    local bin
                    bin=$(resolve_wine_binary "${custom_path}")
                    if [[ -n "${bin}" ]]; then
                        register_custom_wine_metadata "${custom_name}" "${custom_path}"
                    else
                        log_error "Keine gültige 'bin/wine' Struktur in diesem Verzeichnis gefunden."
                    fi
                else
                    log_error "Pfad existiert nicht."
                fi
                sleep 2
                ;;
            3)
                read -rp "Name der zu löschenden Version: " del_ver
                remove_wine "${del_ver}"
                sleep 2
                ;;
            4) return 0 ;;
            *) log_warn "Ungültige Option." ; sleep 1 ;;
        esac
    done
}

menu_prefixes() {
    while true; do
        clear
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        echo "            ${COLOR_GREEN}Wine Manager - Prefixes${COLOR_RESET}            "
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"

        if [[ ! -f "${METADATA_FILE}" ]] || [[ "$(jq '.prefixes | length' "${METADATA_FILE}")" == "0" ]]; then
            echo "Keine registrierten Prefixes gefunden."
            echo ""
            echo "1) Neuen Prefix anlegen"
            echo "2) Zurück zum Hauptmenü"
            read -rp "Auswahl: " opt
            case "${opt}" in
                1) menu_create_prefix ; sleep 2 ;;
                2) return 0 ;;
                *) log_warn "Ungültige Option" ; sleep 1 ;;
            esac
            continue
        fi

        local keys=()
        local idx=1
        while read -r key; do
            local ver
            local path
            ver=$(jq -r --arg k "${key}" '.prefixes[$k].wine_version' "${METADATA_FILE}")
            path=$(jq -r --arg k "${key}" '.prefixes[$k].path' "${METADATA_FILE}")

            local active="inaktiv"
            if command -v pgrep &>/dev/null; then
                for pid in $(pgrep -u "$(id -u)" -x wineserver 2>/dev/null || true); do
                    if [[ -r "/proc/${pid}/environ" ]]; then
                        if tr '\0' '\n' < "/proc/${pid}/environ" 2>/dev/null | grep -qx "WINEPREFIX=${path}"; then
                            active="${COLOR_GREEN}AKTIV${COLOR_RESET}"
                            break
                        fi
                    fi
                done
            fi

            printf "  %2d) %-20s [%-15s] (%s) [%s]\n" "${idx}" "${key}" "${ver}" "${path}" "${active}"
            keys+=("${key}")
            idx=$((idx+1))
        done < <(jq -r '.prefixes | keys[]' "${METADATA_FILE}")

        echo ""
        echo "a) Neuen Prefix anlegen"
        echo "z) Zurück zum Hauptmenü"
        echo ""
        read -rp "Prefix auswählen (Nummer) oder Aktion wählen: " p_opt

        if [[ "${p_opt}" == "a" ]]; then
            menu_create_prefix
            sleep 2
        elif [[ "${p_opt}" == "z" ]]; then
            return 0
        elif [[ "${p_opt}" =~ ^[0-9]+$ ]] && (( p_opt >= 1 && p_opt < idx )); then
            menu_manage_single_prefix "${keys[$((p_opt-1))]}"
        else
            log_warn "Ungültige Eingabe."
            sleep 1
        fi
    done
}

menu_create_prefix() {
    read -rp "Name des neuen Prefixes (keine Sonderzeichen): " p_name
    if [[ -z "${p_name}" ]]; then
        log_error "Name darf nicht leer sein."
        return 1
    fi

    echo "Verfügbare Wine-Versionen:"
    local list_vers=()
    local i=1
    while read -r ver; do
        echo "  ${i}) ${ver}"
        list_vers+=("${ver}")
        i=$((i+1))
    done < <((jq -r '.custom_wines | keys[]' "${METADATA_FILE}" 2>/dev/null; find "${DEFAULT_WINE_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null) | sort -u)

    if (( ${#list_vers[@]} == 0 )); then
        log_error "Keine installierten Wine-Versionen gefunden. Bitte lade zuerst eine herunter."
        return 1
    fi

    read -rp "Wähle Wine-Version (Nummer): " ver_idx
    if [[ ! "${ver_idx}" =~ ^[0-9]+$ ]] || (( ver_idx < 1 || ver_idx >= i )); then
        log_error "Ungültige Auswahl."
        return 1
    fi
    local selected_ver="${list_vers[$((ver_idx-1))]}"

    read -rp "Typ (1: gaming, 2: program) [Standard: 1]: " type_opt
    local selected_type="gaming"
    [[ "${type_opt}" == "2" ]] && selected_type="program"

    read -e -rp "Optional: Pfad zur EXE zur automatischen Architekturbestimmung: " -i "${HOME}/" p_exe_detect
    local actual_exe=""
    if [[ -n "${p_exe_detect}" && -f "${p_exe_detect}" ]]; then
        actual_exe="${p_exe_detect}"
    fi

    create_prefix "${p_name}" "${selected_ver}" "${selected_type}" "${actual_exe}"
}

menu_launch_detected_programs() {
    local name="$1"
    local path="$2"

    clear
    echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
    echo "   Programme in Prefix: ${COLOR_GREEN}${name}${COLOR_RESET}"
    echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
    log_info "Scanne Prefix nach installierten Programmen..."

    local apps=()
    local app_paths=()

    while IFS= read -r app_path; do
        [[ -z "${app_path}" ]] && continue
        app_paths+=("${app_path}")
        local base
        base=$(basename "${app_path}")
        local parent
        parent=$(basename "$(dirname "${app_path}")")
        apps+=("${base} (${parent})")
    done < <(detect_installed_programs "${path}")

    if (( ${#apps[@]} == 0 )); then
        log_warn "Keine installierten Programme automatisch erkannt."
        echo ""
        read -rp "Drücke Enter, um zurückzugehen..." < /dev/tty
        return 0
    fi

    local selected_idx
    selected_idx=$(paged_selector apps "Wähle ein Programm aus")

    if [[ ! "${selected_idx}" =~ ^[0-9]+$ ]] || [[ "${selected_idx}" == "255" ]]; then
        return 0
    fi

    local exe_to_run="${app_paths[selected_idx]}"
    local display_name="${apps[selected_idx]}"

    while true; do
        clear
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        echo "   Programm: ${COLOR_GREEN}${display_name}${COLOR_RESET}"
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        echo "1) Programm starten"
        echo "2) Desktop-Verknüpfung (.desktop) erstellen"
        echo "3) Zurück"
        echo ""
        read -rp "Auswahl [1-3]: " opt < /dev/tty
        case "${opt}" in
            1)
                run_exe_in_prefix "${name}" "${exe_to_run}"
                sleep 2
                break
                ;;
            2)
                local base_app_name
                base_app_name=$(basename "${exe_to_run}" .exe)
                generate_desktop_shortcut "${name}" "${exe_to_run}" "${base_app_name}"
                sleep 2
                break
                ;;
            3)
                break
                ;;
            *)
                log_warn "Ungültige Auswahl."
                sleep 1
                ;;
        esac
    done
}

menu_manage_single_prefix() {
    local name="$1"
    while true; do
        clear
        local metadata
        metadata=$(jq -r --arg n "${name}" '.prefixes[$n]' "${METADATA_FILE}")
        local path
        local ver
        local type
        local arch
        local esync
        local fsync
        local dxvk
        local vkd3d

        path=$(echo "${metadata}" | jq -r '.path')
        ver=$(echo "${metadata}" | jq -r '.wine_version')
        type=$(echo "${metadata}" | jq -r '.type')
        arch=$(echo "${metadata}" | jq -r '.arch // "win64"')
        esync=$(echo "${metadata}" | jq -r '.esync')
        fsync=$(echo "${metadata}" | jq -r '.fsync')
        dxvk=$(echo "${metadata}" | jq -r '.dxvk')
        vkd3d=$(echo "${metadata}" | jq -r '.vkd3d')

        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        echo "   Prefix verwalten: ${COLOR_GREEN}${name}${COLOR_RESET}"
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        echo " Pfad:         ${path}"
        echo " Wine-Version: ${ver}"
        echo " Architektur:  ${arch}"
        echo " Typ:          ${type}"
        echo " ESYNC:        $( [[ "${esync}" == "1" ]] && echo "${COLOR_GREEN}An${COLOR_RESET}" || echo "${COLOR_RED}Aus${COLOR_RESET}" )"
        echo " FSYNC:        $( [[ "${fsync}" == "1" ]] && echo "${COLOR_GREEN}An${COLOR_RESET}" || echo "${COLOR_RED}Aus${COLOR_RESET}" )"
        echo " DXVK:         $( [[ "${dxvk}" == "1" ]] && echo "${COLOR_GREEN}An${COLOR_RESET}" || echo "${COLOR_RED}Aus${COLOR_RESET}" )"
        echo " VKD3D:        $( [[ "${vkd3d}" == "1" ]] && echo "${COLOR_GREEN}An${COLOR_RESET}" || echo "${COLOR_RED}Aus${COLOR_RESET}" )"
        echo "${COLOR_CYAN}-----------------------------------------------${COLOR_RESET}"
        echo "1) Installierte Programme verwalten & starten (Automatische Erkennung)"
        echo "2) EXE/MSI-Programm manuell starten"
        echo "3) Winetricks im Prefix öffnen"
        echo "4) Einstellungen anpassen (ESYNC/FSYNC/DXVK/VKD3D/Wine-Version)"
        echo "5) Alle laufenden Prozesse dieses Prefixes beenden (Kill)"
        echo "6) Prefix löschen (Sicheres Löschen)"
        echo "7) Zurück zur Prefixliste"
        echo ""
        read -rp "Auswahl [1-7]: " opt
        case "${opt}" in
            1)
                menu_launch_detected_programs "${name}" "${path}"
                ;;
            2)
                read -e -rp "Pfad zur EXE/MSI-Datei: " -i "${HOME}/" target_exe
                run_exe_in_prefix "${name}" "${target_exe}"
                sleep 2
                ;;
            3)
                log_info "Starte Winetricks..."
                export WINEPREFIX="${path}"
                local wine_path
                wine_path=$(resolve_wine_path "${ver}")
                export WINE=$(resolve_wine_binary "${wine_path}")
                export WINESERVER
                WINESERVER=$(resolve_wineserver_binary "${wine_path}")
                winetricks || log_warn "Winetricks beendet."
                ;;
            4)
                menu_prefix_settings "${name}"
                ;;
            5)
                kill_prefix_processes "${name}"
                sleep 2
                ;;
            6)
                remove_prefix "${name}"
                return 0
                ;;
            7) return 0 ;;
            *) log_warn "Ungültige Auswahl." ; sleep 1 ;;
        esac
    done
}

menu_prefix_settings() {
    local name="$1"
    while true; do
        clear
        echo "${COLOR_CYAN}--- Einstellungen für ${name} ---${COLOR_RESET}"
        echo "1) ESYNC umschalten"
        echo "2) FSYNC umschalten"
        echo "3) DXVK umschalten"
        echo "4) VKD3D umschalten"
        echo "5) Wine-Version ändern"
        echo "6) Zurück"
        echo ""
        read -rp "Auswahl [1-6]: " opt

        local metadata
        metadata=$(jq -r --arg n "${name}" '.prefixes[$n]' "${METADATA_FILE}")

        case "${opt}" in
            1)
                local cur
                cur=$(echo "${metadata}" | jq -r '.esync')
                local val=$((1 - cur))
                configure_prefix "${name}" "esync" "${val}"
                sleep 1
                ;;
            2)
                local cur
                cur=$(echo "${metadata}" | jq -r '.fsync')
                local val=$((1 - cur))
                configure_prefix "${name}" "fsync" "${val}"
                sleep 1
                ;;
            3)
                local cur
                cur=$(echo "${metadata}" | jq -r '.dxvk')
                local val=$((1 - cur))
                configure_prefix "${name}" "dxvk" "${val}"
                sleep 1
                ;;
            4)
                local cur
                cur=$(echo "${metadata}" | jq -r '.vkd3d')
                local val=$((1 - cur))
                configure_prefix "${name}" "vkd3d" "${val}"
                sleep 1
                ;;
            5)
                echo "Verfügbare Versionen:"
                local list_vers=()
                local i=1
                while read -r ver; do
                    echo "  ${i}) ${ver}"
                    list_vers+=("${ver}")
                    i=$((i+1))
                done < <((jq -r '.custom_wines | keys[]' "${METADATA_FILE}" 2>/dev/null; find "${DEFAULT_WINE_DIR}" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null) | sort -u)

                read -rp "Wähle neue Wine-Version (Nummer): " ver_idx
                if [[ "${ver_idx}" =~ ^[0-9]+$ ]] && (( ver_idx >= 1 && ver_idx < i )); then
                    configure_prefix "${name}" "wine_version" "${list_vers[$((ver_idx-1))]}"
                else
                    log_error "Ungültige Auswahl."
                fi
                sleep 2
                ;;
            6) return 0 ;;
            *) log_warn "Ungültige Auswahl." ; sleep 1 ;;
        esac
    done
}

menu_backups() {
    while true; do
        clear
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        echo "         ${COLOR_GREEN}Wine Manager - Backup & Restore${COLOR_RESET}         "
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        echo "1) Prefix sichern (Backup)"
        echo "2) Prefix wiederherstellen (Restore)"
        echo "3) Zurück zum Hauptmenü"
        echo ""
        read -rp "Auswahl [1-3]: " opt
        case "${opt}" in
            1)
                read -rp "Name des zu sichernden Prefixes: " p_name
                backup_prefix "${p_name}"
                sleep 2
                ;;
            2)
                read -rp "Name für den wiederherzustellenden Prefix: " p_name
                read -e -rp "Pfad zur Backup-Datei (.tar.gz): " -i "${DEFAULT_PREFIX_DIR}/" p_file
                restore_prefix "${p_name}" "${p_file}"
                sleep 2
                ;;
            3) return 0 ;;
            *) log_warn "Ungültige Auswahl." ; sleep 1 ;;
        esac
    done
}

interactive_menu() {
    set +e
    while true; do
        clear
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        echo "       ${COLOR_GREEN}Wine Manager CLI - Interaktives Menü${COLOR_RESET}       "
        echo "${COLOR_CYAN}===============================================${COLOR_RESET}"
        echo "1) Wine-Versionen verwalten"
        echo "2) Prefixes verwalten"
        echo "3) Backup & Restore"
        echo "4) Beenden"
        echo ""
        read -rp "Auswahl [1-4]: " main_opt
        case "${main_opt}" in
            1) menu_wine_versions ;;
            2) menu_prefixes ;;
            3) menu_backups ;;
            4) exit 0 ;;
            *) log_warn "Ungültige Auswahl." ; sleep 1 ;;
        esac
    done
}

# --- CLI & Utility-Funktionen ---
remove_prefix() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then
        log_error "Fehler: Kein Prefix-Name angegeben."
        return 1
    fi
    local prefix_path="${DEFAULT_PREFIX_DIR}/${name}"

    if [[ ! -d "${prefix_path}" ]]; then
        log_warn "Prefix '${name}' existiert nicht."
        return 0
    fi

    if ! confirm_action "Möchtest du den Prefix '${name}' wirklich löschen?"; then
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY] Entferne Prefix-Verzeichnis und Metadaten."
        return 0
    fi

    safe_delete_dir "${prefix_path}"
    remove_prefix_metadata "${name}"
    log_info "Prefix '${name}' wurde erfolgreich entfernt."
}

backup_prefix() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then
        log_error "Fehler: Kein Prefix-Name angegeben."
        return 1
    fi
    local prefix_path="${DEFAULT_PREFIX_DIR}/${name}"
    local backup_file="${DEFAULT_PREFIX_DIR}/${name}_backup_$(date +%Y%m%d_%H%M%S).tar.gz"

    if [[ ! -d "${prefix_path}" ]]; then
        log_error "Prefix '${name}' existiert nicht."
        return 1
    fi

    log_info "Erstelle Backup von '${name}'..."
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY] tar -czf ${backup_file} -C ${DEFAULT_PREFIX_DIR} ${name}"
        return 0
    fi

    tar -czf "${backup_file}" -C "${DEFAULT_PREFIX_DIR}" "${name}"
    log_info "Backup erfolgreich erstellt unter: ${backup_file}"
}

restore_prefix() {
    local name="${1:-}"
    local file="${2:-}"
    if [[ -z "${name}" || -z "${file}" ]]; then
        log_error "Fehler: Name und Backup-Pfad müssen angegeben werden."
        return 1
    fi
    local dest_path="${DEFAULT_PREFIX_DIR}/${name}"

    if [[ ! -f "${file}" ]]; then
        log_error "Backup-Datei '${file}' wurde nicht gefunden."
        return 1
    fi

    if [[ -d "${dest_path}" ]]; then
        log_error "Ziel-Verzeichnis existiert bereits: '${dest_path}'."
        return 1
    fi

    log_info "Stelle Prefix wieder her..."
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY] tar -xzf ${file} -C ${DEFAULT_PREFIX_DIR}"
        return 0
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    tar -xzf "${file}" -C "${tmp_dir}"

    local extracted_dir
    extracted_dir=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d | head -n 1)

    if [[ -z "${extracted_dir}" ]]; then
        log_error "Das Backup-Archiv enthält kein gültiges Verzeichnis."
        rm -rf "${tmp_dir}"
        return 1
    fi

    mv "${extracted_dir}" "${dest_path}"
    rm -rf "${tmp_dir}"

    local metadata
    metadata=$(jq -n \
        --arg path "${dest_path}" \
        --arg ver "system" \
        --arg t "gaming" \
        --arg arch "win64" \
        '{path: $path, wine_version: $ver, type: $t, arch: $arch, esync: 1, fsync: 1, dxvk: 1, vkd3d: 1}')
    update_prefix_metadata "${name}" "${metadata}"
    log_info "Prefix erfolgreich hergestellt."
}

# --- Einstiegspunkt ---
main() {
    # Parsen globaler Flags vor der Ausführung
    while (( $# > 0 )); do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                ASSUME_YES=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -l|--log-file)
                if [[ $# -ge 2 && -n "${2:-}" ]]; then
                    DEFAULT_LOG_FILE="$2"
                    shift 2
                else
                    log_error "--log-file benötigt einen Pfad."
                    exit 1
                fi
                ;;
            -*)
                log_error "Unbekanntes Flag: $1"
                exit 1
                ;;
            *)
                # Beendet das globale Parsing beim ersten Unterbefehl
                break
                ;;
        esac
    done

    load_config
    init_directories
    validate_dependencies
    acquire_lock

    if (( $# == 0 )); then
        interactive_menu
        exit 0
    fi

    local cmd="$1"
    shift

    case "${cmd}" in
        install-wine)
            [[ -z "${1:-}" ]] && { log_error "Wine-Version benötigt."; exit 1; }
            download_and_verify "$1"
            ;;
        remove-wine)
            [[ -z "${1:-}" ]] && { log_error "Wine-Version benötigt."; exit 1; }
            remove_wine "$1"
            ;;
        list-wine)
            list_wine
            ;;
        create-prefix)
            [[ -z "${1:-}" ]] && { log_error "Prefix-Name benötigt."; exit 1; }
            local p_name="$1"
            shift

            local opt_version=""
            local opt_type="gaming"
            local opt_exe=""
            while (( $# > 0 )); do
                case "$1" in
                    --version)
                        if [[ $# -lt 2 || -z "${2:-}" ]]; then
                            log_error "--version benötigt einen Wert."
                            exit 1
                        fi
                        opt_version="$2"
                        shift 2
                        ;;
                    --type)
                        if [[ $# -lt 2 || -z "${2:-}" ]]; then
                            log_error "--type benötigt einen Wert."
                            exit 1
                        fi
                        opt_type="$2"
                        shift 2
                        ;;
                    --exe)
                        if [[ $# -lt 2 || -z "${2:-}" ]]; then
                            log_error "--exe benötigt einen Wert."
                            exit 1
                        fi
                        opt_exe="$2"
                        shift 2
                        ;;
                    *)
                        log_error "Ungültiges Argument: $1"
                        exit 1
                        ;;
                esac
            done

            [[ -z "${opt_version}" ]] && { log_error "--version ist zwingend erforderlich."; exit 1; }
            create_prefix "${p_name}" "${opt_version}" "${opt_type}" "${opt_exe}"
            ;;
        remove-prefix)
            [[ -z "${1:-}" ]] && { log_error "Prefix-Name benötigt."; exit 1; }
            remove_prefix "$1"
            ;;
        list-prefixes)
            if [[ ! -f "${METADATA_FILE}" ]] || [[ "$(jq '.prefixes | length' "${METADATA_FILE}")" == "0" ]]; then
                echo "Keine verwalteten Prefixes."
                exit 0
            fi
            jq -r '.prefixes | to_entries[] | "  - \(.key):\n      Path: \(.value.path)\n      Wine: \(.value.wine_version)\n      Type: \(.value.type)"' "${METADATA_FILE}"
            ;;
        run)
            [[ -z "${1:-}" ]] && { log_error "Prefix-Name benötigt."; exit 1; }
            [[ -z "${2:-}" ]] && { log_error "Pfad zur EXE/MSI benötigt."; exit 1; }
            local p_name="$1"
            local exe="$2"
            shift 2 || shift $#
            run_exe_in_prefix "${p_name}" "${exe}" "$@"
            ;;
        kill)
            [[ -z "${1:-}" ]] && { log_error "Prefix-Name benötigt."; exit 1; }
            kill_prefix_processes "$1"
            ;;
        register-wine)
            [[ -z "${1:-}" ]] || [[ -z "${2:-}" ]] && { log_error "Name und Pfad benötigt."; exit 1; }
            register_custom_wine_metadata "$1" "$2"
            ;;
        backup-prefix)
            [[ -z "${1:-}" ]] && { log_error "Prefix-Name benötigt."; exit 1; }
            backup_prefix "$1"
            ;;
        restore-prefix)
            [[ -z "${1:-}" ]] || [[ -z "${2:-}" ]] && { log_error "Prefix-Name und Backup-Pfad benötigt."; exit 1; }
            restore_prefix "$1" "$2"
            ;;
        *)
            log_error "Unbekannter Befehl: ${cmd}"
            show_help
            exit 1
            ;;
    esac
}

show_help() {
    cat <<EOF
Wine Manager CLI & TUI - Sichere & interaktive Wine/Prefix-Verwaltung

Verwendung:
  \$0 [FLAGS] [COMMAND] [ARGS]
  (Start ohne Parameter öffnet das interaktive Menü)

Flags:
  -d, --dry-run             Befehle anzeigen ohne Änderungen vorzunehmen
  -y, --yes                 Sicherheitsabfragen automatisch bestätigen
  -v, --verbose             Erweiterte Debug-Ausgaben anzeigen
  -l, --log-file <file>     Pfad zur Log-Datei ändern

Befehle:
  install-wine <version>    Installiert vordefiniertes Wine
  remove-wine <version>     Entfernt eine Wine-Version
  list-wine                 Listet alle Wine-Versionen auf
  register-wine <n> <p>     Registriert lokales Wine unter Pfad <p> mit Name <n>

  create-prefix <name>      Erstellt einen Prefix
    --version <version>     Genutzte Wine-Version
    --type <type>           Typ: gaming, program (Standard: gaming)
    --exe <path>            Optionale EXE zur Architekturerkennung (32/64-Bit)

  run <name> <exe> [args]   Startet eine Windows-Anwendung im Prefix
  kill <name>               Beendet alle Prozesse des Prefixes (wineserver -k)
  remove-prefix <name>      Entfernt einen Prefix (Safe Delete)
  list-prefixes             Gibt alle registrierten Prefixes aus
  backup-prefix <name>      Erstellt ein tar.gz Archiv des Prefixes
  restore-prefix <name> <f> Restoriert einen Prefix aus dem Archiv <f>
EOF
}

main "$@"
