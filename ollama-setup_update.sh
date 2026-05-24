#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
trap 'echo "FEHLER in ${FUNCNAME[0]:-main}:${LINENO}" >&2' ERR

# ── Farben ────────────────────────────────────────────────────────────────────
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_RED='\033[0;31m'
readonly C_CYAN='\033[0;36m'
readonly C_BOLD='\033[1m'
readonly C_RESET='\033[0m'

ok()   { echo -e "${C_GREEN}  [OK] ${*}${C_RESET}"; }
warn() { echo -e "${C_YELLOW}  [!!] ${*}${C_RESET}" >&2; }
err()  { echo -e "${C_RED}  [EE] ${*}${C_RESET}" >&2; }
info() { echo -e "${C_CYAN}  [..] ${*}${C_RESET}"; }

# ── Abhängigkeiten prüfen ─────────────────────────────────────────────────────
function check_deps() {
  local fehlend=0
  for cmd in pacman curl fzf; do
    if ! command -v "${cmd}" &>/dev/null; then
      err "${cmd} nicht gefunden — installieren mit: sudo pacman -S ${cmd}"
      (( fehlend++ )) || true
    fi
  done
  (( fehlend == 0 )) || exit 1
}

# ── Layout ────────────────────────────────────────────────────────────────────
function dynamic_width() {
  local w
  w=$(tput cols 2>/dev/null || echo 70)
  (( w > 100 )) && w=100
  (( w < 52  )) && w=52
  echo "${w}"
}

function draw_line() {
  # Zeichenketten-Concat statt tr — tr arbeitet byteweise und bricht UTF-8
  local width="${1:-60}"
  local line='' i
  for (( i = 0; i < width; i++ )); do line+='─'; done
  echo "${line}"
}

function ensure_sudo() {
  sudo -v 2>/dev/null || { err "sudo-Authentifizierung fehlgeschlagen."; exit 1; }
}

function require_ollama() {
  command -v ollama &>/dev/null || {
    err "Ollama ist nicht installiert — bitte zuerst Option 1 ausführen."
    return 1
  }
}

function detect_aur_helper() {
  if   command -v yay  &>/dev/null; then echo "yay"
  elif command -v paru &>/dev/null; then echo "paru"
  else echo ""
  fi
}

function service_status() {
  if systemctl is-active --quiet ollama 2>/dev/null; then
    printf "${C_GREEN}aktiv${C_RESET}"
  else
    printf "${C_YELLOW}gestoppt${C_RESET}"
  fi
}

# ── Hauptmenü ─────────────────────────────────────────────────────────────────
function show_menu() {
  local w
  w=$(dynamic_width)
  clear
  draw_line "${w}"
  echo -e "${C_BOLD}  Ollama Manager  //  Arch Linux${C_RESET}   [ollama: $(service_status)]"
  draw_line "${w}"
  echo -e "  ${C_CYAN}1${C_RESET}  Ollama + Opencode + llm-manager installieren"
  echo -e "  ${C_CYAN}2${C_RESET}  KI-Modelle verwalten"
  echo -e "  ${C_CYAN}3${C_RESET}  Ollama, Modelle & Opencode entfernen"
  echo -e "  ${C_CYAN}q${C_RESET}  Beenden"
  draw_line "${w}"
}

