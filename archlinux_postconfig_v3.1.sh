#!/usr/bin/env bash
# =============================================================================
#  ArchSetup v2.5 — Post-Installation Setup Script
#  Plasma Desktop + Limine Bootloader
#  Getestet auf: Arch Linux (aktuell)
# =============================================================================
#
#  Module:
#   1) Chaotic AUR             11) OnlyOffice
#   2) Snapper + btrfs-asst.  12) NoMachine
#   3) Druckunterstützung     13) Teams for Linux
#   4) Wine + Steam           14) UFW Firewall
#   5) ProtonUp-Qt            15) Dev-Tools (interaktiv)
#   6) Virt-Manager / QEMU   16) Arch Sys Management
#   7) yt-dlp (GitHub)       17) Vivaldi + ffmpeg-Codecs
#   8) yay-bin               18) System-Tweaks
#   9) Zsh + Oh-My-Zsh       19) Eigene Pakete (yay)
#  10) Fish Shell            20) GPU-Treiber (AMD/NVIDIA/Intel)
#
#  Verwendung: ./archsetup.sh [FLAG]
#  FLAGS: --chaotic --snapper --print --gaming --protonup --virt
#         --ytdlp --yay --zsh --fish --onlyoffice --nomachine --teams
#         --ufw --devtools --sysmanage --vivaldi --tweaks --custom
#         --drivers --all
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
# BUGFIX: Vorher '$$chaotic-aur$$' / '$$multilib$$' — $$ ist die PID in Bash!
#         Korrekt: grep nach literal '[chaotic-aur]' / '[multilib]'
has_chaotic()  { grep -q '^\[chaotic-aur\]' /etc/pacman.conf 2>/dev/null; }
has_yay()      { command -v yay &>/dev/null; }
has_multilib() { grep -q '^\[multilib\]'    /etc/pacman.conf 2>/dev/null; }

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
    # BUGFIX: Vorher '/^#$$multilib$$/' — $$ ist PID. Korrekt: literal '[multilib]'
    sudo sed -i '/^#\[multilib\]/{s/^#//; n; s/^#//}' /etc/pacman.conf
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
                lib32-gnutls lib32-libldap lib32-libgpg-error \
                vkd3d libgdiplus protontricks
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

    pkg_install libvirt libvirt-python virt-manager qemu-full \
                qemu-guest-agent libguestfs vde2 swtpm dnsmasq dmidecode

    echo "Activate libvirt.."
    sudo systemctl enable --now libvirtd.service virtlogd.service
    sudo virsh net-autostart default
    sudo virsh net-start default
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
    pkg_install ffmpeg deno python-mutagen python-pycryptodome

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

    local zsh_bin
    zsh_bin="$(command -v zsh)"

    # ── /etc/shells sicherstellen ─────────────────────────────────────────────
    if ! grep -qx "${zsh_bin}" /etc/shells; then
        log "Trage zsh in /etc/shells ein ..."
        echo "${zsh_bin}" | sudo tee -a /etc/shells > /dev/null
        ok "zsh in /etc/shells eingetragen."
    fi

    local zshrc="${HOME}/.zshrc"
    local zprofile="${HOME}/.zprofile"
    local omz_installed=false

    # ── .zshrc anlegen falls nicht vorhanden ──────────────────────────────────
    if [[ ! -f "${zshrc}" ]]; then
        log "Erstelle minimale ~/.zshrc ..."
        cat > "${zshrc}" <<'ZSHRC_EOF'
# ~/.zshrc — Zsh Konfiguration (erstellt von ArchSetup)

# Verlauf
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory sharehistory histignorealldups

# Completion
autoload -Uz compinit && compinit

# Prompt (Standard, wird von Oh-My-Zsh / Powerlevel10k überschrieben)
autoload -Uz promptinit && promptinit
prompt walters

# Aliases
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'
alias ip='ip --color=auto'
ZSHRC_EOF
        ok "~/.zshrc erstellt."
    fi

    # ── .zprofile für Login-Shells ────────────────────────────────────────────
    if [[ ! -f "${zprofile}" ]]; then
        log "Erstelle ~/.zprofile für Login-Shell-Umgebung ..."
        cat > "${zprofile}" <<'ZPRO_EOF'
# ~/.zprofile — wird von Login-Shells geladen (Entspricht .bash_profile)
# Umgebungsvariablen und PATH hier eintragen.

