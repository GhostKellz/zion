#!/usr/bin/env bash
# Zion system-wide installer script
# Run with sudo to install for all users

set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root${NC}"
  echo -e "Please use: sudo $0"
  exit 1
fi

# Check if Zig is installed
echo -e "${BLUE}Checking for Zig installation...${NC}"
if ! command -v zig &> /dev/null; then
  echo -e "${RED}Error: Zig is not installed or not in PATH${NC}"
  echo -e "Please install Zig from https://ziglang.org/download/"
  exit 1
fi

ZIG_VERSION=$(zig version)
echo -e "${GREEN}Found Zig: ${ZIG_VERSION}${NC}"

# Check for dependencies
echo -e "${BLUE}Checking for dependencies...${NC}"
for cmd in curl tar git; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "${RED}Error: $cmd is not installed${NC}"
    echo -e "Please install $cmd before continuing"
    exit 1
  fi
done
echo -e "${GREEN}All dependencies found${NC}"

# Temporary build directory
BUILD_DIR=$(mktemp -d)
echo -e "${BLUE}Using temporary build directory: $BUILD_DIR${NC}"

# Clone repository
echo -e "${BLUE}Cloning repository...${NC}"
git clone https://github.com/ghostkellz/zion "$BUILD_DIR/zion"
cd "$BUILD_DIR/zion"

# Build Zion
echo -e "${BLUE}Building Zion...${NC}"
zig build -Doptimize=ReleaseSafe

# Install to system
echo -e "${BLUE}Installing Zion to /usr/local/bin${NC}"
install -Dm755 "zig-out/bin/zion" "/usr/local/bin/zion"

# Install documentation
echo -e "${BLUE}Installing documentation...${NC}"
install -d "/usr/local/share/doc/zion"
install -Dm644 "README.md" "/usr/local/share/doc/zion/README.md"
install -Dm644 "COMMANDS.md" "/usr/local/share/doc/zion/COMMANDS.md"
install -Dm644 "DOCS.md" "/usr/local/share/doc/zion/DOCS.md"

# Install license if exists
if [ -f "LICENSE" ]; then
  install -Dm644 "LICENSE" "/usr/local/share/licenses/zion/LICENSE"
fi

# Clean up
echo -e "${BLUE}Cleaning up...${NC}"
rm -rf "$BUILD_DIR"

echo -e "${GREEN}Zion has been installed system-wide successfully!${NC}"
echo -e "Run 'zion --version' to verify the installation"
echo -e "Run 'zion help' to see available commands"