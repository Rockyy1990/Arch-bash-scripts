#!/usr/bin/env bash
# pacui.sh — User-friendly Pacman/yay TUI frontend for Arch Linux
# Runs as normal user; sudo is called internally for system operations only.
# NOTE: -e is intentionally omitted — interactive read/grep return non-zero legitimately.

set -uo pipefail
IFS=$'\n\t'

# ─── Identity ─────────────────────────────────────────────────────────────────
readonly PACUI_NAME="PacUI"
readonly PACUI_VERSION="1.0.0"

# ─── Runtime Paths ────────────────────────────────────────────────────────────
readonly CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/pacui"
readonly CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pacui"
readonly LOG_FILE="$CACHE_DIR/pacui.log"
readonly SETTINGS_FILE="$CONFIG_DIR/settings.conf"
mkdir -p "$CACHE_DIR" "$CONFIG_DIR"

# ─── Color Detection ─────────────────────────────────────────────────────────
if [[ -t 1 ]] && tput colors &>/dev/null && [[ "$(tput colors)" -ge 8 ]]; then
  R='\033[0;31m'   G='\033[0;32m'   Y='\033[1;33m'
  B='\033[0;34m'   C='\033[0;36m'   M='\033[0;35m'
  W='\033[1;37m'   D='\033[2m'      BOLD='\033[1m'
  RST='\033[0m'    BG_R='\033[41m'
else
  R='' G='' Y='' B='' C='' M='' W='' D='' BOLD='' RST='' BG_R=''
fi

# ─── Terminal Geometry ────────────────────────────────────────────────────────
# _tw() { local w; w=$(tput cols 2>/dev/null || echo 80); [[ $w -lt 60 ]] && w=60; [[ $w -gt 120 ]] && w=120; echo "$w"; }
# TW=$(_tw)
_tw() {
  local w
  w=$(tput cols 2>/dev/null || echo 80)
  [[ $w -lt 120 ]] && w=100    # Minimum für schmale Fenster
  [[ $w -gt 240 ]] && w=240    # Maximum für 1080p Vollbild (ca. 240 Spalten)
  echo "$w"
}

# ─── Runtime State ────────────────────────────────────────────────────────────
INSTALL_QUEUE=()   # package names pending installation
HAS_YAY=false
HAS_FZF=false
HAS_CHECKUPDATES=false

# ──────────────────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ──────────────────────────────────────────────────────────────────────────────

log() {
  local level="$1"; shift
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"
}

# Print a full-width horizontal rule
hline() {
  local ch="${1:-─}" col="${2:-$D}"
  printf '%b' "$col"
  printf '%0.s'"$ch" $(seq 1 "$TW")
  printf '%b\n' "$RST"
}

# Center a string (ANSI-aware: strips codes for width calculation)
center() {
  local text="$1"
  local plain; plain=$(printf '%b' "$text" | sed 's/\x1b\[[0-9;]*m//g')
  local pad=$(( (TW - ${#plain}) / 2 ))
  [[ $pad -lt 0 ]] && pad=0
  printf "%${pad}s" ""
  printf '%b\n' "$text"
}

# Status line with typed icon
status() {
  local type="$1"; shift; local msg="$*"
  case "$type" in
    ok)    printf " %b✔%b  %s\n" "$G"    "$RST" "$msg" ;;
    warn)  printf " %b⚠%b  %s\n" "$Y"    "$RST" "$msg" ;;
    err)   printf " %b✖%b  %s\n" "$R"    "$RST" "$msg" ;;
    info)  printf " %bℹ%b  %s\n" "$B"    "$RST" "$msg" ;;
    run)   printf " %b▶%b  %s\n" "$C"    "$RST" "$msg" ;;
    aur)   printf " %b◈%b  %s\n" "$M"    "$RST" "$msg" ;;
    crit)  printf " %b%b !! %b %s\n" "$BG_R" "$W" "$RST" "$msg" ;;
  esac
  log "${type^^}" "$msg"
}

# Key/value display
kv() { printf "  %b%-18s%b %s\n" "$BOLD" "$1:" "$RST" "$2"; }

# Section header
section() {
  echo
  printf "%b  ◈ %s%b\n" "${BOLD}${C}" "$*" "$RST"
  hline '─'
}

# Pause for keypress
pause() {
  echo
  printf "  %b[ Beliebige Taste zum Fortfahren ]%b" "$D" "$RST"
  read -rs -n1 || true
  echo
}

# Confirmation prompt — returns 0 for yes, 1 for no
confirm() {
  local prompt="${1:-Fortfahren?}" default="${2:-n}" hint
  [[ "$default" == "y" ]] && hint="${BOLD}[J/n]${RST}" || hint="${D}[j/N]${RST}"
  echo
  printf "  %b?%b %s %b " "$Y" "$RST" "$prompt" "$hint"
  local ans; read -r ans || ans=""
  ans="${ans,,}"
  [[ -z "$ans" ]] && ans="$default"
  [[ "$ans" == "j" || "$ans" == "y" ]]
}

# Print the main header bar
print_header() {
  clear
  TW=$(_tw)
  hline '═' "$C"
  center "${BOLD}${C}${PACUI_NAME}  v${PACUI_VERSION}${RST}"
  center "${D}Paketmanager-Frontend  │  Arch Linux  │  Nutzer: $(whoami)${RST}"
  center "${D}Läuft ohne sudo-Aufruf (sudo nur intern für pacman-Operationen)${RST}"
  hline '═' "$C"
}

# ──────────────────────────────────────────────────────────────────────────────
# DEPENDENCY & ENVIRONMENT CHECK
# ──────────────────────────────────────────────────────────────────────────────

check_deps() {
  if ! command -v pacman &>/dev/null; then
    printf '%bFehler:%b pacman nicht gefunden — Arch Linux erforderlich.\n' "$R" "$RST" >&2
    exit 1
  fi
  command -v yay             &>/dev/null && HAS_YAY=true
  command -v fzf             &>/dev/null && HAS_FZF=true
  command -v checkupdates    &>/dev/null && HAS_CHECKUPDATES=true
}

