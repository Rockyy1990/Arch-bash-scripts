#!/usr/bin/env bash
# =============================================================================
#  ArchSetup v2.3 — Post-Installation Setup Script
#  Plasma Desktop + Limine Bootloader
#  Getestet auf: Arch Linux (aktuell)
# =============================================================================
#
#  Module:
#   1) Chaotic AUR             9) Zsh + Oh-My-Zsh
#   2) Snapper + btrfs-asst.  10) Fish Shell
#   3) Druckunterstützung     11) OnlyOffice
#   4) Wine + Steam           12) NoMachine
#   5) ProtonUp-Qt            13) Teams for Linux
#   6) Virt-Manager / QEMU   14) Dev-Tools (interaktiv)
#   7) yt-dlp (GitHub)       15) Eigene Pakete (yay)
#   8) yay-bin
#
#  Verwendung: ./archsetup.sh [FLAG]
#  FLAGS: --chaotic --snapper --print --gaming --protonup --virt
#         --ytdlp --yay --zsh --fish --onlyoffice --nomachine --teams
#         --devtools --custom --all
# =============================================================================

set -uo pipefail

# ── Farben & Symbole ──────────────────────────────────────────────────────────
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'
readonly CHECK="${GREEN}✔${RESET}"
readonly CROSS="${RED}✘${RESET}"
readonly ARROW="${CYAN}→${RESET}"
readonly WARN_SYM="${YELLOW}⚠${RESET}"
readonly INFO_SYM="${BLUE}ℹ${RESET}"

# ── Ausgabe-Hilfsfunktionen ───────────────────────────────────────────────────
log()  { echo -e "${INFO_SYM}  ${BOLD}$*${RESET}"; }
ok()   { echo -e "${CHECK}  $*"; }
err()  { echo -e "${CROSS}  ${RED}$*${RESET}" >&2; }
warn() { echo -e "${WARN_SYM}  ${YELLOW}$*${RESET}"; }
step() { echo -e "
${ARROW}  ${BOLD}${CYAN}$*${RESET}"; }
sep()  { echo -e "${BLUE}$(printf '─%.0s' {1..62})${RESET}"; }
hint() { echo -e "   ${CYAN}$*${RESET}"; }

# ── Interaktive Ja/Nein-Abfrage ───────────────────────────────────────────────
frage() {
    local prompt="$1"          # FIX: war "\$1" — $1 wurde nie expandiert
    local antwort
    while true; do
        echo -en "${YELLOW}?${RESET}  ${BOLD}${prompt}${RESET} ${CYAN}[j/N]${RESET} "
        read -r antwort
        case "${antwort,,}" in
            j|ja|y|yes) return 0 ;;
            n|nein|no|'') return 1 ;;
            *) warn "Bitte j (Ja) oder n (Nein) eingeben." ;;
        esac
    done
}

# ── Paket-Installationsfunktionen ─────────────────────────────────────────────
pkg_install() {
    log "pacman: installiere $*"
    sudo pacman -S --needed --noconfirm "$@"
}

aur_install() {
    if ! has_yay; then
        err "yay ist nicht installiert! Modul 8 (yay-bin) zuerst ausführen."
        return 1
    fi
    log "AUR (yay): installiere $*"
    yay -S --needed --noconfirm "$@"
}

aur_or_chaotic() {
    if has_chaotic; then
        pkg_install "$@"
    elif has_yay; then
        aur_install "$@"
    else
        warn "$* konnte nicht installiert werden."
        warn "Bitte zuerst Modul 1 (Chaotic AUR) oder Modul 8 (yay-bin) einrichten."
        return 1
    fi
}

# ── Bedingungs-Helfer ─────────────────────────────────────────────────────────
# FIX: '$$..$$' → '$$..$$'  ($$ ist die PID in Bash, nicht ein Literal-Bracket)
has_chaotic()  { grep -q '^$$chaotic-aur$$' /etc/pacman.conf 2>/dev/null; }
has_yay()      { command -v yay &>/dev/null; }
has_multilib() { grep -q '^$$multilib$$'    /etc/pacman.conf 2>/dev/null; }

