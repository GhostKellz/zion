#!/bin/bash

# 🔄 Zion Clean Uninstall + v0.7.0 Reinstall Script
# For single-user deployment - removes v0.6 and installs clean v0.7.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="$HOME/.local/bin"
COMPLETION_DIR="$HOME/.zsh/completions"
CONFIG_DIR="$HOME/.zion"
BACKUP_DIR="$HOME/.zion-backup-$(date +%Y%m%d-%H%M%S)"

echo -e "${CYAN}🔄 Zion Clean Uninstall + v0.7.0 Reinstall${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print step
print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Step 1: Backup existing configuration
print_step "Backing up existing Zion configuration..."
if [ -d "$CONFIG_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    cp -r "$CONFIG_DIR" "$BACKUP_DIR/"
    print_success "Configuration backed up to $BACKUP_DIR"
else
    print_warning "No existing configuration found"
fi

# Step 2: Complete uninstall of v0.6
print_step "Uninstalling Zion v0.6..."

# Remove binary
if [ -f "$INSTALL_DIR/zion" ]; then
    rm -f "$INSTALL_DIR/zion"
    print_success "Removed zion binary from $INSTALL_DIR"
else
    print_warning "No zion binary found in $INSTALL_DIR"
fi

# Remove from system paths (if installed system-wide)
if [ -f "/usr/local/bin/zion" ]; then
    sudo rm -f "/usr/local/bin/zion" 2>/dev/null || print_warning "Could not remove /usr/local/bin/zion (run with sudo if needed)"
fi

# Remove old completions
print_step "Removing old shell completions..."

# Zsh completions
if [ -f "$COMPLETION_DIR/_zion" ]; then
    rm -f "$COMPLETION_DIR/_zion"
    print_success "Removed zsh completion"
fi

# System-wide completions (best effort)
sudo rm -f "/usr/share/zsh/site-functions/_zion" 2>/dev/null || true
sudo rm -f "/usr/share/bash-completion/completions/zion" 2>/dev/null || true
rm -f "$HOME/.local/share/bash-completion/completions/zion" 2>/dev/null || true
rm -f "$HOME/.config/fish/completions/zion.fish" 2>/dev/null || true

# Remove manual pages
sudo rm -f "/usr/local/share/man/man1/zion.1" 2>/dev/null || true
rm -f "$HOME/.local/share/man/man1/zion.1" 2>/dev/null || true

print_success "Old installations cleaned up"

# Step 3: Prerequisites check
print_step "Checking prerequisites..."

# Check for Zig
if ! command_exists zig; then
    print_error "Zig is not installed. Please install Zig 0.11.0+ first."
    exit 1
fi

ZIG_VERSION=$(zig version)
print_success "Found Zig $ZIG_VERSION"

# Check for required tools
for tool in curl tar git; do
    if ! command_exists $tool; then
        print_error "$tool is required but not installed"
        exit 1
    fi
done

print_success "All prerequisites satisfied"

# Step 4: Build and install v0.7.0
print_step "Building Zion v0.7.0..."

# Ensure we're in the right directory
if [ ! -f "build.zig" ]; then
    print_error "Not in Zion project directory. Please run this script from the Zion repository root."
    exit 1
fi

# Clean build
rm -rf zig-cache zig-out

# Build with optimizations
zig build -Doptimize=ReleaseSafe

# Check if build succeeded
if [ ! -f "zig-out/bin/zion" ]; then
    print_error "Build failed - no binary produced"
    exit 1
fi

print_success "Zion v0.7.0 built successfully"

# Step 5: Install binary
print_step "Installing Zion v0.7.0..."

# Ensure install directory exists
mkdir -p "$INSTALL_DIR"

# Install binary
cp zig-out/bin/zion "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/zion"

print_success "Zion v0.7.0 installed to $INSTALL_DIR/zion"

# Step 6: Install shell completions
print_step "Installing shell completions..."

# Zsh completion
if [ -n "$ZSH_VERSION" ] || [ -f "$HOME/.zshrc" ]; then
    mkdir -p "$COMPLETION_DIR"
    cp release/completions/zion.zsh "$COMPLETION_DIR/_zion"
    
    # Add to fpath if not already there
    if ! grep -q "fpath=(.*$COMPLETION_DIR" "$HOME/.zshrc" 2>/dev/null; then
        echo "" >> "$HOME/.zshrc"
        echo "# Zion completion" >> "$HOME/.zshrc"
        echo "fpath=($COMPLETION_DIR \$fpath)" >> "$HOME/.zshrc"
        echo "autoload -U compinit && compinit" >> "$HOME/.zshrc"
        print_success "Added zsh completion and updated .zshrc"
    else
        print_success "Zsh completion installed (fpath already configured)"
    fi
fi

# Bash completion (if bash is available)
if [ -n "$BASH_VERSION" ] || [ -f "$HOME/.bashrc" ]; then
    mkdir -p "$HOME/.local/share/bash-completion/completions/"
    cp release/completions/zion.bash "$HOME/.local/share/bash-completion/completions/zion"
    print_success "Bash completion installed"
fi

# Fish completion (if fish is available)
if command_exists fish; then
    mkdir -p "$HOME/.config/fish/completions/"
    cp release/completions/zion.fish "$HOME/.config/fish/completions/"
    print_success "Fish completion installed"
fi

# Step 7: Verify installation
print_step "Verifying installation..."

# Check if binary is in PATH
if ! command_exists zion; then
    print_warning "Zion not found in PATH. You may need to:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    echo "  # Add this to your ~/.zshrc or ~/.bashrc"
    
    # Auto-add to PATH
    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q "$INSTALL_DIR" "$HOME/.zshrc"; then
            echo "" >> "$HOME/.zshrc"
            echo "# Zion PATH" >> "$HOME/.zshrc"
            echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$HOME/.zshrc"
            print_success "Added $INSTALL_DIR to PATH in .zshrc"
        fi
    fi
    
    # Temporarily add to PATH for verification
    export PATH="$INSTALL_DIR:$PATH"
fi

# Test basic functionality
if command_exists zion; then
    ZION_VERSION=$(zion version 2>/dev/null || echo "unknown")
    print_success "Zion v0.7.0 is working: $ZION_VERSION"
else
    print_error "Installation verification failed"
    exit 1
fi

# Step 8: Initialize v0.7.0 configuration
print_step "Initializing v0.7.0 configuration..."

# Let zion create its config directory
zion help > /dev/null 2>&1 || true

print_success "v0.7.0 configuration initialized"

# Step 9: Migration guidance
echo ""
echo -e "${MAGENTA}🎉 Zion v0.7.0 Installation Complete!${NC}"
echo -e "${MAGENTA}======================================${NC}"
echo ""
echo -e "${GREEN}✅ What's installed:${NC}"
echo "   • Zion v0.7.0 binary: $INSTALL_DIR/zion"
echo "   • Shell completions for your shell"
echo "   • PATH updated in your shell config"
echo ""
echo -e "${BLUE}🚀 New in v0.7.0:${NC}"
echo "   • Multi-registry support (GitHub, Zigistry, Zepplin)"
echo "   • Enhanced package search and filtering"
echo "   • Package signing and security verification"
echo "   • Development dependencies support"
echo "   • Parallel downloading for better performance"
echo "   • Enhanced configuration with environment variables"
echo ""
echo -e "${CYAN}📋 Next steps:${NC}"
echo "   1. Restart your shell or run: source ~/.zshrc"
echo "   2. Test with: zion version"
echo "   3. Try the new interactive search: zion search-interactive"
echo "   4. For existing projects, run: zion init (to upgrade them)"
echo ""
echo -e "${YELLOW}💾 Backup location:${NC}"
echo "   Your old configuration is backed up at: $BACKUP_DIR"
echo ""
echo -e "${GREEN}Happy packaging! 🦎✨${NC}"