# Beispiel: eigene Binaries
# export PATH="${HOME}/.local/bin:${PATH}"
ZPRO_EOF
        ok "~/.zprofile erstellt."
    fi

    # ── Oh-My-Zsh ─────────────────────────────────────────────────────────────
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

    # ── Plugins in .zshrc eintragen ───────────────────────────────────────────
    grep -q 'zsh-autosuggestions.zsh' "${zshrc}" \
        || echo 'source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' \
           >> "${zshrc}"
    grep -q 'zsh-syntax-highlighting.zsh' "${zshrc}" \
        || echo 'source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' \
           >> "${zshrc}"

    # ── Nerd Fonts ────────────────────────────────────────────────────────────
    frage "Nerd Fonts (ttf-jetbrains-mono-nerd) installieren?" \
        && { aur_or_chaotic ttf-jetbrains-mono-nerd || warn "Nerd Fonts fehlgeschlagen."; }

    # ── Standard-Shell setzen ─────────────────────────────────────────────────
    if chsh -s "${zsh_bin}" "${USER}"; then
        ok "Zsh ist jetzt Standard-Shell für '${USER}'."
    else
        err "chsh fehlgeschlagen! Manuell ausführen: chsh -s ${zsh_bin}"
    fi

    warn "Bash-Konfiguration nicht automatisch migriert."
    hint "Aliases und PATH-Ergänzungen aus ~/.bashrc manuell in ~/.zshrc übertragen."
    hint "Login-Variablen (z.B. PATH) gehören in ~/.zprofile."
    hint "Änderungen wirken nach dem nächsten Login."
}

