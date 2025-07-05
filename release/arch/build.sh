#!/usr/bin/env bash
# Manual build script for Zag on Arch Linux that uses the existing Zig installation
set -e

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Zag Manual Build Script for Arch Linux${NC}"

# Check for Zig
if ! command -v zig &> /dev/null; then
    echo -e "${RED}Error: Zig is not installed${NC}"
    echo -e "Please install Zig first:${NC}"
    echo -e "sudo pacman -S zig"
    echo -e "or"
    echo -e "yay -S zig-bin"
    exit 1
fi

ZIG_VERSION=$(zig version)
echo -e "${GREEN}Found Zig: ${ZIG_VERSION}${NC}"

# Get the repo root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"

# Build Zag with the dev version of Zig
echo -e "${BLUE}Building Zag using Zig ${ZIG_VERSION}...${NC}"
cd "$REPO_ROOT"
zig build -Doptimize=ReleaseSafe

# Check if build succeeded
if [ ! -f "$REPO_ROOT/zig-out/bin/zag" ]; then
    echo -e "${RED}Build failed. Binary not found at zig-out/bin/zag${NC}"
    exit 1
fi

echo -e "${GREEN}Build successful!${NC}"

# Install options
echo -e "${BLUE}Select installation method:${NC}"
echo -e "1) Install for current user only (to ~/.local/bin)"
echo -e "2) Install system-wide (requires sudo, to /usr/local/bin)"
echo -e "3) Don't install, just build"
read -p "Choice [1-3]: " -n 1 -r INSTALL_CHOICE
echo

case $INSTALL_CHOICE in
    1)
        echo -e "${BLUE}Installing for current user...${NC}"
        mkdir -p $HOME/.local/bin
        cp "$REPO_ROOT/zig-out/bin/zag" "$HOME/.local/bin/"
        
        # Check if ~/.local/bin is in PATH
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo -e "${YELLOW}Warning: ~/.local/bin is not in your PATH${NC}"
            echo -e "Add the following line to your ~/.bashrc or ~/.zshrc:${NC}"
            echo -e "${BLUE}export PATH=\"\$HOME/.local/bin:\$PATH\"${NC}"
            
            # Offer to add it
            read -p "Add to your shell configuration file now? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if [ -f "$HOME/.bashrc" ]; then
                    echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.bashrc
                    echo -e "${GREEN}Added to ~/.bashrc${NC}"
                    echo -e "Run 'source ~/.bashrc' to update your current session"
                elif [ -f "$HOME/.zshrc" ]; then
                    echo 'export PATH="$HOME/.local/bin:$PATH"' >> $HOME/.zshrc
                    echo -e "${GREEN}Added to ~/.zshrc${NC}"
                    echo -e "Run 'source ~/.zshrc' to update your current session"
                else
                    echo -e "${YELLOW}Could not find .bashrc or .zshrc${NC}"
                fi
            fi
        fi
        
        echo -e "${GREEN}Zag installed to ~/.local/bin/zag${NC}"
        
        # Install ZSH completion for user
        ZSH_USER_DIR="$HOME/.zsh/completions"
        if [ ! -d "$ZSH_USER_DIR" ]; then
            mkdir -p "$ZSH_USER_DIR"
        fi
        cp "$REPO_ROOT/release/completions/zag.zsh" "$ZSH_USER_DIR/_zag"
        echo -e "${GREEN}ZSH completion installed to $ZSH_USER_DIR/_zag${NC}"
        echo -e "${YELLOW}Add this to your .zshrc to enable completion:${NC}"
        echo -e "${BLUE}fpath=(~/.zsh/completions \$fpath)${NC}"
        echo -e "${BLUE}autoload -U compinit && compinit${NC}"
        ;;
    2)
        echo -e "${BLUE}Installing system-wide...${NC}"
        if command -v sudo &> /dev/null; then
            sudo cp "$REPO_ROOT/zig-out/bin/zag" "/usr/local/bin/"
            echo -e "${GREEN}Zag installed to /usr/local/bin/zag${NC}"
        else
            echo -e "${YELLOW}sudo not available, trying with su...${NC}"
            su -c "cp '$REPO_ROOT/zig-out/bin/zag' '/usr/local/bin/'"
            echo -e "${GREEN}Zag installed to /usr/local/bin/zag${NC}"
        fi
        
        # Install ZSH completion systemwide
        ZSH_COMPLETION_DIR="/usr/share/zsh/site-functions"
        if [ -d "$ZSH_COMPLETION_DIR" ]; then
            echo -e "${BLUE}Installing ZSH completion systemwide...${NC}"
            if command -v sudo &> /dev/null; then
                sudo cp "$REPO_ROOT/release/completions/zag.zsh" "$ZSH_COMPLETION_DIR/_zag"
                echo -e "${GREEN}ZSH completion installed to $ZSH_COMPLETION_DIR/_zag${NC}"
            else
                su -c "cp '$REPO_ROOT/release/completions/zag.zsh' '$ZSH_COMPLETION_DIR/_zag'"
                echo -e "${GREEN}ZSH completion installed to $ZSH_COMPLETION_DIR/_zag${NC}"
            fi
        else
            echo -e "${YELLOW}ZSH site-functions directory not found. Skipping ZSH completion installation.${NC}"
        fi
        
        # Install bash completion if available
        BASH_COMPLETION_DIR="/usr/share/bash-completion/completions"
        if [ -d "$BASH_COMPLETION_DIR" ]; then
            echo -e "${BLUE}Installing Bash completion systemwide...${NC}"
            if command -v sudo &> /dev/null; then
                sudo cp "$REPO_ROOT/release/completions/zag.bash" "$BASH_COMPLETION_DIR/zag"
                echo -e "${GREEN}Bash completion installed to $BASH_COMPLETION_DIR/zag${NC}"
            else
                su -c "cp '$REPO_ROOT/release/completions/zag.bash' '$BASH_COMPLETION_DIR/zag'"
                echo -e "${GREEN}Bash completion installed to $BASH_COMPLETION_DIR/zag${NC}"
            fi
        fi
        
        # Install man page
        MAN_DIR="/usr/local/share/man/man1"
        echo -e "${BLUE}Installing man page...${NC}"
        if command -v sudo &> /dev/null; then
            sudo mkdir -p "$MAN_DIR"
            sudo cp "$REPO_ROOT/release/man/zag.1" "$MAN_DIR/zag.1"
            sudo mandb &>/dev/null
            echo -e "${GREEN}Man page installed to $MAN_DIR/zag.1${NC}"
        else
            su -c "mkdir -p '$MAN_DIR' && cp '$REPO_ROOT/release/man/zag.1' '$MAN_DIR/zag.1' && mandb &>/dev/null"
            echo -e "${GREEN}Man page installed to $MAN_DIR/zag.1${NC}"
        fi
        ;;
    3)
        echo -e "${GREEN}Build completed. Binary is at:${NC}"
        echo -e "$REPO_ROOT/zig-out/bin/zag"
        ;;
    *)
        echo -e "${RED}Invalid option. Exiting.${NC}"
        exit 1
        ;;
esac

echo -e "${BLUE}All done!${NC}"
echo -e "Run 'zag help' to see available commands."