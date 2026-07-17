<p align="center">
  <img src="assets/logo/zion-transparent.png" alt="Zion Logo" width="200"/>
</p>

<h1 align="center">Zion</h1>

<p align="center">
  <strong>A Zig Project, Toolchain, and Dependency Utility</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Zig-F7A41D?style=for-the-badge&logo=zig&logoColor=white" alt="Zig">
  <img src="https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=archlinux&logoColor=white" alt="Arch Linux">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Ed25519_Signing-8B5CF6?style=for-the-badge&logo=letsencrypt&logoColor=white" alt="Ed25519 Signing">
  <img src="https://img.shields.io/badge/Dependency_Metadata-10B981?style=for-the-badge" alt="Dependency Metadata">
  <img src="https://img.shields.io/badge/Version_Manager-3B82F6?style=for-the-badge" alt="Version Manager">
</p>


Zion is a development tool for the [Zig programming language](https://ziglang.org)
with project scaffolding, toolchain helpers, dependency metadata, and a built-in
test workflow. Registry-backed package resolution is still being hardened and
should be treated as experimental.

## 🚀 Quick Start

```bash
# Install Zion
curl -fsSL https://zion.cktech.sh | sudo bash

# Inspect setup guidance
zion setup all

# Create and inspect a project
zion init my-project && cd my-project
zion status
```

## ✨ Features

### 🔧 Zig Version Management
- Install, select, list, and remove supported Zig versions
- Detect a system Zig installation on supported hosts
- Download selected x86_64 Linux toolchains from ziglang.org
- Switch between Zion-managed and system toolchains

```bash
zion zig install 0.14.1              # Install stable release
zion zig use system                  # Use Arch system Zig
zion zig current                     # Show detailed status
```

### 🧠 ZLS Integration (Language Server)
- Health and compatibility checks
- Platform-specific installation guidance
- Local configuration generation
- Editor setup guidance

```bash
zion zls doctor                      # Check ZLS health
zion zls config                      # Generate optimal config
zion zls install                     # Installation guidance
```

### 🎯 Environment Setup
- **Lightweight onboarding** - Verify the core tools you need are installed
- **Follow-up guidance** - Pairs with `zion zig` and `zion zls` flows
- **Verification** - `zion setup verify` reports detected prerequisites

```bash
zion setup all                       # Show setup guidance
zion setup verify                    # Inspect detected prerequisites
```

### 📁 Workspace Management (Cargo-style)
- Organize related packages under a workspace
- Store shared workspace configuration
- Build workspace members
- Scaffold package structures

```bash
zion workspace init                  # Initialize workspace
zion workspace add mylib             # Add library package
zion workspace build                 # Build all packages
```

### 📦 Dependency Metadata

- Parse and update `build.zig.zon` dependency entries
- Maintain `zion.lock` metadata
- Parse GitHub shorthand such as `gh/owner/repo@<version>`
- Inspect local dependency trees and circular dependencies
- Explain recorded dependency chains with `zion why`

Remote registry search, resolution, and publishing are experimental. They are
not documented as release-ready until the registry client stops using placeholder
responses and has end-to-end fixture coverage.

### 🏗️ Arch Linux Integration
- Detects `pacman`-installed Zig and ZLS
- Includes Arch packaging files and manual build helpers

### 🛡️ Security & Policy
- Local Ed25519 signing and verification primitives
- Hash generation and verification commands
- GPG keyring inspection helpers
- Allow/deny and hash requirements through `zion policy`

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
- **Helpful errors** - "Did you mean?" suggestions with Levenshtein matching
- **Diagnostics** - Detailed troubleshooting with `zion debug` and `zion check`

### 🧪 Testing Workflows
- **Zion-native workflow surface** - `zion test` now handles both direct test execution and higher-level workflow helpers
- **Starter suite generation** - Create a Zion-native suite under `tests/zion_test_suite.zig`
- **Reproducible controls** - Seeded runs, configurable case counts, and workflow time budgets
- **Focused execution** - Include/exclude filters, failed-only reruns, and automation profiles
- **Report output** - Write structured per-test JSON summaries under `.zion/test/reports/`

```bash
zion test bootstrap                  # Scaffold compatibility workflow
zion test run --seed 123 --cases 32 --include property
zion test bench --cases 50 --time-budget 250
zion test ci --ci-profile hardened
zion test report --open --include fuzz
```

## Installation

The minimum supported Zig toolchain is declared in `build.zig.zon`. Check that
field before building; development snapshots change too quickly to duplicate in
documentation.

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

This creates a Zig project structure:
- `src/main.zig` - An example Zig program
- `build.zig` - A build script with Zion integration markers
- `build.zig.zon` - A manifest file for project metadata and dependencies

### Experimental dependency resolution

Registry-backed dependency resolution is not yet a stable workflow. The command
surface is available for development and fixture testing:

```bash
zion add mitchellh/libxev
```

Do not rely on this path for release automation until registry resolution and
transactional manifest updates pass the documented release gate.

### Advanced features

```bash
# GitHub shorthand syntax
zion add gh/mitchellh/libxev@v0.2.0

# Dependency analysis
zion why libxev                   # Why is this package in my tree?

# Policy management
zion policy init                  # Create policy file
zion policy audit --json          # Emit structured compliance output

# Cross-compilation targets
zion target add wasm32-wasi
zion target add aarch64-linux-gnu

# Security: Generate signing keys
zion security keygen

```

### Build your project

```bash
zig build
```

Build behavior is determined by the generated project and its manifest.

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