# ── Voraussetzungsprüfungen ───────────────────────────────────────────────────
require_no_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        err "Dieses Skript NICHT als root ausführen!"
        exit 1
    fi
}

check_internet() {
    step "Internetverbindung prüfen"
    if ping -c1 -W3 archlinux.org &>/dev/null; then
        ok "Internetverbindung vorhanden."
    else
        err "Keine Internetverbindung! Bitte zuerst Netzwerk einrichten."
        exit 1
    fi
}

enable_multilib() {
    if has_multilib; then
        return 0
    fi
    log "Aktiviere [multilib]-Repository in /etc/pacman.conf ..."
    # FIX: '/^#$$multilib$$/' → '/^#$$multilib$$/'
    sudo sed -i '/^#$$multilib$$/{s/^#//; n; s/^#//}' /etc/pacman.conf
    if has_multilib; then
        sudo pacman -Sy --noconfirm
        ok "Multilib aktiviert."
    else
        err "Multilib konnte nicht aktiviert werden. Bitte /etc/pacman.conf manuell prüfen."
        return 1
    fi
}

# =============================================================================
#  MODULE
# =============================================================================

# ── 1. Chaotic AUR ────────────────────────────────────────────────────────────
setup_chaotic_aur() {
    step "Chaotic AUR einrichten"
    sep

    if has_chaotic; then
        warn "Chaotic AUR ist bereits konfiguriert. Überspringe."
        return 0
    fi

    log "Importiere Chaotic-AUR Signaturschlüssel ..."
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB

    log "Installiere Chaotic-AUR Keyring und Mirrorlist ..."
    sudo pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
    sudo pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

    log "Füge [chaotic-aur]-Sektion zu /etc/pacman.conf hinzu ..."
    sudo tee -a /etc/pacman.conf > /dev/null <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF

    sudo pacman -Sy --noconfirm
    ok "Chaotic AUR erfolgreich eingerichtet."
}

# ── 2. Snapper + btrfs-assistant ─────────────────────────────────────────────
setup_snapper() {
    step "Snapper + btrfs-assistant einrichten"
    sep

    pkg_install snapper snap-pac
    aur_or_chaotic btrfs-assistant

    if [[ ! -f /etc/snapper/configs/root ]]; then
        log "Erstelle Snapper-Konfiguration für '/' ..."
        sudo umount /.snapshots 2>/dev/null || true
        sudo rm -rf /.snapshots
        sudo snapper -c root create-config /
        sudo btrfs subvolume delete /.snapshots 2>/dev/null || true
        sudo mkdir -p /.snapshots
        sudo mount -a 2>/dev/null \
            || warn "Automatisches Einbinden fehlgeschlagen. Bitte /.snapshots in /etc/fstab prüfen."
        sudo chmod 750 /.snapshots
    else
        warn "Snapper-Root-Konfiguration existiert bereits. Überspringe Erstellung."
    fi

    log "Aktiviere Snapper-Timer-Dienste ..."
    sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer

    ok "Snapper + btrfs-assistant eingerichtet."
    warn "Snapshot-Bootmenüeinträge für Limine müssen manuell"
    warn "in /boot/limine/limine.conf gepflegt werden (kein grub-btrfs)."
}

# ── 3. Druckunterstützung (CUPS) ──────────────────────────────────────────────
setup_print() {
    step "Druckunterstützung (CUPS) einrichten"
    sep

    pkg_install cups cups-pdf ghostscript gsfonts \
                system-config-printer print-manager

    frage "HP-Drucker vorhanden? (hplip installieren)" \
        && pkg_install hplip
    frage "Epson-Drucker vorhanden? (epson-inkjet-printer-escpr)" \
        && { aur_or_chaotic epson-inkjet-printer-escpr || warn "Epson-Treiber fehlgeschlagen."; }
    frage "Brother-Drucker vorhanden? (brlaser installieren)" \
        && { aur_or_chaotic brlaser || warn "brlaser fehlgeschlagen."; }
    frage "Canon-Drucker vorhanden? (cnijfilter2 installieren)" \
        && { aur_or_chaotic cnijfilter2 || warn "cnijfilter2 fehlgeschlagen."; }

    sudo systemctl enable --now cups.service
    ok "Druckunterstützung eingerichtet."
    hint "KDE: Systemeinstellungen → Drucker → Drucker hinzufügen"
}