# ── 1) Installation ───────────────────────────────────────────────────────────
function install_ollama() {
  local aur_helper
  aur_helper=$(detect_aur_helper)

  echo
  warn "GPU-Backend Auswahl:"
  warn "  ollama-rocm   = AMD-Grafikkarten (ROCm-Treiber erforderlich)"
  warn "  ollama-vulkan = allgemein: iGPU, Nvidia-Fallback, sonstige"
  warn "Nicht benötigte Backends verursachen keine Fehler, belegen aber Speicher."
  warn "Hinweis: Nur ein Backend gleichzeitig aktiv — ROCm hat Vorrang vor Vulkan."
  echo
  read -rp "  ollama-rocm   installieren (AMD)? [j/N]: " do_rocm
  read -rp "  ollama-vulkan installieren (iGPU)? [j/N]: " do_vulkan

  local base_pkgs=("ollama")
  [[ "${do_rocm,,}"   == "j" ]] && base_pkgs+=("ollama-rocm")
  [[ "${do_vulkan,,}" == "j" ]] && base_pkgs+=("ollama-vulkan")

  info "Installiere: ${base_pkgs[*]} …"
  sudo pacman -S --needed --noconfirm "${base_pkgs[@]}"
  ok "Ollama-Kern installiert."

  # opencode & llm-manager sind AUR-Pakete
  info "Installiere AUR-Pakete: opencode llm-manager …"
  if [[ -z "${aur_helper}" ]]; then
    err "Kein AUR-Helper gefunden (yay oder paru wird benötigt)."
    warn "yay zuerst installieren, dann Option 1 erneut ausführen:"
    warn "  git clone https://aur.archlinux.org/yay.git"
    warn "  cd yay && makepkg -si"
    warn "opencode und llm-manager werden übersprungen."
  else
    "${aur_helper}" -S --needed --noconfirm opencode llm-manager
    ok "opencode & llm-manager installiert via ${aur_helper}."
    warn "Hinweis: opencode benötigt eine aktive Ollama-Instanz als Backend."
    warn "         llm-manager ermöglicht Modellverwaltung über eine Web-UI."
  fi

  info "ollama.service aktivieren und starten …"
  sudo systemctl enable --now ollama
  ok "ollama.service ist aktiv."

  # Konfig-Ordner anlegen mit README
  local config_dir="${HOME}/Ollama_config"
  if [[ ! -d "${config_dir}" ]]; then
    mkdir -p "${config_dir}"
    cat > "${config_dir}/README.txt" << 'EOF'
Ollama Modell-Konfigurationsordner
====================================
Lege hier deine Modelfiles ab (z.B. Modelfile.llama3, Modelfile.mistral).

Beispiel Modelfile:
  FROM llama3
  SYSTEM "Du bist ein hilfreicher Assistent."
  PARAMETER temperature 0.7
  PARAMETER num_ctx 4096

Modell daraus bauen:
  ollama create mein-modell -f ~/Ollama_config/Modelfile.llama3

Modell testen:
  ollama run mein-modell

Alle eigenen Modelle auflisten:
  ollama list

Dokumentation:
  https://github.com/ollama/ollama/blob/main/docs/modelfile.md

OLLAMA_MODELS (optional — Speicherort für Modell-Binaries ändern):
  export OLLAMA_MODELS=~/Ollama_config/models
  Eintragen in ~/.bashrc oder ~/.zshrc, danach:
  systemctl --user restart ollama  (oder: sudo systemctl restart ollama)
EOF
    ok "Konfigurationsordner erstellt: ${config_dir}"
    ok "README.txt mit Kurzanleitung wurde abgelegt."
  else
    warn "${config_dir} existiert bereits — wird nicht überschrieben."
  fi

  echo
  warn "Hinweise nach der Installation:"
  warn "  ROCm-Nutzer: Benutzer zu GPU-Gruppen hinzufügen (Neuanmeldung nötig):"
  warn "    sudo usermod -aG render,video \$USER"
  warn "  Modelfiles ablegen in: ${config_dir}"
  warn "  API erreichbar unter:  http://localhost:11434"
  warn "  Logs prüfen mit:       journalctl -u ollama -f"
}

# ── 2) Modellverwaltung ───────────────────────────────────────────────────────
function fetch_available_models() {
  # Ollama-Such-API — q= liefert alle Modelle sortiert nach Downloads
  local url="https://ollama.com/api/search?q=&p=1&ps=200"
  info "Lade Modellliste von ollama.com …"
  if ! curl -fsSL --max-time 15 "${url}" 2>/dev/null \
      | grep -oP '"name":"\K[^"]+' | sort -u; then
    warn "ollama.com nicht erreichbar — manuell unter: https://ollama.com/library"
    return 1
  fi
}

