#!/usr/bin/env bash
# Local installation script for cktechdev's Arch workstation
# This script builds and installs zion, overwriting any existing installation
set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Zion Local Installation Script for cktechdev${NC}"
echo -e "${BLUE}This will build and install Zion, overwriting existing installation${NC}"

# Check for Zig
if ! command -v zig &> /dev/null; then
    echo -e "${RED}Error: Zig is not installed${NC}"
    echo -e "Please install Zig first: sudo pacman -S zig"
    exit 1
fi

ZIG_VERSION=$(zig version)
echo -e "${GREEN}Found Zig: ${ZIG_VERSION}${NC}"

# Get the repo root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$SCRIPT_DIR"

# Stop existing zion processes if any
if pgrep -x "zion" > /dev/null; then
    echo -e "${YELLOW}Stopping running zion processes...${NC}"
    pkill -x "zion" || true
fi

# Clean previous build
echo -e "${BLUE}Cleaning previous build...${NC}"
cd "$REPO_ROOT"
rm -rf zig-out zig-cache .zig-cache

# Build Zion
echo -e "${BLUE}Building Zion using Zig ${ZIG_VERSION}...${NC}"
zig build -Doptimize=ReleaseSafe

# Check if build succeeded
if [ ! -f "$REPO_ROOT/zig-out/bin/zion" ]; then
    echo -e "${RED}Build failed. Binary not found at zig-out/bin/zion${NC}"
    exit 1
fi

echo -e "${GREEN}Build successful!${NC}"

# Remove existing installation
if [ -f "/usr/local/bin/zion" ]; then
    echo -e "${YELLOW}Removing existing system installation...${NC}"
    sudo rm -f /usr/local/bin/zion
fi

if [ -f "$HOME/.local/bin/zion" ]; then
    echo -e "${YELLOW}Removing existing user installation...${NC}"
    rm -f "$HOME/.local/bin/zion"
fi

# Install system-wide
echo -e "${BLUE}Installing system-wide to /usr/local/bin...${NC}"
sudo cp "$REPO_ROOT/zig-out/bin/zion" "/usr/local/bin/zion"
sudo chmod +x "/usr/local/bin/zion"
echo -e "${GREEN}Zion installed to /usr/local/bin/zion${NC}"

# Install completions
ZSH_COMPLETION_DIR="/usr/share/zsh/site-functions"
BASH_COMPLETION_DIR="/usr/share/bash-completion/completions"

if [ -f "$REPO_ROOT/release/completions/zion.zsh" ] && [ -d "$ZSH_COMPLETION_DIR" ]; then
    echo -e "${BLUE}Installing ZSH completion...${NC}"
    sudo cp "$REPO_ROOT/release/completions/zion.zsh" "$ZSH_COMPLETION_DIR/_zion"
    echo -e "${GREEN}ZSH completion installed${NC}"
fi

if [ -f "$REPO_ROOT/release/completions/zion.bash" ] && [ -d "$BASH_COMPLETION_DIR" ]; then
    echo -e "${BLUE}Installing Bash completion...${NC}"
    sudo cp "$REPO_ROOT/release/completions/zion.bash" "$BASH_COMPLETION_DIR/zion"
    echo -e "${GREEN}Bash completion installed${NC}"
fi

# Install man page
MAN_DIR="/usr/local/share/man/man1"
if [ -f "$REPO_ROOT/release/man/zion.1" ]; then
    echo -e "${BLUE}Installing man page...${NC}"
    sudo mkdir -p "$MAN_DIR"
    sudo cp "$REPO_ROOT/release/man/zion.1" "$MAN_DIR/zion.1"
    sudo mandb &>/dev/null || true
    echo -e "${GREEN}Man page installed${NC}"
fi

# Verify installation
echo -e "${BLUE}Verifying installation...${NC}"
if command -v zion &> /dev/null; then
    INSTALLED_VERSION=$(zion --version 2>/dev/null || echo "unknown")
    echo -e "${GREEN}Zion installed successfully!${NC}"
    echo -e "${GREEN}Version: ${INSTALLED_VERSION}${NC}"
else
    echo -e "${RED}Installation verification failed${NC}"
    exit 1
fi

echo -e "${BLUE}All done! 🚀${NC}"
echo -e "Run 'zion help' to see available commands"
echo -e "Run 'man zion' to read the manual"