# ── 4. Wine + Steam ───────────────────────────────────────────────────────────
setup_wine_steam() {
    step "Wine + Steam Gaming-Plattform einrichten"
    sep

    enable_multilib

    pkg_install wine-staging winetricks wine-mono wine-gecko \
                lib32-mesa lib32-vulkan-icd-loader \
                lib32-alsa-lib lib32-alsa-plugins lib32-libpulse \
                lib32-gnutls lib32-libldap lib32-libgpg-error
    pkg_install steam

    frage "Lutris installieren?"   && pkg_install lutris
    frage "Gamemode installieren?" && {
        pkg_install gamemode lib32-gamemode
        sudo usermod -aG gamemode "${USER}"
        warn "Gruppenänderung (gamemode) wird nach dem nächsten Login aktiv."
    }
    frage "MangoHud installieren?" && pkg_install mangohud lib32-mangohud

    ok "Wine + Steam eingerichtet."
}

# ── 5. ProtonUp-Qt ────────────────────────────────────────────────────────────
setup_protonup() {
    step "ProtonUp-Qt einrichten"
    sep
    enable_multilib
    aur_or_chaotic protonup-qt && ok "ProtonUp-Qt installiert."
    hint "Steam → Einstellungen → Steam Play → Proton-GE über ProtonUp-Qt verwalten."
}

# ── 6. Virt-Manager / QEMU / KVM ─────────────────────────────────────────────
setup_virt() {
    step "Virt-Manager / QEMU / KVM einrichten"
    sep

    grep -qE '(vmx|svm)' /proc/cpuinfo \
        || warn "CPU-Virtualisierung nicht erkannt – bitte im BIOS aktivieren."

    pkg_install virt-manager qemu-full libvirt \
                edk2-ovmf dnsmasq iptables-nft \
                virt-viewer bridge-utils

    sudo systemctl enable --now libvirtd.service
    sudo virsh net-autostart default 2>/dev/null || true
    sudo virsh net-start    default 2>/dev/null || true
    sudo usermod -aG libvirt,kvm "${USER}"

    if frage "IOMMU / PCI-Passthrough (Limine) konfigurieren?"; then
        warn "Kernel-Parameter in /boot/limine/limine.conf ergänzen:"
        hint "AMD:   amd_iommu=on iommu=pt"
        hint "Intel: intel_iommu=on iommu=pt"
    fi

    ok "Virt-Manager / QEMU eingerichtet."
    warn "Gruppenänderungen (libvirt, kvm) werden nach dem nächsten Login aktiv."
}

# ── 7. yt-dlp ─────────────────────────────────────────────────────────────────
setup_ytdlp() {
    step "yt-dlp installieren (aktuellste Binary von GitHub)"
    sep

    local bin_path="/usr/local/bin/yt-dlp"
    local api_url="https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
    local download_url

    download_url=$(
        curl -fsSL "${api_url}" \
            | grep '"browser_download_url"' \
            | grep '"/yt-dlp"' \
            | head -1 \
            | cut -d'"' -f4
    )
    [[ -z "${download_url}" ]] && \
        download_url="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"

    sudo curl -fsSL -o "${bin_path}" "${download_url}"
    sudo chmod a+rx "${bin_path}"
    pkg_install ffmpeg python-mutagen python-pycryptodome

    ok "yt-dlp $(yt-dlp --version 2>/dev/null || echo 'unbekannt') → ${bin_path}"

    sudo tee /usr/local/bin/yt-dlp-update > /dev/null <<'EOF'
#!/usr/bin/env bash
echo "Aktualisiere yt-dlp ..."
yt-dlp -U
EOF
    sudo chmod +x /usr/local/bin/yt-dlp-update
    ok "Update-Befehl verfügbar: yt-dlp-update"
}