# ── 10. Fish Shell ────────────────────────────────────────────────────────────
setup_fish() {
    step "Fish Shell als Standard-Shell einrichten"
    sep

    pkg_install fish

    local fish_bin
    fish_bin="$(command -v fish)"

    # ── /etc/shells sicherstellen ─────────────────────────────────────────────
    if ! grep -qx "${fish_bin}" /etc/shells; then
        log "Trage fish in /etc/shells ein ..."
        echo "${fish_bin}" | sudo tee -a /etc/shells > /dev/null
        ok "fish in /etc/shells eingetragen."
    fi

    # ── Konfigurationsverzeichnis und config.fish anlegen ─────────────────────
    local fish_conf_dir="${HOME}/.config/fish"
    local fish_conf="${fish_conf_dir}/config.fish"

    mkdir -p "${fish_conf_dir}"

    if [[ ! -f "${fish_conf}" ]]; then
        log "Erstelle minimale ~/.config/fish/config.fish ..."
        cat > "${fish_conf}" <<'FISH_EOF'
# ~/.config/fish/config.fish — Fish Konfiguration (erstellt von ArchSetup)

# Umgebungsvariablen (Beispiel)
# set -gx PATH $HOME/.local/bin $PATH

# Aliases
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'

# Farbiged Prompt-Greeting deaktivieren (optional)
# set -g fish_greeting ""
FISH_EOF
        ok "~/.config/fish/config.fish erstellt."
    fi

    # ── fisher (Plugin-Manager) ───────────────────────────────────────────────
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

        frage "fzf.fish (Fuzzy Finder Integration) installieren?" \
            && { pkg_install fzf
                 fish -c "fisher install PatrickF1/fzf.fish" \
                && ok "fzf.fish installiert." || warn "fzf.fish fehlgeschlagen."; }
    fi

    # ── Nerd Fonts ────────────────────────────────────────────────────────────
    frage "Nerd Fonts (ttf-jetbrains-mono-nerd) installieren?" \
        && { aur_or_chaotic ttf-jetbrains-mono-nerd || warn "Nerd Fonts fehlgeschlagen."; }

    # ── Standard-Shell setzen ─────────────────────────────────────────────────
    if chsh -s "${fish_bin}" "${USER}"; then
        ok "Fish ist jetzt Standard-Shell für '${USER}'."
    else
        err "chsh fehlgeschlagen! Manuell ausführen: chsh -s ${fish_bin}"
    fi

    warn "Bash-Konfiguration nicht automatisch migriert."
    hint "Fish verwendet eine andere Syntax als Bash — .bashrc-Aliases manuell"
    hint "in ~/.config/fish/config.fish übertragen (kein 'export', sondern 'set -gx')."
    hint "Änderungen wirken nach dem nächsten Login."
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

# ── 14. UFW Firewall ──────────────────────────────────────────────────────────
setup_ufw() {
    step "UFW Firewall einrichten"
    sep

    pkg_install ufw

    log "Setze Standard-Policies: deny incoming / allow outgoing ..."
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    ok "Standard-Policies gesetzt."
    sep

    # ── SSH ───────────────────────────────────────────────────────────────────
    if frage "SSH (Port 22/tcp + 22/udp) erlauben?"; then
        sudo ufw allow 22/tcp comment "SSH"
        sudo ufw allow 22/udp comment "SSH"
        ok "SSH-Regeln hinzugefügt."
        frage "SSH Rate Limiting aktivieren? (Schutz gegen Brute-Force)" && {
            sudo ufw limit 22/tcp comment "SSH Rate Limit"
            sudo ufw limit 22/udp comment "SSH Rate Limit (UDP)"
            ok "SSH Rate Limiting aktiviert."
        }
    fi

    # ── DNS ───────────────────────────────────────────────────────────────────
    if frage "DNS (Port 53/tcp + 53/udp) erlauben?"; then
        sudo ufw allow 53/tcp comment "DNS"
        sudo ufw allow 53/udp comment "DNS"
        ok "DNS-Regeln hinzugefügt."
        frage "DNS Rate Limiting aktivieren? (Port 53/udp)" && {
            sudo ufw limit 53/udp comment "DNS Rate Limit"
            ok "DNS Rate Limiting aktiviert."
        }
    fi

    # ── HTTP ──────────────────────────────────────────────────────────────────
    if frage "HTTP (Port 80/tcp) erlauben?"; then
        sudo ufw allow 80/tcp comment "HTTP"
        ok "HTTP-Regel hinzugefügt."
        frage "HTTP Rate Limiting aktivieren?" && {
            sudo ufw limit 80/tcp comment "HTTP Rate Limit"
            ok "HTTP Rate Limiting aktiviert."
        }
    fi

    # ── HTTPS ─────────────────────────────────────────────────────────────────
    if frage "HTTPS (Port 443/tcp) erlauben?"; then
        sudo ufw allow 443/tcp comment "HTTPS"
        ok "HTTPS-Regel hinzugefügt."
        frage "HTTPS Rate Limiting aktivieren?" && {
            sudo ufw limit 443/tcp comment "HTTPS Rate Limit"
            ok "HTTPS Rate Limiting aktiviert."
        }
    fi

    # ── Samba ─────────────────────────────────────────────────────────────────
    if frage "Samba (Port 139/tcp + 445/tcp) erlauben?"; then
        sudo ufw allow 139/tcp comment "Samba"
        sudo ufw allow 445/tcp comment "Samba"
        ok "Samba-Regeln hinzugefügt."
    fi

    # ── NoMachine ─────────────────────────────────────────────────────────────
    if frage "NoMachine (Port 4000/tcp) erlauben?"; then
        sudo ufw allow 4000/tcp comment "Nomachine"
        ok "NoMachine-Regel hinzugefügt."
        frage "NoMachine Rate Limiting aktivieren?" && {
            sudo ufw limit 4000/tcp comment "Nomachine Rate Limit"
            ok "NoMachine Rate Limiting aktiviert."
        }
    fi

    sep

    # ── Logging ───────────────────────────────────────────────────────────────
    if frage "UFW Logging aktivieren? (Stufe: medium)"; then
        sudo ufw logging on
        sudo ufw logging medium
        ok "UFW Logging aktiviert (medium)."
    fi

    sep

    if frage "UFW jetzt aktivieren? ${YELLOW}(Achtung: aktive SSH-Verbindung vorher prüfen!)${RESET}"; then
        sudo ufw enable
        ok "UFW ist jetzt aktiv."
    else
        warn "UFW wurde NICHT aktiviert."
        hint "Manuell aktivieren: sudo ufw enable"
    fi

    echo
    sudo ufw status verbose || true
    ok "UFW-Einrichtung abgeschlossen."
    hint "Regeln anzeigen:    sudo ufw status numbered"
    hint "UFW deaktivieren:   sudo ufw disable"
    hint "Regel entfernen:    sudo ufw delete <Nummer>"
}

# ── 15. Dev-Tools ─────────────────────────────────────────────────────────────
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

# ── 16. Arch System Management Script ────────────────────────────────────────
setup_arch_sys_management() {
    step "Arch System Management Script auf Desktop installieren"
    sep

    local script_path="${HOME}/Schreibtisch/arch_sys_management.py"

    if [[ ! -d "${HOME}/Schreibtisch" ]]; then
        warn "Verzeichnis ~/Schreibtisch nicht gefunden (kein deutsches KDE-Desktop-Verzeichnis?)."
        frage "Skript stattdessen im Home-Verzeichnis ablegen?" \
            || { warn "Arch System Management Script übersprungen."; return 0; }
        script_path="${HOME}/arch_sys_management.py"
    fi

    log "Schreibe ${script_path} ..."

    tee "${script_path}" > /dev/null <<'EOF'
#!/usr/bin/env python3

import os
import subprocess
import sys

# ── Farben ────────────────────────────────────────────────────────────────────
ORANGE = '\033[38;5;208m'
BLUE   = '\033[34m'
GREEN  = '\033[32m'
RED    = '\033[31m'
BOLD   = '\033[1m'
RESET  = '\033[0m'

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────
def clear_screen():
    os.system('clear')

def print_menu():
    clear_screen()
    border = f"{ORANGE}{'═'*52}{RESET}"
    print(border)
    print(f"{ORANGE}{BOLD}{'ARCH LINUX SYSTEM MANAGEMENT':^52}{RESET}")
    print(border)
    entries = [
        ("1", "System Upgrade"),
        ("2", "System Upgrade mit YAY"),
        ("3", "Pacman Cache leeren"),
        ("4", "Arch Linux Keyring erneuern"),
        ("5", "Pacman Datenbank aktualisieren"),
        ("6", "Verwaiste Pakete entfernen"),   # NEU
        ("7", "Systemdienste auf Fehler prüfen"),  # NEU
        ("8", "Beenden"),
    ]
    for num, label in entries:
        print(f"  {ORANGE}{num}.{RESET}  {label}")
    print()

def success_message():
    print(f"\n{GREEN}✔ Erfolgreich ausgeführt!{RESET}\n")
    input("Drücke Enter zum Fortfahren...")

def error_message(msg: str):
    print(f"\n{RED}✘ Fehler: {msg}{RESET}\n")
    input("Drücke Enter zum Fortfahren...")

def confirm(prompt: str) -> bool:
    """Gibt True zurück wenn der Nutzer mit 'j' oder 'J' bestätigt."""
    answer = input(f"{ORANGE}{prompt} [j/N]: {RESET}").strip().lower()
    return answer == 'j'

def execute_command(command: str, description: str, require_confirm: bool = False):
    """Führt einen Shell-Befehl aus und gibt Erfolg/Fehler aus."""
    print(f"\n{ORANGE}▶ {description}{RESET}")
    print(f"  {BOLD}Befehl:{RESET} {command}\n")

    if require_confirm and not confirm("Wirklich fortfahren?"):
        print(f"{BLUE}Abgebrochen.{RESET}")
        input("Drücke Enter zum Fortfahren...")
        return

    try:
        subprocess.run(command, shell=True, check=True)
        success_message()
    except subprocess.CalledProcessError as e:
        error_message(str(e))
    except Exception as e:
        error_message(str(e))

# ── Neue Funktion 1: Verwaiste Pakete entfernen ───────────────────────────────
def remove_orphans():
    """
    Listet verwaiste Pakete (als Abhängigkeit installiert, aber nicht mehr
    benötigt) und entfernt sie nach Bestätigung.
    """
    print(f"\n{ORANGE}▶ Verwaiste Pakete suchen...{RESET}\n")
    try:
        result = subprocess.run(
            'pacman -Qtdq',
            shell=True, capture_output=True, text=True
        )
        orphans = result.stdout.strip()

        if not orphans:
            print(f"{GREEN}✔ Keine verwaisten Pakete gefunden.{RESET}\n")
            input("Drücke Enter zum Fortfahren...")
            return

        print(f"{ORANGE}Gefundene verwaiste Pakete:{RESET}")
        for pkg in orphans.splitlines():
            print(f"  {BLUE}•{RESET} {pkg}")
        print()

        if confirm("Alle verwaisten Pakete entfernen?"):
            subprocess.run(
                'sudo pacman -Rns $(pacman -Qtdq) --noconfirm',
                shell=True, check=True
            )
            success_message()
        else:
            print(f"{BLUE}Abgebrochen.{RESET}")
            input("Drücke Enter zum Fortfahren...")

    except subprocess.CalledProcessError as e:
        error_message(str(e))
    except Exception as e:
        error_message(str(e))

# ── Neue Funktion 2: Fehlgeschlagene Systemdienste anzeigen ───────────────────
def check_failed_services():
    """
    Zeigt alle fehlgeschlagenen systemd-Dienste an und bietet an,
    den Status eines bestimmten Dienstes detailliert abzurufen.
    """
    print(f"\n{ORANGE}▶ Fehlgeschlagene Systemdienste prüfen...{RESET}\n")
    try:
        result = subprocess.run(
            'systemctl --failed --no-pager --no-legend',
            shell=True, capture_output=True, text=True
        )
        output = result.stdout.strip()

        if not output:
            print(f"{GREEN}✔ Keine fehlgeschlagenen Dienste gefunden.{RESET}\n")
            input("Drücke Enter zum Fortfahren...")
            return

        print(f"{RED}Fehlgeschlagene Dienste:{RESET}")
        services = []
        for line in output.splitlines():
            parts = line.split()
            if parts:
                services.append(parts[0])
                print(f"  {RED}✘{RESET} {line}")
        print()

        if services and confirm("Status eines Dienstes genauer anzeigen?"):
            service = input(
                f"{ORANGE}Dienstname eingeben: {RESET}"
            ).strip()
            if service:
                print()
                subprocess.run(
                    f'systemctl status {service} --no-pager',
                    shell=True
                )
                print()

        input("Drücke Enter zum Fortfahren...")

    except Exception as e:
        error_message(str(e))

# ── Hauptprogramm ─────────────────────────────────────────────────────────────
def main():
    actions = {
        '1': lambda: execute_command('sudo pacman -Syu',               'System Upgrade'),
        '2': lambda: execute_command('yay -Syu',                       'System Upgrade mit YAY'),
        '3': lambda: execute_command('sudo pacman -Scc --noconfirm',   'Pacman Cache leeren',
                                     require_confirm=True),
        '4': lambda: execute_command(
                'sudo pacman-key --init && sudo pacman-key --populate archlinux',
                'Arch Linux Keyring erneuern'),
        '5': lambda: execute_command('sudo pacman -Fyy',               'Pacman Datenbank aktualisieren'),
        '6': remove_orphans,
        '7': check_failed_services,
    }

    while True:
        print_menu()
        choice = input(f"{ORANGE}Wähle eine Option (1-8): {RESET}").strip()

        if choice == '8':
            clear_screen()
            print(f"{ORANGE}Auf Wiedersehen!{RESET}\n")
            sys.exit(0)

        action = actions.get(choice)
        if action:
            action()
        else:
            print(f"{RED}Ungültige Auswahl. Bitte 1–8 eingeben.{RESET}")
            input("Drücke Enter zum Fortfahren...")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n{ORANGE}Skript beendet.{RESET}\n")
        sys.exit(0)
EOF

    chmod +x "${script_path}"
    ok "arch_sys_management.py erstellt: ${script_path}"
    hint "Starten mit: python3 ${script_path}"
    hint "Oder direkt: ${script_path}"
}

# ── 19. Eigene Pakete (yay) ───────────────────────────────────────────────────
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
#  MODUL 20 — GPU-TREIBER
# =============================================================================

# ── 20. GPU-Treiber (AMD / NVIDIA / Intel) ────────────────────────────────────
setup_drivers() {
    step "GPU-Treiber installieren"
    sep

    # ── Auto-Erkennung ────────────────────────────────────────────────────────
    local gpu_vendor=""
    if command -v lspci &>/dev/null; then
        local lspci_out
        lspci_out=$(lspci 2>/dev/null | grep -iE 'VGA|3D|Display')
        if echo "${lspci_out}" | grep -qi 'AMD\|ATI\|Radeon'; then
            gpu_vendor="amd"
        elif echo "${lspci_out}" | grep -qi 'NVIDIA'; then
            gpu_vendor="nvidia"
        elif echo "${lspci_out}" | grep -qi 'Intel'; then
            gpu_vendor="intel"
        fi
    fi

    if [[ -n "${gpu_vendor}" ]]; then
        log "Erkannte GPU-Hersteller: ${gpu_vendor^^}"
        lspci 2>/dev/null | grep -iE 'VGA|3D|Display' | while IFS= read -r line; do
            hint "  ${line}"
        done
    else
        warn "GPU konnte nicht automatisch erkannt werden (lspci nicht verfügbar?)."
    fi

    sep
    echo -e "
  ${BOLD}${CYAN}Welchen Treiber möchtest du installieren?${RESET}
"
    echo -e "  ${CYAN} 1)${RESET}  AMD     ${BLUE}(RDNA/GCN — mesa, vulkan-radeon, ROCm, Wayland)${RESET}"
    echo -e "  ${CYAN} 2)${RESET}  NVIDIA  ${BLUE}(proprietär — nvidia/nvidia-dkms, Wayland-KMS)${RESET}"
    echo -e "  ${CYAN} 3)${RESET}  Intel   ${BLUE}(mesa, vulkan-intel, intel-media-driver)${RESET}"
    echo -e "  ${CYAN} 4)${RESET}  Alle drei installieren  ${BLUE}(Hybrid-/Multi-GPU-System)${RESET}"
    echo -e "  ${CYAN} 0)${RESET}  Abbrechen"
    echo

    if [[ -n "${gpu_vendor}" ]]; then
        echo -en "  ${BOLD}Auswahl${RESET} [0–4, erkannt: ${CYAN}${gpu_vendor^^}${RESET}]: "
    else
        echo -en "  ${BOLD}Auswahl${RESET} [0–4]: "
    fi

    local auswahl
    read -r auswahl

    case "${auswahl}" in
        1) _driver_amd    ;;
        2) _driver_nvidia ;;
        3) _driver_intel  ;;
        4) _driver_amd; _driver_nvidia; _driver_intel ;;
        0|'') warn "Treiber-Installation abgebrochen."; return 0 ;;
        *) warn "Ungültige Auswahl: '${auswahl}'"; return 1 ;;
    esac

    ok "GPU-Treiber-Installation abgeschlossen."
    warn "Bitte System neu starten, damit alle Treiber vollständig aktiv werden."
    hint "Neustart:  sudo reboot"
}

