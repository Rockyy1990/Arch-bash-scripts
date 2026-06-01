#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
trap 'echo "ERR ${FUNCNAME[0]:-main}:${LINENO}" >&2' ERR

# ── Colors ─────────────────────────────────────────────────────────────────────
readonly C_OK='\033[0;32m'
readonly C_WARN='\033[0;33m'
readonly C_ERR='\033[0;31m'
readonly C_INFO='\033[0;36m'
readonly C_HINT='\033[0;35m'
readonly C_HEAD='\033[1;34m'
readonly C_SUB='\033[0;34m'
readonly C_BOLD='\033[1m'
readonly C_DIM='\033[2m'
readonly C_RESET='\033[0m'

ok()   { printf "${C_OK}✔ %s${C_RESET}\n"   "${*}"; }
warn() { printf "${C_WARN}⚠ %s${C_RESET}\n" "${*}" >&2; }
err()  { printf "${C_ERR}✘ %s${C_RESET}\n"  "${*}" >&2; }
info() { printf "${C_INFO}→ %s${C_RESET}\n" "${*}"; }
hint() { printf "${C_HINT}  ℹ %s${C_RESET}\n" "${*}"; }
die()  { err "${*}"; exit 1; }

# ── Terminal helpers ───────────────────────────────────────────────────────────
term_width() { tput cols 2>/dev/null || echo 80; }

separator() {
  local w; w=$(term_width)
  printf '%*s\n' "${w}" '' | tr ' ' '-'
}

# B4 fix: split printf so color escape is not in the format string
thin_sep() {
  local w line; w=$(term_width)
  line=$(printf '%*s' "${w}" '' | tr ' ' '·')
  printf '%b%s%b\n' "${C_DIM}" "${line}" "${C_RESET}"
}

# S1/P1 fix: cache separator string, avoid two subshells
section() {
  local sep; sep=$(separator)
  printf '\n%b%s%b\n' "${C_HEAD}" "${sep}" "${C_RESET}"
  printf '  %b%s%b\n' "${C_BOLD}" "${1}" "${C_RESET}"
  printf '%b%s%b\n'   "${C_HEAD}" "${sep}" "${C_RESET}"
}

prompt_yn() {
  printf '%b [y/N] ' "${1}"
  local ans; read -r ans
  [[ "${ans,,}" == "y" ]]
}

prompt_path() {
  local label="${1}" default="${2}"
  printf '%b\n  Default: %b%s%b\n  Path: ' \
    "${label}" "${C_DIM}" "${default}" "${C_RESET}"
  local p; read -r p
  printf '%s' "${p:-${default}}"
}

# ── Sudo elevation ─────────────────────────────────────────────────────────────
_sudo_keepalive_pid=""

ensure_sudo() {
  (( EUID == 0 )) && return 0
  info "Root privileges required."
  sudo -v || die "sudo authentication failed"
  ( while true; do sudo -n true; sleep 55; done ) &
  _sudo_keepalive_pid=$!
  trap '_cleanup_sudo' EXIT
}

# B1 fix: plain if instead of A&&B||C
_cleanup_sudo() {
  if [[ -n "${_sudo_keepalive_pid}" ]]; then
    kill "${_sudo_keepalive_pid}" 2>/dev/null || true
  fi
}

# ── Backup helper ──────────────────────────────────────────────────────────────
backup_file() {
  local file="${1:?backup_file: path required}"
  [[ -f "${file}" ]] || return 0
  local bak
  bak="${file}.bak.$(date +%Y%m%d_%H%M%S)"
  sudo cp -a "${file}" "${bak}"
  info "Backup: ${bak}"
}

