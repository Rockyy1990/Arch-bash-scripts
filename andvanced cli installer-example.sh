#!/bin/bash

# Define orange color
ORANGE='\e[38;5;214m'
RESET='\e[0m'

# Function to display the menu
display_menu() {
    clear
    echo -e "${ORANGE}==============================${RESET}"
    echo -e "${ORANGE}      Advanced Installer       ${RESET}"
    echo -e "${ORANGE}==============================${RESET}"
    echo -e "${ORANGE}1) Install Software A         ${RESET}"
    echo -e "${ORANGE}2) Install Software B         ${RESET}"
    echo -e "${ORANGE}3) Configure System           ${RESET}"
    echo -e "${ORANGE}4) Run Updates                ${RESET}"
    echo -e "${ORANGE}5) Exit                       ${RESET}"
    echo -e "${ORANGE}==============================${RESET}"
    echo -ne "${ORANGE}Select an option [1-5]: ${RESET}"
}

# Function for installing Software A
install_software_a() {
    echo -e "${ORANGE}Installing Software A...${RESET}"
    # (Insert actual installation commands here)
    sleep 1
    echo -e "${ORANGE}Software A installed!${RESET}"
    read -p "Press Enter to continue..."
}

# Function for installing Software B
install_software_b() {
    echo -e "${ORANGE}Installing Software B...${RESET}"
    # (Insert actual installation commands here)
    sleep 1
    echo -e "${ORANGE}Software B installed!${RESET}"
    read -p "Press Enter to continue..."
}

# Function for configuring system
configure_system() {
    echo -e "${ORANGE}Configuring System...${RESET}"
    # (Insert actual configuration commands here)
    sleep 1
    echo -e "${ORANGE}System configured!${RESET}"
    read -p "Press Enter to continue..."
}

# Function for running updates
run_updates() {
    echo -e "${ORANGE}Running updates...${RESET}"
    # (Insert actual update commands here)
    sleep 1
    echo -e "${ORANGE}Updates completed!${RESET}"
    read -p "Press Enter to continue..."
}

# Main loop
while true; do
    display_menu
    read -r choice
    case $choice in
        1) install_software_a ;;
        2) install_software_b ;;
        3) configure_system ;;
        4) run_updates ;;
        5) echo -e "${ORANGE}Exiting...${RESET}" ; exit 0 ;;
        *) echo -e "${ORANGE}Invalid option, please try again.${RESET}" ; sleep 1 ;;
    esac
done
