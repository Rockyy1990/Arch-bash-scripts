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
      fehlend=$(( fehlend + 1 ))
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
    printf '%s' "${C_GREEN}aktiv${C_RESET}"
  else
    printf '%s' "${C_YELLOW}gestoppt${C_RESET}"
  fi
}

# Physische CPU-Kerne ermitteln — LANG=C für Locale-Unabhängigkeit
function get_phys_cores() {
  local cores log_cores
  cores=$(LANG=C lscpu | awk '/^Core\(s\) per socket:/{c=$NF} /^Socket\(s\):/{s=$NF} END{print c*s}')
  log_cores=$(nproc)
  [[ -z "${cores}" || "${cores}" == "0" ]] && cores="${log_cores}"
  echo "${cores}"
}

# Lokale Ollama-Modelle als zeilenweise Liste ausgeben
function get_local_models() {
  ollama list 2>/dev/null | awk 'NR>1 && $1!="" {print $1}' || true
}

# ~/Ollama_config anlegen falls nicht vorhanden
function ensure_config_dir() {
  local config_dir="${HOME}/Ollama_config"
  if [[ ! -d "${config_dir}" ]]; then
    mkdir -p "${config_dir}"
    ok "Konfigurationsordner erstellt: ${config_dir}"
  fi
}

# Einheitliche Warnung wenn kein AUR-Helper gefunden
function warn_no_aur() {
  err "Kein AUR-Helper gefunden (yay oder paru wird benötigt)."
  warn "yay installieren:"
  warn "  git clone https://aur.archlinux.org/yay.git"
  warn "  cd yay && makepkg -si"
}
function show_menu() {
  local w
  w=$(dynamic_width)
  clear
  draw_line "${w}"
  echo -e "${C_BOLD}  Ollama Manager  //  Arch Linux${C_RESET}   [ollama: $(service_status)]"
  draw_line "${w}"
  echo -e "  ${C_BOLD}── Installation ──────────────────────────────${C_RESET}"
  echo -e "  ${C_CYAN}1${C_RESET}  Ollama + llm-manager installieren (GPU generisch)"
  echo -e "  ${C_CYAN}2${C_RESET}  AMD Ryzen + Vulkan Setup + Systemoptimierung"
  echo -e "  ${C_CYAN}3${C_RESET}  CPU-only Setup + Systemoptimierung"
  echo -e "  ${C_BOLD}── Verwaltung ────────────────────────────────${C_RESET}"
  echo -e "  ${C_CYAN}4${C_RESET}  KI-Modelle verwalten"
  echo -e "  ${C_CYAN}5${C_RESET}  Modelfile-Assistent"
  echo -e "  ${C_CYAN}6${C_RESET}  Opencode nachinstallieren"
  echo -e "  ${C_BOLD}── System ────────────────────────────────────${C_RESET}"
  echo -e "  ${C_CYAN}7${C_RESET}  Deinstallation"
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
  local do_rocm do_vulkan
  read -rp "  ollama-rocm   installieren (AMD)? [j/N]: " do_rocm
  read -rp "  ollama-vulkan installieren (iGPU)? [j/N]: " do_vulkan

  local base_pkgs=("ollama")
  [[ "${do_rocm,,}"   == "j" ]] && base_pkgs+=("ollama-rocm")
  [[ "${do_vulkan,,}" == "j" ]] && base_pkgs+=("ollama-vulkan")

  info "Installiere: ${base_pkgs[*]} …"
  sudo pacman -S --needed --noconfirm "${base_pkgs[@]}"
  ok "Ollama-Kern installiert."

  # opencode optional — llm-manager immer
  info "Installiere AUR-Paket: llm-manager …"
  local do_opencode
  read -rp "  opencode ebenfalls installieren? (KI-gestützter Code-Editor) [j/N]: " do_opencode
  local aur_pkgs=("llm-manager")
  [[ "${do_opencode,,}" == "j" ]] && aur_pkgs+=("opencode")

  if [[ -z "${aur_helper}" ]]; then
    warn_no_aur
    warn "Nach Installation von yay Option 1 erneut ausführen."
    warn "AUR-Pakete werden übersprungen."
  else
    "${aur_helper}" -S --needed --noconfirm "${aur_pkgs[@]}"
    ok "AUR-Pakete installiert: ${aur_pkgs[*]} via ${aur_helper}."
    warn "Hinweis: llm-manager — Web-UI zur Modellverwaltung unter http://localhost:8080"
    [[ "${do_opencode,,}" == "j" ]] && \
      warn "Hinweis: opencode benötigt eine aktive Ollama-Instanz als Backend."
  fi

  info "ollama.service aktivieren und starten …"
  sudo systemctl enable --now ollama
  ok "ollama.service ist aktiv."

  # Konfig-Ordner anlegen + README nur beim ersten Mal
  local config_dir="${HOME}/Ollama_config"
  ensure_config_dir
  if [[ -f "${config_dir}/README.txt" ]]; then
    warn "${config_dir} existiert bereits — README wird nicht überschrieben."
  else
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
    ok "README.txt mit Kurzanleitung wurde abgelegt."
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
  if [[ -z "${out}" ]] || [[ "${out}" == NAME* && $(wc -l <<< "${out}") -le 1 ]]; then
    warn "Keine lokalen Modelle installiert."
    warn "Hinweis: Modelle herunterladen über Option 2 → Modell herunterladen."
  else
    echo -e "${C_BOLD}${out}${C_RESET}"
    warn "Tipp: Modell direkt starten mit: ollama run <modellname>"
  fi
}