# ── Build dependency check ─────────────────────────────────────────────────────
check_build_deps() {
  section "Build Dependencies"

  local deps=(base-devel openssl zlib bzip2 readline sqlite ncurses xz tk libffi)
  local missing=()

  for pkg in "${deps[@]}"; do
    pacman -Q "${pkg}" &>/dev/null || missing+=("${pkg}")
  done

  if (( ${#missing[@]} == 0 )); then
    ok "All build dependencies present"
    hint "Tip: 'pyenv install --list' shows all available Python versions"
    return 0
  fi

  warn "Missing: ${missing[*]}"
  hint "Tip: These are required for compiling CPython from source via pyenv"
  if prompt_yn "Install missing build dependencies?"; then
    sudo pacman -S --noconfirm --needed "${missing[@]}"
    ok "Build dependencies installed"
  else
    warn "Skipped — pyenv Python builds will fail without these packages"
  fi
}

# ── GPU detection ──────────────────────────────────────────────────────────────
detect_gpu() {
  local gpu_info
  gpu_info=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)
  if grep -qi nvidia <<< "${gpu_info}"; then
    echo "nvidia"
  elif grep -qi 'amd\|radeon' <<< "${gpu_info}"; then
    echo "amd"
  else
    echo "none"
  fi
}

# ── pip check / install ────────────────────────────────────────────────────────
check_pip() {
  section "pip Status"

  # S2 fix: clean if/elif instead of &&-chain
  local pip_cmd=""
  if command -v pip &>/dev/null; then
    pip_cmd="pip"
  elif command -v pip3 &>/dev/null; then
    pip_cmd="pip3"
  fi

  if [[ -n "${pip_cmd}" ]]; then
    ok "${pip_cmd} found: $(${pip_cmd} --version 2>&1)"
    hint "Tip: Use 'pip install --user <pkg>' to avoid system-wide installs"
    hint "Tip: Inside a venv, omit --user; the venv is already isolated"
    return 0
  fi

  warn "pip not found"
  if prompt_yn "Install python-pip via pacman?"; then
    sudo pacman -S --noconfirm --needed python-pip
    ok "python-pip installed"
  else
    warn "pip installation skipped"
  fi
}

# ── pyenv install ──────────────────────────────────────────────────────────────
install_pyenv() {
  section "pyenv Installation"

  if command -v pyenv &>/dev/null; then
    ok "pyenv already installed: $(pyenv --version)"
    hint "Tip: Run 'pyenv update' to fetch the latest Python version list"
    return 0
  fi

  warn "pyenv not found"
  hint "Tip: pyenv lets you install and switch multiple Python versions without touching the system Python"
  prompt_yn "Install pyenv?" || { warn "pyenv installation skipped"; return 0; }

  if command -v yay &>/dev/null; then
    yay -S --noconfirm pyenv
  elif command -v paru &>/dev/null; then
    paru -S --noconfirm pyenv
  else
    warn "No AUR helper found — using official pyenv installer script"
    hint "Tip: Install 'yay' or 'paru' for easier AUR management"
    command -v curl &>/dev/null || sudo pacman -S --noconfirm --needed curl
    curl -fsSL https://pyenv.run | bash
  fi
  ok "pyenv installed"
}

# ── pyenv: install a Python version ───────────────────────────────────────────
install_python_version() {
  section "Install Python via pyenv"

  if ! command -v pyenv &>/dev/null; then
    warn "pyenv not found — run option 3 first"
    return 1
  fi

  info "Available recent CPython versions:"
  # S3 fix: single sed call with two -e expressions
  pyenv install --list 2>/dev/null \
    | grep -E '^\s+3\.(1[0-9]|[2-9][0-9])\.[0-9]+$' \
    | tail -20 \
    | sed -e "s/^/  ${C_DIM}/" -e "s/$/${C_RESET}/"

  printf '\nVersion to install (e.g. 3.12.4), or Enter to skip: '
  local ver; read -r ver
  [[ -z "${ver}" ]] && { info "Skipped"; return 0; }

  [[ "${ver}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { warn "Invalid version format — expected X.Y.Z"; return 1; }

  hint "Tip: Build uses PYTHON_CONFIGURE_OPTS from /etc/profile.d/pyenv-opt.sh if set (option 6)"
  info "Building Python ${ver} — this may take 5-10 minutes..."
  pyenv install "${ver}"
  ok "Python ${ver} installed"

  if prompt_yn "Set ${ver} as global default?"; then
    pyenv global "${ver}"
    ok "pyenv global → ${ver}"
    hint "Tip: Use 'pyenv local <version>' inside a project dir to override the global"
  fi
}

# ── pyenv shell config ─────────────────────────────────────────────────────────
configure_shell() {
  section "Shell Configuration"

  local shell_rc
  case "${SHELL##*/}" in
    zsh)  shell_rc="${HOME}/.zshrc" ;;
    bash) shell_rc="${HOME}/.bashrc" ;;
    fish) shell_rc="${HOME}/.config/fish/config.fish" ;;
    *)    warn "Unknown shell '${SHELL##*/}' — skipping"; return 0 ;;
  esac

  if grep -q '# pyenv init' "${shell_rc}" 2>/dev/null; then
    ok "pyenv already configured in ${shell_rc}"
    return 0
  fi

  cat >> "${shell_rc}" <<'EOF'

# pyenv init
export PYENV_ROOT="${HOME}/.pyenv"
[[ -d "${PYENV_ROOT}/bin" ]] && export PATH="${PYENV_ROOT}/bin:${PATH}"
eval "$(pyenv init -)"
EOF
  ok "pyenv init added to ${shell_rc}"
  hint "Tip: Run 'source ${shell_rc}' or open a new terminal to activate pyenv"
}

