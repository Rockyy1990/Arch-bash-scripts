#!/bin/bash
################################################################################
# yt-dlp Download Manager (Bash-Version)
# Unterstützt Audio, Video, Playlist-Downloads und Cookie-Management
# Erfordert: yt-dlp, ffmpeg
################################################################################

# Strikte Fehlerbehandlung (aber nicht für Menü-Eingaben)
set -u

# ── Konfiguration ────────────────────────────────────────────────────────────

readonly HOME_DIR="${HOME}"
readonly COOKIES_FILE="${HOME_DIR}/.config/yt-dlp/cookies.txt"
readonly DOWNLOAD_DIR="${HOME_DIR}/Downloads/yt-dlp"

# Verzeichnisse beim Start sicherstellen
mkdir -p "$(dirname "$COOKIES_FILE")" 2>/dev/null || true
mkdir -p "$DOWNLOAD_DIR" 2>/dev/null || true

# ── Hilfsfunktionen ──────────────────────────────────────────────────────────

clear_screen() {
    clear
}

pause_menu() {
    echo ""
    read -p "Weiter mit Enter ..."
}

get_url() {
    local url
    read -p "URL eingeben: " url

    # Whitespace trimmen
    url="${url#"${url%%[![:space:]]*}"}"
    url="${url%"${url##*[![:space:]]}"}"

    if [[ -z "$url" ]]; then
        echo "⚠  Fehler: URL darf nicht leer sein."
        return 1
    fi

    if ! is_valid_url "$url"; then
        echo "⚠  Fehler: Ungültiges URL-Format."
        return 1
    fi

    echo "$url"
    return 0
}

is_valid_url() {
    local url="\$1"
    # Validierung: URL muss mit http:// oder https:// beginnen
    if [[ "$url" =~ ^https?://[^[:space:]] ]]; then
        return 0
    fi
    return 1
}

run_yt_dlp() {
    local -a args=("$@")
    local exit_code=0

    # yt-dlp mit Cookies (falls vorhanden) ausführen
    if [[ -f "$COOKIES_FILE" ]]; then
        yt-dlp --cookies "$COOKIES_FILE" "${args[@]}" || exit_code=$?
    else
        yt-dlp "${args[@]}" || exit_code=$?
    fi

    if [[ $exit_code -eq 0 ]]; then
        return 0
    elif [[ $exit_code -eq 130 ]]; then
        echo "⚠  Download abgebrochen (Ctrl+C)."
        return 1
    else
        echo "✗  yt-dlp beendet mit Fehlercode $exit_code."
        return 1
    fi
}

open_directory() {
    local path="\$1"

    if [[ ! -d "$path" ]]; then
        echo "⚠  Verzeichnis existiert nicht: $path"
        return 1
    fi

    case "$OSTYPE" in
        darwin*)
            # macOS
            open "$path" 2>/dev/null || {
                echo "⚠  Verzeichnis konnte nicht geöffnet werden."
                return 1
            }
            ;;
        msys|cygwin|win32)
            # Windows / WSL
            if command -v explorer.exe &>/dev/null; then
                explorer.exe "$(cygpath -w "$path")" 2>/dev/null || {
                    echo "⚠  Verzeichnis konnte nicht geöffnet werden."
                    return 1
                }
            else
                echo "⚠  Explorer nicht gefunden."
                return 1
            fi
            ;;
        *)
            # Linux - mehrere Dateimanager versuchen
            local opened=0
            for cmd in xdg-open nautilus dolphin thunar pcmanfm; do
                if command -v "$cmd" &>/dev/null; then
                    "$cmd" "$path" 2>/dev/null && opened=1 && break
                fi
            done

            if [[ $opened -eq 0 ]]; then
                echo "⚠  Kein Dateimanager gefunden (xdg-open, nautilus, dolphin, thunar, pcmanfm)."
                return 1
            fi
            ;;
    esac

    return 0
}

check_yt_dlp() {
    if ! command -v yt-dlp &>/dev/null; then
        echo "✗  Fehler: 'yt-dlp' wurde nicht gefunden."
        echo "   Installation: pip install -U yt-dlp"
        return 1
    fi
    return 0
}

# ── Download-Funktionen ──────────────────────────────────────────────────────

readonly OUTPUT_SINGLE="${DOWNLOAD_DIR}/%(title)s.%(ext)s"
readonly OUTPUT_PLAYLIST="${DOWNLOAD_DIR}/%(playlist)s/%(playlist_index)s - %(title)s.%(ext)s"

download_audio() {
    check_yt_dlp || { pause_menu; return; }

    local url
    url=$(get_url) || { pause_menu; return; }

    echo "⬇  Lade Audio herunter …"
    if run_yt_dlp \
        --extract-audio \
        --audio-format aac \
        --audio-quality 0 \
        -o "$OUTPUT_SINGLE" \
        "$url"; then
        echo "✓  Download abgeschlossen."
    fi
    pause_menu
}

download_video() {
    check_yt_dlp || { pause_menu; return; }

    local url
    url=$(get_url) || { pause_menu; return; }

    echo "⬇  Lade Video in bester Qualität herunter …"
    if run_yt_dlp \
        -f "bestvideo+bestaudio/best" \
        --merge-output-format mp4 \
        -o "$OUTPUT_SINGLE" \
        "$url"; then
        echo "✓  Download abgeschlossen."
    fi
    pause_menu
}

