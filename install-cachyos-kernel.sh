#!/usr/bin/env bash
# install-cachyos-kernel.sh  –  v2.0
# Menü-basiertes Installations-/Verwaltungs-Skript für CachyOS-Kernel auf Arch Linux
# Nutzung: ./install-cachyos-kernel.sh  (sudo-Passwort wird automatisch abgefragt)

set -euo pipefail
IFS=$'\n\t'   # BUGFIX: war IFS=$'\n    \t' (Literal-Zeilenumbruch im Quelltext)

# ─── Farben & Formatierung ────────────────────────────────────────────────────
readonly C_RED='\033[0;31m'
readonly C_GRN='\033[0;32m'
readonly C_YLW='\033[1;33m'
readonly C_CYN='\033[0;36m'
readonly C_BLD='\033[1m'
readonly C_RST='\033[0m'

info()  { echo -e "${C_CYN}[INFO]${C_RST}  $*"; }
ok()    { echo -e "${C_GRN}[OK]${C_RST}    $*"; }
warn()  { echo -e "${C_YLW}[WARN]${C_RST}  $*" >&2; }
err()   { echo -e "${C_RED}[FEHLER]${C_RST} $*" >&2; }

# ─── Konfiguration ───────────────────────────────────────────────────────────
readonly LOG="/var/log/cachyos-kernel-installer.log"
readonly REPOFILE="/etc/pacman.d/cachyos.conf"
readonly PACMAN_CONF="/etc/pacman.conf"
readonly TMPDIR_BASE="/tmp/cachyos-installer.$$"
readonly MKINITCPIO_CMD="${MKINITCPIO_CMD:-/usr/bin/mkinitcpio}"
readonly GRUB_MKCONFIG_CMD="${GRUB_MKCONFIG_CMD:-/usr/bin/grub-mkconfig}"
readonly PACMAN_CMD="${PACMAN_CMD:-/usr/bin/pacman}"

# ─── Sudo-Eskalation ─────────────────────────────────────────────────────────
# BUGFIX: "\$0" war ein Escaped-Literal – sudo bekam den String '$0' übergeben,
#         nicht den tatsächlichen Skriptpfad. Korrigiert zu "$0".
require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo -e "${C_YLW}Root-Rechte erforderlich. Bitte sudo-Passwort eingeben:${C_RST}"
    # -E: Umgebungsvariablen (z.B. PAGER, PACMAN_CMD) beibehalten
    exec sudo -E bash "$0" "$@"
  fi
}

# ─── Logging ─────────────────────────────────────────────────────────────────
_init_log() {
  mkdir -p "$(dirname "$LOG")"
  touch "$LOG"
  echo "=== CachyOS Kernel Installer $(date -Iseconds) ===" >> "$LOG"
}

echolog() {
  echo -e "$@" | tee -a "$LOG"
}

# ─── Hilfsfunktionen ─────────────────────────────────────────────────────────

# BUGFIX: local prompt="\$1" → der Prompt wurde nie angezeigt, weil $1 nicht
#         expandiert wurde. Korrigiert zu local prompt="$1".
confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local ans
  if [[ "$default" == [Yy] ]]; then
    read -rp "$prompt [Y/n]: " ans
    case "$ans" in
      "" | [Yy] | [Yy][Ee][Ss]) return 0 ;;
      *) return 1 ;;
    esac
  else
    read -rp "$prompt [y/N]: " ans
    case "$ans" in
      [Yy] | [Yy][Ee][Ss]) return 0 ;;
      *) return 1 ;;
    esac
  fi
}

check_pacman() {
  if ! command -v "$PACMAN_CMD" &>/dev/null; then
    err "pacman nicht gefunden. Nur für Arch Linux / Arch-basierte Systeme."
    exit 1
  fi
}

safe_mkdirtmp() {
  mkdir -p "$TMPDIR_BASE"
  echo "$TMPDIR_BASE"
}

