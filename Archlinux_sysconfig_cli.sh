#!/usr/bin/env bash
# sysconfig_manage.sh - Systemkonfigurations-Verwaltung für Arch Linux
# Datum: 2026-03-23

ORANGE='\033[0;33m'
NC='\033[0m'
EDITOR_BIN="nano"

if ! command -v "$EDITOR_BIN" >/dev/null 2>&1; then
  echo "nano ist nicht installiert. Bitte installiere nano und starte das Skript erneut."
  exit 1
fi

backup_file() {
  local file="$1"
  if [ -e "$file" ]; then
    local bak="${file}.$(date +%Y%m%d%H%M%S).bak"
    cp -a -- "$file" "$bak" && echo "Backup: $bak"
  fi
}

prompt_use_sudo() {
  # returns 0 = use sudo, 1 = don't use sudo, 2 = abort (sudo requested but not installed)
  read -r -p "Mit sudo ausführen? (j/n): " use
  if [[ "$use" =~ ^[jJ] ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      echo "sudo ist nicht installiert. Aktion abgebrochen."
      return 2
    fi
    return 0
  else
    return 1
  fi
}

open_file_with_editor() {
  # Args: targetPath
  local target="$1"
  # If target is a symlink (except resolv.conf handled separately), resolve it
  if [ -L "$target" ] && [ "$target" != "/etc/resolv.conf" ]; then
    target=$(readlink -f "$target")
  fi
  if [ ! -e "$target" ]; then
    read -r -p "Datei $target existiert nicht. Neu anlegen? (j/n): " ans
    [[ "$ans" =~ ^[jJ] ]] || return 1
    touch "$target" || { echo "Konnte $target nicht anlegen."; return 1; }
  fi
  backup_file "$target"
  "$EDITOR_BIN" "$target"
}

open_file_with_optional_sudo() {
  # Args: targetPath
  local target="$1"
  prompt_use_sudo
  local pw=$?
  if [ $pw -eq 2 ]; then return 1; fi
  if [ $pw -eq 0 ]; then
    # use sudo to run editor on the target (preserve user environment for nano)
    sudo env "EDITOR=$EDITOR_BIN" "$EDITOR_BIN" "$target"
  else
    open_file_with_editor "$target"
  fi
  return $?
}

edit_bashrc() {
  # For normal user edit ~/.bashrc (current user)
  local user_bashrc="$HOME/.bashrc"
  open_file_with_optional_sudo "$user_bashrc"
}

edit_profile() {
  local target="/etc/profile"
  open_file_with_optional_sudo "$target"
}

edit_environment() {
  local target="/etc/environment"
  open_file_with_optional_sudo "$target"
}

edit_fstab() {
  local target="/etc/fstab"
  open_file_with_optional_sudo "$target"
}

edit_pacman() {
  local target="/etc/pacman.conf"
  open_file_with_optional_sudo "$target"
}

edit_pacman_mirrors() {
  local target="/etc/pacman.d/mirrorlist"
  if [ -e /etc/pacman.d/mirrorlist.pacnew ]; then
    echo "Achtung: /etc/pacman.d/mirrorlist.pacnew existiert. Bitte prüfen."
  fi
  open_file_with_optional_sudo "$target"
}

edit_resolv() {
  local target="/etc/resolv.conf"
  if [ -L "$target" ]; then
    echo "/etc/resolv.conf ist ein Symlink:"
    ls -l "$target"
    read -r -p "Symlink folgen und Ziel bearbeiten? (j/n): " follow
    if [[ "$follow" =~ ^[jJ] ]]; then
      target=$(readlink -f "$target")
    fi
  fi
  open_file_with_optional_sudo "$target"
}

manage_networkmanager() {
  PS3="Auswahl: "
  options=("Start/Enable NetworkManager" "Stop/Disable NetworkManager" "Status" "Edit /etc/NetworkManager/NetworkManager.conf" "Back")
  select opt in "${options[@]}"; do
    case $REPLY in
      1)
        prompt_use_sudo; pw=$?
        if [ $pw -eq 2 ]; then break; fi
        if [ $pw -eq 0 ]; then
          sudo systemctl enable --now NetworkManager.service && echo "NetworkManager enabled and started." || echo "Fehler."
        else
          systemctl enable --now NetworkManager.service && echo "NetworkManager enabled and started." || echo "Fehler (benötigt evtl. root)."
        fi
        read -r -p "Drücke Enter zum Zurückkehren..."
        break
        ;;
      2)
        prompt_use_sudo; pw=$?
        if [ $pw -eq 2 ]; then break; fi
        if [ $pw -eq 0 ]; then
          sudo systemctl disable --now NetworkManager.service && echo "NetworkManager stopped and disabled." || echo "Fehler."
        else
          systemctl disable --now NetworkManager.service && echo "NetworkManager stopped and disabled." || echo "Fehler (benötigt evtl. root)."
        fi
        read -r -p "Drücke Enter zum Zurückkehren..."
        break
        ;;
      3)
        prompt_use_sudo; pw=$?
        if [ $pw -eq 2 ]; then break; fi
        if [ $pw -eq 0 ]; then
          sudo systemctl status NetworkManager.service --no-pager
        else
          systemctl status NetworkManager.service --no-pager
        fi
        read -r -p "Drücke Enter zum Zurückkehren..."
        break
        ;;
      4)
        local target="/etc/NetworkManager/NetworkManager.conf"
        open_file_with_optional_sudo "$target"
        break
        ;;
      5) break;;
      *) echo "Ungültig.";;
    esac
  done
}

