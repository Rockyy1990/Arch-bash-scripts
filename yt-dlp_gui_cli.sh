#!/usr/bin/env bash
################################################################################
# yt-dlp Download Manager (Bash-Version)
# Audio, Video, Playlist-Downloads und Cookie-Management
#
# Abhängigkeiten : yt-dlp, ffmpeg
# Bash-Version   : >= 4.0
################################################################################

# ── Bash-Version prüfen ──────────────────────────────────────────────────────
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Fehler: Dieses Script benötigt Bash >= 4.0 (gefunden: ${BASH_VERSION})." >&2
    exit 1
fi

# set -u   -> unbound variables sind ein Fehler
# set -o pipefail -> Pipe-Fehler nicht verschlucken
# -e absichtlich NICHT aktiv (wegen interaktiver Menü-Eingaben)
set -u
set -o pipefail

# ── Konfiguration ────────────────────────────────────────────────────────────

readonly HOME_DIR="${HOME}"
readonly COOKIES_FILE="${HOME_DIR}/.config/yt-dlp/cookies.txt"
readonly DOWNLOAD_DIR="${HOME_DIR}/Downloads/yt-dlp"

mkdir -p "$(dirname "$COOKIES_FILE")" 2>/dev/null || true
mkdir -p "$DOWNLOAD_DIR"                2>/dev/null || true

readonly OUTPUT_SINGLE="${DOWNLOAD_DIR}/%(title)s.%(ext)s"
readonly OUTPUT_PLAYLIST="${DOWNLOAD_DIR}/%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"

# ── Farben ───────────────────────────────────────────────────────────────────
# Farben nur aktivieren, wenn:
#   - stdout ein TTY ist
#   - TERM != "dumb"
#   - NO_COLOR nicht gesetzt (https://no-color.org/)
if [[ -t 1 ]] && [[ "${TERM:-dumb}" != "dumb" ]] && [[ -z "${NO_COLOR:-}" ]]; then
    readonly C_RESET=$'\033[0m'
    readonly C_BOLD=$'\033[1m'
    readonly C_DIM=$'\033[2m'

    readonly C_RED=$'\033[0;31m'
    readonly C_GREEN=$'\033[0;32m'
    readonly C_YELLOW=$'\033[0;33m'
    readonly C_MAGENTA=$'\033[0;35m'
    readonly C_CYAN=$'\033[0;36m'

    readonly C_BRED=$'\033[1;31m'
    readonly C_BGREEN=$'\033[1;32m'
    readonly C_BYELLOW=$'\033[1;33m'
    readonly C_BCYAN=$'\033[1;36m'
    readonly C_BWHITE=$'\033[1;37m'
else
    readonly C_RESET=""   C_BOLD=""    C_DIM=""
    readonly C_RED=""     C_GREEN=""   C_YELLOW=""
    readonly C_MAGENTA="" C_CYAN=""
    readonly C_BRED=""    C_BGREEN=""  C_BYELLOW="" C_BCYAN="" C_BWHITE=""
fi

# ── Log-Funktionen ───────────────────────────────────────────────────────────

log_info()  { printf "%b\n" "${C_BCYAN}ℹ  ${C_RESET}${1}"; }
log_ok()    { printf "%b\n" "${C_BGREEN}✓  ${C_RESET}${C_GREEN}${1}${C_RESET}"; }
log_warn()  { printf "%b\n" "${C_BYELLOW}⚠  ${C_RESET}${C_YELLOW}${1}${C_RESET}" >&2; }
log_err()   { printf "%b\n" "${C_BRED}✗  ${C_RESET}${C_RED}${1}${C_RESET}" >&2; }
log_dl()    { printf "%b\n" "${C_BCYAN}⬇  ${C_RESET}${C_CYAN}${1}${C_RESET}"; }
log_up()    { printf "%b\n" "${C_BCYAN}⬆  ${C_RESET}${C_CYAN}${1}${C_RESET}"; }

# ── Trap für sauberes Beenden ────────────────────────────────────────────────

