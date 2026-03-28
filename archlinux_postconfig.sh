#!/usr/bin/env bash
# =============================================================================
#  ArchSetup v2.1 — Post-Installation Setup Script
#  Plasma Desktop + Limine Bootloader
#  Getestet auf: Arch Linux (aktuell)
# =============================================================================
#
#  Module:
#   1) Chaotic AUR             8) yay-bin
#   2) Snapper + btrfs-asst.   9) Zsh + Oh-My-Zsh
#   3) Druckunterstützung     10) Fish Shell
#   4) Wine + Steam           11) OnlyOffice
#   5) ProtonUp-Qt            12) NoMachine
#   6) Virt-Manager / QEMU   13) Teams for Linux
#   7) yt-dlp (GitHub)
#
#  Verwendung: ./archsetup.sh [FLAG]
#  FLAGS: --chaotic --snapper --print --gaming --protonup --virt
#         --ytdlp --yay --zsh --fish --onlyoffice --nomachine --teams --all
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
step() { echo -e "\n${ARROW}  ${BOLD}${CYAN}$*${RESET}"; }
sep()  { echo -e "${BLUE}$(printf '─%.0s' {1..62})${RESET}"; }
hint() { echo -e "   ${CYAN}$*${RESET}"; }

# ── Interaktive Ja/Nein-Abfrage ───────────────────────────────────────────────
# Rückgabe: 0 = Ja, 1 = Nein
frage() {
    local prompt="$1"
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

# Installiert bevorzugt über Chaotic AUR (pacman), fällt auf yay zurück
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
has_chaotic()  { grep -q '^\[chaotic-aur\]' /etc/pacman.conf 2>/dev/null; }
has_yay()      { command -v yay &>/dev/null; }
has_multilib() { grep -q '^\[multilib\]' /etc/pacman.conf 2>/dev/null; }

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
    # Entkommentiert [multilib] und die zugehörige Include-Zeile
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

    # Hinweis: grub-btrfs / grub-btrfsd entfällt, da Limine als Bootloader
    # verwendet wird. Snapshot-Boot-Einträge müssen manuell in limine.conf
    # gepflegt oder über ein eigenes pacman-Hook-Skript realisiert werden.
    pkg_install snapper snap-pac

    # btrfs-assistant: bevorzugt über Chaotic AUR, sonst via yay
    aur_or_chaotic btrfs-assistant

    # Snapper-Root-Konfiguration anlegen (falls noch nicht vorhanden)
    if [[ ! -f /etc/snapper/configs/root ]]; then
        log "Erstelle Snapper-Konfiguration für '/' ..."
        # Eventuell vorhandenes /.snapshots aushängen, damit snapper seine
        # Subvolume-Struktur korrekt anlegen kann
        sudo umount /.snapshots 2>/dev/null || true
        sudo rm -rf /.snapshots
        sudo snapper -c root create-config /
        # Von snapper erzeugtes Subvolume entfernen und eigenes (aus fstab) einbinden
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
    warn "Snapshot-Häufigkeit anpassen via /etc/snapper/configs/root"
    warn "(TIMELINE_LIMIT_HOURLY, DAILY, WEEKLY, MONTHLY, YEARLY)."
}

# ── 3. Druckunterstützung (CUPS) ──────────────────────────────────────────────
setup_print() {
    step "Druckunterstützung (CUPS) einrichten"
    sep

    pkg_install cups cups-pdf ghostscript gsfonts \
                system-config-printer print-manager

    if frage "HP-Drucker vorhanden? (hplip installieren)"; then
        pkg_install hplip
    fi

    if frage "Epson-Drucker vorhanden? (epson-inkjet-printer-escpr installieren)"; then
        aur_or_chaotic epson-inkjet-printer-escpr \
            || warn "Epson-Treiber konnte nicht installiert werden."
    fi

    if frage "Brother-Drucker vorhanden? (brlaser installieren)"; then
        aur_or_chaotic brlaser \
            || warn "Brother-Treiber (brlaser) konnte nicht installiert werden."
    fi

    if frage "Canon-Drucker vorhanden? (cnijfilter2 installieren)"; then
        aur_or_chaotic cnijfilter2 \
            || warn "Canon-Treiber (cnijfilter2) konnte nicht installiert werden."
    fi

    log "Aktiviere und starte CUPS-Dienst ..."
    sudo systemctl enable --now cups.service

    ok "Druckunterstützung eingerichtet."
    hint "KDE: Systemeinstellungen → Drucker → Drucker hinzufügen"
}

