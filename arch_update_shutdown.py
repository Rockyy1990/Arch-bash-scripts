#!/usr/bin/env python

import subprocess
import sys
import logging
import os

# Set up logging
logging.basicConfig(
    filename='system_upgrade.log',
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

def run_command(command):
    try:
        logging.info(f"Running command: {' '.join(command)}")
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as e:
        logging.error(f"An error occurred while running command: {e}")
        sys.exit(1)

def upgrade_system():
    logging.info("Updating the package database...")
    run_command(["pkexec", "pacman", "-Syu"])

def shutdown_system():
    logging.info("Shutting down the system...")
    run_command(["pkexec", "shutdown", "now"])

if __name__ == "__main__":
    if os.geteuid() == 0:
        # Only run if the script is not executed with root privileges
        upgrade_system()
        shutdown_system()
    else:
        logging.error("This script must be run with elevated privileges.")
        print("This script must be run with elevated privileges.")
        sys.exit(1)

