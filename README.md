# Zion - A Modern Zig Tool

[![Made with Zig](https://img.shields.io/badge/Made%20with-Zig-orange.svg)](https://ziglang.org)
[![Zig 0.15+](https://img.shields.io/badge/Zig-0.15%2B-blue.svg)](https://ziglang.org/download)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-0.3.0-brightgreen.svg)](https://github.com/ghostkellz/zion/releases)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](https://github.com/ghostkellz/zion)

Zion is a modern, cargo-inspired package manager for the [Zig programming language](https://ziglang.org). It provides seamless dependency management with automatic build integration, advanced security features, and performance optimizations, making Zig project development as smooth as possible.

## ✨ Features

- 📦 **Automatic dependency management** - Add packages with `zion add username/repo`
- 🔄 **Smart build integration** - Automatically modifies your `build.zig` file
- 📁 **Package extraction** - Downloads and extracts packages to `.zion/deps/`
- 🔒 **Reproducible builds** - Lock files ensure consistent dependency versions
- 🌐 **GitHub integration** - Direct support for GitHub repositories
- 🧩 **Project scaffolding** - Initialize new projects with `zion init`
- 🧹 **Clean command** - Remove build artifacts and caches
- ✅ **Package validation** - Ensures downloaded packages have proper structure
- 🔗 **Transitive dependencies** - Handles dependency chains automatically
- 🛡️ **Security system** - Ed25519 package signing and verification
- 🚀 **Performance optimization** - Smart caching and parallel downloads
- 🔧 **Debug tools** - Project analysis and troubleshooting capabilities

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

This will create:
- `src/main.zig` - An example Zig program
- `build.zig` - A build script for your project
- `build.zig.zon` - A manifest file for your project dependencies

### Add a dependency

```bash
zion add mitchellh/libxev
```

This will:
1. Download the GitHub repository tarball
2. Extract it to `.zion/deps/libxev/`
3. Validate the package structure
4. Calculate and verify SHA256 hash
5. Add it to your `build.zig.zon` file
6. Update the `zion.lock` file with exact versions
7. **Automatically modify `build.zig`** to include the dependency

After running this command, you can immediately use the library in your code:
```zig
const libxev = @import("libxev");
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