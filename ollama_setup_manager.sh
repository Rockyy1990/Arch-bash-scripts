#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
trap 'echo "ERROR in ${FUNCNAME[0]:-main}:${LINENO}" >&2' ERR

# ── Colors & Styling ──────────────────────────────────────────────────────────
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_RED='\033[0;31m'
readonly C_CYAN='\033[0;36m'
readonly C_BOLD='\033[1m'
readonly C_RESET='\033[0m'

# Systemd override drop-in directory for Ollama service configuration
readonly SYSTEMD_DROP_DIR="/etc/systemd/system/ollama.service.d"

# Logger helpers with semantic colors
ok()   { echo -e "${C_GREEN}  [OK] ${*}${C_RESET}"; }
warn() { echo -e "${C_YELLOW}  [!!] ${*}${C_RESET}" >&2; }
err()  { echo -e "${C_RED}  [EE] ${*}${C_RESET}" >&2; }
info() { echo -e "${C_CYAN}  [..] ${*}${C_RESET}"; }

# ── Sudo & Authentication Wrapper ─────────────────────────────────────────────

# Ensures root privileges via interactive sudo prompt if not already authenticated
ensure_sudo() {
    if [[ $EUID -eq 0 ]]; then
        return 0
    fi
    # Check if we already have cached sudo credentials
    if ! command sudo -n true 2>/dev/null; then
        info "Bitte Root-Passwort eingeben (sudo):"
        command sudo -v || { err "Sudo-Authentifizierung fehlgeschlagen."; exit 1; }
    fi
}

# Safely writes system configurations to files using interactive sudo blocks
write_sys_file() {
    local target_path="${1}"
    local content="${2}"
    ensure_sudo
    printf '%b' "${content}" | command sudo tee "${target_path}" >/dev/null
    command sudo chmod 644 "${target_path}"
}

# ── Dependency Checks ─────────────────────────────────────────────────────────
check_deps() {
    local missing=0
    for cmd in pacman curl fzf; do
        if ! command -v "${cmd}" &>/dev/null; then
            err "${cmd} not found — please install manually: sudo pacman -S ${cmd}"
            (( missing++ )) || true
        fi
    done
    (( missing == 0 )) || exit 1
}

# ── UI Layout ─────────────────────────────────────────────────────────────────
dynamic_width() {
    local w
    w=$(tput cols 2>/dev/null || echo 70)
    (( w > 100 )) && w=100
    (( w < 52  )) && w=52
    echo "${w}"
}

draw_line() {
    local width="${1:-60}"
    local line
    printf -v line "%${width}s" ""
    echo "${line// /─}"
}

# ── Helpers ───────────────────────────────────────────────────────────────────
require_ollama() {
    command -v ollama &>/dev/null || {
        err "Ollama is not installed — please run installation options 1-4 first."
        return 1
    }
}

detect_aur_helper() {
    if command -v yay &>/dev/null; then
        echo "yay"
    elif command -v paru &>/dev/null; then
        echo "paru"
    fi
}

service_status() {
    if systemctl is-active --quiet ollama 2>/dev/null; then
        printf '%s' "${C_GREEN}aktiv${C_RESET}"
    else
        printf '%s' "${C_YELLOW}gestoppt${C_RESET}"
    fi
}

# Computes physical CPU cores lazily to optimize thread-affinity binding
get_phys_cores() {
    local cores=0
    if command -v lscpu &>/dev/null; then
        cores=$(lscpu -p=CORE 2>/dev/null | grep -v '^#' | sort -u | wc -l || echo 0)
    fi
    if [[ -z "${cores}" ]] || (( cores == 0 )); then
        cores=$(nproc 2>/dev/null || echo 1)
    fi
    echo "${cores}"
}

get_local_models() {
    ollama list 2>/dev/null | awk 'NR>1 && $1!="" {print $1}' || true
}

ensure_config_dir() {
    local config_dir="${HOME}/Ollama_config"
    if [[ ! -d "${config_dir}" ]]; then
        mkdir -p "${config_dir}"
        ok "Konfigurationsordner erstellt: ${config_dir}"
    fi

    if [[ ! -f "${config_dir}/README.txt" ]]; then
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
EOF
    fi
}

warn_no_aur() {
    err "Kein AUR-Helper gefunden (yay oder paru wird benötigt)."
    err "yay installieren:"
    err "  git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si"
}

