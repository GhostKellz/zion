# Zion - A Modern Zig Development Tool

[![Made with Zig](https://img.shields.io/badge/Made%20with-Zig-orange.svg)](https://ziglang.org)
[![Zig 0.15+](https://img.shields.io/badge/Zig-0.15%2B-blue.svg)](https://ziglang.org/download)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-0.3.0-brightgreen.svg)](https://github.com/ghostkellz/zion/releases)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](https://github.com/ghostkellz/zion)

Zion is a modern, comprehensive development tool for the [Zig programming language](https://ziglang.org). Inspired by Cargo's elegance, Zion provides seamless package management, advanced security features, performance optimization, and powerful development tools - making Zig project development as smooth and professional as possible.

## ✨ Features

### 📦 Package Management
- **Automatic dependency management** - Add packages with `zion add username/repo`
- **Smart build integration** - Automatically modifies your `build.zig` file
- **Package extraction** - Downloads and extracts packages to `.zion/deps/`
- **Reproducible builds** - Lock files ensure consistent dependency versions
- **GitHub integration** - Direct support for GitHub repositories
- **Transitive dependencies** - Handles dependency chains automatically

### 🛡️ Security & Trust
- **Ed25519 package signing** - Cryptographic signature verification
- **Trust management system** - Signer reputation and trust levels
- **Package verification** - Ensures package integrity and authenticity
- **Secure key generation** - Built-in cryptographic key management

### 🚀 Performance & Optimization
- **Smart caching system** - TTL-based cache with 85%+ hit rates
- **Parallel downloads** - Connection pooling and batch processing
- **Performance monitoring** - Real-time metrics and optimization suggestions
- **Compression support** - Automatic cache compression for space efficiency

### 🔧 Development Tools
- **Project scaffolding** - Initialize new projects with `zion init`
- **Debug and analysis** - Project health checks and dependency debugging
- **Build troubleshooting** - Intelligent error diagnosis and suggestions
- **Clean management** - Remove build artifacts and caches
- **Package validation** - Ensures downloaded packages have proper structure

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

For detailed documentation on commands and usage, see [COMMANDS.md](COMMANDS.md).

For advanced usage, configuration options, and architecture details, see [DOCS.md](DOCS.md).

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.