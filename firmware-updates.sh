#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

msg() { printf '%s\n' "$*"; }
pause() {
  local prompt=${1:-"Press any key to continue..."}
  if [ -t 0 ]; then
    read -r -n1 -s -p "$prompt"
    printf '\n'
  else
    msg "$prompt (no TTY)"
  fi
}

for cmd in pacman fwupdmgr; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    msg "Fehler: $cmd ist nicht installiert oder nicht im PATH."
    exit 1
  fi
done

msg "Installiere/aktualisiere fwupd und fwupd-efi (falls nötig)..."
if ! sudo pacman -S --needed --noconfirm fwupd fwupd-efi; then
  msg "pacman-Installation fehlgeschlagen."
  exit 1
fi

pause $'Firmware updates. Drücke eine Taste, um fortzufahren...'
clear

msg "Geräte auflisten:"
sudo fwupdmgr get-devices || true

msg "fwupd Cache/Metadaten aktualisieren..."
sudo fwupdmgr refresh --force
sleep 2

msg "Verfügbare Firmware-Updates abrufen..."
updates_text=$(sudo fwupdmgr get-updates 2>/dev/null || true)

if printf '%s\n' "$updates_text" | grep -Ei 'no updates available|no devices were found' >/dev/null 2>&1; then
  msg "Keine Firmware-Updates gefunden."
  exit 0
fi

msg "Gefundene Updates:"
printf '%s\n' "$updates_text"

pause $'Starte Firmware-Update. Drücke eine Taste zum Fortfahren (oder Ctrl+C zum Abbrechen)...'

msg "Starte fwupdmgr update..."
if ! sudo fwupdmgr update -y; then
  msg "fwupdmgr update schlug fehl."
  exit 1
fi

msg "Update abgeschlossen. Prüfe, ob ein Neustart empfohlen wird..."
if sudo fwupdmgr get-devices 2>/dev/null | grep -Ei 'reboot|needs reboot|required' >/dev/null 2>&1; then
  pause $'Firmware installiert. Neustart empfohlen. Drücke eine Taste zum Neustart...'
  msg "Neustart wird ausgeführt..."
  sudo reboot
else
  msg "Keine Neustart-Empfehlung gefunden. Vorgang abgeschlossen."
fi
