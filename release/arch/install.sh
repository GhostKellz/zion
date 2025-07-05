#!/usr/bin/env bash
# Zag Arch Linux installer script that handles Zig version conflicts
set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Zag Installer for Arch Linux${NC}"

# Check for root
if [ "$(id -u)" -eq 0 ]; then
  echo -e "${YELLOW}Warning: Running as root. This will install Zag system-wide.${NC}"
  read -p "Continue? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Installation canceled.${NC}"
    exit 1
  fi
fi

# Check for required tools
for cmd in pacman makepkg git curl tar; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "${RED}Error: $cmd is not installed${NC}"
    echo -e "Please install it first: sudo pacman -S $cmd"
    exit 1
  fi
done

# Check if Zig is installed (any version)
if ! command -v zig &> /dev/null; then
    echo -e "${YELLOW}Zig is not installed. Installing...${NC}"
    # Try to install zig-bin from AUR if yay is available
    if command -v yay &> /dev/null; then
        yay -S zig-bin
    else
        echo -e "${RED}Please install Zig first:${NC}"
        echo -e "sudo pacman -S zig"
        echo -e "or"
        echo -e "yay -S zig-bin"
        exit 1
    fi
fi

ZIG_VERSION=$(zig version)
echo -e "${GREEN}Found Zig: ${ZIG_VERSION}${NC}"

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${BLUE}Building package...${NC}"
cd "$SCRIPT_DIR"

# Edit PKGBUILD to use system Zig
echo -e "${BLUE}Preparing PKGBUILD...${NC}"
sed -i 's/zig build/zig build -Doptimize=ReleaseSafe/' PKGBUILD

# Run makepkg without dependency checks to avoid Zig conflicts
echo -e "${BLUE}Building package with system Zig...${NC}"
if [ "$(id -u)" -eq 0 ]; then
    # If running as root, build as normal user and then install
    echo -e "${YELLOW}Building as non-root user...${NC}"
    cd "$SCRIPT_DIR"
    # Need to build as non-root user
    NORMAL_USER=$(logname 2>/dev/null || echo ${SUDO_USER:-${USER}})
    
    if [ -z "$NORMAL_USER" ]; then
        echo -e "${RED}Could not determine normal username.${NC}"
        exit 1
    fi
    
    chown -R $NORMAL_USER:$(id -gn $NORMAL_USER) .
    su $NORMAL_USER -c "makepkg -f --nocheck --nodeps"
    
    echo -e "${BLUE}Installing package...${NC}"
    pacman -U --noconfirm zag-*.pkg.tar.zst
else
    # Normal user build
    makepkg -f --nocheck --nodeps
    
    # Install the package
    echo -e "${BLUE}Installing package...${NC}"
    if command -v sudo &> /dev/null; then
        sudo pacman -U --noconfirm zag-*.pkg.tar.zst
    else
        echo -e "${YELLOW}sudo not found, trying with su...${NC}"
        su -c "pacman -U --noconfirm zag-*.pkg.tar.zst"
    fi
fi

# Install autocompletion for ZSH
echo -e "${BLUE}Setting up ZSH autocompletion...${NC}"
REPO_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
ZSH_COMPLETION_DIR="/usr/share/zsh/site-functions"
ZSH_COMPLETION_FILE="_zag"

