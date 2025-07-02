#!/bin/bash

# Last Edit: 01.07.25

echo " Script to create Btrfs subvolumes and Snapper configuration
        ---------------------------------------------------------"
read -p "Press any key to continue.."

# Check if the script is running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Dieses Skript muss als root ausgeführt werden!"
  exit 1
fi

# Prüfen, ob Btrfs verwendet wird
if ! mount | grep -q "type btrfs"; then
  echo "Kein Btrfs-Dateisystem gefunden!"
  exit 1
fi

sudo pacman -S --needed --noconfirm grub-btrfs udisks2-btrfs python-btrfs compsize

# Pfad zum Wurzel-Dateisystem ermitteln
ROOT_DEV=$(findmnt -n -o SOURCE /)
ROOT_MNT=$(findmnt -n -o TARGET /)

# Wichtige Subvolumes definieren
SUBVOLUMES=(
  "@"          # Root-Subvolume
  "@home"      # Home-Verzeichnisse
  "@var"       # Variable Daten
  "@log"       # Log-Dateien
  "@cache"     # Cache-Dateien
  "@snapshots" # Snapshots
)

# Funktion zum Erstellen von Subvolumes
create_subvolume() {
  local path="$1"
  if [ ! -d "$path" ]; then
    echo "Erstelle Subvolume: $path"
    btrfs subvolume create "$path"
  else
    echo "Subvolume existiert bereits: $path"
  fi
}

# Funktion zum Erstellen von Snapper-Konfiguration
create_snapper_config() {
  local subvol="$1"
  local config_name="${subvol#@}"
  if [ -z "$config_name" ]; then
    config_name="root"
  fi
  
  if ! snapper list-configs | grep -q "$config_name"; then
    echo "Erstelle Snapper-Konfiguration für: $subvol"
    snapper -c "$config_name" create-config "$ROOT_MNT/$subvol"
  else
    echo "Snapper-Konfiguration existiert bereits für: $subvol"
  fi
}

# Hauptlogik
echo "=== Btrfs-Subvolumes und Snapper-Konfiguration ==="
echo "Wurzel-Gerät: $ROOT_DEV"
echo "Mount-Punkt:  $ROOT_MNT"
echo ""

# Subvolumes erstellen
for subvol in "${SUBVOLUMES[@]}"; do
  subvol_path="$ROOT_MNT/$subvol"
  create_subvolume "$subvol_path"
done

# Snapper installieren, falls noch nicht vorhanden
if ! command -v snapper &> /dev/null; then
  echo "Snapper ist nicht installiert. Installiere Snapper..."
  if command -v pacman &> /dev/null; then
    pacman -S --needed --noconfirm snapper snap-pac
  elif command -v apt &> /dev/null; then
    apt install -y snapper
  elif command -v dnf &> /dev/null; then
    dnf install -y snapper
  else
    echo "Paketmanager nicht erkannt! Bitte Snapper manuell installieren."
    exit 1
  fi
else
  echo "Snapper ist bereits installiert."
fi

# Snapper-Konfigurationen erstellen
for subvol in "@" "@home" "@var"; do
  create_snapper_config "$subvol"
done

# Basis-Konfiguration für Snapper aktualisieren
echo ""
echo "Aktualisiere Snapper-Basiskonfiguration..."

# Für Root-Konfiguration
snapper -c root set-config \
  NUMBER_LIMIT="50" \
  NUMBER_LIMIT_IMPORTANT="10" \
  TIMELINE_CREATE="yes" \
  TIMELINE_LIMIT_HOURLY="24" \
  TIMELINE_LIMIT_DAILY="7" \
  TIMELINE_LIMIT_WEEKLY="4" \
  TIMELINE_LIMIT_MONTHLY="12" \
  TIMELINE_LIMIT_YEARLY="2"

# Für Home-Konfiguration
snapper -c home set-config \
  NUMBER_LIMIT="30" \
  NUMBER_LIMIT_IMPORTANT="5" \
  TIMELINE_CREATE="yes" \
  TIMELINE_LIMIT_HOURLY="12" \
  TIMELINE_LIMIT_DAILY="7" \
  TIMELINE_LIMIT_WEEKLY="4" \
  TIMELINE_LIMIT_MONTHLY="6" \
  TIMELINE_LIMIT_YEARLY="1"

echo ""
echo "=== Fertig ==="
echo "Folgende Subvolumes wurden erstellt:"
btrfs subvolume list "$ROOT_MNT"
echo ""
echo "Folgende Snapper-Konfigurationen sind vorhanden:"
snapper list-configs
echo ""

# Fstab-Einträge als Kommentar ausgeben
echo "Bitte fügen Sie die folgenden Einträge zu Ihrer /etc/fstab hinzu:"
echo "# Btrfs Subvolumes"
for subvol in "${SUBVOLUMES[@]}"; do
  echo "# $ROOT_DEV/$subvol  /$subvol  btrfs  subvol=$subvol  0  0"
done

echo ""
echo "Stellen Sie sicher, dass Ihre /etc/fstab angepasst wird, um die neuen Subvolumes zu mounten!"