prompt_aur_additions() {
    local aur_helper
    aur_helper=$(detect_aur_helper)

    if [[ -z "${aur_helper}" ]]; then
        warn_no_aur
        warn "Zusatztools (llm-manager, opencode) werden übersprungen."
        return
    fi

    local do_llm do_opencode
    read -rp "  llm-manager installieren (Web-UI)? [j/N]: " do_llm
    read -rp "  opencode installieren (KI Code-Editor)? [j/N]: " do_opencode

    local aur_pkgs=()
    [[ "${do_llm,,}" == "j" ]] && aur_pkgs+=("llm-manager")
    [[ "${do_opencode,,}" == "j" ]] && aur_pkgs+=("opencode")

    if (( ${#aur_pkgs[@]} > 0 )); then
        info "Installiere AUR-Pakete: ${aur_pkgs[*]} …"
        "${aur_helper}" -S --needed --noconfirm "${aur_pkgs[@]}"
        ok "AUR-Pakete installiert."
    fi
}

# Detects consumer AMD GPUs that require HSA_OVERRIDE_GFX_VERSION for native ROCm support
detect_amd_gfx_override() {
    local gpu_info
    gpu_info=$(lspci -nn 2>/dev/null | grep -i "VGA\|Display" | grep -i "AMD" || echo "")
    if [[ -n "${gpu_info}" ]]; then
        # Check for RDNA 2 consumer series (Navi 21-24 / RX 6000)
        if echo "${gpu_info}" | grep -qiE "Navi 2[1-4]|Radeon RX 6[6-9]00"; then
            echo "HSA_OVERRIDE_GFX_VERSION=10.3.0"
        # Check for RDNA 3 consumer series (Navi 31-33 / RX 7000)
        elif echo "${gpu_info}" | grep -qiE "Navi 3[1-3]|Radeon RX 7[6-9]00"; then
            echo "HSA_OVERRIDE_GFX_VERSION=11.0.0"
        fi
    fi
    return 0
}

# ── Menus ─────────────────────────────────────────────────────────────────────
show_menu() {
    local w
    w=$(dynamic_width)
    clear
    draw_line "${w}"
    echo -e "${C_BOLD}  Ollama Manager & Optimizer  //  Arch Linux${C_RESET}   [ollama: $(service_status)]"
    draw_line "${w}"
    echo -e "  ${C_BOLD}── Installation & Setup ──────────────────────${C_RESET}"
    echo -e "  ${C_CYAN}1${C_RESET}  NVIDIA CUDA Setup       (Maximale Performance)"
    echo -e "  ${C_CYAN}2${C_RESET}  AMD ROCm Setup          (Dedizierte AMD GPUs)"
    echo -e "  ${C_CYAN}3${C_RESET}  AMD Vulkan Setup        (Ryzen APUs / iGPUs)"
    echo -e "  ${C_CYAN}4${C_RESET}  CPU-only Setup          (Ohne Grafikkarte)"
    echo -e "  ${C_BOLD}── Tuning & Überwachung ──────────────────────${C_RESET}"
    echo -e "  ${C_CYAN}5${C_RESET}  Globale Performance-Einstellungen ${C_YELLOW}[WICHTIG]${C_RESET}"
    echo -e "  ${C_CYAN}s${C_RESET}  System-Status & GPU Logs"
    echo -e "  ${C_BOLD}── Modelle & Werkzeuge ───────────────────────${C_RESET}"
    echo -e "  ${C_CYAN}6${C_RESET}  KI-Modelle verwalten    (Download / Update)"
    echo -e "  ${C_CYAN}7${C_RESET}  Modelfile-Assistent"
    echo -e "  ${C_CYAN}8${C_RESET}  Opencode nachinstallieren"
    echo -e "  ${C_BOLD}── System ────────────────────────────────────${C_RESET}"
    echo -e "  ${C_CYAN}0${C_RESET}  Deinstallation"
    echo -e "  ${C_CYAN}q${C_RESET}  Beenden"
    draw_line "${w}"
}

# ── 1) NVIDIA CUDA Setup ──────────────────────────────────────────────────────
setup_nvidia_cuda() {
    ensure_sudo
    if ! lspci -d 10de: &>/dev/null; then
        warn "Keine NVIDIA GPU über lspci gefunden — Setup wird dennoch fortgesetzt."
    fi

    info "Installiere Basis-Pakete (ollama, nvidia-utils) …"
    command sudo pacman -S --needed --noconfirm ollama nvidia-utils

    prompt_aur_additions

    local drop_file="${SYSTEMD_DROP_DIR}/nvidia-cuda.conf"
    command sudo mkdir -p "${SYSTEMD_DROP_DIR}"
    local content="[Service]\nEnvironment=\"OLLAMA_FLASH_ATTENTION=1\"\nLimitNOFILE=65536\nNice=-10\nCPUWeight=90\nIOWeight=80\n"
    write_sys_file "${drop_file}" "${content}"
    ok "NVIDIA systemd-Override geschrieben."

    ensure_config_dir
    command sudo systemctl daemon-reload
    command sudo systemctl enable --now ollama
    ok "ollama.service ist aktiv (NVIDIA CUDA-optimiert)."
}

# ── 2) AMD ROCm Setup ─────────────────────────────────────────────────────────
setup_amd_rocm() {
    ensure_sudo
    if ! lspci -d 1002: &>/dev/null; then
        warn "Keine AMD GPU gefunden — Setup wird dennoch fortgesetzt."
    fi

    info "Installiere Basis-Pakete (ollama, ollama-rocm) …"
    command sudo pacman -S --needed --noconfirm ollama ollama-rocm

    prompt_aur_additions

    info "Füge Benutzer zu render/video Gruppen hinzu …"
    command sudo usermod -aG render,video "${USER}"

    # Auto-detect and configure GFX override variables to prevent fallback to CPU on consumer cards
    local override_env=""
    local detected_override
    detected_override=$(detect_amd_gfx_override)
    if [[ -n "${detected_override}" ]]; then
        info "AMD GPU-Architektur erkannt. Setze: ${detected_override}"
        override_env="Environment=\"${detected_override}\"\n"
    fi

    local drop_file="${SYSTEMD_DROP_DIR}/amd-rocm.conf"
    command sudo mkdir -p "${SYSTEMD_DROP_DIR}"
    local content="[Service]\n${override_env}Environment=\"OLLAMA_FLASH_ATTENTION=1\"\nLimitNOFILE=65536\nNice=-10\nCPUWeight=90\nIOWeight=80\n"
    write_sys_file "${drop_file}" "${content}"
    ok "AMD ROCm systemd-Override geschrieben."

    ensure_config_dir
    command sudo systemctl daemon-reload
    command sudo systemctl enable --now ollama
    ok "ollama.service ist aktiv (AMD ROCm-optimiert)."
    warn "WICHTIG: Bitte den PC neu starten, damit die Gruppenrechte aktiv werden!"
}

# ── 3) AMD Vulkan Setup ───────────────────────────────────────────────────────
setup_amd_vulkan() {
    ensure_sudo
    local phys_cores
    phys_cores=$(get_phys_cores)

    info "Installiere Vulkan Basis-Pakete …"
    command sudo pacman -S --needed --noconfirm ollama ollama-vulkan vulkan-radeon vulkan-icd-loader

    prompt_aur_additions

    local drop_file="${SYSTEMD_DROP_DIR}/amd-vulkan.conf"
    command sudo mkdir -p "${SYSTEMD_DROP_DIR}"
    local content="[Service]\nEnvironment=\"AMD_VULKAN_ICD=RADV\"\nEnvironment=\"RADV_PERFTEST=gpl\"\nEnvironment=\"OLLAMA_FLASH_ATTENTION=1\"\nEnvironment=\"OLLAMA_NUM_PARALLEL=1\"\nEnvironment=\"OLLAMA_NUM_THREAD=${phys_cores}\"\nEnvironment=\"MALLOC_ARENA_MAX=2\"\nLimitNOFILE=65536\nNice=-10\nCPUWeight=80\nIOWeight=80\n"
    write_sys_file "${drop_file}" "${content}"

    local sysctl_file="/etc/sysctl.d/99-ollama-amd-vulkan.conf"
    local content_sysctl="vm.swappiness = 10\nvm.dirty_ratio = 20\nvm.dirty_background_ratio = 5\nvm.vfs_cache_pressure = 50\n"
    write_sys_file "${sysctl_file}" "${content_sysctl}"
    command sudo sysctl -p "${sysctl_file}" &>/dev/null || true

    command sudo bash -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null' || true
    write_sys_file "/etc/tmpfiles.d/ollama-thp.conf" "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise\n"

    ensure_config_dir
    command sudo systemctl daemon-reload
    command sudo systemctl enable --now ollama
    ok "ollama.service ist aktiv (AMD Vulkan-optimiert)."
}

# ── 4) CPU-Only Setup ─────────────────────────────────────────────────────────
setup_cpu_only() {
    ensure_sudo
    warn "CPU-only Modus ist signifikant langsamer als GPU-Beschleunigung."
    info "Installiere ollama (CPU-only) …"
    command sudo pacman -S --needed --noconfirm ollama

    prompt_aur_additions

    local phys_cores
    phys_cores=$(get_phys_cores)
    info "Erkannt: ${phys_cores} physische Kerne."

    local drop_file="${SYSTEMD_DROP_DIR}/cpu-optimized.conf"
    command sudo mkdir -p "${SYSTEMD_DROP_DIR}"
    local content="[Service]\nEnvironment=\"OLLAMA_NUM_THREAD=${phys_cores}\"\nEnvironment=\"OLLAMA_FLASH_ATTENTION=1\"\nEnvironment=\"OLLAMA_NUM_PARALLEL=1\"\nEnvironment=\"MALLOC_ARENA_MAX=2\"\nEnvironment=\"OMP_NUM_THREADS=${phys_cores}\"\nEnvironment=\"OLLAMA_INTEL_GPU=0\"\nLimitNOFILE=65536\nNice=-10\nCPUWeight=90\nIOWeight=80\n"
    write_sys_file "${drop_file}" "${content}"

    local sysctl_file="/etc/sysctl.d/99-ollama-cpu.conf"
    local content_sysctl="vm.swappiness = 10\nvm.dirty_ratio = 20\nvm.dirty_background_ratio = 5\nvm.vfs_cache_pressure = 50\n"
    write_sys_file "${sysctl_file}" "${content_sysctl}"
    command sudo sysctl -p "${sysctl_file}" &>/dev/null || true

    command sudo bash -c 'echo madvise > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null' || true
    write_sys_file "/etc/tmpfiles.d/ollama-thp.conf" "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise\n"

    if command -v cpupower &>/dev/null; then
        command sudo cpupower frequency-set -g performance &>/dev/null || true
        command sudo systemctl enable --now cpupower.service 2>/dev/null || true
    fi

    ensure_config_dir
    command sudo systemctl daemon-reload
    command sudo systemctl enable --now ollama
    ok "ollama.service ist aktiv (CPU-optimiert)."
}

# ── 5) Global Performance Tuning ──────────────────────────────────────────────
global_performance_tuning() {
    require_ollama || return
    local w
    w=$(dynamic_width)
    echo
    draw_line "${w}"
    echo -e "${C_BOLD}  Globale Performance-Einstellungen${C_RESET}"
    draw_line "${w}"
    warn "Diese Einstellungen betreffen Ollama netzwerkweit und für alle Modelle."

    echo -e "  ${C_CYAN}OLLAMA_KEEP_ALIVE${C_RESET}: Dauer, wie lange das Modell im RAM/VRAM verbleibt."
    echo -e "  Tipp: '-1' hält das Modell dauerhaft geladen (Ladezeit=0s)."
    local keep_alive
    read -rp "  Wert eingeben [z.B. 24h, 30m, -1 | Enter = -1]: " keep_alive
    keep_alive="${keep_alive:--1}"

    echo
    echo -e "  ${C_CYAN}OLLAMA_KV_CACHE_TYPE${C_RESET}: Quantisierung des Kontext-Speichers."
    echo -e "  Tipp: 'q8_0' spart ca. 40% VRAM beim Kontextfenster bei kaum Qualitätsverlust."
    local kv_cache
    read -rp "  Wert eingeben [q8_0, q4_0, f16 | Enter = q8_0]: " kv_cache
    kv_cache="${kv_cache:-q8_0}"

    echo
    echo -e "  ${C_CYAN}OLLAMA_NUM_PARALLEL${C_RESET}: Parallele Anfrageverarbeitung."
    echo -e "  Tipp: '2' oder '4' erlaubt das zeitgleiche Bedienen mehrerer Client-Anfragen."
    local parallel
    read -rp "  Wert eingeben [z.B. 1, 2, 4 | Enter = 1]: " parallel
    parallel="${parallel:-1}"

    ensure_sudo
    local drop_file="${SYSTEMD_DROP_DIR}/global-tuning.conf"
    command sudo mkdir -p "${SYSTEMD_DROP_DIR}"
    local content="[Service]\nEnvironment=\"OLLAMA_KEEP_ALIVE=${keep_alive}\"\nEnvironment=\"OLLAMA_KV_CACHE_TYPE=${kv_cache}\"\nEnvironment=\"OLLAMA_NUM_PARALLEL=${parallel}\"\n"
    write_sys_file "${drop_file}" "${content}"

    command sudo systemctl daemon-reload
    if systemctl is-active --quiet ollama; then
        info "Starte Ollama-Dienst neu, um Einstellungen anzuwenden …"
        command sudo systemctl restart ollama
    fi
    ok "Globale Tuning-Einstellungen angewendet!"
}

# ── S) System Status & Logs ───────────────────────────────────────────────────
show_system_status() {
    # Temporarily disable exit-on-error and pipefail to guarantee we don't crash
    # the manager script if any diagnostic query fails or returns a non-zero exit
    set +e
    set +o pipefail

    ensure_sudo
    local w
    w=$(dynamic_width)
    echo
    draw_line "${w}"
    echo -e "${C_BOLD}  System-Status & Logs${C_RESET}"
    draw_line "${w}"

    echo -e "\n${C_CYAN}[ Ollama Service ]${C_RESET}"
    systemctl status ollama --no-pager 2>/dev/null | head -n 8 || true

    local amd_found=0
    local amd_gpu_names=""
    
    # Pre-fetch precise PCI branding name for AMD devices
    if command -v lspci &>/dev/null; then
        amd_gpu_names=$(lspci -nn | grep -i "VGA\|Display" | grep -i "AMD" || echo "")
    fi

    # Display GPU specific telemetry
    if command -v nvidia-smi &>/dev/null; then
        echo -e "\n${C_CYAN}[ NVIDIA GPU Auslastung ]${C_RESET}"
        nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=csv 2>/dev/null || echo "NVIDIA-SMI konnte nicht abgefragt werden."
    elif command -v rocm-smi &>/dev/null; then
        echo -e "\n${C_CYAN}[ AMD ROCm GPU Auslastung (ROCm-SMI) ]${C_RESET}"
        rocm-smi --showuse --showmeminfo vram 2>/dev/null || echo "ROCm-SMI konnte nicht abgefragt werden."
        amd_found=1
    fi

    # Scrape native sysfs kernel nodes for AMD/Radeon statistics
    local card vram_total_raw vram_used_raw gpu_busy_raw total_bytes used_bytes total_mib used_mib total_gib used_gib vendor
    for card in /sys/class/drm/card[0-9]*; do
        [[ -e "${card}" ]] || continue
        if [[ -d "${card}/device" ]]; then
            vendor=$(cat "${card}/device/vendor" 2>/dev/null || echo "")
            if [[ "${vendor}" =~ 0x1002 || "${vendor}" =~ 1002 ]]; then
                amd_found=1
                echo -e "\n${C_CYAN}[ AMD GPU Auslastung (Sysfs) - ${card##*/} ]${C_RESET}"
                
                if [[ -n "${amd_gpu_names}" ]]; then
                    echo -e "  Modell         : $(echo "${amd_gpu_names}" | head -n 1 | sed 's/.*: //')"
                fi
                
                vram_total_raw=$(cat "${card}/device/mem_info_vram_total" 2>/dev/null | tr -d '\0' | tr -cd '0-9' || echo 0)
                vram_used_raw=$(cat "${card}/device/mem_info_vram_used" 2>/dev/null | tr -d '\0' | tr -cd '0-9' || echo 0)
                gpu_busy_raw=$(cat "${card}/device/gpu_busy_percent" 2>/dev/null | tr -d '\0' | tr -cd '0-9' || echo "N/A")
                
                total_bytes=${vram_total_raw:-0}
                used_bytes=${vram_used_raw:-0}
                
                if [[ -n "${total_bytes}" ]] && (( total_bytes > 0 )); then
                    total_mib=$(( total_bytes / 1024 / 1024 ))
                    used_mib=$(( used_bytes / 1024 / 1024 ))
                    
                    total_gib=$(awk "BEGIN {printf \"%.2f\", ${total_bytes}/1024/1024/1024}" 2>/dev/null || echo "N/A")
                    used_gib=$(awk "BEGIN {printf \"%.2f\", ${used_bytes}/1024/1024/1024}" 2>/dev/null || echo "N/A")
                    
                    echo -e "  GPU-Auslastung : ${gpu_busy_raw}%"
                    echo -e "  VRAM-Belegung  : ${used_mib} MiB / ${total_mib} MiB (${used_gib} GiB / ${total_gib} GiB)"
                else
                    echo "  Metriken konnten nicht ausgelesen werden (VRAM-Größe ungültig)."
                fi
            fi
        fi
    done

    # Fallback system resource metrics
    if (( amd_found == 0 )) && ! command -v nvidia-smi &>/dev/null; then
        echo -e "\n${C_CYAN}[ System-RAM Auslastung ]${C_RESET}"
        free -h 2>/dev/null || true
    fi

    # Display Kernel logs for AMD cards
    if [[ -n "${amd_gpu_names}" ]] || (( amd_found == 1 )); then
        echo -e "\n${C_CYAN}[ AMD GPU Treiber-Meldungen (Letzte 5) ]${C_RESET}"
        command sudo journalctl -k -b 2>/dev/null | grep -iE 'amdgpu|radeon' | tail -n 5 || echo "  Keine AMDGPU-Kernelmeldungen gefunden."
    fi

    echo -e "\n${C_CYAN}[ Letzte 15 Ollama Log-Einträge ]${C_RESET}"
    command sudo journalctl -u ollama -n 15 --no-pager 2>/dev/null || true
    echo

    # Intelligent diagnostic block to explain when AMD is found but logs say "no GPU"
    if [[ -n "${amd_gpu_names}" ]] || (( amd_found == 1 )); then
        if command sudo journalctl -u ollama -n 50 --no-pager 2>/dev/null | grep -qiE 'cpu-only|no compatible gpus|falling back to cpu|failed to find compatible gpu'; then
            echo
            warn "DIAGNOSE: AMD GPU erkannt, aber Ollama meldet CPU-Modus!"
            warn "Abhilfe:"
            warn "  1. Starte deinen PC neu (damit die Gruppenrechte aktiv werden)."
            warn "  2. Stelle sicher, dass die passende Treibermethode (Option 2 ROCm oder Option 3 Vulkan) installiert wurde."
            echo
        fi
    fi

    # Restore strict bash environments safely before exiting function scope
    set -e
    set -o pipefail

    read -rp "  Drücke Enter, um zum Hauptmenü zurückzukehren …" _
}

# ── 6) Model Management ───────────────────────────────────────────────────────

# Fetch model tags parsing HTML-JSON payloads safely using PCRE regex with a hardcoded fallback
fetch_available_models() {
    local url="https://ollama.com/api/search?q=&p=1&ps=200"
    info "Lade Modellliste von ollama.com …"
    local models
    if models=$(curl -fsSL --max-time 10 "${url}" 2>/dev/null | grep -oP '"name":"\K[^"]+' | sort -u); then
        echo "${models}"
    else
        # Provide a reliable offline production fallback list
        echo -e "llama3.2:3b\nllama3.1:8b\nqwen2.5-coder:7b\nphi4:14b\nmistral-nemo:12b"
    fi
}

list_local_models() {
    require_ollama || return
    local models
    models=$(get_local_models)
    if [[ -z "${models}" ]]; then
        warn "Keine lokalen Modelle installiert."
        return
    fi
    echo -e "${C_BOLD}$(ollama list 2>/dev/null || true)${C_RESET}"
    info "Tipp: Modell direkt starten mit: ollama run <modellname>"
}

pull_models() {
    require_ollama || return
    local w
    w=$(dynamic_width)

    echo
    draw_line "${w}"
    echo -e "${C_BOLD}  Empfohlene Modelle${C_RESET}"
    draw_line "${w}"
    echo -e "  ${C_CYAN}llama3.2:3b${C_RESET}         (Meta, schnell, CPU-freundlich, ~2 GB)"
    echo -e "  ${C_CYAN}llama3.1:8b${C_RESET}         (Meta, sehr ausgewogen, ~5 GB)"
    echo -e "  ${C_CYAN}qwen2.5-coder:7b${C_RESET}    (Alibaba, Top für Code, ~5 GB)"
    echo -e "  ${C_CYAN}phi4:14b${C_RESET}            (Microsoft, starkes Reasoning, ~9 GB)"
    echo -e "  ${C_CYAN}mistral-nemo:12b${C_RESET}    (Mistral, multilingual, ~7 GB)"
    echo

    info "Lade Online-Modellliste … (Leertaste=auswählen, Enter=bestätigen, Esc=abbrechen)"
    local model_list selected
    model_list=$(fetch_available_models 2>/dev/null || true)

    selected=$(echo "${model_list}" | fzf --multi \
          --prompt="  Modell herunterladen > " \
          --header="Leertaste=auswählen  Enter=herunterladen  Esc=abbrechen" \
          --color="hl:green,hl+:green" || true)

    [[ -z "${selected}" ]] && { warn "Kein Modell ausgewählt."; return; }

    while IFS= read -r model; do
        info "Lade ${model} herunter …"
        ollama pull "${model}"
        ok "${model} bereit."
    done <<< "${selected}"
}

update_models() {
    require_ollama || return
    local local_models
    local_models=$(get_local_models)

    if [[ -z "${local_models}" ]]; then
        warn "Keine lokalen Modelle gefunden — nichts zu aktualisieren."
        return
    fi

    info "Verwaiste Modell-Layer bereinigen …"
    ollama prune 2>/dev/null || true

    warn "Alle lokalen Modelle werden neu geladen (kann lange dauern) …"
    while IFS= read -r model; do
        info "Aktualisiere ${model} …"
        ollama pull "${model}"
        ok "${model} aktualisiert."
    done <<< "${local_models}"
}

remove_models() {
    require_ollama || return
    local local_models
    local_models=$(get_local_models)

    [[ -z "${local_models}" ]] && { warn "Keine lokalen Modelle installiert."; return; }

    local selected
    selected=$(echo "${local_models}" | fzf --multi \
          --prompt="  Modell entfernen > " \
          --header="Leertaste=auswählen  Enter=löschen  Esc=abbrechen" \
          --color="hl:red,hl+:red" || true)

    [[ -z "${selected}" ]] && return

    warn "Werden gelöscht: $(echo "${selected}" | tr '\n' ' ')"
    local confirm
    read -rp "  Wirklich löschen? [j/N]: " confirm
    [[ "${confirm,,}" != "j" ]] && return

    while IFS= read -r model; do
        ollama rm "${model}"
        ok "Entfernt: ${model}"
    done <<< "${selected}"
}

model_menu() {
    local sub
    while true; do
        echo
        echo -e "  ${C_BOLD}── KI-Modelle verwalten ──${C_RESET}"
        echo -e "  ${C_CYAN}1${C_RESET}  Lokale Modelle anzeigen"
        echo -e "  ${C_CYAN}2${C_RESET}  Modell herunterladen"
        echo -e "  ${C_CYAN}3${C_RESET}  Alle Modelle aktualisieren"
        echo -e "  ${C_CYAN}4${C_RESET}  Modelle entfernen"
        echo -e "  ${C_CYAN}z${C_RESET}  Zurück"
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

# ── 7) Modelfile Assistant ────────────────────────────────────────────────────
modelfile_assistant() {
    require_ollama || return
    local config_dir="${HOME}/Ollama_config"
    ensure_config_dir

    local base_model="" local_models
    local_models=$(get_local_models)

    if [[ -n "${local_models}" ]]; then
        base_model=$(echo "${local_models}" | fzf --prompt="  Basismodell > " \
            --header="Enter=auswählen  Esc=manuell eingeben oder abbrechen" \
            --color="hl:cyan,hl+:cyan" || true)
    fi

    # Fallback if no model was selected in fzf or fzf was bypassed/escaped
    if [[ -z "${base_model:-}" ]]; then
        read -rp "  Basismodell manuell eingeben (z.B. llama3.2:3b | 'q' zum Abbrechen): " base_model
    fi

    # Exit cleanly if 'q' or empty string was entered to return back to the menu
    if [[ -z "${base_model}" || "${base_model}" == "q" || "${base_model}" == "Q" ]]; then
        info "Modelfile-Assistent abgebrochen."
        return 0
    fi

    local sys_prompt temperature num_ctx repeat_penalty model_name ctx_choice
    read -rp "  SYSTEM-Prompt (Enter=leer | 'q' zum Abbrechen): " sys_prompt
    if [[ "${sys_prompt}" == "q" || "${sys_prompt}" == "Q" ]]; then
        info "Modelfile-Assistent abgebrochen."
        return 0
    fi

    while true; do
        read -rp "  Temperature [0.0-1.0, Enter=0.7 | 'q' zum Abbrechen]: " temperature
        temperature="${temperature:-0.7}"
        if [[ "${temperature}" == "q" || "${temperature}" == "Q" ]]; then
            info "Modelfile-Assistent abgebrochen."
            return 0
        fi
        [[ "${temperature}" =~ ^0(\.[0-9]+)?$|^1(\.0+)?$ ]] && break
        warn "Ungültiger Wert."
    done

    # Provide "Abbrechen" in the list of ctx choices
    select ctx_choice in "2048" "4096" "8192" "16384" "32768" "Manuell eingeben" "Abbrechen"; do
        case "${ctx_choice}" in
            "Manuell eingeben")
                read -rp "  num_ctx eingeben: " num_ctx
                num_ctx="${num_ctx:-4096}"
                break
                ;;
            "Abbrechen")
                info "Modelfile-Assistent abgebrochen."
                return 0
                ;;
            "")
                warn "Ungültige Auswahl."
                ;;
            *)
                num_ctx="${ctx_choice}"
                break
                ;;
        esac
    done

    read -rp "  repeat_penalty [Enter=1.1 | 'q' zum Abbrechen]: " repeat_penalty
    repeat_penalty="${repeat_penalty:-1.1}"
    if [[ "${repeat_penalty}" == "q" || "${repeat_penalty}" == "Q" ]]; then
        info "Modelfile-Assistent abgebrochen."
        return 0
    fi

    read -rp "  Name für das eigene Modell (oder 'q' zum Abbrechen): " model_name
    if [[ -z "${model_name}" || "${model_name}" == "q" || "${model_name}" == "Q" ]]; then
        info "Modelfile-Assistent abgebrochen."
        return 0
    fi
    model_name="${model_name//[^a-zA-Z0-9_-]/}"
    if [[ -z "${model_name}" ]]; then
        warn "Ungültiger Name nach Filterung."
        return 1
    fi

    local filename="${config_dir}/Modelfile.${model_name}"

    {
        echo "FROM ${base_model}"
        [[ -n "${sys_prompt}" ]] && echo -e "\nSYSTEM \"${sys_prompt}\""
        echo -e "\nPARAMETER temperature ${temperature}"
        echo "PARAMETER num_ctx ${num_ctx}"
        echo "PARAMETER repeat_penalty ${repeat_penalty}"
    } > "${filename}"

    ok "Modelfile geschrieben: ${filename}"

    local do_create
    read -rp "  Modell jetzt bauen? [j/N]: " do_create
    if [[ "${do_create,,}" == "j" ]]; then
        ollama create "${model_name}" -f "${filename}" && ok "Modell erstellt."
    fi
}

