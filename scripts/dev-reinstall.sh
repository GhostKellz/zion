#!/bin/bash

# 🔄 Quick Dev Reinstall Script for Zion v0.7.0
# Tailored for single developer workflow

set -e

echo "🔄 Quick Zion v0.7.0 dev reinstall..."

# Clean previous installation
echo "🧹 Cleaning previous installation..."
rm -f ~/.local/bin/zion
rm -f ~/.zsh/completions/_zion

# Build fresh v0.7.0
echo "🔨 Building v0.7.0..."
zig build -Doptimize=ReleaseSafe

# Install
echo "📦 Installing..."
mkdir -p ~/.local/bin ~/.zsh/completions
cp zig-out/bin/zion ~/.local/bin/
cp release/completions/zion.zsh ~/.zsh/completions/_zion

# Update PATH in .zshrc if needed
if ! grep -q "\.local/bin" ~/.zshrc 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
fi

# Update completion in .zshrc if needed  
if ! grep -q "\.zsh/completions" ~/.zshrc 2>/dev/null; then
    echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
    echo 'autoload -U compinit && compinit' >> ~/.zshrc
fi

# Test
export PATH="$HOME/.local/bin:$PATH"
echo "✅ Installed: $(zion version)"
echo ""
echo "🎉 Ready! Restart your shell or run: source ~/.zshrc"
echo "💡 Try: zion search-interactive"