# Verify sudo is usable; prompt and test if not cached
check_sudo() {
  if sudo -n true 2>/dev/null; then return 0; fi
  section "sudo-Authentifizierung erforderlich"
  status warn "Für systemweite Paketoperationen wird sudo benötigt."
  status info "Das Skript selbst benötigt keine elevated Rechte."
  echo
  if ! sudo true 2>/dev/null; then
    status err "sudo-Authentifizierung fehlgeschlagen."
    status info "Alternative: polkit-Helfer einrichten:"
    printf "  %b→ /etc/polkit-1/rules.d/49-pacman.rules%b\n" "$D" "$RST"
    printf "  %b→ Dokumentation: https://wiki.archlinux.org/title/Polkit%b\n" "$D" "$RST"
    return 1
  fi
  return 0
}

# ──────────────────────────────────────────────────────────────────────────────
# PACKAGE SEARCH
# ──────────────────────────────────────────────────────────────────────────────

# Parse pacman/yay -Ss output into "repo|pkg|ver|desc" entries
_parse_search_results() {
  local input="$1"
  local current_pkg="" current_repo="" current_ver=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^([a-zA-Z0-9_-]+)/([^ ]+)[[:space:]]+([^ ]+) ]]; then
      current_repo="${BASH_REMATCH[1]}"
      current_pkg="${BASH_REMATCH[2]}"
      current_ver="${BASH_REMATCH[3]}"
    elif [[ -n "$current_pkg" ]]; then
      local desc; desc=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
      printf '%s|%s|%s|%s\n' "$current_repo" "$current_pkg" "$current_ver" "$desc"
      current_pkg=""
    fi
  done <<< "$input"
}