# ── 8) Install Opencode ───────────────────────────────────────────────────────
install_opencode() {
    local aur_helper
    aur_helper=$(detect_aur_helper)

    [[ -z "${aur_helper}" ]] && { warn_no_aur; return; }

    if pacman -Q opencode &>/dev/null; then
        ok "opencode ist bereits installiert."
        return
    fi

    local confirm
    read -rp "  opencode jetzt installieren? [j/N]: " confirm
    [[ "${confirm,,}" != "j" ]] && return

    "${aur_helper}" -S --needed --noconfirm opencode
    ok "opencode installiert."
}

# ── 0) Uninstall Operations ───────────────────────────────────────────────────
_remove_models_only() {
    warn "Alle Modelldaten unter ~/.ollama werden DAUERHAFT gelöscht."
    local confirm
    read -rp "  Zur Bestätigung 'ja' eingeben: " confirm
    [[ "${confirm}" != "ja" ]] && return

    ensure_sudo
    [[ -n "${HOME}" ]] || { err "HOME nicht gesetzt — Abbruch."; return 1; }

    local restart=0
    if systemctl is-active --quiet ollama 2>/dev/null; then
        info "ollama.service kurz stoppen (Dateisperre vermeiden) …"
        command sudo systemctl stop ollama
        restart=1
    fi

    command sudo rm -rf "${HOME}/.ollama"
    ok "Modelldaten gelöscht."

    (( restart == 1 )) && command sudo systemctl start ollama
}

