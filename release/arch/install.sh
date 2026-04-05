#!/usr/bin/env bash
# Zion Arch Linux installer helper
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Zion Installer for Arch Linux${NC}"

for cmd in pacman makepkg git curl tar zig; do
  if ! command -v "$cmd" &> /dev/null; then
    echo -e "${RED}Error: $cmd is not installed${NC}"
    exit 1
  fi
done

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo -e "${BLUE}Building Arch package...${NC}"
makepkg -f --nocheck

PKG_FILE=$(ls -1 zion-*.pkg.tar.* 2>/dev/null | head -n 1)
if [ -z "$PKG_FILE" ]; then
  echo -e "${RED}Failed to locate built package${NC}"
  exit 1
fi

echo -e "${BLUE}Installing package ${PKG_FILE}...${NC}"
sudo pacman -U --noconfirm "$PKG_FILE"

echo -e "${GREEN}Zion installed successfully.${NC}"
echo -e "Run 'zion version' and 'zion help' to verify the installation."
