#!/usr/bin/env bash

sudo tee /usr/local/bin/arch-maintenance > /dev/null << 'EOF'
#!/bin/bash

# Directories and files
LOG_DIR="/var/log/arch_maintenance"
UPDATE_LOG="$LOG_DIR/update.log"
TRIM_LOG="$LOG_DIR/trim.log"
CLEAN_LOG="$LOG_DIR/clean.log"
LOCK_DIR="/tmp/arch_maintenance"
UPDATE_LOCK="$LOCK_DIR/update.lock"
TRIM_LOCK="$LOCK_DIR/trim.lock"

# Colors for output
RED='033[0;31m'
GREEN='033[0;32m'
YELLOW='033[1;33m'
NC='033[0m' # No Color

# Function for initialization
initialize() {
    # Create log directory if it does not exist
    if [ ! -d "$LOG_DIR" ]; then
        mkdir -p "$LOG_DIR"
        chmod 755 "$LOG_DIR"
    fi

    # Create lock directory
    if [ ! -d "$LOCK_DIR" ]; then
        mkdir -p "$LOCK_DIR"
    fi

    # Create log files if they do not exist
    touch "$UPDATE_LOG" "$TRIM_LOG" "$CLEAN_LOG"
    chmod 644 "$UPDATE_LOG" "$TRIM_LOG" "$CLEAN_LOG"
}

# Function for system update
system_update() {
    if [ -f "$UPDATE_LOCK" ]; then
        echo -e "${YELLOW}Update is already running or was performed recently.${NC}" | tee -a "$UPDATE_LOG"
        return
    fi

    echo -e "${GREEN}Starting system update...${NC}" | tee -a "$UPDATE_LOG"
    echo "Update started at: $(date)" | tee -a "$UPDATE_LOG"
    touch "$UPDATE_LOCK"

    # Perform update
    if pacman -Syu --noconfirm; then
        echo -e "${GREEN}Update successfully completed at: $(date)${NC}" | tee -a "$UPDATE_LOG"
    else
        echo -e "${RED}Update failed at: $(date)${NC}" | tee -a "$UPDATE_LOG"
    fi
    rm -f "$UPDATE_LOCK"
}

# Function for fstrim
run_trim() {
    if [ -f "$TRIM_LOCK" ]; then
        echo -e "${YELLOW}TRIM is already running or was performed recently.${NC}" | tee -a "$TRIM_LOG"
        return
    fi

    echo -e "${GREEN}Starting SSD TRIM...${NC}" | tee -a "$TRIM_LOG"
    echo "TRIM started at: $(date)" | tee -a "$TRIM_LOG"
    touch "$TRIM_LOCK"

    # Perform TRIM for all partitions
    if fstrim -av; then
        echo -e "${GREEN}TRIM successfully completed at: $(date)${NC}" | tee -a "$TRIM_LOG"
    else
        echo -e "${RED}TRIM failed at: $(date)${NC}" | tee -a "$TRIM_LOG"
    fi
    rm -f "$TRIM_LOCK"
}

# Function for system cleanup
system_clean() {
    echo -e "${GREEN}Starting system cleanup...${NC}" | tee -a "$CLEAN_LOG"
    echo "Cleanup started at: $(date)" | tee -a "$CLEAN_LOG"
    
    # Clean package cache (keeps the latest versions)
    paccache -rk2

    # Remove uninstalled packages from cache
    paccache -ruk0

    # Remove orphaned packages
    orphans=$(pacman -Qtdq)
    if [ -n "$orphans" ]; then
        echo "Removing orphaned packages:" | tee -a "$CLEAN_LOG"
        pacman -Rns --noconfirm $orphans | tee -a "$CLEAN_LOG"
    else
        echo "No orphaned packages found." | tee -a "$CLEAN_LOG"
    fi

    # Cache cleanup for various users
    find /home -type d -name '.cache' -exec rm -rf {} \; 2>/dev/null
    echo -e "${GREEN}Cleanup completed at: $(date)${NC}" | tee -a "$CLEAN_LOG"
}

# Main function
main() {
    initialize

    # Default to perform all tasks
    local do_update=true
    local do_trim=false
    local do_clean=true

    # Check arguments
    while getopts "tuc" opt; do
        case $opt in
            t) do_trim=true ;;
            u) do_update=true ;;
            c) do_clean=true ;;
            *) echo "Usage: $0 [-t] [-u] [-c]" >&2
               exit 1 ;;
        esac
    done

    # Perform update
    if $do_update; then
        system_update
    fi

    # Perform TRIM (only if explicitly requested or every 3 weeks)
    if $do_trim || [ -z "$(find "$TRIM_LOG" -mtime -21 -print -quit)" ]; then
        run_trim
    fi

    # Perform cleanup
    if $do_clean; then
        system_clean
    fi

    echo -e "${GREEN}Maintenance tasks completed.${NC}"
}

main "$@"
EOF

sudo chmod +x /usr/local/bin/arch-maintenance

sudo mkdir -p /var/log/arch_maintenance
sudo chmod 755 /var/log/arch_maintenance

read -p "Open crontab with: sudo crontab -e and add the following lines:
   
# System update every 3 days
0 3 */3 * * /usr/local/bin/arch-maintenance -u -c

# TRIM every 3 weeks
0 4 * * 0 [ \$(($(date +%s) / 86400 % 21)) -eq 0 ] && /usr/local/bin/arch-maintenance -t

# Cleanup every week
0 5 * * 0 /usr/local/bin/arch-maintenance -c

Press any key to exit this script. You are done.
"
exit