# ── 4. Wine + Steam ───────────────────────────────────────────────────────────
setup_wine_steam() {
    step "Wine + Steam Gaming-Plattform einrichten"
    sep

    enable_multilib

    log "Installiere Wine Staging + 32-Bit-Bibliotheken ..."
    pkg_install wine-staging winetricks wine-mono wine-gecko \
                lib32-mesa lib32-vulkan-icd-loader \
                lib32-alsa-lib lib32-alsa-plugins lib32-libpulse \
                lib32-gnutls lib32-libldap lib32-libgpg-error

    log "Installiere Steam ..."
    pkg_install steam

    if frage "Lutris (universeller Game-Manager) installieren?"; then
        pkg_install lutris
    fi

    if frage "Gamemode (CPU/GPU-Leistungsoptimierung) installieren?"; then
        pkg_install gamemode lib32-gamemode
        sudo usermod -aG gamemode "${USER}"
        warn "Gruppenänderung (gamemode) wird nach dem nächsten Login aktiv."
    fi

    if frage "MangoHud (FPS/Performance-Overlay) installieren?"; then
        pkg_install mangohud lib32-mangohud
    fi

    ok "Wine + Steam eingerichtet."
    hint "ProtonUp-Qt (Modul 5) für Proton-GE-Verwaltung separat verfügbar."
}

# ── 5. ProtonUp-Qt ────────────────────────────────────────────────────────────
setup_protonup() {
    step "ProtonUp-Qt einrichten (Proton-GE / Wine-GE Verwaltung)"
    sep

    # Multilib für Steam-Kompatibilität sicherstellen
    enable_multilib

    if aur_or_chaotic protonup-qt; then
        ok "ProtonUp-Qt installiert."
        hint "Steam → Einstellungen → Steam Play → Proton-GE über ProtonUp-Qt verwalten."
        hint "Wine-GE für Lutris wird ebenfalls über ProtonUp-Qt verwaltet."
    fi
}

# ── 6. Virt-Manager / QEMU / KVM ─────────────────────────────────────────────
setup_virt() {
    step "Virt-Manager / QEMU / KVM einrichten"
    sep

    # KVM-Hardwareunterstützung prüfen
    if ! grep -qE '(vmx|svm)' /proc/cpuinfo; then
        warn "CPU-Virtualisierung (VT-x / AMD-V) nicht erkannt."
        warn "Bitte Virtualisierung im BIOS/UEFI aktivieren."
    fi

    pkg_install virt-manager qemu-full libvirt \
                edk2-ovmf dnsmasq iptables-nft \
                virt-viewer bridge-utils

    log "Aktiviere libvirtd-Dienst ..."
    sudo systemctl enable --now libvirtd.service

    log "Aktiviere Standard-NAT-Netzwerk für virtuelle Maschinen ..."
    sudo virsh net-autostart default 2>/dev/null || true
    sudo virsh net-start default 2>/dev/null || true

    log "Füge '${USER}' zu Gruppen libvirt und kvm hinzu ..."
    sudo usermod -aG libvirt,kvm "${USER}"

    if frage "IOMMU / PCI-Passthrough (Limine-Kernel-Parameter) konfigurieren?"; then
        warn "Folgende Kernel-Parameter in /boot/limine/limine.conf unter 'CMDLINE' ergänzen:"
        hint "AMD CPU:   amd_iommu=on iommu=pt"
        hint "Intel CPU: intel_iommu=on iommu=pt"
        hint "Beispiel: CMDLINE=quiet splash amd_iommu=on iommu=pt"
    fi

    ok "Virt-Manager / QEMU eingerichtet."
    warn "Gruppenänderungen (libvirt, kvm) werden nach dem nächsten Login aktiv."
}