cleanup() {
    # Cursor wieder anzeigen, falls etwas ihn versteckt hat
    printf "%b" "${C_RESET}"
    echo ""
    exit 130
}
trap cleanup INT TERM

# ── Hilfsfunktionen ──────────────────────────────────────────────────────────

clear_screen() { clear; }

pause_menu() {
    echo ""
    read -r -p "$(printf "%b" "${C_DIM}Weiter mit Enter ...${C_RESET}")" _
}

is_valid_url() {
    local url="$1"                        # <- Fix: war \$1
    [[ "$url" =~ ^https?://[^[:space:]]+$ ]]
}

# Gibt bei Erfolg die URL auf stdout aus, Fehlermeldungen gehen auf stderr.
get_url() {
    local url
    read -r -p "$(printf "%b" "${C_BWHITE}URL eingeben: ${C_RESET}")" url

    # Whitespace trimmen
    url="${url#"${url%%[![:space:]]*}"}"
    url="${url%"${url##*[![:space:]]}"}"

    if [[ -z "$url" ]]; then
        log_warn "URL darf nicht leer sein."
        return 1
    fi

    if ! is_valid_url "$url"; then
        log_warn "Ungültiges URL-Format (erwartet: http:// oder https://)."
        return 1
    fi

    printf "%s\n" "$url"
}

run_yt_dlp() {
    local -a args=("$@")
    local exit_code=0

    if [[ -f "$COOKIES_FILE" ]]; then
        yt-dlp --cookies "$COOKIES_FILE" "${args[@]}" || exit_code=$?
    else
        yt-dlp "${args[@]}" || exit_code=$?
    fi

    case $exit_code in
        0)   return 0 ;;
        130) log_warn "Download abgebrochen (Ctrl+C)." ; return 1 ;;
        *)   log_err  "yt-dlp beendet mit Fehlercode $exit_code." ; return 1 ;;
    esac
}

open_directory() {
    local path="$1"                       # <- Fix: war \$1

    if [[ ! -d "$path" ]]; then
        log_warn "Verzeichnis existiert nicht: $path"
        return 1
    fi

    case "$OSTYPE" in
        darwin*)
            open "$path" 2>/dev/null || {
                log_warn "Verzeichnis konnte nicht geöffnet werden."
                return 1
            }
            ;;
        msys*|cygwin*|win32)
            if command -v explorer.exe &>/dev/null; then
                explorer.exe "$(cygpath -w "$path")" 2>/dev/null || {
                    log_warn "Verzeichnis konnte nicht geöffnet werden."
                    return 1
                }
            else
                log_warn "Explorer nicht gefunden."
                return 1
            fi
            ;;
        *)
            local opened=0
            local cmd
            for cmd in xdg-open nautilus dolphin thunar pcmanfm nemo caja; do
                if command -v "$cmd" &>/dev/null; then
                    "$cmd" "$path" &>/dev/null && { opened=1; break; }
                fi
            done
            if (( opened == 0 )); then
                log_warn "Kein Dateimanager gefunden (xdg-open, nautilus, dolphin, thunar, pcmanfm, nemo, caja)."
                return 1
            fi
            ;;
    esac
    return 0
}

check_yt_dlp() {
    if ! command -v yt-dlp &>/dev/null; then
        log_err "'yt-dlp' wurde nicht gefunden."
        printf "%b\n" "   ${C_DIM}Installation: pip install -U yt-dlp${C_RESET}"
        return 1
    fi
    return 0
}

check_ffmpeg() {
    if ! command -v ffmpeg &>/dev/null; then
        log_warn "'ffmpeg' wurde nicht gefunden — Merging/Konvertierung könnte scheitern."
    fi
}

# ── Download-Funktionen ──────────────────────────────────────────────────────

download_audio() {
    check_yt_dlp || { pause_menu; return; }
    local url
    url=$(get_url) || { pause_menu; return; }

    log_dl "Lade Audio herunter (M4A/AAC, beste Qualität) …"
    if run_yt_dlp \
        --extract-audio \
        --audio-format m4a \
        --audio-quality 0 \
        -o "$OUTPUT_SINGLE" \
        "$url"; then
        log_ok "Download abgeschlossen."
    fi
    pause_menu
}