download_audio_and_video() {
    check_yt_dlp || { pause_menu; return; }

    local url
    url=$(get_url) || { pause_menu; return; }

    echo "⬇  Lade Audio + Video herunter …"
    if run_yt_dlp \
        -f "bestvideo+bestaudio/best" \
        --merge-output-format mp4 \
        -o "$OUTPUT_SINGLE" \
        "$url"; then
        echo "✓  Download abgeschlossen."
    fi
    pause_menu
}

download_playlist_audio() {
    check_yt_dlp || { pause_menu; return; }

    local url
    url=$(get_url) || { pause_menu; return; }

    echo "⬇  Lade Playlist (Audio) herunter …"
    if run_yt_dlp \
        --extract-audio \
        --audio-format aac \
        --audio-quality 0 \
        -o "$OUTPUT_PLAYLIST" \
        "$url"; then
        echo "✓  Playlist-Download abgeschlossen."
    fi
    pause_menu
}

download_playlist_video() {
    check_yt_dlp || { pause_menu; return; }

    local url
    url=$(get_url) || { pause_menu; return; }

    echo "⬇  Lade Playlist (Video) herunter …"
    if run_yt_dlp \
        -f "bestvideo+bestaudio/best" \
        --merge-output-format mp4 \
        -o "$OUTPUT_PLAYLIST" \
        "$url"; then
        echo "✓  Playlist-Download abgeschlossen."
    fi
    pause_menu
}

# ── Cookie-Management ────────────────────────────────────────────────────────

# Indexed Array für garantierte Reihenfolge
declare -a BROWSERS=(
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
    echo "Browser auswählen:"

    local i
    for i in "${!BROWSERS[@]}"; do
        local idx=$((i + 1))
        local browser="${BROWSERS[$i]}"
        echo "  $idx) ${browser^}"
    done
    echo "  7) Abbrechen"

    read -p "Wahl: " choice

    if [[ "$choice" == "7" ]]; then
        return
    fi

    # Validierung der Eingabe
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt 6 ]]; then
        echo "⚠  Ungültige Auswahl."
        pause_menu
        return
    fi

    local browser_idx=$((choice - 1))
    local browser="${BROWSERS[$browser_idx]}"

    echo "⬇  Importiere Cookies von ${browser^} …"
    if yt-dlp --cookies-from-browser "$browser" --cookies "$COOKIES_FILE" "https://www.youtube.com" 2>/dev/null; then
        echo "✓  Cookies von ${browser^} erfolgreich importiert."
    else
        echo "✗  Fehler beim Importieren der ${browser^}-Cookies."
    fi
    pause_menu
}

update_yt_dlp() {
    check_yt_dlp || { pause_menu; return; }

    echo "⬆  Aktualisiere yt-dlp …"
    if yt-dlp -U; then
        echo "✓  yt-dlp erfolgreich aktualisiert."
    else
        local exit_code=$?
        echo "✗  Fehler beim Update: Fehlercode $exit_code"
    fi
    pause_menu
}

# ── Menü ─────────────────────────────────────────────────────────────────────

show_menu() {
    local line="════════════════════════════════════════════════════"

    echo "$line"
    echo "           yt-dlp Download Manager"
    echo "$line"
    echo "  1)  Audio herunterladen          (AAC, beste Qualität)"
    echo "  2)  Video herunterladen          (beste Qualität, MP4)"
    echo "  3)  Audio + Video herunterladen  (beste Qualität, MP4)"
    echo "  4)  Playlist herunterladen       (Audio, AAC)"
    echo "  5)  Playlist herunterladen       (Video, MP4)"
    echo "  6)  Cookies aus Browser importieren"
    echo "  7)  yt-dlp aktualisieren"
    echo "  8)  Download-Verzeichnis öffnen"
    echo "  9)  Beenden"
    echo "$line"

    local cookie_status="✗ nicht gesetzt"
    if [[ -f "$COOKIES_FILE" ]]; then
        cookie_status="✓ vorhanden"
    fi

    echo "  Cookies : $cookie_status"
    echo "  Ziel    : $DOWNLOAD_DIR"
    echo "$line"
}

# ── Hauptschleife ─────────────────────────────────────────────────────────────

main() {
    while true; do
        clear_screen
        show_menu
        read -p "Option wählen (1–9): " choice

        case "$choice" in
            1)
                download_audio
                ;;
            2)
                download_video
                ;;
            3)
                download_audio_and_video
                ;;
            4)
                download_playlist_audio
                ;;
            5)
                download_playlist_video
                ;;
            6)
                import_cookies
                ;;
            7)
                update_yt_dlp
                ;;
            8)
                open_directory "$DOWNLOAD_DIR"
                pause_menu
                ;;
            9)
                echo "Auf Wiedersehen! 👋"
                exit 0
                ;;
            *)
                echo "⚠  Ungültige Eingabe. Bitte 1–9 wählen."
                pause_menu
                ;;
        esac
    done
}

# ── Einstiegspunkt ──────────────────────────────────────────────────────────

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