# ── 8. yay-bin ────────────────────────────────────────────────────────────────
setup_yay() {
    step "yay-bin (AUR-Helper) installieren"
    sep

    if has_yay; then
        ok "yay ist bereits installiert: $(yay --version | head -1)"
        return 0
    fi

    pkg_install git base-devel

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '${tmpdir}'" RETURN

    git clone --depth=1 https://aur.archlinux.org/yay-bin.git "${tmpdir}/yay-bin"
    (cd "${tmpdir}/yay-bin" && makepkg -si --noconfirm)

    has_yay \
        && ok "yay erfolgreich installiert: $(yay --version | head -1)" \
        || { err "yay-Installation fehlgeschlagen."; return 1; }
}

# ── 9. Zsh + Oh-My-Zsh ────────────────────────────────────────────────────────
setup_zsh() {
    step "Zsh als Standard-Shell einrichten"
    sep

    pkg_install zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting

    local zshrc="${HOME}/.zshrc"
    local omz_installed=false

    if frage "Oh-My-Zsh installieren?"; then
        if [[ -d "${HOME}/.oh-my-zsh" ]]; then
            warn "Oh-My-Zsh ist bereits installiert."
            omz_installed=true
        else
            RUNZSH=no CHSH=no \
                sh -c "$(curl -fsSL \
                    https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
                -- --unattended
            omz_installed=true
            ok "Oh-My-Zsh installiert."
        fi

        if [[ "${omz_installed}" == true ]] && frage "Powerlevel10k Theme installieren?"; then
            local p10k_dir="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}/themes/powerlevel10k"
            if [[ ! -d "${p10k_dir}" ]]; then
                git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${p10k_dir}"
                sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "${zshrc}"
                ok "Powerlevel10k installiert."
            else
                warn "Powerlevel10k ist bereits installiert."
            fi
        fi
    fi

    frage "Nerd Fonts (ttf-jetbrains-mono-nerd) installieren?" \
        && { aur_or_chaotic ttf-jetbrains-mono-nerd || warn "Nerd Fonts fehlgeschlagen."; }

    if [[ -f "${zshrc}" ]]; then
        grep -q 'zsh-autosuggestions.zsh' "${zshrc}" \
            || echo 'source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' \
               >> "${zshrc}"
        grep -q 'zsh-syntax-highlighting.zsh' "${zshrc}" \
            || echo 'source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' \
               >> "${zshrc}"
    fi

    chsh -s "$(command -v zsh)" "${USER}"
    ok "Zsh ist jetzt Standard-Shell."
}

# ── 10. Fish Shell ────────────────────────────────────────────────────────────
setup_fish() {
    step "Fish Shell als Standard-Shell einrichten"
    sep

    pkg_install fish

    if frage "fisher (Plugin-Manager) installieren?"; then
        fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish \
                | source && fisher install jorgebucaran/fisher" \
            && ok "fisher installiert." \
            || warn "fisher fehlgeschlagen."

        frage "Tide Prompt installieren?" \
            && { fish -c "fisher install IlanCosman/tide@v6" \
                && ok "Tide installiert." || warn "Tide fehlgeschlagen."; }

        frage "z (Directory-Jumper) installieren?" \
            && { fish -c "fisher install jethrokuan/z" \
                && ok "z installiert." || warn "z fehlgeschlagen."; }
    fi

    frage "Nerd Fonts (ttf-jetbrains-mono-nerd) installieren?" \
        && { aur_or_chaotic ttf-jetbrains-mono-nerd || warn "Nerd Fonts fehlgeschlagen."; }

    chsh -s "$(command -v fish)" "${USER}"
    ok "Fish ist jetzt Standard-Shell."
    hint "Konfiguration: ~/.config/fish/config.fish"
}

# ── 11. OnlyOffice ────────────────────────────────────────────────────────────
setup_onlyoffice() {
    step "OnlyOffice Desktop Editors installieren"
    sep
    aur_or_chaotic onlyoffice-bin && ok "OnlyOffice installiert."
}

