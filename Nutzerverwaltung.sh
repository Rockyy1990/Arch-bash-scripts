#!/usr/bin/env bash
# manage_users.sh - Rechteverwaltungs-Skript für Arch Linux
# Datum: 2026-03-23

ORANGE='\033[0;33m'
NC='\033[0m'

# Prüfen ob sudo/root verfügbar; wenn nicht, neu starten mit sudo
if [ "$EUID" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    echo -e "${ORANGE}Nicht root. Starte mit sudo...${NC}"
    exec sudo "$0" "$@"
  else
    echo "Dieses Skript benötigt Root-Rechte und sudo ist nicht installiert."
    exit 1
  fi
fi

pause() {
  read -r -p "Drücke Enter zum Fortfahren..."
}

create_user() {
  read -r -p "Benutzername (login): " username
  if id "$username" >/dev/null 2>&1; then
    echo "Benutzer '$username' existiert bereits."
    return
  fi
  read -r -p "Vollständiger Name (geplant für GECOS, leer lassen für none): " gecos
  read -r -p "Home-Verzeichnis (leer = /home/$username): " homedir
  homedir=${homedir:-/home/$username}
  read -r -p "Shell (leer = /bin/bash): " shell
  shell=${shell:-/bin/bash}

  # useradd mit home directory, create, gecos und shell
  useradd -m -d "$homedir" -s "$shell" -c "$gecos" "$username"
  if [ $? -ne 0 ]; then
    echo "Fehler beim Anlegen des Benutzers."
    return
  fi

  # Passwort setzen
  echo "Bitte Passwort für $username setzen:"
  passwd "$username"

  echo "Benutzer '$username' wurde erstellt."
}

delete_user() {
  read -r -p "Benutzername zum Löschen: " username
  if ! id "$username" >/dev/null 2>&1; then
    echo "Benutzer '$username' existiert nicht."
    return
  fi
  read -r -p "Home-Verzeichnis ebenfalls löschen? (j/n): " delhome
  if [[ "$delhome" =~ ^[jJ] ]]; then
    userdel -r "$username"
  else
    userdel "$username"
  fi
  if [ $? -eq 0 ]; then
    echo "Benutzer '$username' wurde gelöscht."
  else
    echo "Fehler beim Löschen des Benutzers."
  fi
}

add_group() {
  read -r -p "Name der neuen Gruppe: " groupname
  if getent group "$groupname" >/dev/null 2>&1; then
    echo "Gruppe '$groupname' existiert bereits."
    return
  fi
  groupadd "$groupname"
  if [ $? -eq 0 ]; then
    echo "Gruppe '$groupname' wurde erstellt."
  else
    echo "Fehler beim Erstellen der Gruppe."
  fi
}

remove_group() {
  read -r -p "Name der zu entfernenden Gruppe: " groupname
  if ! getent group "$groupname" >/dev/null 2>&1; then
    echo "Gruppe '$groupname' existiert nicht."
    return
  fi
  groupdel "$groupname"
  if [ $? -eq 0 ]; then
    echo "Gruppe '$groupname' wurde entfernt."
  else
    echo "Fehler beim Entfernen der Gruppe."
  fi
}

show_user_groups() {
  read -r -p "Benutzername zur Gruppenanzeige: " username
  if ! id "$username" >/dev/null 2>&1; then
    echo "Benutzer '$username' existiert nicht."
    return
  fi
  # Ausgabe der Gruppen
  groups "$username"
}

edit_sudoers() {
  echo "Öffne sudoers mit visudo (sichere Methode)."
  echo "Wenn du eine Zeile hinzufügst, benutze die Syntax:"
  echo "  user ALL=(ALL) ALL"
  echo "oder für eine Gruppe (ohne %):"
  echo "  %group ALL=(ALL) ALL"
  read -r -p "Visudo öffnen? (j/n): " confirm
  if [[ ! "$confirm" =~ ^[jJ] ]]; then
    echo "Abgebrochen."
    return
  fi

  # Setze VISUAL/EDITOR auf nano wenn nicht gesetzt, fallback auf vi
  if ! command -v visudo >/dev/null 2>&1; then
    echo "visudo ist nicht verfügbar. Bitte installieren oder visudo manuell verwenden."
    return
  fi

  # Falls EDITOR nicht gesetzt ist, bevorzugt nano, sonst vi
  if [ -z "$EDITOR" ]; then
    if command -v nano >/dev/null 2>&1; then
      EDITOR=nano
    else
      EDITOR=vi
    fi
    export EDITOR
  fi

  visudo
  if [ $? -eq 0 ]; then
    echo "sudoers erfolgreich überprüft und gespeichert."
  else
    echo "visudo meldete einen Fehler. Änderungen nicht übernommen."
  fi
}

menu() {
  while true; do
    clear
    echo -e "${ORANGE}=== Rechteverwaltung Menü ===${NC}"
    echo -e "${ORANGE}1)${NC} Benutzer erstellen"
    echo -e "${ORANGE}2)${NC} Benutzer löschen"
    echo -e "${ORANGE}3)${NC} Gruppe hinzufügen"
    echo -e "${ORANGE}4)${NC} Gruppe entfernen"
    echo -e "${ORANGE}5)${NC} Gruppen eines Benutzers anzeigen"
    echo -e "${ORANGE}6)${NC} sudoers-Datei bearbeiten (visudo)"
    echo -e "${ORANGE}7)${NC} Beenden"
    read -r -p $'\nAuswahl: ' opt

    case "$opt" in
      1) create_user; pause;;
      2) delete_user; pause;;
      3) add_group; pause;;
      4) remove_group; pause;;
      5) show_user_groups; pause;;
      6) edit_sudoers; pause;;
      7) echo "Beenden."; exit 0;;
      *) echo "Ungültige Auswahl."; pause;;
    esac
  done
}

# Start des Menüs
menu