function list_local_models() {
  require_ollama || return
  local out
  out=$(ollama list 2>/dev/null || true)
  if [[ -z "${out}" ]] || [[ "${out}" == NAME* && $(echo "${out}" | wc -l) -le 1 ]]; then
    warn "Keine lokalen Modelle installiert."
    warn "Hinweis: Modelle herunterladen über Option 2 → Modell herunterladen."
  else
    echo -e "${C_BOLD}${out}${C_RESET}"
    warn "Tipp: Modell direkt starten mit: ollama run <modellname>"
  fi
}

function pull_models() {
  require_ollama || return
  info "Lade Modellliste … (Leertaste=auswählen, Enter=bestätigen, Esc=abbrechen)"
  warn "Hinweis: Modellgröße variiert stark — kleine Modelle (z.B. qwen2.5:1.5b) ~1 GB,"
  warn "         große Modelle (z.B. llama3.3:70b) können über 40 GB groß sein."
  local model_list selected
  model_list=$(fetch_available_models 2>/dev/null || true)
  if [[ -z "${model_list}" ]]; then
    warn "Modellliste leer — Internetverbindung prüfen."
    return
  fi

  selected=$(echo "${model_list}" \
    | fzf --multi \
          --prompt="  Modell herunterladen > " \
          --header="Leertaste=auswählen  Enter=herunterladen  Esc=abbrechen" \
          --color="hl:green,hl+:green" \
    || true)

  [[ -z "${selected}" ]] && { warn "Kein Modell ausgewählt."; return; }

  while IFS= read -r model; do
    info "Lade ${model} herunter …"
    ollama pull "${model}"
    ok "${model} bereit."
  done <<< "${selected}"

  warn "Tipp: Modell testen mit: ollama run <modellname>"
}

function update_models() {
  require_ollama || return
  local local_models
  local_models=$(ollama list 2>/dev/null | awk 'NR>1 && $1!="" {print $1}' || true)

  if [[ -z "${local_models}" ]]; then
    warn "Keine lokalen Modelle gefunden — nichts zu aktualisieren."
    return
  fi

  info "Verwaiste Modell-Layer bereinigen …"
  # prune ist nicht in allen Ollama-Versionen verfügbar
  ollama prune 2>/dev/null && ok "Bereinigung abgeschlossen." \
    || warn "ollama prune nicht verfügbar — wird übersprungen."

  warn "Alle lokalen Modelle werden neu geladen (kann lange dauern) …"
  while IFS= read -r model; do
    info "Aktualisiere ${model} …"
    ollama pull "${model}"
    ok "${model} aktualisiert."
  done <<< "${local_models}"

  ok "Alle Modelle auf aktuellem Stand."
  warn "Tipp: Nicht mehr benötigte Modelle entfernen um Speicher freizugeben."
}

function remove_models() {
  require_ollama || return
  local local_models
  local_models=$(ollama list 2>/dev/null | awk 'NR>1 && $1!="" {print $1}' || true)

  if [[ -z "${local_models}" ]]; then
    warn "Keine lokalen Modelle installiert."
    return
  fi

  local selected
  selected=$(echo "${local_models}" \
    | fzf --multi \
          --prompt="  Modell entfernen > " \
          --header="Leertaste=auswählen  Enter=löschen  Esc=abbrechen" \
          --color="hl:red,hl+:red" \
    || true)

  [[ -z "${selected}" ]] && { warn "Nichts ausgewählt."; return; }

  warn "Werden gelöscht: $(echo "${selected}" | tr '\n' ' ')"
  warn "Achtung: Modell-Dateien werden unwiderruflich entfernt!"
  read -rp "  Wirklich löschen? [j/N]: " confirm
  [[ "${confirm,,}" != "j" ]] && { info "Abgebrochen."; return; }

  while IFS= read -r model; do
    ollama rm "${model}"
    ok "Entfernt: ${model}"
  done <<< "${selected}"

  warn "Tipp: Speicherbelegung prüfen mit: df -h ~/.ollama"
}