edit_hostname() {
  local target="/etc/hostname"
  open_file_with_optional_sudo "$target"
  read -r -p "Aktuellen Hostname mit hostnamectl setzen? (j/n): " ans
  if [[ "$ans" =~ ^[jJ] ]]; then
    prompt_use_sudo; pw=$?
    if [ $pw -eq 2 ]; then return 1; fi
    if [ $pw -eq 0 ]; then
      newh=$(sudo head -n1 /etc/hostname 2>/dev/null)
      [ -n "$newh" ] && sudo hostnamectl set-hostname "$newh" && echo "Hostname gesetzt: $newh"
    else
      newh=$(head -n1 /etc/hostname 2>/dev/null)
      [ -n "$newh" ] && hostnamectl set-hostname "$newh" && echo "Hostname gesetzt: $newh"
    fi
  fi
}

edit_hosts() {
  local target="/etc/hosts"
  open_file_with_optional_sudo "$target"
}

edit_makepkg() {
  local target="/etc/makepkg.conf"
  if [ ! -e "$target" ]; then
    read -r -p "$target nicht gefunden. Neu anlegen? (j/n): " ans
    [[ "$ans" =~ ^[jJ] ]] || return
  fi
  open_file_with_optional_sudo "$target"
}

pause() { read -r -p "Drücke Enter zum Fortfahren..."; }

menu() {
  while true; do
    clear
    echo -e "${ORANGE}=== Systemkonfig-Verwaltung ===${NC}"
    echo -e "${ORANGE}1)${NC} ~/.bashrc bearbeiten (aktueller Benutzer)"
    echo -e "${ORANGE}2)${NC} /etc/profile bearbeiten"
    echo -e "${ORANGE}3)${NC} /etc/environment bearbeiten"
    echo -e "${ORANGE}4)${NC} /etc/fstab bearbeiten"
    echo -e "${ORANGE}5)${NC} /etc/pacman.conf bearbeiten"
    echo -e "${ORANGE}6)${NC} Mirrorlist (/etc/pacman.d/mirrorlist) bearbeiten"
    echo -e "${ORANGE}7)${NC} /etc/resolv.conf bearbeiten"
    echo -e "${ORANGE}8)${NC} NetworkManager (systemweit) verwalten"
    echo -e "${ORANGE}9)${NC} Hostname (/etc/hostname) bearbeiten"
    echo -e "${ORANGE}10)${NC} /etc/hosts bearbeiten"
    echo -e "${ORANGE}11)${NC} /etc/makepkg.conf bearbeiten"
    echo -e "${ORANGE}12)${NC} Beenden"
    read -r -p $'\nAuswahl: ' opt

    case "$opt" in
      1) edit_bashrc; pause;;
      2) edit_profile; pause;;
      3) edit_environment; pause;;
      4) edit_fstab; pause;;
      5) edit_pacman; pause;;
      6) edit_pacman_mirrors; pause;;
      7) edit_resolv; pause;;
      8) manage_networkmanager; pause;;
      9) edit_hostname; pause;;
      10) edit_hosts; pause;;
      11) edit_makepkg; pause;;
      12) echo "Beenden."; exit 0;;
      *) echo "Ungültige Auswahl."; pause;;
    esac
  done
}

menu
