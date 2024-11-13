#!/bin/bash

read -p "Das Paket dialog muss installiert sein"

# Eine Liste von Paketen, die zur Installation verfügbar sind
available_packages=(
    "vim"
    "htop"
    "git"
    "curl"
    "wget"
    "neofetch"
    "gcc"
    "make"
)

# Temporäre Datei zur Speicherung der Auswahl
tempfile=$(mktemp)

# Dialog für die Auswahl der Pakete
dialog --title "Arch Linux Paketinstallation" --checklist "Wählen Sie die zu installierenden Pakete aus:" 15 50 8 \
    "${available_packages[0]}" "Texteditor" off \
    "${available_packages[1]}" "Prozess-Viewer" off \
    "${available_packages[2]}" "Versionskontrollsystem" off \
    "${available_packages[3]}" "Datenübertragungsprogramm" off \
    "${available_packages[4]}" "Datenübertragungsprogramm" off \
    "${available_packages[5]}" "Systeminfo-Tool" off \
    "${available_packages[6]}" "C Compiler" off \
    "${available_packages[7]}" "Makefile-Tool" off \
    2> "$tempfile"

# Wenn der Benutzer abbricht
if [ $? -ne 0 ]; then
    echo "Installation abgebrochen."
    rm -f "$tempfile"
    exit
fi

# Pakete aus der temporären Datei lesen
selected_packages=($(<"$tempfile"))
rm -f "$tempfile"

# Pakete installieren
if [[ ${#selected_packages[@]} -gt 0 ]]; then
    echo "Installiere die folgenden Pakete: ${selected_packages[*]}"
    sudo pacman -S --needed --noconfirm "${selected_packages[@]}"
else
    echo "Keine Pakete ausgewählt."
fi
