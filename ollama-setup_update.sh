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
    printf '%s' "${C_GREEN}aktiv${C_RESET}"
  else
    printf '%s' "${C_YELLOW}gestoppt${C_RESET}"
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
  echo -e "  ${C_CYAN}1${C_RESET}  Ollama + llm-manager installieren (GPU)"
  echo -e "  ${C_CYAN}2${C_RESET}  KI-Modelle verwalten"
  echo -e "  ${C_CYAN}3${C_RESET}  Deinstallation"
  echo -e "  ${C_CYAN}4${C_RESET}  CPU-only Setup + Systemoptimierung"
  echo -e "  ${C_CYAN}5${C_RESET}  Modelfile-Assistent"
  echo -e "  ${C_CYAN}6${C_RESET}  Opencode nachinstallieren"
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

  # opencode optional — llm-manager immer
  info "Installiere AUR-Paket: llm-manager …"
  read -rp "  opencode ebenfalls installieren? (KI-gestützter Code-Editor) [j/N]: " do_opencode
  local aur_pkgs=("llm-manager")
  [[ "${do_opencode,,}" == "j" ]] && aur_pkgs+=("opencode")

  if [[ -z "${aur_helper}" ]]; then
    err "Kein AUR-Helper gefunden (yay oder paru wird benötigt)."
    warn "yay zuerst installieren, dann Option 1 erneut ausführen:"
    warn "  git clone https://aur.archlinux.org/yay.git"
    warn "  cd yay && makepkg -si"
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

# ── 3) Deinstallation (Untermenü) ────────────────────────────────────────────
function _remove_models_only() {
  warn "Alle Modelldaten unter ~/.ollama werden DAUERHAFT gelöscht."
  warn "Eigene Modelfiles in ~/Ollama_config bleiben erhalten."
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
  local sysctl_file="/etc/sysctl.d/99-ollama-cpu.conf"
  local thp_file="/etc/tmpfiles.d/ollama-thp.conf"

  echo
  info "Folgende Einträge werden entfernt (falls vorhanden):"
  echo -e "  ${C_YELLOW}  ${config_dir}${C_RESET}   (eigene Modelfiles)"
  echo -e "  ${C_YELLOW}  ${drop_file}${C_RESET}"
  echo -e "  ${C_YELLOW}  ${sysctl_file}${C_RESET}"
  echo -e "  ${C_YELLOW}  ${thp_file}${C_RESET}"
  echo
  warn "Achtung: Eigene Modelfiles in ${config_dir} gehen verloren!"
  read -rp "  Bestätigen mit 'ja': " confirm
  [[ "${confirm}" != "ja" ]] && { info "Abgebrochen."; return; }

  if [[ -d "${config_dir}" ]]; then
    rm -rf "${config_dir}"
    ok "${config_dir} gelöscht."
  else
    info "${config_dir} nicht vorhanden — übersprungen."
  fi

  local removed_sysctl=0
  for f in "${drop_file}" "${sysctl_file}" "${thp_file}"; do
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
            "/etc/sysctl.d/99-ollama-cpu.conf" \
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
  phys_cores=$(LANG=C lscpu | awk '/^Core\(s\) per socket:/{c=$NF} /^Socket\(s\):/{s=$NF} END{print c*s}')
  log_cores=$(nproc)
  # Fallback falls lscpu-Parsing fehlschlägt
  [[ -z "${phys_cores}" || "${phys_cores}" == "0" ]] && phys_cores="${log_cores}"
  info "Erkannt: ${phys_cores} physische Kerne / ${log_cores} logische Kerne."
  warn "Tipp: Ollama nutzt physische Kerne für Inferenz — HyperThreading bringt wenig."

  # ── systemd Service-Override ─────────────────────────────────────────────
  local drop_dir="/etc/systemd/system/ollama.service.d"
  local drop_file="${drop_dir}/cpu-optimized.conf"
  info "Erstelle systemd-Override: ${drop_file} …"
  sudo mkdir -p "${drop_dir}"
  sudo tee "${drop_file}" > /dev/null << EOF
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
  ok "systemd-Override geschrieben."

  # ── sysctl-Tuning ────────────────────────────────────────────────────────
  local sysctl_file="/etc/sysctl.d/99-ollama-cpu.conf"
  info "Schreibe sysctl-Tuning: ${sysctl_file} …"
  sudo tee "${sysctl_file}" > /dev/null << 'EOF'
# Ollama CPU-Tuning — generiert von ollama-setup.sh

# Weniger Swap-Auslagerung — Modelle im RAM halten
vm.swappiness = 10

# Mehr Zeit für Dirty Pages — reduziert I/O-Stalls beim Laden großer Modelle
vm.dirty_ratio = 20
vm.dirty_background_ratio = 5

# Weniger aggressives Leeren des Dentry/Inode-Cache
vm.vfs_cache_pressure = 50
EOF
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
  sudo tee /etc/tmpfiles.d/ollama-thp.conf > /dev/null << 'EOF'
# Transparent Hugepages für Ollama (große zusammenhängende Allokationen)
w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise
EOF
  ok "Transparent Hugepages: madvise (persistent via tmpfiles.d)."

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
  local config_dir="${HOME}/Ollama_config"
  if [[ ! -d "${config_dir}" ]]; then
    mkdir -p "${config_dir}"
    ok "Konfigurationsordner erstellt: ${config_dir}"
  fi

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
  mkdir -p "${config_dir}"

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
  local_models=$(ollama list 2>/dev/null | awk 'NR>1 && $1!="" {print $1}' || true)

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
    err "Kein AUR-Helper gefunden (yay oder paru wird benötigt)."
    warn "yay installieren:"
    warn "  git clone https://aur.archlinux.org/yay.git"
    warn "  cd yay && makepkg -si"
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
  read -rp "  opencode jetzt installieren? [j/N]: " confirm
  [[ "${confirm,,}" != "j" ]] && { info "Abgebrochen."; return; }

  "${aur_helper}" -S --needed --noconfirm opencode
  ok "opencode installiert."
  warn "Tipp: opencode im Terminal starten mit: opencode"
  warn "      Ollama-Endpunkt wird automatisch auf http://localhost:11434 gesetzt."
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
        remove_menu
        continue
        ;;
      4)
        ensure_sudo
        setup_cpu_only
        ;;
      5)
        modelfile_assistant
        ;;
      6)
        ensure_sudo
        install_opencode
        ;;
      q|Q)
        info "Auf Wiedersehen."
        exit 0
        ;;
      *)
        warn "Ungültige Eingabe — bitte 1–6 oder q eingeben."
        ;;
    esac
    echo
    read -rp "  Weiter mit Enter …" _
  done
}

main "$@"