# ── 12. NoMachine ─────────────────────────────────────────────────────────────
setup_nomachine() {
    step "NoMachine (Remote Desktop) installieren"
    sep
    if aur_or_chaotic nomachine; then
        sudo systemctl enable --now nxserver.service 2>/dev/null \
            || warn "nxserver.service konnte nicht gestartet werden."
        ok "NoMachine installiert."
        hint "Standard-Port: 4000 | Firewall: sudo ufw allow 4000/tcp"
    fi
}

# ── 13. Teams for Linux ───────────────────────────────────────────────────────
setup_teams() {
    step "Teams for Linux installieren"
    sep
    warn "Inoffizieller, community-gepflegter Electron-Client."
    aur_or_chaotic teams-for-linux-bin && ok "Teams for Linux installiert."
    hint "Projektseite: https://github.com/IsmaelMartinez/teams-for-linux"
}

# ── 14. Dev-Tools ─────────────────────────────────────────────────────────────
setup_devtools() {
    step "Dev-Tools — Entwicklerwerkzeuge einrichten"
    sep

    if ! has_yay; then
        err "yay ist nicht installiert!"
        warn "Bitte zuerst Modul 8 (yay-bin) ausführen."
        return 1
    fi

    # ── Vordefinierte Paketgruppen ────────────────────────────────────────────
    declare -A DEV_GROUPS=(
        ["Basis-Tools (git, base-devel, make, cmake)"]="git base-devel make cmake"
        ["Editoren (neovim, vim, nano)"]="neovim vim nano"
        ["VSCode (code, AUR)"]="visual-studio-code-bin"
        ["Python (python, pip, venv, ipython)"]="python python-pip python-virtualenv ipython"
        ["Node.js + npm + yarn"]="nodejs npm yarn"
        ["Rust (rustup)"]="rustup"
        ["Go (golang)"]="go"
        ["Java (JDK 21 + maven + gradle)"]="jdk21-openjdk maven gradle"
        ["Docker + Docker Compose"]="docker docker-compose"
        ["Podman + Buildah"]="podman buildah"
        ["Datenbanken (postgresql, mariadb, sqlite)"]="postgresql mariadb sqlite"
        ["Netzwerk-Tools (curl, wget, httpie, nmap, netcat)"]="curl wget python-httpie nmap gnu-netcat"
        ["API-Tools (insomnia-bin, postman-bin, AUR)"]="insomnia-bin postman-bin"
        ["Terminal-Tools (tmux, screen, htop, btop, fzf, ripgrep, bat, eza)"]="tmux screen htop btop fzf ripgrep bat eza"
        ["Git-Extras (lazygit, git-delta, tig)"]="lazygit git-delta tig"
        ["Hex-Editor + Debugger (hexyl, gdb, lldb, strace)"]="hexyl gdb lldb strace"
        ["Container-Orchestrierung (kubectl, helm, k9s, AUR)"]="kubectl helm k9s"
        ["Terraform + Ansible"]="terraform ansible"
        ["Lua + LuaRocks"]="lua luarocks"
        ["PHP + Composer"]="php composer"
    )

    # Schlüssel sortiert laden
    local -a group_keys
    mapfile -t group_keys < <(printf '%s
' "${!DEV_GROUPS[@]}" | sort)

    # ── Gruppenauswahl anzeigen ───────────────────────────────────────────────
    echo -e "
${BOLD}${CYAN}Verfügbare Paketgruppen:${RESET}
"
    local i=1
    for key in "${group_keys[@]}"; do
        printf "  ${CYAN}%2d)${RESET}  %s
" "${i}" "${key}"
        (( i++ ))
    done

    sep
    echo -e "  ${CYAN} a)${RESET}  ${BOLD}Alle Gruppen installieren${RESET}"
    echo -e "  ${CYAN} 0)${RESET}  Abbrechen"
    sep

    echo -e "${YELLOW}?${RESET}  ${BOLD}Gruppen wählen${RESET} ${CYAN}(z.B. 1 3 5 | a | 0):${RESET} "
    echo -en "  → "
    read -r raw_input

    case "${raw_input,,}" in
        0)
            warn "Dev-Tools Einrichtung abgebrochen."
            return 0
            ;;
        a|all)
            log "Installiere alle Paketgruppen ..."
            for key in "${group_keys[@]}"; do
                step "${key}"
                # shellcheck disable=SC2086
                yay -S --needed --noconfirm ${DEV_GROUPS["${key}"]} \
                    || warn "Fehler bei: ${key}"
            done
            ;;
        *)
            local -a selected_keys=()
            local num

            for num in ${raw_input}; do
                if ! [[ "${num}" =~ ^[0-9]+$ ]]; then
                    warn "Ungültige Eingabe ignoriert: '${num}'"
                    continue
                fi
                local idx=$(( num - 1 ))
                if (( idx >= 0 && idx < ${#group_keys[@]} )); then
                    selected_keys+=( "${group_keys[${idx}]}" )
                else
                    warn "Nummer außerhalb des Bereichs ignoriert: ${num}"
                fi
            done

            if [[ ${#selected_keys[@]} -eq 0 ]]; then
                warn "Keine gültigen Gruppen ausgewählt."
                return 0
            fi

            echo -e "
${BOLD}Ausgewählte Gruppen:${RESET}"
            for key in "${selected_keys[@]}"; do
                echo -e "  ${CHECK}  ${key}"
            done
            echo

            if frage "Installation starten?"; then
                for key in "${selected_keys[@]}"; do
                    step "Installiere: ${key}"
                    # shellcheck disable=SC2086
                    yay -S --needed --noconfirm ${DEV_GROUPS["${key}"]} \
                        || warn "Fehler bei: ${key}"
                done
            else
                warn "Installation abgebrochen."
                return 0
            fi
            ;;
    esac

    # ── Docker-Dienst & Gruppe ────────────────────────────────────────────────
    if command -v docker &>/dev/null; then
        if ! groups "${USER}" | grep -q '\bdocker\b'; then
            log "Füge '${USER}' zur Gruppe 'docker' hinzu ..."
            sudo usermod -aG docker "${USER}"
            warn "Docker-Gruppenänderung wird nach dem nächsten Login aktiv."
        fi
        if ! systemctl is-enabled docker.service &>/dev/null; then
            log "Aktiviere Docker-Dienst ..."
            sudo systemctl enable --now docker.service
        fi
    fi

    # ── Rust-Toolchain initialisieren ─────────────────────────────────────────
    if command -v rustup &>/dev/null && [[ ! -d "${HOME}/.rustup/toolchains" ]]; then
        log "Initialisiere Rust stable Toolchain via rustup ..."
        rustup default stable
        ok "Rust stable Toolchain installiert."
    fi

    sep
    ok "Dev-Tools Einrichtung abgeschlossen!"
    hint "Tipp: 'yay -Ss <Suchbegriff>' zum Suchen weiterer Pakete."
    hint "Tipp: 'yay -Syu' hält alle Pakete (inkl. AUR) aktuell."
}

# ── 15. Eigene Pakete (yay) ───────────────────────────────────────────────────
setup_custom_packages() {
    step "Eigene Pakete via yay installieren"
    sep

    if ! has_yay; then
        err "yay ist nicht installiert!"
        warn "Bitte zuerst Modul 8 (yay-bin) ausführen."
        return 1
    fi

    echo -e "
${BOLD}${CYAN}Eigene Pakete via yay installieren${RESET}"
    sep
    echo -e "${CYAN}Tipp:${RESET} Mehrere Pakete mit Leerzeichen trennen."
    echo -e "${CYAN}Tipp:${RESET} Leere Eingabe → zurück zum Menü.\n"

    while true; do
        echo -en "${YELLOW}?${RESET}  ${BOLD}Paketname(n) eingeben${RESET} ${CYAN}(oder Enter zum Beenden):${RESET} "
        read -r custom_input

        # Leere Eingabe = fertig
        [[ -z "${custom_input}" ]] && break

        # Pakete in Array aufteilen
        read -ra custom_pkgs <<< "${custom_input}"

        echo -e "
${BOLD}Suche in Repositories & AUR:${RESET}"
        sep

        # Jedes Paket einzeln suchen und Treffer anzeigen
        local pkg
        for pkg in "${custom_pkgs[@]}"; do
            echo -e "
${CYAN}── Suchergebnisse für: ${BOLD}${pkg}${RESET}"
            yay -Ss "${pkg}" 2>/dev/null | head -20 \
                || warn "Keine Treffer für '${pkg}' gefunden."
        done

        sep
        if frage "Diese Pakete installieren: ${BOLD}${custom_pkgs[*]}${RESET}?"; then
            yay -S --needed --noconfirm "${custom_pkgs[@]}" \
                && ok "Pakete installiert: ${custom_pkgs[*]}" \
                || warn "Installation teilweise fehlgeschlagen. Bitte Ausgabe prüfen."
        else
            warn "Installation übersprungen."
        fi

        echo
    done

    ok "Eigene Pakete abgeschlossen."
}

# =============================================================================
#  HAUPT-MENÜ
# =============================================================================

print_banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║      ArchSetup v2.3 — Post-Installation Configurator         ║"
    echo "  ║             Plasma Desktop  ·  Limine Bootloader             ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    printf "${BOLD}Benutzer:${RESET} ${CYAN}%-14s${RESET}  " "${USER}"
    printf "${BOLD}Kernel:${RESET} ${CYAN}%s${RESET}
" "$(uname -r)"
    sep
}

print_menu() {
    echo -e "
  ${BOLD}Was soll eingerichtet werden?${RESET}
"
    echo -e "  ${CYAN} 1)${RESET}  Chaotic AUR                    ${BLUE}(Drittanbieter-Repository)${RESET}"
    echo -e "  ${CYAN} 2)${RESET}  Snapper + btrfs-assistant      ${BLUE}(BTRFS Snapshots)${RESET}"
    echo -e "  ${CYAN} 3)${RESET}  Druckunterstützung             ${BLUE}(CUPS + Treiber)${RESET}"
    echo -e "  ${CYAN} 4)${RESET}  Wine + Steam                   ${BLUE}(Gaming-Plattform)${RESET}"
    echo -e "  ${CYAN} 5)${RESET}  ProtonUp-Qt                    ${BLUE}(Proton-GE / Wine-GE Verwaltung)${RESET}"
    echo -e "  ${CYAN} 6)${RESET}  Virt-Manager / QEMU            ${BLUE}(Virtualisierung + KVM)${RESET}"
    echo -e "  ${CYAN} 7)${RESET}  yt-dlp                         ${BLUE}(aktuellste Binary von GitHub)${RESET}"
    echo -e "  ${CYAN} 8)${RESET}  yay-bin                        ${BLUE}(AUR-Helper)${RESET}"
    echo -e "  ${CYAN} 9)${RESET}  Zsh                            ${BLUE}(Standard-Shell + Oh-My-Zsh)${RESET}"
    echo -e "  ${CYAN}10)${RESET}  Fish Shell                     ${BLUE}(Standard-Shell + fisher)${RESET}"
    echo -e "  ${CYAN}11)${RESET}  OnlyOffice                     ${BLUE}(Office-Suite, AUR)${RESET}"
    echo -e "  ${CYAN}12)${RESET}  NoMachine                      ${BLUE}(Remote Desktop, AUR)${RESET}"
    echo -e "  ${CYAN}13)${RESET}  Teams for Linux                ${BLUE}(Inoffizieller Teams-Client, AUR)${RESET}"
    echo -e "  ${CYAN}14)${RESET}  Dev-Tools                      ${BLUE}(Entwicklerwerkzeuge, interaktiv)${RESET}"
    echo -e "  ${CYAN}15)${RESET}  Eigene Pakete                  ${BLUE}(Freie Paketauswahl via yay)${RESET}"
    echo
    sep
    echo -e "  ${CYAN} a)${RESET}  ${BOLD}Alle Module${RESET} der Reihe nach ausführen"
    echo -e "  ${CYAN} 0)${RESET}  Beenden"
    echo
}

# Alle verfügbaren Modul-Nummern
readonly -a ALL_MODULES=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)

run_module() {
    local num
    num="${1}"
    case "${num}" in
        1)  setup_chaotic_aur      ;;
        2)  setup_snapper          ;;
        3)  setup_print            ;;
        4)  setup_wine_steam       ;;
        5)  setup_protonup         ;;
        6)  setup_virt             ;;
        7)  setup_ytdlp            ;;
        8)  setup_yay              ;;
        9)  setup_zsh              ;;
        10) setup_fish             ;;
        11) setup_onlyoffice       ;;
        12) setup_nomachine        ;;
        13) setup_teams            ;;
        14) setup_devtools         ;;
        15) setup_custom_packages  ;;
        *)  warn "Unbekannte Modul-Nummer: ${num}" ;;
    esac
}