# ── AMD ───────────────────────────────────────────────────────────────────────
_driver_amd() {
    step "AMD-Treiber installieren"
    sep
    enable_multilib

    log "Installiere AMDGPU-Kern + Vulkan + Wayland-Protokolle ..."
    pkg_install \
        mesa mesa-utils lib32-mesa \
        vulkan-radeon lib32-vulkan-radeon \
        vulkan-icd-loader lib32-vulkan-icd-loader egl-wayland \
        wayland-protocols plasma-wayland-protocols libvdpau-va-gl libva


    frage "ROCm / OpenCL installieren? (KI-Workloads, GPU-Compute)" \
        && pkg_install rocm-opencl-runtime rocm-hip-runtime

    frage "Monitoring-Tool radeontop installieren?" \
        && pkg_install radeontop

    ok "AMD-Treiber installiert."
    hint "Vulkan prüfen:     vulkaninfo --summary"
    hint "VA-API prüfen:     vainfo"
    hint "Kernel-Modul:      lsmod | grep amdgpu"
    hint "GPU-Monitoring:    radeontop"
}

# ── NVIDIA ────────────────────────────────────────────────────────────────────
_driver_nvidia() {
    step "NVIDIA-Treiber installieren"
    sep
    enable_multilib

    warn "Für Maxwell (GTX 750/900) und neuer → proprietärer nvidia-Treiber."
    warn "Für ältere Karten ggf. nvidia-470xx-dkms (AUR) verwenden."
    echo

    # Kernelauswahl: nvidia (nur linux) vs nvidia-dkms (alle Kernel)
    local pkg_driver="nvidia-dkms"
    if frage "Nutzt du ausschließlich den Standard-Kernel (linux)? → 'nvidia' statt 'nvidia-dkms'"; then
        pkg_driver="nvidia"
    fi

    log "Installiere NVIDIA-Treiber (${pkg_driver}) ..."
    pkg_install \
        "${pkg_driver}" \
        nvidia-utils lib32-nvidia-utils \
        nvidia-settings \
        egl-wayland \
        opencl-nvidia lib32-opencl-nvidia \
        vulkan-icd-loader lib32-vulkan-icd-loader

    # ── Kernel-Early-Loading (MODULES in mkinitcpio.conf) ─────────────────────
    local mkinit="/etc/mkinitcpio.conf"
    log "Prüfe NVIDIA-MODULES in ${mkinit} ..."
    if grep -q 'nvidia' "${mkinit}"; then
        warn "NVIDIA-Module scheinen bereits in ${mkinit} eingetragen zu sein."
    else
        sudo sed -i \
            's/^MODULES=(\(.*\))/MODULES=(\1 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
            "${mkinit}"
        ok "MODULES in ${mkinit} um NVIDIA-Treiber ergänzt."
    fi

    # ── modprobe-Optionen (KMS + Power-Management) ────────────────────────────
    log "Erstelle /etc/modprobe.d/nvidia.conf ..."
    sudo tee /etc/modprobe.d/nvidia.conf > /dev/null <<'NVIDIA_CONF'
# NVIDIA-Optionen (ArchSetup — Modul 20)
# DRM-Kernel-Mode-Setting (für Wayland zwingend erforderlich)
options nvidia_drm modeset=1
# Video-Memory bei Suspend erhalten (verhindert Artefakte nach Aufwachen)
options nvidia NVreg_PreserveVideoMemoryAllocations=1
NVIDIA_CONF
    ok "/etc/modprobe.d/nvidia.conf geschrieben."

    # ── initramfs neu generieren ──────────────────────────────────────────────
    log "Regeneriere initramfs (mkinitcpio -P) ..."
    sudo mkinitcpio -P

    # ── Suspend-/Hibernate-Dienste ────────────────────────────────────────────
    if frage "NVIDIA Suspend/Hibernate-Dienste aktivieren? (empfohlen bei KDE Wayland)"; then
        sudo systemctl enable \
            nvidia-suspend.service \
            nvidia-hibernate.service \
            nvidia-resume.service
        ok "NVIDIA Power-Management-Dienste aktiviert."
    fi

    ok "NVIDIA-Treiber installiert."
    hint "KMS-Status prüfen:  cat /sys/module/nvidia_drm/parameters/modeset  (→ Y)"
    hint "GPU-Info:           nvidia-smi"
    hint "Vulkan prüfen:      vulkaninfo --summary"
}