download_video() {
    check_yt_dlp || { pause_menu; return; }
    check_ffmpeg
    local url
    url=$(get_url) || { pause_menu; return; }

    log_dl "Lade Video in bester Qualität herunter …"
    if run_yt_dlp \
        -f "bestvideo+bestaudio/best" \
        --merge-output-format mp4 \
        -o "$OUTPUT_SINGLE" \
        "$url"; then
        log_ok "Download abgeschlossen."
    fi
    pause_menu
}

download_audio_and_video() {
    check_yt_dlp || { pause_menu; return; }
    check_ffmpeg
    local url
    url=$(get_url) || { pause_menu; return; }

    log_dl "Lade Audio + Video herunter …"
    if run_yt_dlp \
        -f "bestvideo+bestaudio/best" \
        --merge-output-format mp4 \
        -o "$OUTPUT_SINGLE" \
        "$url"; then
        log_ok "Download abgeschlossen."
    fi
    pause_menu
}

download_playlist_audio() {
    check_yt_dlp || { pause_menu; return; }
    local url
    url=$(get_url) || { pause_menu; return; }

    log_dl "Lade Playlist (Audio) herunter …"
    if run_yt_dlp \
        --yes-playlist \
        --extract-audio \
        --audio-format m4a \
        --audio-quality 0 \
        -o "$OUTPUT_PLAYLIST" \
        "$url"; then
        log_ok "Playlist-Download abgeschlossen."
    fi
    pause_menu
}

download_playlist_video() {
    check_yt_dlp || { pause_menu; return; }
    check_ffmpeg
    local url
    url=$(get_url) || { pause_menu; return; }

    log_dl "Lade Playlist (Video) herunter …"
    if run_yt_dlp \
        --yes-playlist \
        -f "bestvideo+bestaudio/best" \
        --merge-output-format mp4 \
        -o "$OUTPUT_PLAYLIST" \
        "$url"; then
        log_ok "Playlist-Download abgeschlossen."
    fi
    pause_menu
}

# ── Cookie-Management ────────────────────────────────────────────────────────

declare -ra BROWSERS=(
    "firefox"
    "vivaldi"
    "chrome"
    "chromium"
    "brave"
    "edge"
)