run_all_modules() {
    print_banner
    log "Starte alle ${#ALL_MODULES[@]} Module ..."
    local num
    for num in "${ALL_MODULES[@]}"; do
        sep
        run_module "${num}"
    done
    sep
    ok "Alle Module abgeschlossen!"
    warn "Bitte neu anmelden, damit alle Gruppenänderungen wirksam werden."
}

interactive_menu() {
    local auswahl
    while true; do
        print_banner
        print_menu

        echo -en "  ${BOLD}Auswahl${RESET} [0-15 / a]: "
        read -r auswahl

        case "${auswahl}" in
            0)
                echo -e "
${GREEN}  Auf Wiedersehen! Viel Spaß mit Arch Linux.${RESET}\n"
                exit 0
                ;;
            a|A|all)
                run_all_modules
                echo -en "
Zurück zum Menü mit Enter ..."
                read -r
                ;;
            1|2|3|4|5|6|7|8|9|10|11|12|13|14|15)
                print_banner
                run_module "${auswahl}"
                echo -en "
Zurück zum Menü mit Enter ..."
                read -r
                ;;
            '')
                ;;
            *)
                warn "Ungültige Eingabe: '${auswahl}' – Bitte 0–15 oder 'a' eingeben."
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
#  EINSTIEGSPUNKT
# =============================================================================