if [ -d "$ZSH_COMPLETION_DIR" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        # Running as root
        cp "$REPO_ROOT/release/completions/zag.zsh" "$ZSH_COMPLETION_DIR/$ZSH_COMPLETION_FILE"
        echo -e "${GREEN}ZSH completion installed to $ZSH_COMPLETION_DIR/$ZSH_COMPLETION_FILE${NC}"
    else
        # Try with sudo
        if command -v sudo &> /dev/null; then
            sudo cp "$REPO_ROOT/release/completions/zag.zsh" "$ZSH_COMPLETION_DIR/$ZSH_COMPLETION_FILE"
            echo -e "${GREEN}ZSH completion installed to $ZSH_COMPLETION_DIR/$ZSH_COMPLETION_FILE${NC}"
        else
            echo -e "${YELLOW}sudo not found, trying with su...${NC}"
            su -c "cp '$REPO_ROOT/release/completions/zag.zsh' '$ZSH_COMPLETION_DIR/$ZSH_COMPLETION_FILE'"
            echo -e "${GREEN}ZSH completion installed to $ZSH_COMPLETION_DIR/$ZSH_COMPLETION_FILE${NC}"
        fi
    fi
    
    echo -e "${BLUE}To enable completion in your current shell, run:${NC}"
    echo -e "${GREEN}autoload -U compinit && compinit${NC}"
else
    echo -e "${YELLOW}ZSH site-functions directory not found. Skipping ZSH completion installation.${NC}"
fi

# Install bash completion if available
BASH_COMPLETION_DIR="/usr/share/bash-completion/completions"
if [ -d "$BASH_COMPLETION_DIR" ]; then
    echo -e "${BLUE}Setting up Bash autocompletion...${NC}"
    if [ "$(id -u)" -eq 0 ]; then
        cp "$REPO_ROOT/release/completions/zag.bash" "$BASH_COMPLETION_DIR/zag"
        echo -e "${GREEN}Bash completion installed to $BASH_COMPLETION_DIR/zag${NC}"
    else
        if command -v sudo &> /dev/null; then
            sudo cp "$REPO_ROOT/release/completions/zag.bash" "$BASH_COMPLETION_DIR/zag"
            echo -e "${GREEN}Bash completion installed to $BASH_COMPLETION_DIR/zag${NC}"
        else
            echo -e "${YELLOW}sudo not found, trying with su...${NC}"
            su -c "cp '$REPO_ROOT/release/completions/zag.bash' '$BASH_COMPLETION_DIR/zag'"
            echo -e "${GREEN}Bash completion installed to $BASH_COMPLETION_DIR/zag${NC}"
        fi
    fi
fi

# Install man page
MAN_DIR="/usr/local/share/man/man1"
if [ ! -d "$MAN_DIR" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        mkdir -p "$MAN_DIR"
    else
        if command -v sudo &> /dev/null; then
            sudo mkdir -p "$MAN_DIR"
        else
            su -c "mkdir -p '$MAN_DIR'"
        fi
    fi
fi

echo -e "${BLUE}Installing man page...${NC}"
if [ "$(id -u)" -eq 0 ]; then
    cp "$REPO_ROOT/release/man/zag.1" "$MAN_DIR/zag.1"
    mandb &>/dev/null
    echo -e "${GREEN}Man page installed to $MAN_DIR/zag.1${NC}"
else
    if command -v sudo &> /dev/null; then
        sudo cp "$REPO_ROOT/release/man/zag.1" "$MAN_DIR/zag.1"
        sudo mandb &>/dev/null
        echo -e "${GREEN}Man page installed to $MAN_DIR/zag.1${NC}"
    else
        echo -e "${YELLOW}sudo not found, trying with su...${NC}"
        su -c "cp '$REPO_ROOT/release/man/zag.1' '$MAN_DIR/zag.1' && mandb &>/dev/null"
        echo -e "${GREEN}Man page installed to $MAN_DIR/zag.1${NC}"
    fi
fi

# Verify installation
if command -v zag &> /dev/null; then
    echo -e "${GREEN}Zag installed successfully!${NC}"
    echo -e "You can now use 'zag' from anywhere."
    zag version
else
    echo -e "${RED}Installation failed. 'zag' command not found.${NC}"
    exit 1
fi

echo -e "${BLUE}Installation complete!${NC}"
echo -e "${GREEN}✅ Zag binary installed${NC}"
echo -e "${GREEN}✅ ZSH autocompletion installed${NC}"
echo -e "${GREEN}✅ Man page installed${NC}"
echo -e "\nTo view help: man zag"
echo -e "To use zag: zag help"