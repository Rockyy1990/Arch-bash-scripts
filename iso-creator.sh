#!/bin/bash

read -p "Usage: ./create-iso.sh /path/to/source /path/to/output.iso"

# Usage function
usage() {
    echo "Usage: $0 <source-directory> <output-iso-file>"
    exit 1
}

# Check the number of arguments
if [[ $# -ne 2 ]]; then
    usage
fi

SOURCE_DIR="$1"
OUTPUT_ISO="$2"

# Check if source directory exists
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "Error: Source directory '$SOURCE_DIR' does not exist."
    exit 1
fi

# Create the ISO file
mkisofs -o "$OUTPUT_ISO" \
        -b isolinux.bin \
        -c boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -R -J -v -T "$SOURCE_DIR"

# Check if mkisofs was successful
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create ISO file."
    exit 1
fi

echo "Bootable ISO created at '$OUTPUT_ISO'."