# ── 7. yt-dlp (aktuellste Version von GitHub) ────────────────────────────────
setup_ytdlp() {
    step "yt-dlp installieren (aktuellste Binary von GitHub)"
    sep

    local bin_path="/usr/local/bin/yt-dlp"
    local api_url="https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
    local download_url

    log "Ermittle aktuellste yt-dlp Release-URL via GitHub API ..."
    # Suche nach dem einfachen 'yt-dlp'-Binary (kein .tar.gz, kein .exe usw.)
    download_url=$(
        curl -fsSL "${api_url}" \
            | grep '"browser_download_url"' \
            | grep '"/yt-dlp"' \
            | head -1 \
            | cut -d'"' -f4
    )

    if [[ -z "${download_url}" ]]; then
        warn "Automatische URL-Erkennung fehlgeschlagen – nutze statische Fallback-URL."
        download_url="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
    fi

    log "Lade herunter: ${download_url}"
    sudo curl -fsSL -o "${bin_path}" "${download_url}"
    sudo chmod a+rx "${bin_path}"

    # Empfohlene Abhängigkeiten für vollständige Funktionalität
    pkg_install ffmpeg python-mutagen python-pycryptodome

    local version
    version=$(yt-dlp --version 2>/dev/null || echo "unbekannt")
    ok "yt-dlp ${version} → ${bin_path}"

    # Einfaches Update-Wrapper-Skript anlegen
    sudo tee /usr/local/bin/yt-dlp-update > /dev/null <<'EOF'
#!/usr/bin/env bash
echo "Aktualisiere yt-dlp auf die neueste Version ..."
yt-dlp -U
EOF
    sudo chmod +x /usr/local/bin/yt-dlp-update
    ok "Update-Befehl verfügbar: yt-dlp-update"
}

# ── 8. yay-bin (AUR-Helper) ───────────────────────────────────────────────────
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
    # Temporäres Verzeichnis bei Funktionsrückkehr automatisch bereinigen
    trap "rm -rf '${tmpdir}'" RETURN

    log "Klone yay-bin aus dem AUR nach ${tmpdir} ..."
    git clone --depth=1 https://aur.archlinux.org/yay-bin.git "${tmpdir}/yay-bin"

    log "Baue und installiere yay-bin (makepkg) ..."
    # makepkg darf NICHT als root laufen – durch require_no_root() sichergestellt
    (cd "${tmpdir}/yay-bin" && makepkg -si --noconfirm)

    if has_yay; then
        ok "yay erfolgreich installiert: $(yay --version | head -1)"
    else
        err "yay-Installation fehlgeschlagen. Bitte die Ausgabe prüfen."
        return 1
    fi
}

# ── 9. Zsh + Oh-My-Zsh ────────────────────────────────────────────────────────
setup_zsh() {
    step "Zsh als Standard-Shell einrichten"
    sep

    pkg_install zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting

    local omz_installed=false
    local zshrc="${HOME}/.zshrc"

    if frage "Oh-My-Zsh Framework installieren?"; then
        if [[ -d "${HOME}/.oh-my-zsh" ]]; then
            warn "Oh-My-Zsh ist bereits installiert."
            omz_installed=true
        else
            log "Installiere Oh-My-Zsh ..."
            # RUNZSH=no und CHSH=no: kein automatischer Shell-Wechsel, wir machen das selbst
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
                ok "Powerlevel10k installiert – Konfigurator startet beim nächsten Zsh-Login."
            else
                warn "Powerlevel10k ist bereits installiert."
            fi
        fi
    fi

    if frage "Nerd Fonts (ttf-jetbrains-mono-nerd) installieren?"; then
        aur_or_chaotic ttf-jetbrains-mono-nerd \
            || warn "Nerd Fonts konnten nicht installiert werden."
    fi

    # System-Plugins in .zshrc einbinden (nur wenn noch nicht vorhanden)
    if [[ -f "${zshrc}" ]]; then
        log "Binde System-Plugins in .zshrc ein ..."
        grep -q 'zsh-autosuggestions.zsh' "${zshrc}" \
            || echo 'source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh' \
               >> "${zshrc}"
        grep -q 'zsh-syntax-highlighting.zsh' "${zshrc}" \
            || echo 'source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh' \
               >> "${zshrc}"
    fi

    log "Setze Zsh als Standard-Shell für '${USER}' ..."
    chsh -s "$(command -v zsh)" "${USER}"

    ok "Zsh ist jetzt Standard-Shell. Änderung wird beim nächsten Login aktiv."
}

