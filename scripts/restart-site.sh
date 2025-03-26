#!/bin/bash
# /usr/local/bin/restart-site.sh

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --site-name) SITE_NAME="$2"; shift ;;  # Capture site name
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Ensure SITE_NAME is provided
if [[ -z "$SITE_NAME" ]]; then
    echo "Error: --site-name is required."
    exit 1
fi

# Define the target directory
SITE_DIR="$HOME/docker-sites/$SITE_NAME"

# Check if the directory exists
if [[ ! -d "$SITE_DIR" ]]; then
    echo "Error: Directory $SITE_DIR does not exist."
    exit 1
fi

# Run docker-compose without changing current directory
(
    cd "$SITE_DIR" || exit 1
    docker-compose down && docker-compose up -d
)