_do_remove_packages() {
    local pkgs=("$@")
    ensure_sudo
    info "ollama.service stoppen …"
    command sudo systemctl disable --now ollama 2>/dev/null || true
    command sudo pacman -Rns --noconfirm "${pkgs[@]}"
    ok "Pakete entfernt: ${pkgs[*]}"
}

_remove_packages_only() {
    local pkgs=()
    for p in ollama ollama-rocm ollama-vulkan opencode llm-manager; do
        if pacman -Q "${p}" &>/dev/null; then pkgs+=("${p}"); fi
    done

    (( ${#pkgs[@]} == 0 )) && { warn "Keine passenden Pakete gefunden."; return; }

    warn "Werden entfernt: ${pkgs[*]}"
    local confirm
    read -rp "  Bestätigen mit 'ja': " confirm
    [[ "${confirm}" != "ja" ]] && return

    _do_remove_packages "${pkgs[@]}"
}

_remove_all_confirm() {
    echo
    warn "VOLLSTÄNDIGE Deinstallation. Alle Daten und Modelfiles werden unwiderruflich gelöscht."
    local confirm
    read -rp "  Zur Bestätigung 'ja' eingeben: " confirm
    [[ "${confirm}" != "ja" ]] && return

    ensure_sudo
    [[ -n "${HOME}" ]] || { err "HOME nicht gesetzt — Abbruch."; return 1; }

    local pkgs=()
    for p in ollama ollama-rocm ollama-vulkan opencode llm-manager; do
        if pacman -Q "${p}" &>/dev/null; then pkgs+=("${p}"); fi
    done

    (( ${#pkgs[@]} > 0 )) && _do_remove_packages "${pkgs[@]}"

    command sudo rm -rf "${HOME}/.ollama"
    command sudo rm -rf "${HOME}/Ollama_config"

    local files_to_remove=(
        "${SYSTEMD_DROP_DIR}/nvidia-cuda.conf"
        "${SYSTEMD_DROP_DIR}/amd-rocm.conf"
        "${SYSTEMD_DROP_DIR}/amd-vulkan.conf"
        "${SYSTEMD_DROP_DIR}/cpu-optimized.conf"
        "${SYSTEMD_DROP_DIR}/global-tuning.conf"
        "/etc/sysctl.d/99-ollama-cpu.conf"
        "/etc/sysctl.d/99-ollama-amd-vulkan.conf"
        "/etc/tmpfiles.d/ollama-thp.conf"
    )
    for f in "${files_to_remove[@]}"; do
        [[ -f "${f}" ]] && command sudo rm -f "${f}"
    done

    command sudo rmdir --ignore-fail-on-non-empty "${SYSTEMD_DROP_DIR}" 2>/dev/null || true
    command sudo systemctl daemon-reload 2>/dev/null || true
    ok "Deinstallation abgeschlossen."
}

remove_menu() {
    local sub
    while true; do
        echo
        echo -e "  ${C_BOLD}── Deinstallation ──${C_RESET}"
        echo -e "  ${C_CYAN}1${C_RESET}  Nur Modelle entfernen     (~/.ollama)"
        echo -e "  ${C_CYAN}2${C_RESET}  Nur Pakete deinstallieren (ollama, opencode …)"
        echo -e "  ${C_CYAN}3${C_RESET}  Alles entfernen           (Modelle, Configs, Pakete)"
        echo -e "  ${C_CYAN}z${C_RESET}  Zurück"
        read -rp "  Auswahl: " sub

        case "${sub}" in
            1) _remove_models_only ;;
            2) _remove_packages_only ;;
            3) _remove_all_confirm ;;
            z|Z) return ;;
            *) warn "Ungültige Eingabe." ;;
        esac
        echo
        read -rp "  Weiter mit Enter …" _
    done
}

# ── Main Entrypoint ───────────────────────────────────────────────────────────
main() {
    check_deps
    local choice

    while true; do
        show_menu
        read -rp "  Auswahl: " choice
        case "${choice}" in
            1) setup_nvidia_cuda ;;
            2) setup_amd_rocm ;;
            3) setup_amd_vulkan ;;
            4) setup_cpu_only ;;
            5) global_performance_tuning ;;
            s|S) show_system_status; continue ;;
            6) model_menu; continue ;;
            7) modelfile_assistant ;;
            8) install_opencode ;;
            0) remove_menu; continue ;;
            q|Q) info "Auf Wiedersehen."; exit 0 ;;
            *) warn "Ungültige Eingabe." ;;
        esac
        echo
        read -rp "  Weiter mit Enter …" _
    done
}

main "$@"