# ── CPU optimisation ───────────────────────────────────────────────────────────
configure_cpu() {
  section "CPU Build Optimisation"

  local cores; cores=$(nproc)
  ok "Detected ${cores} CPU threads"

  if (( cores < 4 )); then
    warn "Low core count (${cores}) — CPython builds will be slow"
  fi

  backup_file /etc/makepkg.conf

  _makepkg_set() {
    local key="${1}" val="${2}" file="/etc/makepkg.conf"
    if sudo grep -q "^${key}=" "${file}" 2>/dev/null; then
      sudo sed -i "s|^${key}=.*|${key}=${val}|" "${file}"
    else
      printf '%s=%s\n' "${key}" "${val}" | sudo tee -a "${file}" >/dev/null
    fi
  }

  _makepkg_set MAKEFLAGS "\"-j${cores}\""
  ok "MAKEFLAGS=-j${cores}"

  # shellcheck disable=SC2016
  local cflags='"-march=native -O2 -pipe -fno-plt -fexceptions -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security -fstack-clash-protection -fcf-protection"'
  _makepkg_set CFLAGS "${cflags}"
  # shellcheck disable=SC2016
  _makepkg_set CXXFLAGS '"$CFLAGS -Wp,-D_GLIBCXX_ASSERTIONS"'
  ok "CFLAGS/CXXFLAGS → -march=native"

  local profile_d="/etc/profile.d/pyenv-opt.sh"
  printf '#!/bin/sh\nexport PYTHON_CONFIGURE_OPTS="--enable-optimizations --with-lto"\nexport MAKE_OPTS="-j%s"\n' \
    "${cores}" | sudo tee "${profile_d}" >/dev/null
  sudo chmod 644 "${profile_d}"
  ok "pyenv build opts → ${profile_d}"
  hint "Tip: --enable-optimizations runs PGO; --with-lto enables link-time optimisation — ~10-20% faster Python"
}

# ── GPU optimisation ───────────────────────────────────────────────────────────
configure_gpu() {
  section "GPU Configuration"
  local gpu_type; gpu_type=$(detect_gpu)
  info "Detected GPU: ${gpu_type}"

  case "${gpu_type}" in
    nvidia) _configure_nvidia ;;
    amd)    _configure_amd ;;
    none)
      warn "No discrete GPU detected"
      hint "Tip: GPU acceleration (CUDA/ROCm) is needed for PyTorch/TensorFlow GPU support"
      ;;
  esac
}

