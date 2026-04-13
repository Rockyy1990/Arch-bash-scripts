#!/bin/bash

# Reflector Script für deutsche Mirrors
# Dieses Script findet die 14 besten deutschen Mirrors und aktualisiert die Pacman-Datenbank

echo "=== Reflector - Deutsche Mirrorlist ==="
echo "Suche nach den 14 besten deutschen Mirrors..."
echo ""

# Reflector mit deutschen Mirrors ausführen
# -c DE: nur deutsche Mirrors
# -l 14: 14 Mirrors auswählen
# -p https DE: nur deutsche Mirrors
# -l 14: 14 Mirrors auswählen
# -p https: nur HTTPS-Protokoll
# -t 12: Timeout von 12 Sekunden
# --sort rate: nach Download-Geschwindigkeit sortieren
# --save: direkt in die Mirrorlist speichern
sudo pacman -S --needed --noconfirm reflector
clear

sudo reflector \
    -c DE \
    -l 14 \
    -p https \
    --sort rate \
    --save /etc/pacman.d/mirrorlist

# Überprüfen, ob Reflector erfolgreich war
if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Mirrorlist erfolgreich aktualisiert!"
    echo ""
    echo "=== Aktualisiere Pacman-Datenbank ==="

    # Pacman-Datenbank synchronisieren
    sudo pacman -Sy

    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Pacman-Datenbank erfolgreich aktualisiert!"
    else
        echo ""
        echo "✗ Fehler beim Aktualisieren der Pacman-Datenbank!"
        exit 1
    fi
else
    echo ""
    echo "✗ Fehler beim Aktualisieren der Mirrorlist!"
    exit 1
fi

echo ""
echo "=== Fertig! ==="