action_search() {
  print_header
  section "Pakete suchen"
  printf "  %bSuchbegriff:%b " "$BOLD" "$RST"
  local query; read -r query || return
  [[ -z "$query" ]] && return

  status run "Suche in offiziellen Repos..."
  local repo_raw; repo_raw=$(pacman -Ss "$query" 2>/dev/null || true)
  local results=()
  while IFS= read -r entry; do
    [[ -n "$entry" ]] && results+=("repo|$entry")
  done < <(_parse_search_results "$repo_raw")

  if $HAS_YAY; then
    status aur "Suche im AUR..."
    local aur_raw; aur_raw=$(yay -Ssa "$query" 2>/dev/null | grep -A1 '^aur/' || true)
    while IFS= read -r entry; do
      [[ -n "$entry" ]] && results+=("aur|$entry")
    done < <(_parse_search_results "$aur_raw")
  fi

  if [[ ${#results[@]} -eq 0 ]]; then
    status warn "Keine Pakete für '${query}' gefunden."
    pause; return
  fi

  _display_search_results "${results[@]}"
}

_display_search_results() {
  local results=("$@")
  section "Suchergebnisse"
  echo
  printf "  %b%4s  %-28s %-14s %-12s  %s%b\n" \
    "$BOLD" "Nr." "Paket" "Version" "Quelle" "Beschreibung" "$RST"
  hline '-'

  local i=1
  for entry in "${results[@]}"; do
    IFS='|' read -r _type repo pkg ver desc <<< "$entry"

    local installed_mark=""
    pacman -Q "$pkg" &>/dev/null && installed_mark=" ${G}[installiert]${RST}"

    local src_color
    case "$repo" in
      core|extra|community|multilib) src_color="$B" ;;
      aur)                           src_color="$M" ;;
      *)                             src_color="$C" ;;
    esac

    printf "  %b%4d%b  %-28s %-14s %b%-12s%b  %-38s%b\n" \
      "$BOLD" "$i" "$RST" \
      "${pkg:0:27}" "${ver:0:13}" \
      "$src_color" "${repo:0:11}" "$RST" \
      "${desc:0:37}" "$installed_mark"
    (( i++ ))
  done

  echo
  printf "  %bNr. eingeben%b (z.B. %b1 3%b), %bi%b<Nr.> für Details, %bEnter%b zum Abbrechen:%b " \
    "$BOLD" "$RST" "$C" "$RST" "$C" "$RST" "$C" "$RST" "$D"
  local sel; read -r sel || return
  [[ -z "$sel" ]] && return

  # "i3" → show info for item 3
  if [[ "$sel" =~ ^i([0-9]+)$ ]]; then
    local n="${BASH_REMATCH[1]}"
    if (( n >= 1 && n <= ${#results[@]} )); then
      _show_pkg_info "${results[$((n-1))]}"
    fi
    return
  fi

  local added=0
  for num in $sel; do
    if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#results[@]} )); then
      IFS='|' read -r _t _r pkg _v _d <<< "${results[$((num-1))]}"
      local already=false
      for q in "${INSTALL_QUEUE[@]+"${INSTALL_QUEUE[@]}"}"; do [[ "$q" == "$pkg" ]] && already=true && break; done
      if $already; then
        status info "$pkg ist bereits in der Warteschlange."
      else
        INSTALL_QUEUE+=("$pkg")
        status ok "Warteschlange ← ${BOLD}$pkg${RST}"
        (( added++ ))
      fi
    fi
  done

  if (( added > 0 )); then
    echo
    if confirm "Ausgewählte Pakete jetzt installieren? ($added Paket/e)"; then
      run_install_queue
    else
      status info "Pakete gespeichert → Menü [5] Warteschlange."
    fi
  fi
  pause
}

_show_pkg_info() {
  local entry="$1"
  IFS='|' read -r _type repo pkg _ver _desc <<< "$entry"
  section "Paket-Info: ${C}${pkg}${RST}"
  local cmd
  if [[ "$repo" == "aur" ]] && $HAS_YAY; then
    cmd="yay -Si $pkg"
  else
    cmd="pacman -Si $pkg"
  fi
  $cmd 2>/dev/null | while IFS= read -r line; do printf "  %s\n" "$line"; done || true
  pause
}

# ──────────────────────────────────────────────────────────────────────────────
# INSTALL QUEUE
# ──────────────────────────────────────────────────────────────────────────────

_show_queue_list() {
  if [[ ${#INSTALL_QUEUE[@]} -eq 0 ]]; then
    status info "Warteschlange ist leer."; return 1
  fi
  local i=1
  for pkg in "${INSTALL_QUEUE[@]}"; do
    printf "  %b%3d%b  %s\n" "$BOLD" "$i" "$RST" "$pkg"
    (( i++ ))
  done
  return 0
}

run_install_queue() {
  if [[ ${#INSTALL_QUEUE[@]} -eq 0 ]]; then
    status warn "Installationswarteschlange ist leer."; return
  fi

  section "Installationsplan"
  echo
  _show_queue_list
  echo

  # Classify packages: AUR vs repo
  local aur_pkgs=() repo_pkgs=()
  for pkg in "${INSTALL_QUEUE[@]}"; do
    if $HAS_YAY && yay -Si "$pkg" 2>/dev/null | grep -qi '^Repository.*aur'; then
      aur_pkgs+=("$pkg")
    else
      repo_pkgs+=("$pkg")
    fi
  done

  [[ ${#repo_pkgs[@]} -gt 0 ]] && kv "Quelle: Repo"  "${repo_pkgs[*]}"
  [[ ${#aur_pkgs[@]} -gt 0  ]] && kv "Quelle: AUR"   "${aur_pkgs[*]}"

  # AUR security gate
  local install_aur=false
  if [[ ${#aur_pkgs[@]} -gt 0 ]]; then
    echo
    status crit "AUR-Sicherheitshinweis"
    printf "  AUR-Pakete sind %bNICHT%b offiziell geprüft.\n" "$BOLD" "$RST"
    printf "  %bPKGBUILD-Dateien vor dem Bau lesen:%b yay --editmenu\n" "$D" "$RST"
    printf "  %bOrigin prüfen:%b               https://aur.archlinux.org/packages/%s\n" \
      "$D" "$RST" "${aur_pkgs[0]}"
    echo
    if confirm "AUR-Pakete bauen und installieren?"; then
      install_aur=true
    else
      aur_pkgs=()
      status warn "AUR-Pakete aus dieser Sitzung übersprungen."
    fi
  fi

  # Dry-run simulation (repo packages only — pacman supports --print)
  if [[ ${#repo_pkgs[@]} -gt 0 ]]; then
    section "Vorschau (Simulation)"
    status run "Simuliere pacman-Transaktion..."
    echo
    if ! sudo pacman -S --print-format "  Installieren: %-28n  %v  (%s)\n" \
        "${repo_pkgs[@]}" 2>&1; then
      status err "Simulation fehlgeschlagen — Abhängigkeitsprobleme?"
      handle_error "pacman-install" "Trockenlauf-Fehler für: ${repo_pkgs[*]}"
      pause; return
    fi
  fi

  echo
  if ! confirm "Installation starten? (sudo wird angefordert)" "n"; then
    status info "Abgebrochen. Warteschlange bleibt erhalten."; return
  fi
  check_sudo || { pause; return; }

  # Execute
  section "Installation läuft…"
  local all_ok=true

  if [[ ${#repo_pkgs[@]} -gt 0 ]]; then
    status run "Repo-Pakete: ${repo_pkgs[*]}"
    if sudo pacman -S --needed --noconfirm "${repo_pkgs[@]}" 2>&1 | tee -a "$LOG_FILE"; then
      status ok "Repo-Pakete installiert."
    else
      all_ok=false
      handle_error "pacman-install" "Fehler bei: ${repo_pkgs[*]}"
    fi
  fi

  if $install_aur && [[ ${#aur_pkgs[@]} -gt 0 ]] && $HAS_YAY; then
    status aur "AUR-Pakete: ${aur_pkgs[*]}"
    if yay -S --needed --noconfirm "${aur_pkgs[@]}" 2>&1 | tee -a "$LOG_FILE"; then
      status ok "AUR-Pakete installiert."
    else
      all_ok=false
      handle_error "yay-install" "Fehler bei: ${aur_pkgs[*]}"
    fi
  fi

  if $all_ok; then
    status ok "Alle Pakete erfolgreich installiert."
    log "INFO" "Installed: ${INSTALL_QUEUE[*]}"
    INSTALL_QUEUE=()
  else
    status warn "Teilweise fehlgeschlagen — Protokoll: $LOG_FILE"
  fi
  pause
}

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: INSTALL
# ──────────────────────────────────────────────────────────────────────────────
action_install() {
  print_header
  action_search
}

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: REMOVE
# ──────────────────────────────────────────────────────────────────────────────
action_remove() {
  print_header
  section "Paket entfernen"
  printf "  %bFilter / Paketname:%b " "$BOLD" "$RST"
  local query; read -r query || return
  [[ -z "$query" ]] && return

  local pkgs=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && pkgs+=("$line")
  done < <(pacman -Qq 2>/dev/null | grep -i "$query" || true)

  if [[ ${#pkgs[@]} -eq 0 ]]; then
    status warn "Kein installiertes Paket für '${query}' gefunden."
    pause; return
  fi

  section "Installierte Pakete — Treffer für: ${C}${query}${RST}"
  echo
  local i=1
  for pkg in "${pkgs[@]}"; do
    local ver; ver=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
    printf "  %b%4d%b  %-30s %b%s%b\n" "$BOLD" "$i" "$RST" "$pkg" "$D" "$ver" "$RST"
    (( i++ ))
  done

  echo
  printf "  %bNummer auswählen [1-%d], Enter = Abbrechen:%b " "$BOLD" "${#pkgs[@]}" "$RST"
  local sel; read -r sel || return
  [[ -z "$sel" || ! "$sel" =~ ^[0-9]+$ ]] && return
  (( sel < 1 || sel > ${#pkgs[@]} )) && return

  local target="${pkgs[$((sel-1))]}"

  # Dependency check
  section "Abhängigkeitsprüfung: ${C}${target}${RST}"
  local reqby; reqby=$(pacman -Qi "$target" 2>/dev/null | grep '^Required By' | sed 's/Required By[[:space:]]*:[[:space:]]*//')
  local rm_flags=""

  if [[ -n "$reqby" && "$reqby" != "None" ]]; then
    status warn "Folgende Pakete hängen von ${BOLD}${target}${RST} ab:"
    printf '%s' "$reqby" | tr ' ' '\n' | grep -v '^$' | while read -r dep; do
      printf "  %b→%b %s\n" "$Y" "$RST" "$dep"
    done
    echo
    status crit "Entfernen kann das System destabilisieren!"
    if ! confirm "Trotzdem entfernen? (--cascade)"; then
      status info "Abgebrochen."; pause; return
    fi
    rm_flags="--cascade"
  else
    status ok "Keine abhängigen Pakete — sicher zu entfernen."
  fi

  echo
  kv "Ziel"   "$target"
  kv "Modus"  "${rm_flags:-Standard (-R)}"
  echo
  status warn "Diese Aktion ist nicht automatisch rückgängig zu machen."

  if ! confirm "Paket ${BOLD}${target}${RST} jetzt entfernen?"; then
    status info "Abgebrochen."; pause; return
  fi
  check_sudo || { pause; return; }

  section "Entfernung läuft…"
  log "INFO" "Removing: $target flags=$rm_flags"
  # shellcheck disable=SC2086
  if sudo pacman -R $rm_flags --noconfirm "$target" 2>&1 | tee -a "$LOG_FILE"; then
    status ok "${BOLD}${target}${RST} erfolgreich entfernt."
  else
    handle_error "pacman-remove" "Fehler beim Entfernen von: $target"
  fi
  pause
}

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: UPDATE
# ──────────────────────────────────────────────────────────────────────────────
action_update() {
  print_header
  section "System aktualisieren"
  status run "Prüfe auf Updates…"

  local updates=""
  if $HAS_CHECKUPDATES; then
    updates=$(checkupdates 2>/dev/null || true)
  else
    updates=$(pacman -Qu 2>/dev/null || true)
  fi
  local ucount; ucount=$(printf '%s' "$updates" | grep -c '.' || true)

  if [[ -z "$updates" ]]; then
    status ok "System ist aktuell — keine Repo-Updates verfügbar."
  else
    section "Verfügbare Updates (${C}${ucount}${RST} Pakete)"
    echo
    printf "  %b%-32s  %-18s  %-18s%b\n" "$BOLD" "Paket" "Aktuell" "Neu" "$RST"
    hline '-'
    printf '%s' "$updates" | while IFS= read -r line; do
      if [[ "$line" =~ ^([^ ]+)[[:space:]]+([^ ]+)[[:space:]]+-\>[[:space:]]+([^ ]+) ]]; then
        printf "  %-32s  %b%-18s%b  %b%-18s%b\n" \
          "${BASH_REMATCH[1]}" "$R" "${BASH_REMATCH[2]}" "$RST" \
          "$G" "${BASH_REMATCH[3]}" "$RST"
      else
        printf "  %s\n" "$line"
      fi
    done
  fi

  # AUR updates
  if $HAS_YAY; then
    echo
    status aur "Prüfe AUR-Updates…"
    local aur_up; aur_up=$(yay -Qu 2>/dev/null | grep -v 'pacman' || true)
    if [[ -n "$aur_up" ]]; then
      status warn "AUR-Updates vorhanden:"
      printf '%s' "$aur_up" | while IFS= read -r line; do
        printf "  %b→%b %s\n" "$M" "$RST" "$line"
      done
    else
      status ok "Keine AUR-Updates."
    fi
  fi

  echo
  hline '-'
  printf "  %b[1]%b Alle aktualisieren  %b[2]%b Selektiv auswählen  %b[q]%b Zurück: " \
    "$BOLD" "$RST" "$BOLD" "$RST" "$BOLD" "$RST"
  local choice; read -r choice || return
  case "$choice" in
    1) _perform_full_update ;;
    2) _perform_selective_update "$updates" ;;
    *) return ;;
  esac
}

_perform_full_update() {
  echo
  status warn "Alle verfügbaren Pakete werden aktualisiert."
  if ! confirm "Vollständiges Update starten? (sudo wird angefordert)" "n"; then return; fi
  check_sudo || { pause; return; }

  section "Update läuft…"
  log "INFO" "Full system update started"
  if $HAS_YAY; then
    status run "yay -Syu (Repo + AUR)…"
    if yay -Syu --noconfirm 2>&1 | tee -a "$LOG_FILE"; then
      status ok "System vollständig aktualisiert."
    else
      handle_error "yay-update" "Update fehlgeschlagen."
    fi
  else
    status run "pacman -Syu…"
    if sudo pacman -Syu --noconfirm 2>&1 | tee -a "$LOG_FILE"; then
      status ok "System aktualisiert."
    else
      handle_error "pacman-update" "Update fehlgeschlagen."
    fi
  fi
  pause
}

_perform_selective_update() {
  local updates="$1"
  [[ -z "$updates" ]] && { status info "Keine Updates verfügbar."; pause; return; }

  section "Selektives Update"
  echo
  # Single pass: build ordered pkg list AND a name→full-line map
  local pkgs=()
  declare -A pkg_lines
  while IFS= read -r line; do
    local pname; pname=$(printf '%s' "$line" | awk '{print $1}')
    [[ -n "$pname" ]] && { pkgs+=("$pname"); pkg_lines["$pname"]="$line"; }
  done <<< "$updates"

  local i=1
  for pkg in "${pkgs[@]}"; do
    printf "  %b%3d%b  %s\n" "$BOLD" "$i" "$RST" "${pkg_lines[$pkg]}"
    (( i++ ))
  done

  echo
  printf "  %bNummern eingeben%b (z.B. %b1 3 5%b) oder %bEnter%b = alle: " \
    "$BOLD" "$RST" "$C" "$RST" "$C" "$RST"
  local sel; read -r sel || return

  local chosen=()
  if [[ -z "$sel" ]]; then
    chosen=("${pkgs[@]}")
  else
    local num_arr=()
    read -ra num_arr <<< "$sel"
    for num in "${num_arr[@]}"; do
      [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#pkgs[@]} )) \
        && chosen+=("${pkgs[$((num-1))]}")
    done
  fi

  [[ ${#chosen[@]} -eq 0 ]] && { status warn "Keine Pakete ausgewählt."; return; }

  check_sudo || { pause; return; }
  section "Aktualisiere: ${chosen[*]}"
  log "INFO" "Selective update: ${chosen[*]}"
  if sudo pacman -S --noconfirm "${chosen[@]}" 2>&1 | tee -a "$LOG_FILE"; then
    status ok "Ausgewählte Pakete aktualisiert."
  else
    handle_error "pacman-update" "Fehler beim selektiven Update."
  fi
  pause
}

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: ROLLBACK
# ──────────────────────────────────────────────────────────────────────────────
action_rollback() {
  print_header
  section "Paket-Rollback (aus pacman-Cache)"
  status info "Zeige kürzlich installierte/aktualisierte Pakete laut pacman.log"
  echo

  local logpath="/var/log/pacman.log"
  if [[ ! -r "$logpath" ]]; then
    status err "pacman.log nicht lesbar: $logpath"
    pause; return
  fi

  # Show last 20 installed/upgraded transactions
  local entries=()
  while IFS= read -r line; do
    entries+=("$line")
  done < <(grep -E '\[(installed|upgraded)\]' "$logpath" | tail -20 | tac)

  if [[ ${#entries[@]} -eq 0 ]]; then
    status warn "Keine Transaktionseinträge gefunden."; pause; return
  fi

  local i=1
  printf "  %b%3s  %-25s %-14s %-10s  %s%b\n" "$BOLD" "Nr." "Paket" "Aktion" "Datum" "Version" "$RST"
  hline '-'
  for entry in "${entries[@]}"; do
    local dt action pkg ver
    dt=$(printf '%s' "$entry"    | grep -oP '^\[\K[^\]]+')
    action=$(printf '%s' "$entry" | grep -oP '\[(installed|upgraded)\]' | tr -d '[]')
    pkg=$(printf '%s' "$entry"   | grep -oP '\[\w+\] \K[^ ]+')
    ver=$(printf '%s' "$entry"   | grep -oP '\(.*\)' | head -1)
    printf "  %b%3d%b  %-25s %-14s %-12s %s\n" \
      "$BOLD" "$i" "$RST" "${pkg:0:24}" "$action" "${dt:0:10}" "$ver"
    (( i++ ))
  done

  echo
  printf "  %bNummer zum Rollback auswählen, Enter = Abbrechen:%b " "$BOLD" "$RST"
  local sel; read -r sel || return
  [[ -z "$sel" || ! "$sel" =~ ^[0-9]+$ ]] && return
  (( sel < 1 || sel > ${#entries[@]} )) && return

  local chosen_entry="${entries[$((sel-1))]}"
  local pkg_name; pkg_name=$(printf '%s' "$chosen_entry" | grep -oP '\[(installed|upgraded)\] \K[^ ]+')

  # Find available cached versions
  section "Verfügbare Versionen im Cache: ${C}${pkg_name}${RST}"
  local cache_files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && cache_files+=("$f")
  done < <(find /var/cache/pacman/pkg/ -name "${pkg_name}-*.pkg.tar.*" 2>/dev/null | sort -V)

  if [[ ${#cache_files[@]} -eq 0 ]]; then
    status warn "Keine gecachten Pakete für '${pkg_name}' gefunden."
    status info "Ältere Versionen ggf. mit 'downgrade' oder ALA abrufen."
    pause; return
  fi

  local j=1
  for f in "${cache_files[@]}"; do
    printf "  %b%3d%b  %s\n" "$BOLD" "$j" "$RST" "$(basename "$f")"
    (( j++ ))
  done

  echo
  printf "  %bVersion auswählen [1-%d]:%b " "$BOLD" "${#cache_files[@]}" "$RST"
  local vsel; read -r vsel || return
  [[ -z "$vsel" || ! "$vsel" =~ ^[0-9]+$ ]] && return
  (( vsel < 1 || vsel > ${#cache_files[@]} )) && return

  local target_file="${cache_files[$((vsel-1))]}"
  echo
  kv "Ziel-Datei" "$(basename "$target_file")"
  status warn "Downgrade überschreibt die aktuelle Version."

  if ! confirm "Rollback jetzt durchführen?"; then
    status info "Abgebrochen."; return
  fi
  check_sudo || { pause; return; }

  section "Rollback läuft…"
  log "INFO" "Rollback: $target_file"
  if sudo pacman -U --noconfirm "$target_file" 2>&1 | tee -a "$LOG_FILE"; then
    status ok "Rollback erfolgreich."
  else
    handle_error "pacman-rollback" "Rollback fehlgeschlagen für: $target_file"
  fi
  pause
}

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: STATUS & QUEUE
# ──────────────────────────────────────────────────────────────────────────────
action_status() {
  print_header
  section "Installationsstatus & Warteschlange"

  # Queue management
  section "Aktuelle Warteschlange"
  if _show_queue_list; then
    echo
    printf "  %b[i]%b Jetzt installieren  %b[r]%b Paket entfernen  %b[c]%b Leeren  %bEnter%b Zurück: " \
      "$BOLD" "$RST" "$BOLD" "$RST" "$BOLD" "$RST" "$BOLD" "$RST"
    local qc; read -r qc || qc=""
    case "$qc" in
      i) run_install_queue ;;
      c) if confirm "Warteschlange leeren?"; then INSTALL_QUEUE=(); status ok "Geleert."; fi ;;
      r)
        printf "  %bNummer:%b " "$BOLD" "$RST"; read -r rn || rn=""
        if [[ "$rn" =~ ^[0-9]+$ ]] && (( rn >= 1 && rn <= ${#INSTALL_QUEUE[@]} )); then
          local removed="${INSTALL_QUEUE[$((rn-1))]}"
          INSTALL_QUEUE=("${INSTALL_QUEUE[@]:0:$((rn-1))}" "${INSTALL_QUEUE[@]:$rn}")
          status ok "Entfernt: $removed"
        fi ;;
    esac
  fi

  # System summary
  section "Systemübersicht"
  local orphans; orphans=$(pacman -Qdtq 2>/dev/null | wc -l || echo 0)
  kv "Kernel"         "$(uname -r)"
  kv "Pakete gesamt"  "$(pacman -Q 2>/dev/null | wc -l)"
  kv "Explizit inst." "$(pacman -Qe 2>/dev/null | wc -l)"
  kv "Fremdpakete"    "$(pacman -Qm 2>/dev/null | wc -l)"
  local waisen_label="${orphans} Paket/e"
  (( orphans > 0 )) && waisen_label+=" ${Y}(→ Option 6 → AUR-Menü)${RST}"
  kv "Waisen"         "$waisen_label"
  kv "Cache"          "$(du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1 || echo 'N/A')"
  if $HAS_YAY; then
    kv "yay" "$(yay --version 2>/dev/null | head -1)"
  else
    kv "yay" "nicht installiert"
  fi
  pause
}

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: AUR MANAGER
# ──────────────────────────────────────────────────────────────────────────────
action_aur() {
  print_header
  section "AUR-Manager Optionen"

  if ! $HAS_YAY; then
    status warn "yay ist nicht installiert."
    echo
    status info "yay-Bootstrap (manuell, kein AUR-Helper benötigt):"
    printf "  %b git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si%b\n" "$C" "$RST"
    pause; return
  fi

  echo
  printf "  %b1%b  Veraltete AUR-Pakete anzeigen\n"     "$BOLD" "$RST"
  printf "  %b2%b  Paket-Cache bereinigen\n"             "$BOLD" "$RST"
  printf "  %b3%b  Waisenpakete entfernen\n"             "$BOLD" "$RST"
  printf "  %b4%b  Paketdatenbank prüfen (pacman -Dk)\n" "$BOLD" "$RST"
  printf "  %b5%b  yay-Konfiguration anzeigen\n"         "$BOLD" "$RST"
  printf "  %bq%b  Zurück\n"                             "$BOLD" "$RST"
  echo
  printf "  %bAuswahl:%b " "$BOLD" "$RST"
  local choice; read -r choice || return

  case "$choice" in
    1)
      section "Fremdpakete / veraltete AUR-Pakete"
      yay -Qm 2>/dev/null | while IFS= read -r line; do
        printf "  %b◈%b %s\n" "$M" "$RST" "$line"
      done || status info "Keine Fremdpakete."
      ;;
    2)
      section "Cache bereinigen"
      status info "Entferne nicht mehr benötigte Build-Verzeichnisse und alte Paket-Caches."
      if confirm "pacman + yay Cache bereinigen?"; then
        check_sudo || { pause; return; }
        sudo pacman -Sc --noconfirm 2>&1 | tee -a "$LOG_FILE"
        yay -Sc --noconfirm 2>&1 | tee -a "$LOG_FILE"
        status ok "Bereinigung abgeschlossen."
      fi
      ;;
    3)
      section "Waisenpakete"
      local orphan_list; orphan_list=$(pacman -Qdt 2>/dev/null || true)
      if [[ -z "$orphan_list" ]]; then
        status ok "Keine Waisenpakete vorhanden."
      else
        printf '%s' "$orphan_list"
        echo
        status warn "Obige Pakete werden von keinem installierten Paket benötigt."
        if confirm "Alle Waisenpakete entfernen?"; then
          check_sudo || { pause; return; }
          # shellcheck disable=SC2046
          sudo pacman -Rns $(pacman -Qdtq) --noconfirm 2>&1 | tee -a "$LOG_FILE"
          status ok "Waisenpakete entfernt."
        fi
      fi
      ;;
    4)
      section "Datenbankintegrität prüfen"
      check_sudo || { pause; return; }
      sudo pacman -Dk 2>&1 | tee -a "$LOG_FILE"
      ;;
    5)
      section "yay-Konfiguration"
      local yay_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/yay/config.json"
      if [[ -f "$yay_cfg" ]]; then
        cat "$yay_cfg"
      else
        status info "Keine yay-Konfigurationsdatei gefunden: $yay_cfg"
      fi
      ;;
    *) return ;;
  esac
  pause
}

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: SETTINGS
# ──────────────────────────────────────────────────────────────────────────────
_bool_label() { [[ "$1" == "true" ]] && printf '%bEin%b' "$G" "$RST" || printf '%bAus%b' "$R" "$RST"; }
_toggle()     { [[ "$1" == "true" ]] && echo "false" || echo "true"; }

action_settings() {
  print_header
  section "Einstellungen"

  # Defaults
  local use_color=true confirm_always=true log_enabled=true
  # shellcheck source=/dev/null
  [[ -f "$SETTINGS_FILE" ]] && source "$SETTINGS_FILE" || true

  echo
  printf "  %b1%b  Farben aktiviert:            %b\n" "$BOLD" "$RST" "$(_bool_label $use_color)"
  printf "  %b2%b  Bestätigung immer anzeigen:  %b\n" "$BOLD" "$RST" "$(_bool_label $confirm_always)"
  printf "  %b3%b  Protokollierung:             %b\n" "$BOLD" "$RST" "$(_bool_label $log_enabled)"
  printf "  %b4%b  Konfiguration zurücksetzen\n"       "$BOLD" "$RST"
  printf "  %bq%b  Zurück\n"                           "$BOLD" "$RST"
  echo
  printf "  %bAuswahl:%b " "$BOLD" "$RST"
  local c; read -r c || return
  case "$c" in
    1) use_color=$(_toggle "$use_color") ;;
    2) confirm_always=$(_toggle "$confirm_always") ;;
    3) log_enabled=$(_toggle "$log_enabled") ;;
    4) if confirm "Alle Einstellungen zurücksetzen?"; then rm -f "$SETTINGS_FILE"; status ok "Zurückgesetzt."; pause; return; fi ;;
    *) return ;;
  esac

  cat > "$SETTINGS_FILE" <<-EOF
	# PacUI Configuration — generated $(date)
	use_color=$use_color
	confirm_always=$confirm_always
	log_enabled=$log_enabled
	EOF
  status ok "Einstellungen gespeichert: $SETTINGS_FILE"
  pause
}

# ──────────────────────────────────────────────────────────────────────────────
# ACTION: LOGS
# ──────────────────────────────────────────────────────────────────────────────
action_logs() {
  print_header
  section "Protokoll: $LOG_FILE"

  if [[ ! -f "$LOG_FILE" ]]; then
    status info "Keine Protokolldatei vorhanden."; pause; return
  fi

  local size; size=$(du -sh "$LOG_FILE" 2>/dev/null | cut -f1)
  kv "Dateigröße" "$size"
  kv "Einträge"   "$(wc -l < "$LOG_FILE")"
  echo
  printf "  %b1%b  Letzte 50 Einträge\n" "$BOLD" "$RST"
  printf "  %b2%b  Nur Fehler und Warnungen\n" "$BOLD" "$RST"
  printf "  %b3%b  Vollständig anzeigen (less)\n" "$BOLD" "$RST"
  printf "  %b4%b  Protokoll leeren\n" "$BOLD" "$RST"
  printf "  %bq%b  Zurück\n" "$BOLD" "$RST"
  echo
  printf "  %bAuswahl:%b " "$BOLD" "$RST"
  local c; read -r c || return

  case "$c" in
    1)
      section "Letzte 50 Einträge"
      tail -50 "$LOG_FILE" | while IFS= read -r line; do
        if   [[ "$line" =~ \[ERROR\] ]]; then printf "  %b%s%b\n" "$R" "$line" "$RST"
        elif [[ "$line" =~ \[WARN\]  ]]; then printf "  %b%s%b\n" "$Y" "$line" "$RST"
        elif [[ "$line" =~ \[OK\]    ]]; then printf "  %b%s%b\n" "$G" "$line" "$RST"
        else                                   printf "  %b%s%b\n" "$D" "$line" "$RST"
        fi
      done ;;
    2)
      section "Fehler & Warnungen"
      grep -E '\[(ERROR|WARN)\]' "$LOG_FILE" | tail -30 | while IFS= read -r line; do
        [[ "$line" =~ ERROR ]] && printf "  %b%s%b\n" "$R" "$line" "$RST" \
                               || printf "  %b%s%b\n" "$Y" "$line" "$RST"
      done || status info "Keine Fehler im Protokoll." ;;
    3) less +G "$LOG_FILE"; return ;;
    4) if confirm "Protokoll leeren?"; then : > "$LOG_FILE"; status ok "Protokoll geleert."; fi ;;
    *) return ;;
  esac
  pause
}

# ──────────────────────────────────────────────────────────────────────────────
# ERROR HANDLER
# ──────────────────────────────────────────────────────────────────────────────
handle_error() {
  local context="$1" message="$2"
  log "ERROR" "[$context] $message"
  echo
  status err "$message"
  echo

  case "$context" in
    pacman-install)
      status info "Lösungsvorschläge:"
      printf "  %b→%b Paketname prüfen:            %bpacman -Ss <paket>%b\n" "$Y" "$RST" "$C" "$RST"
      printf "  %b→%b Datenbank synchronisieren:   %bsudo pacman -Sy%b\n"    "$Y" "$RST" "$C" "$RST"
      printf "  %b→%b Schlüsselring aktualisieren: %bsudo pacman -S archlinux-keyring%b\n" "$Y" "$RST" "$C" "$RST"
      ;;
    yay-install)
      status info "Lösungsvorschläge:"
      printf "  %b→%b Build-Cache prüfen: %b~/.cache/yay/%b\n"               "$Y" "$RST" "$C" "$RST"
      printf "  %b→%b PKGBUILD lesen:     %byay --editmenu%b\n"              "$Y" "$RST" "$C" "$RST"
      printf "  %b→%b Abhängigkeiten manuell installieren\n"                  "$Y" "$RST"
      ;;
    pacman-remove)
      status info "Lösungsvorschläge:"
      printf "  %b→%b Abhängige Pakete zuerst entfernen\n"                    "$Y" "$RST"
      printf "  %b→%b Erzwingen (gefährlich!): %bsudo pacman -Rdd <paket>%b\n" "$Y" "$RST" "$R" "$RST"
      ;;
    pacman-update|yay-update)
      status info "Lösungsvorschläge:"
      printf "  %b→%b Spiegelserver aktualisieren: %breflector --latest 5 --save /etc/pacman.d/mirrorlist%b\n" "$Y" "$RST" "$C" "$RST"
      printf "  %b→%b Schlüsselring:               %bsudo pacman -S archlinux-keyring%b\n" "$Y" "$RST" "$C" "$RST"
      printf "  %b→%b Arch Wiki:                   %bhttps://wiki.archlinux.org/title/Pacman%b\n" "$Y" "$RST" "$C" "$RST"
      ;;
    pacman-rollback)
      status info "Lösungsvorschläge:"
      printf "  %b→%b Archived Linux Archive: %bhttps://archive.archlinux.org/packages/%b\n" "$Y" "$RST" "$C" "$RST"
      printf "  %b→%b downgrade AUR-Helfer:   %byay -S downgrade%b\n"        "$Y" "$RST" "$C" "$RST"
      ;;
    *)
      status info "Protokoll prüfen: $LOG_FILE" ;;
  esac

  echo
  printf "  %b[r]%b Wiederholen  %b[l]%b Log  %bEnter%b Fortfahren: " \
    "$BOLD" "$RST" "$BOLD" "$RST" "$BOLD" "$RST"
  local ec; read -r ec || ec=""
  case "$ec" in
    l) action_logs ;;
  esac
}

# ──────────────────────────────────────────────────────────────────────────────
# HELP SCREEN
# ──────────────────────────────────────────────────────────────────────────────
show_help() {
  print_header
  section "Hilfe & Referenz"

  echo
  printf "  %bNavigation%b\n" "$BOLD" "$RST"
  kv "  1–9"         "Menüpunkt wählen"
  kv "  q / Enter"   "Zurück / Abbrechen"
  kv "  j / n"       "Ja / Nein bei Dialogen"
  kv "  i<Nr.>"      "Paket-Info in Suchergebnissen"

  echo
  printf "  %bStatusfarben%b\n" "$BOLD" "$RST"
  printf "  %b✔ Grün%b    Erfolg / Installiert\n"   "$G" "$RST"
  printf "  %b⚠ Gelb%b    Warnung / Bestätigung\n"  "$Y" "$RST"
  printf "  %b✖ Rot%b     Fehler / Abbruch\n"       "$R" "$RST"
  printf "  %bℹ Blau%b    Information\n"             "$B" "$RST"
  printf "  %b▶ Cyan%b    Prozess läuft\n"           "$C" "$RST"
  printf "  %b◈ Lila%b    AUR-bezogen\n"             "$M" "$RST"
  printf "  %b!! Rot-BG%b Kritische Warnung\n"       "${BG_R}${W}" "$RST"

  echo
  printf "  %bPrivilegien & sudo%b\n" "$BOLD" "$RST"
  printf "  Dieses Skript startet als normaler Nutzer.\n"
  printf "  %bsudo%b wird nur für pacman-Systemoperationen intern angefragt.\n" "$BOLD" "$RST"
  printf "  %bPolkit-Alternative:%b\n" "$BOLD" "$RST"
  printf "    %b/etc/polkit-1/rules.d/49-pacman.rules%b\n" "$C" "$RST"
  printf "    %bhttps://wiki.archlinux.org/title/Polkit%b\n" "$D" "$RST"

  echo
  printf "  %bPfade%b\n" "$BOLD" "$RST"
  kv "  Konfiguration" "$SETTINGS_FILE"
  kv "  Protokoll"     "$LOG_FILE"
  kv "  Cache-Dir"     "$CACHE_DIR"

  pause
}

# ──────────────────────────────────────────────────────────────────────────────
# MAIN MENU
# ──────────────────────────────────────────────────────────────────────────────
main_menu() {
  while true; do
    print_header

    # Queue badge
    if [[ ${#INSTALL_QUEUE[@]} -gt 0 ]]; then
      center "${Y}⚠ Installationswarteschlange: ${#INSTALL_QUEUE[@]} Paket/e ausstehend${RST}"
      echo
    fi

    # Orphan hint (cheap: reuse cached value if we had it, otherwise skip for speed)
    local orphan_count; orphan_count=$(pacman -Qdt 2>/dev/null | wc -l || echo 0)

    printf "  %b%-4s  %-36s%b\n" "$BOLD" "Nr." "Aktion" "$RST"
    hline '-'
    local queue_badge="" yay_badge=""
    (( ${#INSTALL_QUEUE[@]} > 0 )) && \
      printf -v queue_badge '%b[%d ausstehend]%b' "$Y" "${#INSTALL_QUEUE[@]}" "$RST"
    if $HAS_YAY; then
      printf -v yay_badge '%b[yay verfügbar]%b' "$G" "$RST"
    else
      printf -v yay_badge '%b[yay fehlt]%b'     "$Y" "$RST"
    fi

    printf "  %b 1%b  System aktualisieren\n"              "$BOLD" "$RST"
    printf "  %b 2%b  Paket installieren\n"                "$BOLD" "$RST"
    printf "  %b 3%b  Paket entfernen\n"                   "$BOLD" "$RST"
    printf "  %b 4%b  Pakete suchen\n"                     "$BOLD" "$RST"
    printf "  %b 5%b  %-36s%b\n" "$BOLD" "$RST" "Status & Warteschlange" "$queue_badge"
    printf "  %b 6%b  %-36s%b\n" "$BOLD" "$RST" "AUR-Manager"            "$yay_badge"
    printf "  %b 7%b  Rollback (Paket-Downgrade)\n"        "$BOLD" "$RST"
    printf "  %b 8%b  Einstellungen\n"                     "$BOLD" "$RST"
    printf "  %b 9%b  Protokolle anzeigen\n"               "$BOLD" "$RST"
    printf "  %b 0%b  Hilfe\n"                             "$BOLD" "$RST"
    printf "  %b q%b  Beenden\n"                           "$BOLD" "$RST"
    hline '-'

    if (( orphan_count > 0 )); then
      printf "  %bℹ %d Waisenpakete gefunden → Option 6 → AUR-Menü%b\n" "$Y" "$orphan_count" "$RST"
    fi

    echo
    printf "  %bAuswahl [0–9 / q]:%b " "$BOLD" "$RST"
    local choice; read -r choice || break

    case "$choice" in
      1) action_update   ;;
      2) action_install  ;;
      3) action_remove   ;;
      4) action_search   ;;
      5) action_status   ;;
      6) action_aur      ;;
      7) action_rollback ;;
      8) action_settings ;;
      9) action_logs     ;;
      0) show_help       ;;
      q|Q) break         ;;
    esac
  done
}

# ──────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ──────────────────────────────────────────────────────────────────────────────
main() {
  trap 'echo; status info "PacUI beendet."; exit 0' INT TERM

  check_deps
  log "INFO" "${PACUI_NAME} ${PACUI_VERSION} gestartet — Nutzer: $(whoami)"

  # Feature summary on first run
  print_header
  echo
  if $HAS_YAY; then
    status ok "yay erkannt — AUR-Unterstützung aktiv."
  else
    status warn "yay nicht gefunden — nur offizielle Repos verfügbar."
  fi
  $HAS_FZF && status ok "fzf erkannt (optionale Schnellauswahl)."
  if $HAS_CHECKUPDATES; then
    status ok "checkupdates erkannt."
  else
    status info "checkupdates nicht gefunden — nutze pacman -Qu."
  fi
  echo
  pause

  main_menu

  echo
  status info "${PACUI_NAME} beendet. Auf Wiedersehen!"
  log "INFO" "${PACUI_NAME} beendet"
}

main "$@"