_configure_nvidia() {
  local pkgs=()
  command -v nvidia-smi &>/dev/null || pkgs+=(nvidia nvidia-utils)
  command -v nvcc       &>/dev/null || pkgs+=(cuda)

  if (( ${#pkgs[@]} > 0 )); then
    warn "Missing NVIDIA packages: ${pkgs[*]}"
    if prompt_yn "Install them?"; then
      sudo pacman -S --noconfirm --needed "${pkgs[@]}"
      ok "NVIDIA packages installed"
    fi
  else
    ok "NVIDIA driver + CUDA already present"
  fi

  local env_file="/etc/profile.d/cuda-env.sh"
  # shellcheck disable=SC2016
  printf '#!/bin/sh\nexport CUDA_HOME="/opt/cuda"\nexport PATH="${CUDA_HOME}/bin:${PATH}"\nexport LD_LIBRARY_PATH="${CUDA_HOME}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"\n' \
    | sudo tee "${env_file}" >/dev/null
  sudo chmod 644 "${env_file}"
  ok "CUDA env → ${env_file}"
  hint "Tip: Install PyTorch with CUDA via: pip install torch --index-url https://download.pytorch.org/whl/cu121"
}

_configure_amd() {
  local pkgs=()
  command -v rocminfo &>/dev/null || pkgs+=(rocm-hip-sdk)

  if (( ${#pkgs[@]} > 0 )); then
    warn "Missing ROCm packages: ${pkgs[*]}"
    if prompt_yn "Install them?"; then
      sudo pacman -S --noconfirm --needed "${pkgs[@]}"
      ok "ROCm installed"
      sudo usermod -aG render,video "${USER}"
      ok "User ${USER} added to render,video groups"
      warn "Re-login required for group membership to take effect"
    fi
  else
    ok "ROCm already present"
  fi

  local env_file="/etc/profile.d/rocm-env.sh"
  # shellcheck disable=SC2016
  printf '#!/bin/sh\nexport ROCM_HOME="/opt/rocm"\nexport PATH="${ROCM_HOME}/bin:${PATH}"\nexport LD_LIBRARY_PATH="${ROCM_HOME}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"\n# Set HSA_OVERRIDE_GFX_VERSION manually if needed for unofficial GPUs\n' \
    | sudo tee "${env_file}" >/dev/null
  sudo chmod 644 "${env_file}"
  ok "ROCm env → ${env_file}"
  hint "Tip: Install PyTorch with ROCm via: pip install torch --index-url https://download.pytorch.org/whl/rocm5.7"
}

# ── System parameters ──────────────────────────────────────────────────────────
configure_system() {
  section "System Parameters"

  local sysctl_conf="/etc/sysctl.d/99-pyenv-perf.conf"
  sudo tee "${sysctl_conf}" >/dev/null <<'EOF'
fs.file-max = 2097152
vm.max_map_count = 1048576
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF
  sudo sysctl --system 2>&1 \
    | grep -E 'pyenv-perf|Applying' \
    | sed 's/^/  /' || true
  ok "sysctl → ${sysctl_conf}"

  local limits_conf="/etc/security/limits.d/99-pyenv.conf"
  printf '%s soft nofile 65535\n%s hard nofile 65535\n' \
    "${USER}" "${USER}" | sudo tee "${limits_conf}" >/dev/null
  ok "ulimit nofile=65535 → ${limits_conf}"

  local systemd_conf="/etc/systemd/system.conf.d/99-pyenv-limits.conf"
  sudo mkdir -p "$(dirname "${systemd_conf}")"
  printf '[Manager]\nDefaultLimitNOFILE=65535\n' \
    | sudo tee "${systemd_conf}" >/dev/null
  ok "systemd DefaultLimitNOFILE → ${systemd_conf}"
  hint "Tip: vm.max_map_count=1048576 is required for PyTorch/FAISS with large models"
}

# ══════════════════════════════════════════════════════════════════════════════
# VIRTUAL ENVIRONMENT MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

_python_bin() {
  if command -v pyenv &>/dev/null; then
    pyenv which python 2>/dev/null || command -v python3 || die "No python found"
  else
    command -v python3 || die "No python3 found"
  fi
}

# B3 fix: use pre-increment so (( ++found )) is always nonzero after first hit
_list_venvs() {
  local base="${1}"
  [[ -d "${base}" ]] || { warn "Directory not found: ${base}"; return 1; }
  local found=0
  while IFS= read -r -d '' dir; do
    if [[ -f "${dir}/bin/activate" ]]; then
      local pyver=""
      pyver=$("${dir}/bin/python" --version 2>&1 | awk '{print $2}' || echo "?")
      # B6/B7 fix: split color escapes out of printf format string
      printf '  %b%-40s%b %b%s%b\n' \
        "${C_OK}" "${dir#"${base}"/}" "${C_RESET}" \
        "${C_DIM}" "Python ${pyver}" "${C_RESET}"
      (( ++found )) || true
    fi
  done < <(find "${base}" -maxdepth 2 -type d -print0 2>/dev/null)
  (( found > 0 )) || warn "No venvs found under ${base}"
}

# ── Create venv ────────────────────────────────────────────────────────────────
venv_create() {
  section "Create Virtual Environment"

  local python_bin; python_bin=$(_python_bin)
  local pyver; pyver=$("${python_bin}" --version 2>&1)
  info "Using: ${python_bin} (${pyver})"

  if command -v pyenv &>/dev/null; then
    local gv; gv=$(pyenv global 2>/dev/null || echo "system")
    hint "Tip: Active pyenv version is '${gv}'. Run 'pyenv local <ver>' to change per-project"
  fi

  local venv_base
  venv_base=$(prompt_path "Base directory for venvs" "${HOME}/.venvs")

  printf '  Name for new venv: '
  local venv_name; read -r venv_name
  [[ -z "${venv_name}" ]] && { warn "Aborted — no name given"; return 1; }
  [[ "${venv_name}" =~ ^[a-zA-Z0-9._-]+$ ]] \
    || { warn "Invalid name — use only [a-zA-Z0-9._-]"; return 1; }

  local venv_path="${venv_base}/${venv_name}"

  if [[ -d "${venv_path}" ]]; then
    warn "Directory already exists: ${venv_path}"
    prompt_yn "Overwrite?" || return 1
    rm -rf "${venv_path}"
  fi

  local extra_args=()
  prompt_yn "Include system site-packages?" && extra_args+=(--system-site-packages)

  # B2 fix: declare local before conditional, assign after
  local do_upgrade=0
  if prompt_yn "Upgrade pip/setuptools/wheel after creation?"; then do_upgrade=1; fi

  mkdir -p "${venv_base}"
  "${python_bin}" -m venv "${extra_args[@]}" "${venv_path}"
  ok "venv created: ${venv_path}"

  if (( do_upgrade )); then
    "${venv_path}/bin/pip" install --quiet --upgrade pip setuptools wheel
    ok "pip/setuptools/wheel upgraded"
  fi

  hint "Activate:   source ${venv_path}/bin/activate"
  hint "Deactivate: deactivate"

  if prompt_yn "Write .python-version + activate alias to current dir?"; then
    local pyver_short=""
    pyver_short=$(pyenv version-name 2>/dev/null || true)
    [[ -n "${pyver_short}" ]] && printf '%s\n' "${pyver_short}" > .python-version
    printf "alias activate='source %s/bin/activate'\n" "${venv_path}" >> "${HOME}/.bashrc"
    ok ".python-version written; 'activate' alias added to ~/.bashrc"
    warn "Restart shell or 'source ~/.bashrc' for alias to take effect"
  fi
}

# ── List venvs ─────────────────────────────────────────────────────────────────
venv_list() {
  section "List Virtual Environments"

  local venv_base
  venv_base=$(prompt_path "Base directory to scan" "${HOME}/.venvs")

  info "Scanning ${venv_base}:"
  _list_venvs "${venv_base}"
}

# ── Delete venv ────────────────────────────────────────────────────────────────
venv_delete() {
  section "Delete Virtual Environment"

  local venv_base
  venv_base=$(prompt_path "Base directory" "${HOME}/.venvs")
  _list_venvs "${venv_base}" || return 1

  printf '  Name to delete: '
  local venv_name; read -r venv_name
  [[ -z "${venv_name}" ]] && { warn "Aborted"; return 1; }

  local venv_path="${venv_base}/${venv_name}"
  [[ -f "${venv_path}/bin/activate" ]] \
    || { warn "Not a valid venv: ${venv_path}"; return 1; }

  warn "This will permanently remove: ${venv_path}"
  prompt_yn "Confirm deletion?" || { info "Aborted"; return 0; }

  rm -rf "${venv_path}"
  ok "Deleted: ${venv_path}"
}

# ── Clone venv ─────────────────────────────────────────────────────────────────
venv_clone() {
  section "Clone Virtual Environment"

  local venv_base
  venv_base=$(prompt_path "Base directory" "${HOME}/.venvs")
  _list_venvs "${venv_base}" || return 1

  printf '  Source venv name: '
  local src_name; read -r src_name
  local src_path="${venv_base}/${src_name}"
  [[ -f "${src_path}/bin/activate" ]] \
    || { warn "Not a valid venv: ${src_path}"; return 1; }

  printf '  New venv name: '
  local dst_name; read -r dst_name
  [[ -z "${dst_name}" ]] && { warn "Aborted — no name given"; return 1; }
  local dst_path="${venv_base}/${dst_name}"
  [[ -d "${dst_path}" ]] && { warn "Already exists: ${dst_path}"; return 1; }

  local python_bin; python_bin=$(_python_bin)
  local req_tmp; req_tmp=$(mktemp /tmp/venv-reqs.XXXXXX)
  trap 'rm -f "${req_tmp}"' RETURN

  # S4 fix: use the source venv's own pip for freeze (not system pip)
  "${src_path}/bin/pip" freeze > "${req_tmp}"
  info "Frozen $(wc -l < "${req_tmp}") packages from source"

  "${python_bin}" -m venv "${dst_path}"
  "${dst_path}/bin/pip" install --quiet --upgrade pip
  "${dst_path}/bin/pip" install --quiet -r "${req_tmp}"

  ok "Cloned ${src_name} → ${dst_name}"
  hint "Activate: source ${dst_path}/bin/activate"
}

# ── Export requirements ────────────────────────────────────────────────────────
venv_export() {
  section "Export Requirements"

  local venv_base
  venv_base=$(prompt_path "Base directory" "${HOME}/.venvs")
  _list_venvs "${venv_base}" || return 1

  printf '  Venv name: '
  local venv_name; read -r venv_name
  local venv_path="${venv_base}/${venv_name}"
  [[ -f "${venv_path}/bin/activate" ]] \
    || { warn "Not a valid venv: ${venv_path}"; return 1; }

  local out_file="${venv_path}/requirements.txt"
  "${venv_path}/bin/pip" freeze > "${out_file}"
  ok "Exported $(wc -l < "${out_file}") packages → ${out_file}"
  hint "Restore: pip install -r ${out_file}"
}

# ── Install packages into venv ─────────────────────────────────────────────────
venv_install_pkgs() {
  section "Install Packages into venv"

  local venv_base
  venv_base=$(prompt_path "Base directory" "${HOME}/.venvs")
  _list_venvs "${venv_base}" || return 1

  printf '  Venv name: '
  local venv_name; read -r venv_name
  local venv_path="${venv_base}/${venv_name}"
  [[ -f "${venv_path}/bin/activate" ]] \
    || { warn "Not a valid venv: ${venv_path}"; return 1; }

  local req_file="${venv_path}/requirements.txt"
  if [[ -f "${req_file}" ]]; then
    info "Found ${req_file}"
    if prompt_yn "Install from existing requirements.txt?"; then
      "${venv_path}/bin/pip" install -r "${req_file}"
      ok "Packages installed from requirements.txt"
      return 0
    fi
  fi

  printf '  Packages to install (space-separated): '
  local pkgs_raw; read -r pkgs_raw
  [[ -z "${pkgs_raw}" ]] && { warn "Aborted — no packages given"; return 1; }

  local pkgs=()
  read -r -a pkgs <<< "${pkgs_raw}"
  "${venv_path}/bin/pip" install "${pkgs[@]}"
  ok "Installed: ${pkgs[*]}"
}

# ── venv info ──────────────────────────────────────────────────────────────────
venv_info() {
  section "venv Info"

  local venv_base
  venv_base=$(prompt_path "Base directory" "${HOME}/.venvs")
  _list_venvs "${venv_base}" || return 1

  printf '  Venv name: '
  local venv_name; read -r venv_name
  local venv_path="${venv_base}/${venv_name}"
  [[ -f "${venv_path}/bin/activate" ]] \
    || { warn "Not a valid venv: ${venv_path}"; return 1; }

  local python_bin="${venv_path}/bin/python"
  local size_kb pkg_count pyver pip_ver
  size_kb=$(du -sk "${venv_path}" 2>/dev/null | awk '{print $1}')
  pkg_count=$("${venv_path}/bin/pip" list 2>/dev/null | tail -n +3 | wc -l)
  pyver=$("${python_bin}" --version 2>&1)
  pip_ver=$("${venv_path}/bin/pip" --version 2>&1)

  echo ""
  thin_sep
  # B6 fix: color escapes as arguments, not in format string
  printf '  %b%-18s%b %s\n' "${C_BOLD}" "Path:"       "${C_RESET}" "${venv_path}"
  printf '  %b%-18s%b %s\n' "${C_BOLD}" "Python:"     "${C_RESET}" "${pyver}"
  printf '  %b%-18s%b %s\n' "${C_BOLD}" "pip:"        "${C_RESET}" "${pip_ver}"
  printf '  %b%-18s%b %s\n' "${C_BOLD}" "Packages:"   "${C_RESET}" "${pkg_count}"
  printf '  %b%-18s%b %s MB\n' "${C_BOLD}" "Disk usage:" "${C_RESET}" "$(( size_kb / 1024 ))"
  thin_sep

  info "Installed packages:"
  "${venv_path}/bin/pip" list 2>/dev/null | tail -n +3 | sed 's/^/    /'

  if [[ -f "${venv_path}/requirements.txt" ]]; then
    ok "requirements.txt present"
  else
    hint "Tip: Export with option e → 'Export Requirements'"
  fi
}

# ── venv sub-menu ──────────────────────────────────────────────────────────────
menu_venv() {
  while true; do
    local w sep
    w=$(term_width)
    sep=$(printf '%*s' "${w}" '' | tr ' ' '-')
    printf '\n%b%s%b\n' "${C_SUB}" "${sep}" "${C_RESET}"
    # B7 fix: color escapes as arguments to %b, title as %s
    printf '  %b%bPython Environment Management%b\n' "${C_BOLD}" "${C_SUB}" "${C_RESET}"
    printf '%b%s%b\n' "${C_SUB}" "${sep}" "${C_RESET}"
    printf '  %bc)%b Create venv\n'              "${C_OK}"   "${C_RESET}"
    printf '  %bl)%b List venvs\n'               "${C_OK}"   "${C_RESET}"
    printf '  %bi)%b venv info & package list\n' "${C_OK}"   "${C_RESET}"
    printf '  %bp)%b Install packages into venv\n' "${C_OK}" "${C_RESET}"
    printf '  %be)%b Export requirements.txt\n'  "${C_OK}"   "${C_RESET}"
    printf '  %bk)%b Clone venv\n'               "${C_WARN}" "${C_RESET}"
    printf '  %bd)%b Delete venv\n'              "${C_ERR}"  "${C_RESET}"
    printf '  %b0) Back to main menu%b\n'        "${C_DIM}"  "${C_RESET}"
    printf '%b%s%b\n' "${C_SUB}" "${sep}" "${C_RESET}"
    printf '  Choice: '
    local ch; read -r ch

    case "${ch}" in
      c) venv_create ;;
      l) venv_list ;;
      i) venv_info ;;
      p) venv_install_pkgs ;;
      e) venv_export ;;
      k) venv_clone ;;
      d) venv_delete ;;
      0) return 0 ;;
      *) warn "Invalid choice: '${ch}'" ;;
    esac
  done
}