# ── Intel ─────────────────────────────────────────────────────────────────────
_driver_intel() {
    step "Intel-Treiber installieren"
    sep
    enable_multilib

    log "Installiere Intel Mesa + Vulkan + VA-API ..."
    pkg_install \
        mesa lib32-mesa \
        vulkan-intel lib32-vulkan-intel \
        vulkan-icd-loader lib32-vulkan-icd-loader \
        intel-media-driver \
        libva-intel-driver lib32-libva-intel-driver

    warn "xf86-video-intel ist für moderne Intel-GPUs (Haswell+) meist NICHT empfohlen."
    warn "Der Kernel-Modesetting-Treiber (modesetting) ist in der Regel besser."
    frage "xf86-video-intel trotzdem installieren? (nur für ältere Systeme vor Haswell)" \
        && pkg_install xf86-video-intel

    frage "Intel GPU-Tools (intel-gpu-tools) installieren?" \
        && pkg_install intel-gpu-tools

    ok "Intel-Treiber installiert."
    hint "Vulkan prüfen:  vulkaninfo --summary"
    hint "VA-API prüfen:  vainfo"
    hint "GPU-Auslastung: intel_gpu_top"
}

# ── 17. Vivaldi + FFmpeg-Codecs ───────────────────────────────────────────────
setup_vivaldi() {
    step "Vivaldi Browser installieren"
    sep

    aur_or_chaotic vivaldi || { err "Vivaldi-Installation fehlgeschlagen."; return 1; }
    ok "Vivaldi installiert."

    if frage "Proprietäre FFmpeg-Codecs installieren? (H.264, AAC, MP3 …)"; then
        aur_or_chaotic vivaldi-ffmpeg-codecs \
            && ok "vivaldi-ffmpeg-codecs installiert." \
            || warn "vivaldi-ffmpeg-codecs fehlgeschlagen – ggf. Chaotic AUR oder yay prüfen."
    fi

    hint "Tipp: Nach Updates ggf. 'yay -S vivaldi vivaldi-ffmpeg-codecs' erneut ausführen,"
    hint "      da Codec-Version zur Vivaldi-Version passen muss."
    ok "Vivaldi-Modul abgeschlossen."
}