# ── 10. Fish Shell ────────────────────────────────────────────────────────────
setup_fish() {
    step "Fish Shell als Standard-Shell einrichten"
    sep

    pkg_install fish

    if frage "fisher (Fish Plugin-Manager) installieren?"; then
        log "Installiere fisher ..."
        if fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish \
                | source && fisher install jorgebucaran/fisher"; then
            ok "fisher installiert."
        else
            warn "fisher-Installation fehlgeschlagen. Bitte manuell prüfen."
        fi

        if frage "Tide Prompt (modernes Fish-Theme) via fisher installieren?"; then
            fish -c "fisher install IlanCosman/tide@v6" \
                && ok "Tide installiert – Konfigurator startet beim nächsten Fish-Login." \
                || warn "Tide konnte nicht installiert werden."
        fi

        if frage "z (Directory-Jumper) via fisher installieren?"; then
            fish -c "fisher install jethrokuan/z" \
                && ok "z-Plugin installiert." \
                || warn "z-Plugin konnte nicht installiert werden."
        fi
    fi

    if frage "Nerd Fonts (ttf-jetbrains-mono-nerd) installieren?"; then
        aur_or_chaotic ttf-jetbrains-mono-nerd \
            || warn "Nerd Fonts konnten nicht installiert werden."
    fi

    log "Setze Fish als Standard-Shell für '${USER}' ..."
    chsh -s "$(command -v fish)" "${USER}"

    ok "Fish ist jetzt Standard-Shell. Änderung wird beim nächsten Login aktiv."
    hint "Konfigurationsdatei: ~/.config/fish/config.fish"
    hint "Interaktive Webkonfiguration: fish_config  (öffnet Browser)"
}

# ── 11. OnlyOffice ────────────────────────────────────────────────────────────
setup_onlyoffice() {
    step "OnlyOffice Desktop Editors installieren"
    sep

    if aur_or_chaotic onlyoffice-bin; then
        ok "OnlyOffice Desktop Editors installiert."
        hint "Start: Anwendungsmenü → Büro → ONLYOFFICE Desktop Editors"
        hint "Kompatibel mit .docx, .xlsx, .pptx (Microsoft Office-Formaten)."
    fi
}

# ── 12. NoMachine ─────────────────────────────────────────────────────────────
setup_nomachine() {
    step "NoMachine (Remote Desktop) installieren"
    sep

    if aur_or_chaotic nomachine; then
        log "Aktiviere NoMachine-Dienst ..."
        # nxserver.service ist der systemd-Dienst, den nomachine mitbringt
        sudo systemctl enable --now nxserver.service 2>/dev/null \
            || warn "nxserver.service konnte nicht gestartet werden. Bitte manuell prüfen."

        ok "NoMachine installiert und Dienst aktiviert."
        hint "Verbindung: NoMachine-Client auf der Gegenstelle → IP/Hostname eingeben."
        hint "Standard-Port: 4000 (NX-Protokoll)"
        hint "Firewall-Freigabe (ufw): sudo ufw allow 4000/tcp"
    fi
}

# ── 13. Teams for Linux ───────────────────────────────────────────────────────
setup_teams() {
    step "Teams for Linux (inoffizieller Client) installieren"
    sep

    warn "Hinweis: 'teams-for-linux' ist ein inoffizieller, community-gepflegter"
    warn "         Microsoft-Teams-Client (Electron-basiert, Open Source)."
    warn "         Eine offizielle Microsoft-Teams-App für Linux existiert nicht mehr."

    if aur_or_chaotic teams-for-linux-bin; then
        ok "Teams for Linux installiert."
        hint "Start: Anwendungsmenü → Internet → Teams for Linux"
        hint "Projektseite: https://github.com/IsmaelMartinez/teams-for-linux"
    fi
}

