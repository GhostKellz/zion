<p align="center">
  <img src="assets/logo/zion-transparent.png" alt="Zion Logo" width="200"/>
</p>

<h1 align="center">Zion</h1>

<p align="center">
  <strong>A Modern Package Manager for the Zig Programming Language</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Zig-F7A41D?style=for-the-badge&logo=zig&logoColor=white" alt="Zig">
  <img src="https://img.shields.io/badge/0.16.0--dev-F7A41D?style=for-the-badge&logo=zig&logoColor=white" alt="Zig 0.16.0-dev">
  <img src="https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=archlinux&logoColor=white" alt="Arch Linux">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Ed25519_Signing-8B5CF6?style=for-the-badge&logo=letsencrypt&logoColor=white" alt="Ed25519 Signing">
  <img src="https://img.shields.io/badge/Package_Manager-10B981?style=for-the-badge" alt="Package Manager">
  <img src="https://img.shields.io/badge/Version_Manager-3B82F6?style=for-the-badge" alt="Version Manager">
</p>


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
- **Lightweight onboarding** - Verify the core tools you need are installed
- **Follow-up guidance** - Pairs with `zion zig` and `zion zls` flows
- **Verification** - `zion setup verify` confirms everything works

```bash
zion setup all                       # Show setup guidance
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
- **GitHub shorthand** - `zion add gh/owner/repo@v1.0.0` syntax
- **Cryptographic security** - Ed25519 package signing and verification
- **Smart caching** - TTL-based cache for faster repeated fetches
- **Parallel downloads** - Connection pooling and batch processing
- **Dependency tree** - Visualize and detect circular dependencies
- **Dependency analysis** - `zion why <pkg>` explains dependency chains
- **Provenance tracking** - Full audit trail in lockfile (origin, hash, timestamp)

### 🏗️ Arch Linux Integration
- **Arch-aware** - Detects and works with `pacman`-installed Zig/ZLS
- **System PATH integration** - Honors filesystem hierarchy
- **AUR-ready** - PKGBUILD included for packaging

### 🛡️ Security & Policy
- **Package signing** - Ed25519 cryptographic signatures
- **Hash verification** - Integrity checking on all downloads
- **Trust store** - Manage trusted signers with `zion security trust`
- **Key generation** - Built-in key pair generation
- **Policy engine** - Allow/deny lists, hash requirements (`zion policy`)
- **Audit support** - `zion policy audit --json` for CI/CD integration

### 🎯 Cross-Compilation
- **Target management** - Configure build targets with `zion target add`
- **Common targets** - Linux, macOS, Windows, WebAssembly presets
- **Platform detection** - Automatic architecture and OS detection
- **Build integration** - `zig build -Dtarget=<triple>`

```bash
zion target add wasm32-wasi
zion target add aarch64-linux-gnu
zion target list
```

### 🚀 Developer Experience
- **Fast** - Optimized for quick command execution
- **Helpful errors** - "Did you mean?" suggestions with Levenshtein matching
- **Intelligent defaults** - Minimal configuration required
- **Diagnostics** - Detailed troubleshooting with `zion debug` and `zion check`

### 🧪 Testing Workflows
- **Zion-native workflow surface** - `zion test` now handles both direct test execution and higher-level workflow helpers
- **Starter suite generation** - Create a Zion-native suite under `tests/zion_test_suite.zig`
- **Reproducible controls** - Seeded runs, configurable case counts, and workflow time budgets
- **Focused execution** - Include/exclude filters, failed-only reruns, and CI profiles
- **Report output** - Write structured per-test JSON summaries under `.zion/test/reports/`

```bash
zion test bootstrap                  # Scaffold compatibility workflow
zion test run --seed 123 --cases 32 --include property
zion test bench --cases 50 --time-budget 250
zion test ci --ci-profile hardened
zion test report --open --include fuzz
```

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
7. Prints build integration guidance when automatic wiring is unavailable

After running this command, you can immediately use the library:
```zig
const libxev = @import("libxev");
```

### Advanced features

```bash
# GitHub shorthand syntax
zion add gh/mitchellh/libxev@v0.2.0

# Dependency analysis
zion why libxev                   # Why is this package in my tree?

# Policy management
zion policy init                  # Create policy file
zion policy audit --json          # Check compliance (CI-friendly)

# Cross-compilation targets
zion target add wasm32-wasi
zion target add aarch64-linux-gnu

# Security: Generate signing keys
zion security keygen

# Performance: Monitor cache efficiency
zion performance status

# Multiple packages at once
zion add mitchellh/libxev karlseguin/httpz ziglang/zig-clap
```

### Build your project

```bash
zig build
```

Your dependencies are now fully integrated and ready to use!

## Documentation

See the documentation index in [docs/README.md](docs/README.md).

Primary guides:
- [Installation](docs/getting-started/installation.md)
- [Commands Reference](docs/reference/commands.md)
- [Configuration Reference](docs/reference/configuration.md)
- [Registry Reference](docs/reference/registries.md)
- [Security Reference](docs/reference/security.md)
- [Zig And ZLS Reference](docs/reference/zig-and-zls.md)
- [Testing Overview](docs/testing/overview.md)
- [Documentation Index](docs/README.md)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
