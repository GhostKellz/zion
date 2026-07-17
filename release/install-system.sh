#!/usr/bin/env bash
# Zion system-wide installer script
# Run with sudo to install for all users

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRATCH_ROOT="$REPO_ROOT/.scratch"
BUILD_DIR="$SCRATCH_ROOT/install-system-$$"

cleanup() {
  rm -rf "$BUILD_DIR"
  rmdir "$SCRATCH_ROOT" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

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
  echo -e "Please install the Zig version declared by build.zig.zon."
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

# Repository-scoped build directory
mkdir -p "$SCRATCH_ROOT"
echo -e "${BLUE}Using isolated build directory: $BUILD_DIR${NC}"

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
install -Dm644 "docs/README.md" "/usr/local/share/doc/zion/docs-index.md"
install -Dm644 "docs/getting-started/installation.md" "/usr/local/share/doc/zion/installation.md"
install -Dm644 "docs/reference/commands.md" "/usr/local/share/doc/zion/commands.md"

# Install man page (stamp version from build.zig.zon)
VERSION="$(sed -n 's/.*\.version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' build.zig.zon | head -1)"
install -d "/usr/local/share/man/man1"
sed "s/@VERSION@/$VERSION/g" "release/man/zion.1" > "/usr/local/share/man/man1/zion.1"
chmod 644 "/usr/local/share/man/man1/zion.1"

# Install shell completions
install -Dm644 "release/completions/zion.bash" "/usr/local/share/bash-completion/completions/zion"
install -Dm644 "release/completions/zion.zsh" "/usr/local/share/zsh/site-functions/_zion"
install -Dm644 "release/completions/zion.fish" "/usr/local/share/fish/vendor_completions.d/zion.fish"

# Install license if exists
if [ -f "LICENSE" ]; then
  install -Dm644 "LICENSE" "/usr/local/share/licenses/zion/LICENSE"
fi

# Clean up
echo -e "${BLUE}Cleaning up...${NC}"
cleanup

echo -e "${GREEN}Zion has been installed system-wide successfully!${NC}"
echo -e "Run 'zion --version' to verify the installation"
echo -e "Run 'zion help' to see available commands"