# ── 17. System-Tweaks ─────────────────────────────────────────────────────────
setup_system_tweaks() {
    step "System-Tweaks anwenden (Umgebungsvariablen + I/O-Scheduler)"
    sep

    # ── 17a. /etc/environment ──────────────────────────────────────────────────
    if frage "Performance-Umgebungsvariablen in /etc/environment eintragen?"; then
        log "Schreibe Variablen nach /etc/environment ..."

        # Bereits vorhandene Schlüssel nicht doppelt eintragen
        local env_file="/etc/environment"
        local -a env_vars=(
            "CPU_LIMIT=0"
            "CPU_GOVERNOR=performance"
            "GPU_USE_SYNC_OBJECTS=1"
            "PYTHONOPTIMIZE=1"
            "ELEVATOR=deadline"
            "TRANSPARENT_HUGEPAGES=always"
            "MALLOC_CONF=background_thread:true"
            "MALLOC_CHECK=0"
            "MALLOC_TRACE=0"
            "LD_DEBUG_OUTPUT=0"
            "LP_PERF=no_mipmap,no_linear,no_mip_linear,no_tex,no_blend,no_depth,no_alphatest"
            "LESSSECURE=1"
            "PAGER=less"
            "EDITOR=nano"
            "VISUAL=nano"
            "AMD_VULKAN_ICD=RADV"
            "RADV_PERFTEST=aco,sam,nggc"
            "RADV_DEBUG=novrsflatshading"
        )

        local added=0
        local skipped=0
        for entry in "${env_vars[@]}"; do
            local key="${entry%%=*}"
            if grep -q "^${key}=" "${env_file}" 2>/dev/null; then
                warn "  ${key} bereits vorhanden – übersprungen."
                (( skipped++ )) || true
            else
                echo "${entry}" | sudo tee -a "${env_file}" > /dev/null
                (( added++ )) || true
            fi
        done

        ok "${added} Variablen hinzugefügt, ${skipped} bereits vorhanden."
        hint "Änderungen werden nach dem nächsten Login wirksam."
        warn "Hinweis: RADV_*-Variablen sind AMD-spezifisch – auf NVIDIA/Intel ignorieren."
    fi

    sep

    # ── 17b. I/O-Scheduler udev-Regeln ────────────────────────────────────────
    if frage "I/O-Scheduler-Regeln via udev einrichten?"; then
        local rules_file="/etc/udev/rules.d/60-ioschedulers.rules"

        if [[ -f "${rules_file}" ]]; then
            warn "${rules_file} existiert bereits."
            frage "Datei überschreiben?" || { warn "I/O-Scheduler-Konfiguration übersprungen."; return 0; }
        fi

        log "Schreibe ${rules_file} ..."
        sudo tee "${rules_file}" > /dev/null <<'UDEV_EOF'
# I/O-Scheduler-Regeln (ArchSetup)
# NVMe SSDs — 'none' (maximale Performance, eigene interne Queue)
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"

# SATA SSDs und eMMC — 'bfq' (bessere Interaktivität)
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="bfq"

# Rotierende Festplatten — 'bfq'
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
UDEV_EOF

        log "Lade udev-Regeln neu ..."
        sudo udevadm control --reload
        ok "I/O-Scheduler-Regeln eingerichtet und udev neu geladen."
        hint "Aktiven Scheduler prüfen: cat /sys/block/nvme0n1/queue/scheduler"
        hint "                          cat /sys/block/sda/queue/scheduler"
    fi

    ok "System-Tweaks abgeschlossen."
}