# ── Status overview ────────────────────────────────────────────────────────────
show_status() {
  section "Current Status"

  if command -v pip &>/dev/null; then
    ok "pip:      $(pip --version 2>&1)"
  elif command -v pip3 &>/dev/null; then
    ok "pip3:     $(pip3 --version 2>&1)"
  else
    warn "pip:      not found"
  fi

  if command -v pyenv &>/dev/null; then
    ok "pyenv:    $(pyenv --version)"
    local gv; gv=$(pyenv global 2>/dev/null || echo "none")
    info "  global: ${gv}"
    local installed_versions
    installed_versions=$(pyenv versions --bare 2>/dev/null | tr '\n' ' ' || echo "none")
    info "  installed: ${installed_versions}"
  else
    warn "pyenv:    not found"
    hint "Tip: Run option 3 to install pyenv"
  fi

  if [[ -d "${HOME}/.venvs" ]]; then
    local venv_count
    venv_count=$(find "${HOME}/.venvs" -maxdepth 2 -name 'activate' 2>/dev/null | wc -l)
    info "venvs:    ${venv_count} found under ~/.venvs"
  else
    hint "Tip: No ~/.venvs directory yet — use option v to create venvs"
  fi

  local gpu; gpu=$(detect_gpu)
  info "GPU:      ${gpu}"
  if [[ "${gpu}" == "nvidia" ]] && command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name,driver_version,memory.total \
      --format=csv,noheader 2>/dev/null | sed 's/^/            /' || true
  fi

  info "CPUs:     $(nproc) threads — $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
  local mem; mem=$(awk '/MemTotal/ {printf "%.1f GB", $2/1024/1024}' /proc/meminfo)
  info "RAM:      ${mem}"

  local mf; mf=$(grep '^MAKEFLAGS' /etc/makepkg.conf 2>/dev/null || echo "not set")
  info "MAKEFLAGS: ${mf}"

  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    ok "Active venv: ${VIRTUAL_ENV}"
  else
    hint "Tip: No active venv in current shell"
  fi
}