usage() {
    cat <<'EOF'
Verwendung: \$0 [FLAG]

Flags:
  --chaotic     Chaotic AUR einrichten
  --snapper     Snapper + btrfs-assistant
  --print       Druckunterstützung (CUPS)
  --gaming      Wine + Steam
  --protonup    ProtonUp-Qt
  --virt        Virt-Manager / QEMU / KVM
  --ytdlp       yt-dlp (GitHub Binary)
  --yay         yay-bin (AUR-Helper)
  --zsh         Zsh + Oh-My-Zsh
  --fish        Fish Shell + fisher
  --onlyoffice  OnlyOffice Desktop Editors
  --nomachine   NoMachine Remote Desktop
  --teams       Teams for Linux
  --devtools    Dev-Tools (Entwicklerwerkzeuge, interaktiv)
  --custom      Eigene Pakete via yay installieren
  --all         Alle Module nacheinander ausführen
  --help | -h   Diese Hilfe anzeigen

Ohne Flag: Interaktives Menü starten
EOF
}

main() {
    require_no_root
    check_internet

    if [[ $# -gt 0 ]]; then
        case "\$1" in                    # FIX: war "\\$1" — \$1 wurde nie expandiert
            --chaotic)    setup_chaotic_aur     ;;
            --snapper)    setup_snapper         ;;
            --print)      setup_print           ;;
            --gaming)     setup_wine_steam      ;;
            --protonup)   setup_protonup        ;;
            --virt)       setup_virt            ;;
            --ytdlp)      setup_ytdlp           ;;
            --yay)        setup_yay             ;;
            --zsh)        setup_zsh             ;;
            --fish)       setup_fish            ;;
            --onlyoffice) setup_onlyoffice      ;;
            --nomachine)  setup_nomachine       ;;
            --teams)      setup_teams           ;;
            --devtools)   setup_devtools        ;;
            --custom)     setup_custom_packages ;;
            --all)        run_all_modules       ;;
            --help|-h)    usage                 ;;
            *)
                err "Unbekannter Parameter: '\$1'"
                usage
                exit 1
                ;;
        esac
    else
        interactive_menu
    fi
}

main "$@"