# =============================================================================
#  HAUPT-MENÜ
# =============================================================================

print_banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔═════════════════════════════════════════════════════════════╗"
    echo "  ║      ArchSetup v2.5 — Post-Installation Configurator        ║"
    echo "  ║             Plasma Desktop  ·  Limine Bootloader            ║"
    echo "  ╚═════════════════════════════════════════════════════════════╝"
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
    echo -e "  ${CYAN}14)${RESET}  UFW Firewall                   ${BLUE}(Regeln einzeln konfigurierbar)${RESET}"
    echo -e "  ${CYAN}15)${RESET}  Dev-Tools                      ${BLUE}(Entwicklerwerkzeuge, interaktiv)${RESET}"
    echo -e "  ${CYAN}16)${RESET}  Arch Sys Management            ${BLUE}(Python-Tool auf Desktop)${RESET}"
    echo -e "  ${CYAN}17)${RESET}  Vivaldi Browser                ${BLUE}(+ vivaldi-ffmpeg-codecs)${RESET}"
    echo -e "  ${CYAN}18)${RESET}  System-Tweaks                  ${BLUE}(/etc/environment + I/O-Scheduler udev)${RESET}"
    echo -e "  ${CYAN}19)${RESET}  Eigene Pakete                  ${BLUE}(Freie Paketauswahl via yay)${RESET}"
    echo -e "  ${CYAN}20)${RESET}  GPU-Treiber                    ${BLUE}(AMD / NVIDIA / Intel — interaktiv)${RESET}"
    echo
    sep
    echo -e "  ${CYAN} a)${RESET}  ${BOLD}Alle Module${RESET} der Reihe nach ausführen"
    echo -e "  ${CYAN} 0)${RESET}  Beenden"
    echo
}