import_cookies() {
    check_yt_dlp || { pause_menu; return; }

    echo ""
    printf "%b\n" "${C_BOLD}${C_BCYAN}Browser auswählen:${C_RESET}"

    local i idx browser
    for i in "${!BROWSERS[@]}"; do
        idx=$((i + 1))
        browser="${BROWSERS[$i]}"
        printf "  ${C_BGREEN}%d${C_RESET}) %s\n" "$idx" "${browser^}"
    done
    printf "%b\n" "  ${C_BRED}0${C_RESET}) ${C_DIM}Abbrechen${C_RESET}"

    local choice
    read -r -p "$(printf "%b" "${C_BWHITE}Wahl: ${C_RESET}")" choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || \
       (( choice < 1 )) || (( choice > ${#BROWSERS[@]} )); then
        log_warn "Ungültige Auswahl."
        pause_menu
        return
    fi

    browser="${BROWSERS[$((choice - 1))]}"

    log_dl "Importiere Cookies von ${browser^} …"
    if yt-dlp \
        --cookies-from-browser "$browser" \
        --cookies "$COOKIES_FILE" \
        --skip-download \
        --quiet \
        --no-warnings \
        "https://www.youtube.com" 2>/dev/null; then
        log_ok "Cookies von ${browser^} erfolgreich importiert."
        log_info "Datei: $COOKIES_FILE"
    else
        log_err "Fehler beim Importieren der ${browser^}-Cookies."
        printf "%b\n" "   ${C_DIM}Tipp: Browser vollständig schließen und erneut versuchen.${C_RESET}"
    fi
    pause_menu
}

update_yt_dlp() {
    check_yt_dlp || { pause_menu; return; }

    log_up "Aktualisiere yt-dlp …"
    local exit_code=0
    yt-dlp -U || exit_code=$?

    if (( exit_code == 0 )); then
        log_ok "yt-dlp erfolgreich aktualisiert."
    else
        log_err "Fehler beim Update (Fehlercode $exit_code)."
        printf "%b\n" "   ${C_DIM}Tipp: Bei pip-Installationen: 'pip install -U yt-dlp'${C_RESET}"
    fi
    pause_menu
}

# ── Menü ─────────────────────────────────────────────────────────────────────

show_menu() {
    local line="════════════════════════════════════════════════════"

    printf "%b\n" "${C_BCYAN}${line}${C_RESET}"
    printf "%b\n" "           ${C_BOLD}${C_BWHITE}yt-dlp Download Manager${C_RESET}"
    printf "%b\n" "${C_BCYAN}${line}${C_RESET}"

    printf "  ${C_BGREEN}1${C_RESET})  %-32s ${C_DIM}(M4A/AAC, beste Qualität)${C_RESET}\n"  "Audio herunterladen"
    printf "  ${C_BGREEN}2${C_RESET})  %-32s ${C_DIM}(beste Qualität, MP4)${C_RESET}\n"      "Video herunterladen"
    printf "  ${C_BGREEN}3${C_RESET})  %-32s ${C_DIM}(beste Qualität, MP4)${C_RESET}\n"      "Audio + Video herunterladen"
    printf "  ${C_BGREEN}4${C_RESET})  %-32s ${C_DIM}(Audio, M4A)${C_RESET}\n"               "Playlist herunterladen"
    printf "  ${C_BGREEN}5${C_RESET})  %-32s ${C_DIM}(Video, MP4)${C_RESET}\n"               "Playlist herunterladen"
    printf "  ${C_BYELLOW}6${C_RESET})  %s\n"                                                "Cookies aus Browser importieren"
    printf "  ${C_BYELLOW}7${C_RESET})  %s\n"                                                "yt-dlp aktualisieren"
    printf "  ${C_BCYAN}8${C_RESET})  %s\n"                                                  "Download-Verzeichnis öffnen"
    printf "  ${C_BRED}9${C_RESET})  %s\n"                                                   "Beenden"

    printf "%b\n" "${C_BCYAN}${line}${C_RESET}"

    local cookie_status
    if [[ -f "$COOKIES_FILE" ]]; then
        cookie_status="${C_GREEN}✓ vorhanden${C_RESET}"
    else
        cookie_status="${C_RED}✗ nicht gesetzt${C_RESET}"
    fi

    printf "  ${C_BOLD}Cookies${C_RESET} : %b\n"  "$cookie_status"
    printf "  ${C_BOLD}Ziel${C_RESET}    : ${C_MAGENTA}%s${C_RESET}\n"  "$DOWNLOAD_DIR"
    printf "%b\n" "${C_BCYAN}${line}${C_RESET}"
}

# ── Hauptschleife ────────────────────────────────────────────────────────────

main() {
    while true; do
        clear_screen
        show_menu

        local choice
        read -r -p "$(printf "%b" "${C_BWHITE}Option wählen (1–9): ${C_RESET}")" choice

        case "$choice" in
            1) download_audio            ;;
            2) download_video            ;;
            3) download_audio_and_video  ;;
            4) download_playlist_audio   ;;
            5) download_playlist_video   ;;
            6) import_cookies            ;;
            7) update_yt_dlp             ;;
            8) open_directory "$DOWNLOAD_DIR" || true ; pause_menu ;;
            9)
                printf "%b\n" "${C_BGREEN}Auf Wiedersehen! 👋${C_RESET}"
                exit 0
                ;;
            *)
                log_warn "Ungültige Eingabe. Bitte 1–9 wählen."
                pause_menu
                ;;
        esac
    done
}

# ── Einstiegspunkt ───────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