cleanup() {
  [[ -d "$TMPDIR_BASE" ]] && rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

# ─── Funktionen ──────────────────────────────────────────────────────────────

backup_initramfs() {
  echolog "Sichere aktuelle initramfs-Images..."
  local ts
  ts="$(date +%F-%H%M%S)"
  local found=0
  for img in /boot/initramfs-*.img; do
    [[ -e "$img" ]] || continue
    cp -av --preserve=mode,timestamps "$img" "${img}.bak-${ts}" 2>&1 | tee -a "$LOG"
    (( found++ )) || true
  done
  if (( found == 0 )); then
    warn "Keine initramfs-Images unter /boot gefunden."
  else
    ok "Backup abgeschlossen (${found} Image(s))."
  fi
}

# BUGFIX: Das Repo wurde in /etc/pacman.d/cachyos.conf geschrieben, aber nie in
#         /etc/pacman.conf eingetragen → Repo blieb dauerhaft wirkungslos.
#         Jetzt wird automatisch ein Include-Eintrag ergänzt.
add_cachyos_repo() {
  if [[ -f "$REPOFILE" ]]; then
    info "Repo-Datei $REPOFILE existiert bereits:"
    sed -n '1,20p' "$REPOFILE" | tee -a "$LOG"
  else
    cat > "$REPOFILE" <<'EOF'
[cachyos]
# SICHERHEITSHINWEIS: "TrustAll" deaktiviert die Signaturprüfung.
# Empfehlung: Importiere die offiziellen CachyOS-Keys und nutze stattdessen
#   SigLevel = Required DatabaseOptional
# Keys: https://github.com/CachyOS/CachyOS-PKGBUILDS
SigLevel = Optional TrustAll
Server = https://repo.cachyos.org/$arch
EOF
    chmod 644 "$REPOFILE"
    ok "Repo-Template geschrieben: $REPOFILE"
  fi

  # Prüfe ob Include bereits in pacman.conf vorhanden
  if grep -qF "Include = $REPOFILE" "$PACMAN_CONF" 2>/dev/null; then
    info "Include-Eintrag bereits in $PACMAN_CONF vorhanden."
  else
    if confirm "Include-Zeile in $PACMAN_CONF eintragen?" "y"; then
      # Füge den Block vor dem [core]-Abschnitt ein
      sed -i "/^\[core\]/i Include = ${REPOFILE}\n" "$PACMAN_CONF"
      ok "Include eingetragen. pacman.conf aktualisiert."
      warn "Bitte prüfe die Reihenfolge der Repos in $PACMAN_CONF manuell."
    else
      warn "Ohne Eintrag in pacman.conf bleibt das Repo inaktiv."
    fi
  fi

  info "Tipp: pacman-key --recv-keys ... && pacman-key --lsign-key ... für Key-Import."
}

list_cachyos_kernels() {
  info "Suche nach CachyOS-Kernelpaketen..."
  "$PACMAN_CMD" -Ss '^linux-cachyos' 2>&1 | tee -a "$LOG" \
    || warn "Keine Treffer oder pacman-Fehler (Repo eingetragen?)."
}

# BUGFIX: local pkg="\$1" → pkg war immer leer, Funktion brach sofort ab.
#         Korrigiert zu local pkg="$1".
install_kernel() {
  local pkg="$1"
  if [[ -z "$pkg" ]]; then
    err "Kein Paketname angegeben."
    return 1
  fi

  info "Aktualisiere Paketdatenbank..."
  if ! "$PACMAN_CMD" -Sy --noconfirm &>/dev/null; then
    warn "pacman -Sy fehlgeschlagen."
    confirm "Trotzdem fortfahren?" || { echolog "Abbruch."; return 1; }
  fi

  local headers_pkg="${pkg}-headers"
  info "Installiere: $pkg + $headers_pkg ..."
  if ! "$PACMAN_CMD" -S --noconfirm "$pkg" "$headers_pkg" 2>&1 | tee -a "$LOG"; then
    warn "Installation mit Headers fehlgeschlagen. Versuche nur $pkg ..."
    "$PACMAN_CMD" -S --noconfirm "$pkg" 2>&1 | tee -a "$LOG" \
      || { err "Installation von $pkg fehlgeschlagen."; return 1; }
  fi

  _rebuild_initramfs
  _update_bootloader
  ok "Installation von $pkg abgeschlossen."
}

# BUGFIX: local pkg="\$1" → selber Fehler wie in install_kernel().
uninstall_kernel() {
  local pkg="$1"
  if [[ -z "$pkg" ]]; then
    err "Kein Paketname angegeben."
    return 1
  fi
  if ! "$PACMAN_CMD" -Q "$pkg" &>/dev/null; then
    err "Paket $pkg ist nicht installiert."
    return 1
  fi

  # Sicherheitsprüfung: mindestens 2 Kernel installiert?
  local kernel_count
  kernel_count=$("$PACMAN_CMD" -Q | grep -cE '^linux[^ ]* ' || true)
  if (( kernel_count <= 1 )); then
    err "Es ist nur ein Kernel installiert. Entfernen würde das System unbootbar machen."
    return 1
  fi

  warn "Entfernen eines Kernels kann das System unbootbar machen!"
  confirm "Wirklich $pkg entfernen?" || { echolog "Abgebrochen."; return 1; }

  "$PACMAN_CMD" -Rns --noconfirm "$pkg" 2>&1 | tee -a "$LOG"
  _rebuild_initramfs
  _update_bootloader
  ok "Entfernung von $pkg abgeschlossen."
}

# BUGFIX: makepkg verweigert den Start als root → explizit als normaler User ausführen.
build_from_pkgbuild() {
  local giturl td pkgdir build_user

  read -rp "Git-URL des PKGBUILD-Repos (leer = Abbrechen): " giturl
  [[ -n "$giturl" ]] || { echolog "Abbruch."; return 1; }

  # makepkg darf nicht als root laufen → ermittle den aufrufenden User
  build_user="${SUDO_USER:-}"
  if [[ -z "$build_user" ]]; then
    err "Kein SUDO_USER gesetzt. Bitte das Skript via sudo aufrufen, nicht direkt als root."
    return 1
  fi

  if ! command -v git &>/dev/null; then
    err "git nicht gefunden. Bitte base-devel und git installieren."
    return 1
  fi
  if ! command -v makepkg &>/dev/null; then
    err "makepkg nicht gefunden. Bitte base-devel installieren."
    return 1
  fi

  td="$(safe_mkdirtmp)/pkgbuild"
  # Clone als normaler User
  sudo -u "$build_user" git clone --depth 1 "$giturl" "$td" 2>&1 | tee -a "$LOG" \
    || { err "git clone fehlgeschlagen."; return 1; }

  pkgdir="$(find "$td" -maxdepth 3 -type f -name PKGBUILD -exec dirname {} \; | head -n1 || true)"
  if [[ -z "$pkgdir" ]]; then
    err "Kein PKGBUILD im Repo gefunden."
    return 1
  fi

  ok "PKGBUILD gefunden: $pkgdir"
  # makepkg als normaler User ausführen (sudo für install-Schritt wird von makepkg -i intern gehandelt)
  cd "$pkgdir"
  sudo -u "$build_user" makepkg -si 2>&1 | tee -a "$LOG"
  ok "Build abgeschlossen. Temporäre Dateien werden aufgeräumt."
}

install_kernel_manager() {
  info "Suche CachyOS Kernel Manager im Repo..."

  if "$PACMAN_CMD" -Ss cachyos 2>/dev/null | grep -qi "kernel-manager"; then
    "$PACMAN_CMD" -S --noconfirm cachyos-kernel-manager 2>&1 | tee -a "$LOG"
    ok "Kernel Manager installiert (aus Repo)."
    return 0
  fi

  warn "Paket nicht im Repo gefunden. Versuche GitHub-Fallback..."
  local td
  td="$(safe_mkdirtmp)/kernel-manager"
  if command -v git &>/dev/null; then
    git clone --depth 1 https://github.com/CachyOS/kernel-manager "$td" 2>&1 | tee -a "$LOG" \
      || { err "Klonen fehlgeschlagen."; return 1; }
    ok "Repo geklont nach: $td"
    info "Folge der README für weitere Build/Install-Schritte."
    ls -la "$td" | tee -a "$LOG"
  else
    err "git nicht installiert."
    return 1
  fi
}

show_logs() {
  if [[ -f "$LOG" ]]; then
    ${PAGER:-less} "$LOG"
  else
    warn "Keine Logdatei vorhanden: $LOG"
  fi
}

update_system() {
  info "Systemupdate (pacman -Syu) ..."
  "$PACMAN_CMD" -Syu --noconfirm 2>&1 | tee -a "$LOG"
  ok "Update abgeschlossen."
}

# ─── Interne Helfer ───────────────────────────────────────────────────────────

_rebuild_initramfs() {
  if command -v "$MKINITCPIO_CMD" &>/dev/null; then
    info "Erstelle initramfs für alle Kernel..."
    "$MKINITCPIO_CMD" -P 2>&1 | tee -a "$LOG"
  else
    warn "mkinitcpio nicht gefunden – initramfs nicht aktualisiert."
  fi
}

_update_bootloader() {
  if command -v "$GRUB_MKCONFIG_CMD" &>/dev/null; then
    info "Aktualisiere GRUB-Konfiguration..."
    "$GRUB_MKCONFIG_CMD" -o /boot/grub/grub.cfg 2>&1 | tee -a "$LOG"
  else
    warn "grub-mkconfig nicht gefunden – bitte Bootloader manuell aktualisieren."
  fi
}

# ─── Menü ────────────────────────────────────────────────────────────────────

show_menu() {
  echo -e "\n${C_BLD}${C_CYN}╔══════════════════════════════════════════╗${C_RST}"
  echo -e "${C_BLD}${C_CYN}║     CachyOS Kernel Installer  v2.0       ║${C_RST}"
  echo -e "${C_BLD}${C_CYN}╠══════════════════════════════════════════╣${C_RST}"
  echo -e "${C_BLD}${C_CYN}║${C_RST}  ${C_BLD}1)${C_RST} CachyOS-Repo hinzufügen              ${C_CYN}║${C_RST}"
  echo -e "${C_BLD}${C_CYN}║${C_RST}  ${C_BLD}2)${C_RST} Verfügbare Kernel suchen             ${C_CYN}║${C_RST}"
  echo -e "${C_BLD}${C_CYN}║${C_RST}  ${C_BLD}3)${C_RST} Kernel installieren                  ${C_CYN}║${C_RST}"
  echo -e "${C_BLD}${C_CYN}║${C_RST}  ${C_BLD}4)${C_RST} Kernel deinstallieren                ${C_CYN}║${C_RST}"
  echo -e "${C_BLD}${C_CYN}║${C_RST}  ${C_BLD}5)${C_RST} Kernel aus PKGBUILD bauen            ${C_CYN}║${C_RST}"
  echo -e "${C_BLD}${C_CYN}║${C_RST}  ${C_BLD}6)${C_RST} CachyOS Kernel Manager installieren  ${C_CYN}║${C_RST}"
  echo -e "${C_BLD}${C_CYN}║${C_RST}  ${C_BLD}7)${C_RST} initramfs sichern                    ${C_CYN}║${C_RST}"
  echo -e "${C_BLD}${C_CYN}║${C_RST}  ${C_BLD}8)${C_RST} System aktualisieren (pacman -Syu)   ${C_CYN}║${C_RST}"
  echo -e "${C_BLD}${C_CYN}║${C_RST}  ${C_BLD}9)${C_RST} Logs anzeigen                        ${C_CYN}║${C_RST}"
  echo -e "${C_BLD}${C_CYN}║${C_RST}  ${C_BLD}0)${C_RST} Beenden                              ${C_CYN}║${C_RST}"
  echo -e "${C_BLD}${C_CYN}╚══════════════════════════════════════════╝${C_RST}"
}

# ─── Hauptlogik ──────────────────────────────────────────────────────────────

# sudo-Eskalation MUSS vor _init_log kommen, da /var/log root-Rechte braucht
require_root "$@"

_init_log
check_pacman

while true; do
  show_menu
  read -rp $'\n'"Wähle Option: " opt
  echo
  case "$opt" in
    1) add_cachyos_repo ;;
    2) list_cachyos_kernels ;;
    3)
      read -rp "Paketname (z.B. linux-cachyos): " PKG
      if [[ -z "$PKG" ]]; then
        warn "Kein Paketname eingegeben."
      else
        backup_initramfs
        install_kernel "$PKG"
      fi
      ;;
    4)
      read -rp "Zu entfernender Paketname: " PKG
      if [[ -z "$PKG" ]]; then
        warn "Kein Paketname eingegeben."
      else
        uninstall_kernel "$PKG"
      fi
      ;;
    5) build_from_pkgbuild ;;
    6) install_kernel_manager ;;
    7) backup_initramfs ;;
    8)
      if confirm "System vollständig aktualisieren?" "y"; then
        update_system
      else
        echolog "Abgebrochen."
      fi
      ;;
    9) show_logs ;;
    0)
      echolog "Beende."
      exit 0
      ;;
    *) warn "Ungültige Auswahl: '$opt'" ;;
  esac
done