function pull_models() {
  require_ollama || return

  local w
  w=$(dynamic_width)
  echo
  draw_line "${w}"
  echo -e "${C_BOLD}  Empfohlene Modelle — Namen zum Kopieren${C_RESET}"
  draw_line "${w}"
  echo -e "${C_BOLD}  Allgemein / Chat:${C_RESET}"
  echo -e "  ${C_CYAN}llama3.2:3b${C_RESET}         (Meta, schnell, gut für CPU, ~2 GB)"
  echo -e "  ${C_CYAN}llama3.1:8b${C_RESET}         (Meta, ausgewogen, ~5 GB)"
  echo -e "  ${C_CYAN}llama3.3:70b${C_RESET}        (Meta, sehr leistungsfähig, ~43 GB)"
  echo -e "  ${C_CYAN}mistral:7b${C_RESET}          (Mistral AI, schnell & präzise, ~4 GB)"
  echo -e "  ${C_CYAN}gemma2:2b${C_RESET}           (Google, sehr kompakt, ~1.6 GB)"
  echo -e "  ${C_CYAN}gemma2:9b${C_RESET}           (Google, hohe Qualität, ~6 GB)"
  echo
  echo -e "${C_BOLD}  Code / Entwicklung:${C_RESET}"
  echo -e "  ${C_CYAN}qwen2.5-coder:7b${C_RESET}    (Alibaba, Codegenerierung, ~5 GB)"
  echo -e "  ${C_CYAN}qwen2.5-coder:32b${C_RESET}   (Alibaba, top Codequalität, ~20 GB)"
  echo -e "  ${C_CYAN}deepseek-coder-v2:16b${C_RESET} (DeepSeek, stark für Code, ~9 GB)"
  echo -e "  ${C_CYAN}codellama:7b${C_RESET}        (Meta, Code & Erklärungen, ~4 GB)"
  echo
  echo -e "${C_BOLD}  Kompakt / CPU-optimiert:${C_RESET}"
  echo -e "  ${C_CYAN}qwen2.5:1.5b${C_RESET}        (Alibaba, sehr klein, ~1 GB)"
  echo -e "  ${C_CYAN}qwen2.5:3b${C_RESET}          (Alibaba, klein & gut, ~2 GB)"
  echo -e "  ${C_CYAN}phi3:mini${C_RESET}           (Microsoft, effizient, ~2.3 GB)"
  echo -e "  ${C_CYAN}phi4:14b${C_RESET}            (Microsoft, starke Reasoning, ~9 GB)"
  echo -e "  ${C_CYAN}smollm2:1.7b${C_RESET}        (HuggingFace, extrem klein, ~1 GB)"
  echo
  echo -e "${C_BOLD}  Mehrsprachig / Deutsch:${C_RESET}"
  echo -e "  ${C_CYAN}qwen2.5:7b${C_RESET}          (Alibaba, gutes Deutsch, ~5 GB)"
  echo -e "  ${C_CYAN}aya:8b${C_RESET}              (Cohere, 23 Sprachen inkl. Deutsch, ~5 GB)"
  echo -e "  ${C_CYAN}mistral-nemo:12b${C_RESET}    (Mistral, multilingual, ~7 GB)"
  draw_line "${w}"
  warn "Format für ollama pull: ollama pull <name>  (z.B. ollama pull llama3.2:3b)"
  warn "Ohne Tag wird automatisch das kleinste verfügbare Modell geladen."
  echo

  info "Lade Online-Modellliste … (Leertaste=auswählen, Enter=bestätigen, Esc=abbrechen)"
  warn "Größenhinweis: ~1 GB (1.5b) bis >40 GB (70b) — Speicher vorher prüfen."
  local model_list selected
  model_list=$(fetch_available_models 2>/dev/null || true)
  if [[ -z "${model_list}" ]]; then
    warn "Online-Liste nicht erreichbar — Modellnamen oben manuell eingeben:"
    warn "  ollama pull <name>"
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
  local_models=$(get_local_models)

  if [[ -z "${local_models}" ]]; then
    warn "Keine lokalen Modelle gefunden — nichts zu aktualisieren."
    return
  fi

  info "Verwaiste Modell-Layer bereinigen …"
  # prune ist nicht in allen Ollama-Versionen verfügbar
  if ollama prune 2>/dev/null; then
    ok "Bereinigung abgeschlossen."
  else
    warn "ollama prune nicht verfügbar — wird übersprungen."
  fi

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
  local_models=$(get_local_models)

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
  local confirm
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

# ── 3) Deinstallation (Untermenü) ────────────────────────────────────────────
function _remove_models_only() {
  warn "Alle Modelldaten unter ~/.ollama werden DAUERHAFT gelöscht."
  warn "Eigene Modelfiles in ~/Ollama_config bleiben erhalten."
  local confirm
  read -rp "  Zur Bestätigung 'ja' eingeben: " confirm
  [[ "${confirm}" != "ja" ]] && { info "Abgebrochen."; return; }

  local restart=0
  if systemctl is-active --quiet ollama 2>/dev/null; then
    info "ollama.service kurz stoppen (Dateisperre vermeiden) …"
    sudo systemctl stop ollama
    restart=1
  fi

  rm -rf "${HOME}/.ollama"
  ok "Modelldaten unter ~/.ollama gelöscht."

  if (( restart == 1 )); then
    sudo systemctl start ollama
    ok "ollama.service wieder gestartet."
  fi
  warn "Tipp: Neue Modelle herunterladen über Option 2 → Modell herunterladen."
}

function _remove_packages_only() {
  local aur_helper
  aur_helper=$(detect_aur_helper)

  info "Installierte Ollama-Pakete ermitteln …"
  local pkgs=()
  for p in ollama ollama-rocm ollama-vulkan opencode llm-manager; do
    if pacman -Q "${p}" &>/dev/null; then pkgs+=("${p}"); fi
  done

  if (( ${#pkgs[@]} == 0 )); then
    warn "Keine passenden Pakete gefunden."
    return
  fi

  warn "Werden entfernt: ${pkgs[*]}"
  warn "Modelldaten (~/.ollama) und Configs bleiben erhalten."
  local confirm
  read -rp "  Bestätigen mit 'ja': " confirm
  [[ "${confirm}" != "ja" ]] && { info "Abgebrochen."; return; }

  _do_remove_packages "${pkgs[@]}"

  if [[ -n "${aur_helper}" ]]; then
    warn "AUR-Reste prüfen: ${aur_helper} -Rns opencode llm-manager"
  fi
}

# Interne Hilfsfunktion — entfernt Pakete ohne eigene Bestätigungsabfrage
function _do_remove_packages() {
  local pkgs=("$@")
  info "ollama.service stoppen …"
  sudo systemctl disable --now ollama 2>/dev/null || true
  sudo pacman -Rns --noconfirm "${pkgs[@]}"
  ok "Pakete entfernt: ${pkgs[*]}"
}

function _remove_configs_only() {
  local config_dir="${HOME}/Ollama_config"
  local drop_file="/etc/systemd/system/ollama.service.d/cpu-optimized.conf"
  local drop_amd="/etc/systemd/system/ollama.service.d/amd-vulkan.conf"
  local sysctl_file="/etc/sysctl.d/99-ollama-cpu.conf"
  local sysctl_amd="/etc/sysctl.d/99-ollama-amd-vulkan.conf"
  local thp_file="/etc/tmpfiles.d/ollama-thp.conf"

  echo
  info "Folgende Einträge werden entfernt (falls vorhanden):"
  echo -e "  ${C_YELLOW}  ${config_dir}${C_RESET}   (eigene Modelfiles)"
  echo -e "  ${C_YELLOW}  ${drop_file}${C_RESET}"
  echo -e "  ${C_YELLOW}  ${drop_amd}${C_RESET}"
  echo -e "  ${C_YELLOW}  ${sysctl_file}${C_RESET}"
  echo -e "  ${C_YELLOW}  ${sysctl_amd}${C_RESET}"
  echo -e "  ${C_YELLOW}  ${thp_file}${C_RESET}"
  echo
  warn "Achtung: Eigene Modelfiles in ${config_dir} gehen verloren!"
  local confirm
  read -rp "  Bestätigen mit 'ja': " confirm
  [[ "${confirm}" != "ja" ]] && { info "Abgebrochen."; return; }

  if [[ -d "${config_dir}" ]]; then
    rm -rf "${config_dir}"
    ok "${config_dir} gelöscht."
  else
    info "${config_dir} nicht vorhanden — übersprungen."
  fi

  local removed_sysctl=0
  for f in "${drop_file}" "${drop_amd}" "${sysctl_file}" "${sysctl_amd}" "${thp_file}"; do
    if [[ -f "${f}" ]]; then
      sudo rm -f "${f}"
      ok "${f} gelöscht."
      removed_sysctl=1
    else
      info "${f} nicht vorhanden — übersprungen."
    fi
  done

  if (( removed_sysctl == 1 )); then
    sudo systemctl daemon-reload
    sudo sysctl --system &>/dev/null
    ok "systemd und sysctl neu geladen."
  fi
}

function _remove_all_confirm() {
  echo
  warn "VOLLSTÄNDIGE Deinstallation:"
  warn "  - Pakete:    ollama, ollama-rocm, ollama-vulkan, opencode, llm-manager"
  warn "  - Modelle:   ~/.ollama  (DAUERHAFT)"
  warn "  - Configs:   ~/Ollama_config, systemd-Override, sysctl, tmpfiles"
  echo
  local confirm
  read -rp "  Zur Bestätigung 'ja' eingeben: " confirm
  [[ "${confirm}" != "ja" ]] && { info "Abgebrochen."; return; }

  info "Installierte Pakete ermitteln …"
  local pkgs=()
  for p in ollama ollama-rocm ollama-vulkan opencode llm-manager; do
    if pacman -Q "${p}" &>/dev/null; then pkgs+=("${p}"); fi
  done
  if (( ${#pkgs[@]} > 0 )); then
    _do_remove_packages "${pkgs[@]}"
  else
    warn "Keine passenden Pakete gefunden."
  fi
  echo
  rm -rf "${HOME}/.ollama"
  ok "Modelldaten gelöscht."
  echo
  # Config-Dateien direkt ohne erneute Abfrage entfernen
  for f in "/etc/systemd/system/ollama.service.d/cpu-optimized.conf" \
            "/etc/systemd/system/ollama.service.d/amd-vulkan.conf" \
            "/etc/sysctl.d/99-ollama-cpu.conf" \
            "/etc/sysctl.d/99-ollama-amd-vulkan.conf" \
            "/etc/tmpfiles.d/ollama-thp.conf"; do
    if [[ -f "${f}" ]]; then
      sudo rm -f "${f}"
      ok "${f} gelöscht."
    fi
  done
  if [[ -d "${HOME}/Ollama_config" ]]; then
    rm -rf "${HOME}/Ollama_config"
    ok "${HOME}/Ollama_config gelöscht."
  fi
  sudo systemctl daemon-reload 2>/dev/null || true
  ok "Deinstallation abgeschlossen."
}

function remove_menu() {
  local w sub
  while true; do
    w=$(dynamic_width)
    echo
    draw_line "${w}"
    echo -e "${C_BOLD}  Deinstallation${C_RESET}"
    draw_line "${w}"
    echo -e "  ${C_CYAN}1${C_RESET}  Nur Modelle entfernen     (~/.ollama)"
    echo -e "  ${C_CYAN}2${C_RESET}  Nur Pakete deinstallieren (ollama, opencode …)"
    echo -e "  ${C_CYAN}3${C_RESET}  Nur Configs entfernen     (Modelfiles, systemd, sysctl)"
    echo -e "  ${C_CYAN}4${C_RESET}  Alles entfernen"
    echo -e "  ${C_CYAN}z${C_RESET}  Zurück"
    draw_line "${w}"
    read -rp "  Auswahl: " sub
    case "${sub}" in
      1) ensure_sudo; _remove_models_only ;;
      2) ensure_sudo; _remove_packages_only ;;
      3) ensure_sudo; _remove_configs_only ;;
      4) ensure_sudo; _remove_all_confirm ;;
      z|Z) return ;;
      *) warn "Ungültige Eingabe." ;;
    esac
    echo
    read -rp "  Weiter mit Enter …" _
  done
}

# ── 4) CPU-only Setup + Systemoptimierung ────────────────────────────────────
function setup_cpu_only() {
  local aur_helper
  aur_helper=$(detect_aur_helper)

  echo
  warn "CPU-only Modus: Kein GPU-Backend — Ollama läuft ausschließlich auf der CPU."
  warn "Empfohlen für Systeme ohne dedizierte GPU oder bei ROCm/Vulkan-Problemen."
  warn "Modelle laufen langsamer als mit GPU — kleine Modelle (≤7B) sind realistisch."
  echo

  # ── Ollama ohne GPU-Backend installieren ────────────────────────────────
  info "Installiere ollama (CPU-only, kein rocm/vulkan) …"
  sudo pacman -S --needed --noconfirm ollama
  ok "Ollama installiert."

  local do_llm do_opencode_cpu
  read -rp "  llm-manager installieren? [j/N]: " do_llm
  read -rp "  opencode installieren?    [j/N]: " do_opencode_cpu

  if [[ -n "${aur_helper}" ]]; then
    local aur_pkgs=()
    [[ "${do_llm,,}"        == "j" ]] && aur_pkgs+=("llm-manager")
    [[ "${do_opencode_cpu,,}" == "j" ]] && aur_pkgs+=("opencode")
    if (( ${#aur_pkgs[@]} > 0 )); then
      "${aur_helper}" -S --needed --noconfirm "${aur_pkgs[@]}"
      ok "AUR-Pakete installiert: ${aur_pkgs[*]}"
    fi
  else
    warn "Kein AUR-Helper — llm-manager/opencode werden übersprungen."
  fi

  # ── Physische CPU-Kerne ermitteln ────────────────────────────────────────
  local phys_cores log_cores
  phys_cores=$(get_phys_cores)
  log_cores=$(nproc)
  info "Erkannt: ${phys_cores} physische Kerne / ${log_cores} logische Kerne."
  warn "Tipp: Ollama nutzt physische Kerne für Inferenz — HyperThreading bringt wenig."

  # ── systemd Service-Override ─────────────────────────────────────────────
  local drop_dir="/etc/systemd/system/ollama.service.d"
  local drop_file="${drop_dir}/cpu-optimized.conf"
  info "Erstelle systemd-Override: ${drop_file} …"
  sudo mkdir -p "${drop_dir}"
  if ! sudo tee "${drop_file}" > /dev/null << EOF
# Ollama CPU-only Optimierungen — generiert von ollama-setup.sh
[Service]
# Physische Kerne für Inferenz (kein HyperThreading-Overhead)
Environment="OLLAMA_NUM_THREAD=${phys_cores}"
# Flash Attention reduziert Speicherverbrauch deutlich
Environment="OLLAMA_FLASH_ATTENTION=1"
# Parallele Anfragen begrenzen (CPU hat keine dedizierte VRAM-Trennung)
Environment="OLLAMA_NUM_PARALLEL=1"
# glibc-Speicherarenen begrenzen — weniger Fragmentierung bei großen Modellen
Environment="MALLOC_ARENA_MAX=2"
# OpenMP-Threads auf physische Kerne setzen
Environment="OMP_NUM_THREADS=${phys_cores}"
# Offloading explizit deaktivieren
Environment="OLLAMA_INTEL_GPU=0"
# Erhöhtes Dateideskriptor-Limit für große Modelldateien
LimitNOFILE=65536
# Hohe CPU-Priorität für den Ollama-Prozess
CPUWeight=90
IOWeight=80
EOF
  then
    err "Fehler beim Schreiben von ${drop_file}"; return 1
  fi
  ok "systemd-Override geschrieben."

  # ── sysctl-Tuning ────────────────────────────────────────────────────────
  local sysctl_file="/etc/sysctl.d/99-ollama-cpu.conf"
  info "Schreibe sysctl-Tuning: ${sysctl_file} …"
  if ! sudo tee "${sysctl_file}" > /dev/null << 'EOF'
# Ollama CPU-Tuning — generiert von ollama-setup.sh

# Weniger Swap-Auslagerung — Modelle im RAM halten
vm.swappiness = 10

# Mehr Zeit für Dirty Pages — reduziert I/O-Stalls beim Laden großer Modelle
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5

# Weniger aggressives Leeren des Dentry/Inode-Cache
vm.vfs_cache_pressure = 50
EOF
  then
    err "Fehler beim Schreiben von ${sysctl_file}"; return 1
  fi
  if sudo sysctl -p "${sysctl_file}" &>/dev/null; then
    ok "sysctl-Parameter aktiv."
  else
    warn "sysctl -p teilweise fehlgeschlagen — Parameter manuell prüfen: ${sysctl_file}"
  fi

  # ── Transparent Hugepages ────────────────────────────────────────────────
  info "Transparent Hugepages auf 'madvise' setzen …"
  if echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null 2>&1; then
    ok "Transparent Hugepages: madvise gesetzt."
  else
    warn "THP-Pfad nicht beschreibbar — Kernel-Unterstützung prüfen."
    warn "  Manuell: echo madvise > /sys/kernel/mm/transparent_hugepage/enabled"
  fi
  # Persistent via tmpfiles.d
  if ! sudo tee /etc/tmpfiles.d/ollama-thp.conf > /dev/null << 'EOF'
# Transparent Hugepages für Ollama (große zusammenhängende Allokationen)
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
EOF
  then
    warn "tmpfiles.d-Eintrag konnte nicht geschrieben werden — THP nicht persistent."
  else
    ok "Transparent Hugepages: madvise (persistent via tmpfiles.d)."
  fi

  # ── CPU-Governor ─────────────────────────────────────────────────────────
  if command -v cpupower &>/dev/null; then
    info "CPU-Governor auf 'performance' setzen …"
    if sudo cpupower frequency-set -g performance &>/dev/null; then
      ok "CPU-Governor: performance."
    else
      warn "CPU-Governor konnte nicht gesetzt werden (Kernel-Modul fehlt?)."
    fi
    # cpupower.service für Persistenz aktivieren
    if systemctl list-unit-files cpupower.service &>/dev/null; then
      if sudo systemctl enable --now cpupower.service 2>/dev/null; then
        ok "cpupower.service aktiviert (bleibt nach Neustart aktiv)."
      else
        warn "cpupower.service konnte nicht aktiviert werden."
      fi
    fi
  else
    warn "cpupower nicht gefunden — Governor bleibt unverändert."
    warn "  Installieren mit: sudo pacman -S cpupower"
    warn "  Danach manuell:   sudo cpupower frequency-set -g performance"
  fi

  # ── Konfig-Ordner ────────────────────────────────────────────────────────
  ensure_config_dir

  # ── Service (neu) laden ───────────────────────────────────────────────────
  info "systemd neu laden und ollama.service starten …"
  sudo systemctl daemon-reload
  sudo systemctl enable --now ollama
  ok "ollama.service ist aktiv (CPU-optimiert)."

  echo
  warn "Zusammenfassung der Optimierungen:"
  warn "  OLLAMA_NUM_THREAD = ${phys_cores}  (physische Kerne)"
  warn "  FLASH_ATTENTION   = 1              (weniger RAM-Verbrauch)"
  warn "  vm.swappiness     = 10             (Modelle im RAM halten)"
  warn "  THP               = madvise        (bessere große Allokationen)"
  warn "  LimitNOFILE       = 65536          (große Modelldateien)"
  warn "Empfohlene Modelle für CPU: llama3.2:3b, qwen2.5:3b, phi3:mini, gemma2:2b"
  warn "Override-Datei anpassen:   ${drop_file}"
  warn "Logs prüfen mit:           journalctl -u ollama -f"
}

# ── 5) Modelfile-Assistent ────────────────────────────────────────────────────
function modelfile_assistant() {
  require_ollama || return
  local config_dir="${HOME}/Ollama_config"
  ensure_config_dir

  local w
  w=$(dynamic_width)
  echo
  draw_line "${w}"
  echo -e "${C_BOLD}  Modelfile-Assistent${C_RESET}"
  draw_line "${w}"
  warn "Erstellt eine Modelfile-Konfiguration in ${config_dir}/"
  warn "und baut daraus optional ein eigenes Ollama-Modell."
  echo

  # ── Basismodell wählen ────────────────────────────────────────────────────
  local base_model
  local local_models
  local_models=$(get_local_models)

  if [[ -n "${local_models}" ]]; then
    info "Basismodell aus installierten Modellen wählen oder manuell eingeben:"
    base_model=$(echo "${local_models}" \
      | fzf --prompt="  Basismodell > " \
            --header="Enter=auswählen  Esc=manuell eingeben" \
            --color="hl:cyan,hl+:cyan" \
      || true)
  fi

  if [[ -z "${base_model}" ]]; then
    read -rp "  Basismodell manuell eingeben (z.B. llama3.2:3b): " base_model
  fi

  if [[ -z "${base_model}" ]]; then
    err "Kein Basismodell angegeben — Abbruch."
    return
  fi

  # ── SYSTEM-Prompt ─────────────────────────────────────────────────────────
  echo
  info "SYSTEM-Prompt definiert das Verhalten und die Rolle des Modells."
  warn "Tipp: Kurz und präzise halten. Leer lassen für Standard-Verhalten."
  local sys_prompt
  read -rp "  SYSTEM-Prompt (Enter=leer): " sys_prompt

  # ── Temperature ───────────────────────────────────────────────────────────
  echo
  info "Temperature steuert Kreativität vs. Präzision:"
  info "  0.0 = deterministisch/präzise   1.0 = kreativ/variabel   (Standard: 0.7)"
  local temperature
  while true; do
    read -rp "  Temperature [0.0-1.0, Enter=0.7]: " temperature
    temperature="${temperature:-0.7}"
    # Prüfen ob gültige Zahl zwischen 0 und 1
    if [[ "${temperature}" =~ ^0(\.[0-9]+)?$|^1(\.0+)?$ ]]; then
      break
    else
      warn "Ungültiger Wert — bitte eine Zahl zwischen 0.0 und 1.0 eingeben."
    fi
  done

  # ── Kontextgröße ──────────────────────────────────────────────────────────
  echo
  info "num_ctx = Kontextfenster (Token). Größer = mehr RAM-Verbrauch."
  info "  Empfehlung: 2048 für schwache Hardware, 4096 Standard, 8192+ für lange Gespräche."
  warn "Tipp: Größere Modelle (>7B) verkraften kaum num_ctx > 4096 auf CPU."
  local num_ctx
  local PS3="  Auswahl: "
  select ctx_choice in "2048" "4096" "8192" "16384" "32768" "Manuell eingeben"; do
    case "${ctx_choice}" in
      "Manuell eingeben")
        read -rp "  num_ctx eingeben: " num_ctx
        [[ "${num_ctx}" =~ ^[0-9]+$ ]] || { warn "Ungültig — setze 4096."; num_ctx=4096; }
        break ;;
      "")
        warn "Ungültige Auswahl." ;;
      *)
        num_ctx="${ctx_choice}"
        break ;;
    esac
  done

  # ── Optionaler repeat_penalty ─────────────────────────────────────────────
  echo
  info "repeat_penalty verhindert Wiederholungen im Text."
  info "  1.0 = deaktiviert   1.1 = Standard   1.3 = stark"
  local repeat_penalty
  read -rp "  repeat_penalty [Enter=1.1]: " repeat_penalty
  repeat_penalty="${repeat_penalty:-1.1}"

  # ── Name des eigenen Modells ──────────────────────────────────────────────
  echo
  local model_name
  read -rp "  Name für das eigene Modell (z.B. mein-assistent): " model_name
  if [[ -z "${model_name}" ]]; then
    err "Kein Modellname angegeben — Abbruch."
    return
  fi
  # Leerzeichen und Sonderzeichen entfernen
  model_name="${model_name//[^a-zA-Z0-9_-]/}"
  if [[ -z "${model_name}" ]]; then
    err "Modellname enthält keine gültigen Zeichen (erlaubt: a-z A-Z 0-9 _ -) — Abbruch."
    return 1
  fi

  # ── Dateiname ─────────────────────────────────────────────────────────────
  local filename="${config_dir}/Modelfile.${model_name}"

  # ── Modelfile schreiben ───────────────────────────────────────────────────
  {
    echo "FROM ${base_model}"
    echo ""
    if [[ -n "${sys_prompt}" ]]; then
      echo "SYSTEM \"${sys_prompt}\""
      echo ""
    fi
    echo "PARAMETER temperature ${temperature}"
    echo "PARAMETER num_ctx ${num_ctx}"
    echo "PARAMETER repeat_penalty ${repeat_penalty}"
  } > "${filename}"

  ok "Modelfile geschrieben: ${filename}"
  echo
  echo -e "${C_BOLD}── Inhalt ──${C_RESET}"
  cat "${filename}"
  echo -e "${C_BOLD}────────────${C_RESET}"

  # ── ollama create ─────────────────────────────────────────────────────────
  echo
  local do_create
  read -rp "  Modell jetzt bauen? (ollama create ${model_name}) [j/N]: " do_create
  if [[ "${do_create,,}" == "j" ]]; then
    info "Baue Modell '${model_name}' …"
    if ollama create "${model_name}" -f "${filename}"; then
      ok "Modell '${model_name}' erfolgreich erstellt."
      warn "Starten mit: ollama run ${model_name}"
    else
      err "ollama create fehlgeschlagen — Modelfile prüfen: ${filename}"
    fi
  else
    warn "Manuell bauen mit:"
    warn "  ollama create ${model_name} -f ${filename}"
  fi
}

# ── 6) Opencode nachinstallieren ──────────────────────────────────────────────
function install_opencode() {
  local aur_helper
  aur_helper=$(detect_aur_helper)

  echo
  if [[ -z "${aur_helper}" ]]; then
    warn_no_aur
    return
  fi

  if pacman -Q opencode &>/dev/null; then
    ok "opencode ist bereits installiert."
    warn "Aktualisieren mit: ${aur_helper} -Su opencode"
    return
  fi

  warn "opencode ist ein KI-gestützter Code-Editor mit Ollama-Backend."
  warn "Voraussetzung: Ollama muss installiert und aktiv sein (Option 1 oder 4)."
  if ! command -v ollama &>/dev/null; then
    warn "Ollama nicht gefunden — opencode wird trotzdem installiert,"
    warn "benötigt aber Ollama zur Laufzeit."
  fi
  echo
  local confirm
  read -rp "  opencode jetzt installieren? [j/N]: " confirm
  [[ "${confirm,,}" != "j" ]] && { info "Abgebrochen."; return; }

  "${aur_helper}" -S --needed --noconfirm opencode
  ok "opencode installiert."
  warn "Tipp: opencode im Terminal starten mit: opencode"
  warn "      Ollama-Endpunkt wird automatisch auf http://localhost:11434 gesetzt."
}

# ── 7) AMD Ryzen + Vulkan Setup ───────────────────────────────────────────────
function setup_amd_vulkan() {
  local aur_helper
  aur_helper=$(detect_aur_helper)

  local w
  w=$(dynamic_width)

  # ── Hardware-Erkennung ───────────────────────────────────────────────────
  local gpu_info apu_hint=""
  gpu_info=$(lspci 2>/dev/null | grep -i 'vga\|3d\|display\|amdgpu' | grep -i 'amd\|radeon' || true)
  # APU-Erkennung: Ryzen-iGPU hat keinen eigenen PCI-Bus-Slot wie dGPU
  if echo "${gpu_info}" | grep -qi 'renoir\|cezanne\|rembrandt\|phoenix\|hawk\|picasso\|raven'; then
    apu_hint="  APU erkannt (geteilter RAM als VRAM) — num_ctx und Modellgröße begrenzen!"
  fi

  # ── Optionen abfragen ────────────────────────────────────────────────────
  echo
  draw_line "${w}"
  echo -e "${C_BOLD}  AMD Ryzen + Vulkan Setup${C_RESET}"
  draw_line "${w}"
  echo

  if [[ -n "${gpu_info}" ]]; then
    ok "AMD GPU erkannt: ${gpu_info}"
  else
    warn "Keine AMD GPU per lspci gefunden — Setup trotzdem möglich."
    warn "Vulkan funktioniert auch ohne vorherige GPU-Erkennung."
  fi
  [[ -n "${apu_hint}" ]] && warn "${apu_hint}"
  echo

  local do_opencode_amd
  read -rp "  opencode ebenfalls installieren? [j/N]: " do_opencode_amd

  # ── Physische CPU-Kerne ermitteln ────────────────────────────────────────
  local phys_cores log_cores
  phys_cores=$(get_phys_cores)
  log_cores=$(nproc)

  # ── Summary aufbauen ─────────────────────────────────────────────────────
  local aur_pkgs=("llm-manager")
  [[ "${do_opencode_amd,,}" == "j" ]] && aur_pkgs+=("opencode")

  local drop_dir="/etc/systemd/system/ollama.service.d"
  local drop_file="${drop_dir}/amd-vulkan.conf"
  local sysctl_file="/etc/sysctl.d/99-ollama-amd-vulkan.conf"
  local thp_conf="/etc/tmpfiles.d/ollama-thp.conf"
  local config_dir="${HOME}/Ollama_config"

  echo
  draw_line "${w}"
  echo -e "${C_BOLD}  Installations-Übersicht${C_RESET}"
  draw_line "${w}"
  echo
  echo -e "${C_BOLD}  Pakete (pacman):${C_RESET}"
  echo -e "  ${C_GREEN}+${C_RESET} ollama"
  echo -e "  ${C_GREEN}+${C_RESET} ollama-vulkan          (Vulkan-Backend)"
  echo -e "  ${C_GREEN}+${C_RESET} vulkan-radeon          (Mesa RADV — AMD Vulkan-Treiber)"
  echo -e "  ${C_GREEN}+${C_RESET} vulkan-icd-loader      (Vulkan ICD-Verwaltung)"
  echo
  echo -e "${C_BOLD}  AUR-Pakete ($( [[ -n "${aur_helper}" ]] && echo "${aur_helper}" || echo "kein Helper!") ):${C_RESET}"
  for p in "${aur_pkgs[@]}"; do
    echo -e "  ${C_GREEN}+${C_RESET} ${p}"
  done
  echo
  echo -e "${C_BOLD}  Systemdateien:${C_RESET}"
  echo -e "  ${C_GREEN}+${C_RESET} ${drop_file}"
  echo -e "        OLLAMA_FLASH_ATTENTION=1, AMD_VULKAN_ICD=RADV"
  echo -e "        RADV_PERFTEST=gpl, OLLAMA_NUM_PARALLEL=1"
  echo -e "        OLLAMA_NUM_THREAD=${phys_cores}, LimitNOFILE=65536"
  echo -e "  ${C_GREEN}+${C_RESET} ${sysctl_file}"
  echo -e "        vm.swappiness=10, vm.dirty_ratio=20"
  echo -e "  ${C_GREEN}+${C_RESET} ${thp_conf}"
  echo -e "        Transparent Hugepages → madvise"
  echo -e "  ${C_GREEN}+${C_RESET} ${config_dir}/  (Modelfile-Verzeichnis)"
  echo
  echo -e "${C_BOLD}  Dienste:${C_RESET}"
  echo -e "  ${C_GREEN}+${C_RESET} ollama.service  enable + start"
  echo
  if [[ -z "${aur_helper}" ]]; then
    warn "ACHTUNG: Kein AUR-Helper — AUR-Pakete werden übersprungen!"
    warn "  yay installieren: git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si"
  fi
  warn "HINWEIS: vulkan-radeon/vulkan-icd-loader werden NICHT bei Deinstallation"
  warn "         entfernt — sie werden ggf. vom Desktop-System benötigt."
  echo
  draw_line "${w}"
  local confirm
  read -rp "  Installation starten? [j/N]: " confirm
  [[ "${confirm,,}" != "j" ]] && { info "Abgebrochen."; return; }

  # ── Pakete installieren ───────────────────────────────────────────────────
  echo
  info "Installiere Basis-Pakete …"
  sudo pacman -S --needed --noconfirm ollama ollama-vulkan vulkan-radeon vulkan-icd-loader
  ok "Pakete installiert."

  if [[ -n "${aur_helper}" ]]; then
    info "Installiere AUR-Pakete: ${aur_pkgs[*]} …"
    "${aur_helper}" -S --needed --noconfirm "${aur_pkgs[@]}"
    ok "AUR-Pakete installiert: ${aur_pkgs[*]}"
  else
    warn "AUR-Pakete übersprungen (kein yay/paru)."
  fi

  # ── Vulkan-Treiber verifizieren ───────────────────────────────────────────
  info "Vulkan-Geräteerkennung prüfen …"
  if command -v vulkaninfo &>/dev/null; then
    if vulkaninfo --summary 2>/dev/null | grep -qi 'radv\|amd'; then
      ok "RADV/AMD Vulkan-Treiber wird erkannt."
    else
      warn "AMD-Gerät in vulkaninfo nicht gefunden — nach Neustart erneut prüfen."
      warn "  Manuell: vulkaninfo --summary"
    fi
  else
    warn "vulkaninfo nicht verfügbar — Erkennung übersprungen."
    warn "  Installieren mit: sudo pacman -S vulkan-tools"
  fi

  # ── systemd-Override schreiben ────────────────────────────────────────────
  info "Erstelle systemd-Override: ${drop_file} …"
  sudo mkdir -p "${drop_dir}"
  if ! sudo tee "${drop_file}" > /dev/null << EOF
# Ollama AMD Ryzen + Vulkan Optimierungen — generiert von ollama-setup.sh
[Service]
# Mesa RADV erzwingen (besser als AMDVLK für Compute/Inferenz)
Environment="AMD_VULKAN_ICD=RADV"
# General Pipeline Libraries — schnellere Shader-Kompilierung
Environment="RADV_PERFTEST=gpl"
# Flash Attention reduziert VRAM-Verbrauch — wichtig für APUs mit geteiltem RAM
Environment="OLLAMA_FLASH_ATTENTION=1"
# Parallele Anfragen begrenzen (Ryzen-iGPU hat limitierten geteilten VRAM)
Environment="OLLAMA_NUM_PARALLEL=1"
# CPU-Threads für Host-Verarbeitung neben GPU-Inferenz
Environment="OLLAMA_NUM_THREAD=${phys_cores}"
# glibc-Arenen begrenzen
Environment="MALLOC_ARENA_MAX=2"
# Dateideskriptor-Limit für große Modelldateien
LimitNOFILE=65536
CPUWeight=80
IOWeight=80
EOF
  then
    err "Fehler beim Schreiben von ${drop_file}"; return 1
  fi
  ok "systemd-Override geschrieben."

  # ── sysctl-Tuning ─────────────────────────────────────────────────────────
  info "Schreibe sysctl-Tuning: ${sysctl_file} …"
  if ! sudo tee "${sysctl_file}" > /dev/null << 'EOF'
# Ollama AMD Ryzen Vulkan Tuning — generiert von ollama-setup.sh

# Modelle im RAM halten (besonders wichtig bei APU mit geteiltem VRAM)
vm.swappiness = 10

# Dirty-Page-Tuning — reduziert I/O-Stalls beim Laden großer Modelle
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5

# Weniger aggressives Cache-Leeren
vm.vfs_cache_pressure = 50
EOF
  then
    err "Fehler beim Schreiben von ${sysctl_file}"; return 1
  fi
  if sudo sysctl -p "${sysctl_file}" &>/dev/null; then
    ok "sysctl-Parameter aktiv."
  else
    warn "sysctl -p teilweise fehlgeschlagen — Parameter prüfen: ${sysctl_file}"
  fi

  # ── Transparent Hugepages ─────────────────────────────────────────────────
  info "Transparent Hugepages auf 'madvise' setzen …"
  if echo madvise | sudo tee /sys/kernel/mm/transparent_hugepage/enabled > /dev/null 2>&1; then
    ok "Transparent Hugepages: madvise gesetzt."
  else
    warn "THP-Pfad nicht beschreibbar — nach Neustart erneut prüfen."
  fi
  if ! sudo tee "${thp_conf}" > /dev/null << 'EOF'
# Transparent Hugepages für Ollama (persistent via tmpfiles.d)
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
EOF
  then
    warn "tmpfiles.d-Eintrag konnte nicht geschrieben werden — THP nicht persistent."
  fi

  # ── Konfig-Ordner ─────────────────────────────────────────────────────────
  ensure_config_dir

  # ── Service starten ───────────────────────────────────────────────────────
  info "systemd neu laden und ollama.service starten …"
  sudo systemctl daemon-reload
  sudo systemctl enable --now ollama
  ok "ollama.service ist aktiv (AMD Vulkan-optimiert)."

  # ── Abschluss-Summary ─────────────────────────────────────────────────────
  echo
  draw_line "${w}"
  echo -e "${C_BOLD}  Abschluss-Übersicht${C_RESET}"
  draw_line "${w}"
  warn "  AMD_VULKAN_ICD    = RADV     (Mesa RADV erzwungen)"
  warn "  RADV_PERFTEST     = gpl      (schnellere Pipeline-Kompilierung)"
  warn "  FLASH_ATTENTION   = 1        (weniger VRAM-Verbrauch)"
  warn "  OLLAMA_NUM_THREAD = ${phys_cores}        (physische CPU-Kerne)"
  warn "  vm.swappiness     = 10       (Modelle im RAM halten)"
  warn "  THP               = madvise  (bessere große Allokationen)"
  echo
  warn "Empfohlene Modelle:"
  warn "  APU / wenig VRAM (<8 GB):  llama3.2:3b, qwen2.5:3b, phi3:mini"
  warn "  dGPU (8–16 GB VRAM):       llama3.1:8b, mistral:7b, gemma2:9b"
  warn "  dGPU (>16 GB VRAM):        llama3.1:70b (quantisiert), qwen2.5:32b"
  echo
  warn "Vulkan-Backend prüfen:   vulkaninfo --summary"
  warn "Logs prüfen:             journalctl -u ollama -f"
  warn "Override anpassen:       ${drop_file}"
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
        ensure_sudo
        setup_amd_vulkan
        ;;
      3)
        ensure_sudo
        setup_cpu_only
        ;;
      4)
        model_menu
        continue
        ;;
      5)
        modelfile_assistant
        ;;
      6)
        install_opencode
        ;;
      7)
        remove_menu
        continue
        ;;
      q|Q)
        info "Auf Wiedersehen."
        exit 0
        ;;
      *)
        warn "Ungültige Eingabe — bitte 1–7 oder q eingeben."
        ;;
    esac
    echo
    read -rp "  Weiter mit Enter …" _
  done
}

main "$@"