# Alle verfügbaren Modul-Nummern
readonly -a ALL_MODULES=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)

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
        14) setup_ufw              ;;
        15) setup_devtools         ;;
        16) setup_arch_sys_management ;;
        17) setup_vivaldi          ;;
        18) setup_system_tweaks    ;;
        19) setup_custom_packages  ;;
        20) setup_drivers          ;;
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

        echo -en "  ${BOLD}Auswahl${RESET} [0-20 / a]: "
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
            1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20)
                print_banner
                run_module "${auswahl}"
                echo -en "
Zurück zum Menü mit Enter ..."
                read -r
                ;;
            '')
                ;;
            *)
                warn "Ungültige Eingabe: '${auswahl}' – Bitte 0–20 oder 'a' eingeben."
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
Verwendung: archsetup.sh [FLAG]

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
  --ufw         UFW Firewall (Regeln interaktiv konfigurieren)
  --devtools    Dev-Tools (Entwicklerwerkzeuge, interaktiv)
  --sysmanage   Arch System Management Script auf Desktop
  --vivaldi     Vivaldi Browser + vivaldi-ffmpeg-codecs
  --tweaks      System-Tweaks (/etc/environment + I/O-Scheduler)
  --custom      Eigene Pakete via yay installieren
  --drivers     GPU-Treiber installieren (AMD / NVIDIA / Intel, interaktiv)
  --all         Alle Module nacheinander ausführen
  --help | -h   Diese Hilfe anzeigen

Ohne Flag: Interaktives Menü starten
EOF
}

main() {
    require_no_root
    check_internet

    if [[ $# -gt 0 ]]; then
        case "$1" in                    # BUGFIX: war "\$1" — \$ escapet $, nie expandiert
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
            --ufw)        setup_ufw             ;;
            --devtools)   setup_devtools        ;;
            --sysmanage)  setup_arch_sys_management ;;
            --vivaldi)    setup_vivaldi         ;;
            --tweaks)     setup_system_tweaks   ;;
            --custom)     setup_custom_packages ;;
            --drivers)    setup_drivers         ;;
            --all)        run_all_modules       ;;
            --help|-h)    usage                 ;;
            *)
                err "Unbekannter Parameter: '$1'"
                usage
                exit 1
                ;;
        esac
    else
        interactive_menu
    fi
}

main "$@"