function model_menu() {
  local w sub
  while true; do
    w=$(dynamic_width)
    echo
    draw_line "${w}"
    echo -e "${C_BOLD}  KI-Modelle verwalten${C_RESET}"
    draw_line "${w}"
    echo -e "  ${C_CYAN}1${C_RESET}  Lokale Modelle anzeigen"
    echo -e "  ${C_CYAN}2${C_RESET}  Modell herunterladen"
    echo -e "  ${C_CYAN}3${C_RESET}  Alle Modelle aktualisieren"
    echo -e "  ${C_CYAN}4${C_RESET}  Modelle entfernen"
    echo -e "  ${C_CYAN}z${C_RESET}  Zurück"
    draw_line "${w}"
    read -rp "  Auswahl: " sub
    case "${sub}" in
      1) list_local_models ;;
      2) pull_models ;;
      3) update_models ;;
      4) remove_models ;;
      z|Z) return ;;
      *) warn "Ungültige Eingabe." ;;
    esac
    echo
    read -rp "  Weiter mit Enter …" _
  done
}

# ── 3) Deinstallation ─────────────────────────────────────────────────────────
function remove_all() {
  echo
  warn "Folgende Pakete werden entfernt: ollama, ollama-rocm, ollama-vulkan, opencode, llm-manager"
  warn "Alle Modelldaten unter ~/.ollama werden DAUERHAFT gelöscht!"
  warn "Der Ordner ~/Ollama_config (eigene Modelfiles) bleibt erhalten."
  read -rp "  Zur Bestätigung 'ja' eingeben: " confirm
  [[ "${confirm}" != "ja" ]] && { info "Abgebrochen."; return; }

  info "ollama.service stoppen und deaktivieren …"
  sudo systemctl disable --now ollama 2>/dev/null || true

  info "Installierte Pakete ermitteln …"
  local pkgs=()
  for p in ollama ollama-rocm ollama-vulkan opencode llm-manager; do
    pacman -Q "${p}" &>/dev/null && pkgs+=("${p}") || true
  done

  if (( ${#pkgs[@]} > 0 )); then
    sudo pacman -Rns --noconfirm "${pkgs[@]}"
    ok "Entfernt: ${pkgs[*]}"
  else
    warn "Keine passenden pacman-Pakete gefunden."
  fi

  # AUR-Pakete ggf. separat entfernen
  local aur_helper
  aur_helper=$(detect_aur_helper)
  if [[ -n "${aur_helper}" ]]; then
    warn "AUR-Pakete ggf. noch vorhanden — manuell prüfen:"
    warn "  ${aur_helper} -Rns opencode llm-manager"
  fi

  info "Modelldaten unter ~/.ollama löschen …"
  rm -rf "${HOME}/.ollama"
  ok "Modelldaten gelöscht."

  warn "Hinweis: ~/Ollama_config (eigene Modelfiles) wurde NICHT gelöscht."
  warn "         Manuell entfernen mit: rm -rf ~/Ollama_config"
}

# ── Hauptprogramm ─────────────────────────────────────────────────────────────
function main() {
  check_deps
  local choice
  while true; do
    show_menu
    read -rp "  Auswahl: " choice
    case "${choice}" in
      1)
        ensure_sudo
        install_ollama
        ;;
      2)
        model_menu
        continue   # model_menu bringt eigene Enter-Schleife mit
        ;;
      3)
        ensure_sudo
        remove_all
        ;;
      q|Q)
        info "Auf Wiedersehen."
        exit 0
        ;;
      *)
        warn "Ungültige Eingabe — bitte 1, 2, 3 oder q eingeben."
        ;;
    esac
    echo
    read -rp "  Weiter mit Enter …" _
  done
}

main "$@"
