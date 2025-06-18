#!/usr/bin/env bash
# Make all installation scripts executable
set -e

# Find the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Make all .sh files executable
echo "Making all scripts executable..."
find "$SCRIPT_DIR" -name "*.sh" -type f -exec chmod +x {} \;

echo "Scripts are now executable!"