# =============================================================================
#  HAUPT-MENÜ
# =============================================================================

print_banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║      ArchSetup v2.1 — Post-Installation Configurator       ║"
    echo "  ║             Plasma Desktop  ·  Limine Bootloader           ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    printf "  ${BOLD}Benutzer:${RESET} ${CYAN}%-14s${RESET}  " "${USER}"
    printf "${BOLD}Host:${RESET} ${CYAN}%-16s${RESET}  " "$(hostname)"
    printf "${BOLD}Kernel:${RESET} ${CYAN}%s${RESET}\n" "$(uname -r)"
    sep
}

print_menu() {
    echo -e "\n  ${BOLD}Was soll eingerichtet werden?${RESET}\n"
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
    echo
    sep
    echo -e "  ${CYAN} a)${RESET}  ${BOLD}Alle Module${RESET} der Reihe nach ausführen"
    echo -e "  ${CYAN} 0)${RESET}  Beenden"
    echo
}

# Alle verfügbaren Modul-Nummern (für Validierung und Alle-Funktion)
readonly -a ALL_MODULES=(1 2 3 4 5 6 7 8 9 10 11 12 13)

run_module() {
    local num="$1"
    case "${num}" in
        1)  setup_chaotic_aur ;;
        2)  setup_snapper     ;;
        3)  setup_print       ;;
        4)  setup_wine_steam  ;;
        5)  setup_protonup    ;;
        6)  setup_virt        ;;
        7)  setup_ytdlp       ;;
        8)  setup_yay         ;;
        9)  setup_zsh         ;;
        10) setup_fish        ;;
        11) setup_onlyoffice  ;;
        12) setup_nomachine   ;;
        13) setup_teams       ;;
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

        echo -en "  ${BOLD}Auswahl${RESET} [0-13 / a]: "
        read -r auswahl

        case "${auswahl}" in
            0)
                echo -e "\n${GREEN}  Auf Wiedersehen! Viel Spaß mit Arch Linux.${RESET}\n"
                exit 0
                ;;
            a|A|all)
                run_all_modules
                echo -en "\nZurück zum Menü mit Enter ..."
                read -r
                ;;
            [1-9]|1[0-3])
                print_banner
                run_module "${auswahl}"
                echo -en "\nZurück zum Menü mit Enter ..."
                read -r
                ;;
            '')
                # Leere Eingabe: Menü einfach neu anzeigen
                ;;
            *)
                warn "Ungültige Eingabe: '${auswahl}' – Bitte 0–13 oder 'a' eingeben."
                sleep 1
                ;;
        esac
    done
}

# =============================================================================
#  EINSTIEGSPUNKT
# =============================================================================

usage() {
    cat <<EOF
Verwendung: $0 [FLAG]

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
  --all         Alle Module nacheinander ausführen
  --help | -h   Diese Hilfe anzeigen

Ohne Flag: Interaktives Menü starten
EOF
}

main() {
    require_no_root
    check_internet

    if [[ $# -gt 0 ]]; then
        case "$1" in
            --chaotic)    setup_chaotic_aur ;;
            --snapper)    setup_snapper     ;;
            --print)      setup_print       ;;
            --gaming)     setup_wine_steam  ;;
            --protonup)   setup_protonup    ;;
            --virt)       setup_virt        ;;
            --ytdlp)      setup_ytdlp       ;;
            --yay)        setup_yay         ;;
            --zsh)        setup_zsh         ;;
            --fish)       setup_fish        ;;
            --onlyoffice) setup_onlyoffice  ;;
            --nomachine)  setup_nomachine   ;;
            --teams)      setup_teams       ;;
            --all)        run_all_modules   ;;
            --help|-h)    usage             ;;
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