# ── Main menu ──────────────────────────────────────────────────────────────────
show_menu() {
  local w sep
  w=$(term_width)
  sep=$(printf '%*s' "${w}" '' | tr ' ' '=')
  printf '\n%b%s%b\n' "${C_HEAD}" "${sep}" "${C_RESET}"
  # B7 fix: title string as %s argument
  printf '  %b%b⚙  pyenv & Python Setup — Arch Linux%b\n' "${C_BOLD}" "${C_HEAD}" "${C_RESET}"
  printf '%b%s%b\n' "${C_HEAD}" "${sep}" "${C_RESET}"

  printf '\n  %b── Setup ───────────────────────────%b\n'       "${C_DIM}" "${C_RESET}"
  printf '  %b1)%b Check / install pip\n'                       "${C_OK}"  "${C_RESET}"
  printf '  %b2)%b Check build dependencies\n'                  "${C_OK}"  "${C_RESET}"
  printf '  %b3)%b Install pyenv\n'                             "${C_OK}"  "${C_RESET}"
  printf '  %b4)%b Configure shell init  (bash / zsh / fish)\n' "${C_OK}"  "${C_RESET}"
  printf '  %b5)%b Install Python version via pyenv\n'          "${C_OK}"  "${C_RESET}"

  printf '\n  %b── Optimisation ────────────────────%b\n'       "${C_DIM}"  "${C_RESET}"
  printf '  %b6)%b Optimise CPU build flags  (makepkg)\n'       "${C_INFO}" "${C_RESET}"
  printf '  %b7)%b Configure GPU  (AMD / NVIDIA autodetect)\n'  "${C_INFO}" "${C_RESET}"
  printf '  %b8)%b Tune system parameters  (sysctl / ulimits)\n' "${C_INFO}" "${C_RESET}"

  printf '\n  %b── Environments ────────────────────%b\n'       "${C_DIM}" "${C_RESET}"
  printf '  %bv)%b %bVirtual environment management%b  →\n'    "${C_SUB}" "${C_RESET}" "${C_BOLD}" "${C_RESET}"

  printf '\n  %b── Info / Misc ─────────────────────%b\n'       "${C_DIM}"  "${C_RESET}"
  printf '  %b9)%b Show current status\n'                       "${C_HINT}" "${C_RESET}"
  printf '  %ba)%b Run all setup steps  (1–8)\n'                "${C_WARN}" "${C_RESET}"
  printf '  %b0)%b Exit\n'                                      "${C_ERR}"  "${C_RESET}"

  printf '\n%b%s%b\n' "${C_HEAD}" "${sep}" "${C_RESET}"
  printf '  Choice: '
}

# ── Main ───────────────────────────────────────────────────────────────────────
main() {
  ensure_sudo

  while true; do
    show_menu
    local choice; read -r choice

    case "${choice}" in
      1) check_pip ;;
      2) check_build_deps ;;
      3) install_pyenv ;;
      4) configure_shell ;;
      5) install_python_version ;;
      6) configure_cpu ;;
      7) configure_gpu ;;
      8) configure_system ;;
      9) show_status ;;
      v|V) menu_venv ;;
      a|A)
        check_pip
        check_build_deps
        install_pyenv
        configure_shell
        configure_cpu
        configure_gpu
        configure_system
        echo ""
        ok "All setup steps completed"
        hint "Tip: Re-login or run 'source ~/.bashrc' / 'source ~/.zshrc' to activate changes"
        hint "Tip: Then use option v to create your first virtual environment"
        ;;
      0) info "Bye."; exit 0 ;;
      *) warn "Invalid choice: '${choice}'" ;;
    esac
  done
}

main "$@"
