<div align="center">
  <img src="assets/logo/zion-transparent.png" alt="Zion Logo" width="200"/>
</div>

# Zion - The Complete Zig Development Tool

[![Made with Zig](https://img.shields.io/badge/Made%20with-Zig-orange.svg)](https://ziglang.org)
[![Zig 0.16+](https://img.shields.io/badge/Zig-0.16%2B-blue.svg)](https://ziglang.org/download)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Releases](https://img.shields.io/github/v/release/ghostkellz/zion?color=brightgreen)](https://github.com/ghostkellz/zion/releases)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](https://github.com/ghostkellz/zion)
[![Arch Linux](https://img.shields.io/badge/Arch%20Linux-Supported-blue.svg)](https://archlinux.org)


Zion is a development tool for the [Zig programming language](https://ziglang.org) that combines package management (like Cargo) with version management (like rustup). Get a complete Zig development environment running quickly.

## 🚀 Quick Start

```bash
# Install Zion
curl -fsSL https://zion.cktech.sh | sudo bash

# Complete development environment setup
zion setup all

# You're ready! Create your first project
zion init my-project && cd my-project
zion add mitchellh/libxev
zion build
```

## ✨ Features

### 🔧 Zig Version Management
- **Complete version lifecycle** - Install, switch, and manage multiple Zig versions
- **System integration** - Seamless detection of Arch Linux package manager installations
- **Real downloads** - Official binaries from ziglang.org for x86_64-linux
- **Smart switching** - `zion zig use system` vs `zion zig use 0.14.1`
- **PATH management** - Automatic shell integration and environment setup

```bash
zion zig install 0.14.1              # Install stable release
zion zig install 0.15.0-dev.936+fc2c1883b  # Install dev build
zion zig use system                  # Use Arch system Zig
zion zig current                     # Show detailed status
```

### 🧠 ZLS Integration (Language Server)
- **Comprehensive diagnostics** - Health checks, compatibility verification
- **Intelligent installation** - Platform-specific guidance (Arch: `pacman -S zls`)
- **Optimal configuration** - Generate perfect ZLS settings automatically
- **Editor integration** - Neovim, VSCode, Emacs setup instructions
- **Mason compatibility** - Works with Neovim Mason installations

```bash
zion zls doctor                      # Comprehensive health check
zion zls config                      # Generate optimal config
zion zls install                     # Installation guidance
```

### 🎯 Environment Setup
- **Complete setup** - Full development environment in one command
- **Modular** - Install only what you need
- **Interactive wizard** - Guided configuration with smart defaults
- **Shell integration** - PATH, completions, profiles automatically configured
- **Verification** - `zion setup verify` confirms everything works

```bash
zion setup all                       # Complete environment
zion setup zig                       # Just Zig management
zion setup verify                    # Check everything works
```

### 📁 Workspace Management (Cargo-style)
- **Multi-package projects** - Organize related packages together
- **Shared configuration** - Unified build settings across packages
- **Parallel building** - Build all packages efficiently
- **Template scaffolding** - Auto-generate package structures

```bash
zion workspace init                  # Initialize workspace
zion workspace add mylib             # Add library package
zion workspace build                 # Build all packages
```

### 📦 Package Management
- **Multi-registry support** - GitHub, Zigistry, Zeppelin registries
- **Cryptographic security** - Ed25519 package signing and verification
- **Smart caching** - TTL-based cache for faster repeated fetches
- **Parallel downloads** - Connection pooling and batch processing
- **Dependency tree** - Visualize and detect circular dependencies

### 🏗️ Arch Linux Integration
- **Arch-aware** - Detects and works with `pacman`-installed Zig/ZLS
- **System PATH integration** - Honors filesystem hierarchy
- **AUR-ready** - PKGBUILD included for packaging

### 🛡️ Security
- **Package signing** - Ed25519 cryptographic signatures
- **Hash verification** - Integrity checking on all downloads
- **Trust store** - Manage trusted signers with `zion security trust`
- **Key generation** - Built-in key pair generation

### 🚀 Developer Experience
- **Fast** - Optimized for quick command execution
- **Helpful errors** - "Did you mean?" suggestions with Levenshtein matching
- **Intelligent defaults** - Minimal configuration required
- **Diagnostics** - Detailed troubleshooting with `zion debug` and `zion check`

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/ghostkellz/zion.git
cd zion

# Build the project
zig build -Doptimize=ReleaseSafe

# Install
zig build install
```

## Getting Started

### Initialize a new project

```bash
mkdir my-project
cd my-project
zion init
```

This creates a complete Zig project structure:
- `src/main.zig` - An example Zig program
- `build.zig` - A build script with Zion integration markers
- `build.zig.zon` - A manifest file for project metadata and dependencies

### Add dependencies

```bash
zion add mitchellh/libxev
```

Zion automatically:
1. Downloads and verifies the GitHub repository
2. Extracts it to `.zion/deps/libxev/`
3. Validates the package structure (build.zig, src/)
4. Calculates and stores SHA256 hash for integrity
5. Updates your `build.zig.zon` manifest
6. Creates/updates the `zion.lock` file
7. **Automatically modifies `build.zig`** to include the dependency

After running this command, you can immediately use the library:
```zig
const libxev = @import("libxev");
```

### Advanced features

```bash
# Security: Generate signing keys
zion security keygen

# Security: Sign a package
zion security sign mypackage.tar.gz

# Performance: Monitor cache efficiency
zion performance status

# Debug: Analyze project health
zion debug project

# Multiple packages at once
zion add mitchellh/libxev karlseguin/httpz ziglang/zig-clap
```

### Build your project

```bash
zig build
```

Your dependencies are now fully integrated and ready to use!

## Documentation

See the [docs/](docs/) folder for detailed documentation:
- [Installation Guide](docs/INSTALL.md)
- [Commands Reference](docs/COMMANDS.md)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
