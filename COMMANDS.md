# Zion Commands Documentation

This document provides detailed information about all available commands in the Zion package manager.

## What's New in v1.1.0 🚀

Zion v1.1.0 "The Deep Integration Release" introduces revolutionary community features:

- **🌐 Multi-Registry Support** - Custom registries, Zepplin, Zigistry with priority fallback
- **🌟 Enhanced Ziglibs Integration** - Curated packages, quality indicators, category browsing
- **⚡ Advanced Zig Manager** - Cross-platform anyzig functionality with zsync async
- **🔥 Advanced Zigistry Features** - Publishing, analytics, trending packages, ratings
- **🧠 Deep ZLS Integration** - Real-time dependency monitoring, IDE optimization
- **🚀 Async Performance** - zsync runtime for blazing-fast operations

**New Commands:** `ziglibs`, `zigistry`, Enhanced `zig`, Enhanced `zls`, Enhanced `add`

## Command Reference

### `zion init`

Initializes a new Zig project with the necessary file structure.

```bash
zion init
```

**What it does:**
- Creates a `src/` directory if it doesn't exist
- Creates a `src/main.zig` file with a Hello World program
- Creates a `build.zig` file with a standard Zig build script
- Creates a `build.zig.zon` file with project metadata

**Options:** None currently available

### `zion add [package]`

Adds a package dependency to your project with full automation.

```bash
zion add username/repo
```

**What it does:**
- Downloads the package tarball from GitHub (currently only GitHub repositories are supported)
- Extracts the package to `.zion/deps/package_name/`
- Validates package structure (checks for build.zig and src/ directory)
- Calculates SHA256 hash of the downloaded tarball
- Adds the dependency to your `build.zig.zon` file
- Updates the `zion.lock` file with exact version information
- **Automatically modifies `build.zig`** to include the new dependency
- Provides fallback instructions if automatic integration fails

**Examples:**
```bash
zion add mitchellh/libxev  # Add libxev from GitHub
zion add ziglang/zig-clap  # Add command-line parser
```

### `zion fetch [package[@version]]` ⭐ **New in v0.4.0**

Fetches dependencies or specific packages with optional version specification.

```bash
zion fetch                          # Fetch all dependencies from build.zig.zon
zion fetch username/repo            # Fetch latest version of specific package
zion fetch username/repo@1.0.0      # Fetch specific version
```

**What it does:**
- **No arguments**: Fetches all dependencies listed in `build.zig.zon`
- **Package only**: Fetches latest version from GitHub releases/tags
- **Package@version**: Fetches specific version with automatic hash calculation
- Automatically discovers GitHub releases and tags
- Downloads and caches packages for later use
- Provides suggestions for adding to project

**Examples:**
```bash
zion fetch                             # Fetch all project dependencies
zion fetch ghostkellz/zcrypto          # Fetch latest zcrypto
zion fetch ghostkellz/zcrypto@0.2.0    # Fetch specific version
zion fetch mitchellh/libxev@v0.1.5     # Works with v-prefixed tags
```

### `zion pin <package>@<version>` ⭐ **New in v0.4.0**

Pins a dependency to a specific version for reproducible builds.

```bash
zion pin package@version
```

**What it does:**
- Locks an existing dependency to a specific version/tag
- Automatically discovers available versions from GitHub
- Downloads and verifies the specified version
- Updates `build.zig.zon` with new URL and hash
- Updates lock file with pinned version information
- Extracts package to deps directory

**Examples:**
```bash
zion pin libxev@0.2.0         # Pin to exact version
zion pin zcrypto@v1.0.1       # Pin to tagged version
```

**Requirements:**
- Package must already be added to the project
- Version must exist in GitHub releases or tags

### `zion unpin <package>` ⭐ **New in v0.4.0**

Unpins a dependency to track the latest version.

```bash
zion unpin package
```

**What it does:**
- Removes version pin from an existing dependency
- Switches to tracking latest release or main branch
- Automatically fetches and updates to latest version
- Updates `build.zig.zon` with new URL and hash
- Updates lock file to remove pin information
- Extracts latest version to deps directory

**Examples:**
```bash
zion unpin libxev            # Track latest libxev version
zion unpin zcrypto           # Switch to latest zcrypto
```

### `zion repair` ⭐ **New in v0.4.0**

Automatically repairs broken hashes and dependency issues.

```bash
zion repair
```

**What it does:**
- Scans all dependencies for hash mismatches
- Re-downloads packages with broken hashes
- Recalculates and updates hashes in `build.zig.zon`
- Updates lock file with corrected information
- Extracts repaired packages to deps directory
- Provides detailed repair report

**Use cases:**
- Hash mismatch errors after upstream changes
- Corrupted cache files
- Missing or broken dependency files
- Lock file inconsistencies

**Example output:**
```
🔧 Repairing project dependencies...
📋 Found 3 dependencies to check

🔍 Checking libxev...
  🔥 Hash mismatch!
  ⬇️  Re-downloading...
  🔧 Updating hash in manifest...
  ✅ Hash updated: 1234abcd...

🎉 All issues repaired successfully!
```

### `zion check` ⭐ **New in v0.4.0**

Performs comprehensive dependency health auditing.

```bash
zion check
```

**What it does:**
- Verifies URL accessibility for all dependencies
- Checks hash integrity of cached packages
- Validates package structure and build files
- Compares lock file consistency
- Checks for available updates
- Analyzes project structure
- Provides detailed health report

**Health checks performed:**
- ✅ URL accessibility
- ✅ Hash verification
- ✅ Package extraction status
- ✅ Lock file consistency
- ✅ Update availability
- ✅ Project structure validation

**Example output:**
```
🩺 Checking project health...
📋 Analyzing 3 dependencies...

🔍 Checking libxev...
  ✅ URL accessible
  ✅ Hash verified
  ✅ Package structure looks good
  ✅ Lock file consistent
  📦 New version available: 0.3.0

🎯 Overall Status: ⚠️  WARNINGS
💡 Some issues found, but project should still work.
   Consider running 'zion repair' or 'zion update' to fix them.
```

**Directory structure after adding:**
```
your-project/
├── build.zig              # ← Automatically updated!
├── build.zig.zon          # ← Updated with dependency
├── zion.lock               # ← Updated with package info
├── .zion/
│   ├── cache/
│   │   └── mitchellh_libxev.tar.gz
│   └── deps/
│       └── libxev/        # ← Extracted package
│           ├── build.zig
│           ├── src/
│           └── ...
```

**Pro tip:** Add this marker to your `build.zig` for perfect dependency placement:
```zig
// zion:deps - dependencies will be added below this line
```

### `zion remove [package]` / `zion rm [package]`

Removes a package dependency from your project with complete cleanup.

```bash
zion remove package_name
zion rm package_name     # Short alias
```

**What it does:**
- Validates that the package exists in your `build.zig.zon` file
- Removes the dependency from your `build.zig.zon` file
- Updates the `zion.lock` file to remove the package entry
- **Automatically removes the dependency from `build.zig`** (blocks added by `zion add`)
- Deletes the package directory from `.zion/deps/package_name/`
- Provides comprehensive feedback about all actions taken

**Examples:**
```bash
zion remove libxev       # Remove libxev dependency
zion rm zig-clap         # Remove using short alias
```

**Sample output:**
```
Removing package: libxev
Checking build.zig.zon for package libxev...
Removing libxev from build.zig.zon...
Updating lock file...
Removing from build.zig...
  ✓ Removed libxev module definition from build.zig
Removing package directory .zion/deps/libxev...
✅ Successfully removed libxev
Actions taken:
  ✓ Removed from build.zig.zon
  ✓ Updated zion.lock
  ✓ Removed from build.zig (if found)
  ✓ Deleted .zion/deps/libxev/ (if found)
```

**Error handling:**
- If package doesn't exist, shows available packages
- Gracefully handles missing files or directories
- Warns about manual dependencies that couldn't be auto-removed

### `zion update`

Updates all dependencies to their latest versions by re-downloading from GitHub.

```bash
zion update
```

**What it does:**
- Loads the current `build.zig.zon` and `zion.lock` files
- For each dependency, re-downloads the tarball from its GitHub URL
- Computes new SHA256 hash and compares with current hash
- **If hash changed:** Updates both manifest files and extracts new version
- **If unchanged:** Shows "Up to date" status and skips processing
- Provides comprehensive summary of updated vs unchanged packages

**Example output:**
```
Updating dependencies...
Checking 2 dependencies for updates...

📦 Checking libxev...
  🔄 Hash changed! Updating...
    Old: 1220abc123def456
    New: 1220def789abc123
  📁 Extracting to .zion/deps/libxev...

📦 Checking zig-clap...
  ✓ Up to date (hash: 1220fed456abc789)

✅ Updated build.zig.zon
✅ Updated zion.lock

📋 Update Summary:
🔄 Updated packages (1):
  - libxev
✅ Up-to-date packages (1):
  - zig-clap

🚀 Updated 1 package(s). Run 'zig build' to use the latest versions.
```

**Benefits:**
- Keep dependencies current with upstream changes
- Automatically updates both manifest and lock files
- Only re-extracts packages that actually changed
- Maintains reproducible builds with exact hashes
- Clear feedback about what was updated

### `zion list` / `zion ls`

Lists all dependencies in the project with their installation status.

```bash
zion list              # Table format
zion ls                # Short alias
zion list --json       # JSON output format
```

**What it does:**
- Displays all dependencies from `build.zig.zon` in a clean table format
- Shows installation status (✅ Installed or ❌ Missing) for each package
- Extracts and displays GitHub repository information
- Provides summary statistics (total, installed, missing)
- Detects hash mismatches between manifest and lock file
- **JSON mode:** Outputs machine-readable JSON array with `--json` flag

**Example table output:**
```
📦 Dependencies for project 'my-project' v0.1.0:
──────────────────────────────────────────────────────────────────────
Name                 Status     Repository                     Hash
──────────────────────────────────────────────────────────────────────
libxev               ✅ Installed mitchellh/libxev                 1220abc123de...
zig-clap             ❌ Missing   Hejsil/zig-clap                1220def456ab...
──────────────────────────────────────────────────────────────────────
Total: 2 dependencies, 1 installed, 1 missing

💡 Run 'zion fetch' to install missing dependencies.
```

**JSON output features:**
- Machine-readable format for tooling integration
- Complete package information including timestamps
- Installation status and file paths
- Repository owner/name extraction

### `zion info [package]`

Shows detailed information about a specific package dependency.

```bash
zion info package_name
```

**What it does:**
- Validates that the package exists in your dependencies
- Displays comprehensive package information including name, URL, and hash
- Shows installation status and file location
- **Lock file integration:** Displays timestamp, version, and sync status
- **Repository parsing:** Extracts GitHub owner and repository name
- **Hash validation:** Warns if manifest and lock file hashes differ
- Provides relevant command suggestions based on package status

**Example output:**
```
📦 Package Information: libxev
──────────────────────────────────────────────────
📍 Name:        libxev
🔗 URL:         https://github.com/mitchellh/libxev/archive/refs/heads/main.tar.gz
🔒 Hash:        1220abc123def456
📦 Full Hash:   1220abc123def456789012345678901234567890abcdef
✅ Status:      Installed
📁 Location:    .zion/deps/libxev

🔒 Lock File Information:
🕐 Timestamp:   1701234567
📅 Added:       1701234567 (Unix timestamp)
✅ Hash Match:  Manifest and lock file are synchronized

🌐 Repository Information:
🏠 Repository:  https://github.com/mitchellh/libxev
👤 Owner:       mitchellh
📚 Repository:  libxev

💡 Commands:
   zion update          # Update all packages
   zion remove libxev   # Remove this package
```

**Error handling:**
- Shows available packages if specified package not found
- Warns about missing build.zig or src/ directory in packages
- Alerts about hash mismatches between manifest and lock file

### `zion clean`

Removes cache and build artifacts to free up disk space.

```bash
zion clean              # Remove .zig-cache and .zion/cache
zion clean --all        # Remove all build artifacts and lock files
```

**What it does:**
- **Default mode:** Removes `.zig-cache/` and `.zion/cache/` directories
- **With `--all` flag:** Also removes `zig-out/` and `zion.lock` files

**Examples:**
```bash
zion clean              # Basic cleanup
zion clean --all        # Complete cleanup including lockfile
```

**Output:**
```
Deleted .zig-cache/
Deleted .zion/cache/
```

### `zion fetch`

Fetches all dependencies specified in your `build.zig.zon` file.

```bash
zion fetch
```

**What it does:**
- Reads the `build.zig.zon` file to determine dependencies
- Compares with `zion.lock` file (if it exists)
- Downloads any missing packages
- Verifies hashes of downloaded packages
- Updates the lock file if needed

**Options:** None currently available

### `zion lock`

Updates or creates the lock file based on your `build.zig.zon` dependencies.

```bash
zion lock
```

**What it does:**
- Reads the `build.zig.zon` file
- Creates or updates the `zion.lock` file with current dependencies
- Doesn't download any packages if they're not cached

**Options:** None currently available

### `zion build`

Builds your project using the Zig build system.

```bash
zion build
```

**What it does:**
- Verifies that `build.zig.zon` exists
- Invokes the Zig build system

**Options:** None currently available. All arguments after the build command are passed to Zig's build system.

### `zion version`

Displays the current version of Zion.

```bash
zion version
```

**Output example:**
```
zion 0.2.0-dev
```

### `zion help`

Displays help information about available commands.

```bash
zion help
```

---

## 🌟 New Commands in v1.1.0

### `zion ziglibs` - Enhanced Ziglibs Integration

Complete integration with the Ziglibs community collection for high-quality, vetted packages.

#### `zion ziglibs list [category]`

Browse all Ziglibs packages with optional category filtering.

```bash
zion ziglibs list                    # All packages
zion ziglibs list network            # Network-related packages
zion ziglibs list crypto             # Cryptography packages
```

**Features:**
- Quality indicators and maintenance status
- Categorized package organization  
- Enhanced metadata display
- Community-vetted package showcase

#### `zion ziglibs search <query>`

Search within Ziglibs packages only for highest quality results.

```bash
zion ziglibs search http             # Search HTTP libraries in Ziglibs
zion ziglibs search json             # Find JSON parsers
```

#### `zion ziglibs status`

Show Ziglibs packages used in the current project.

```bash
zion ziglibs status                  # Display project Ziglibs usage
```

#### `zion ziglibs categories`

List available package categories for browsing.

```bash
zion ziglibs categories              # Show all available categories
```

### `zion zigistry` - Advanced Zigistry Integration

Enhanced features for the Zigistry package registry with analytics and publishing.

#### `zion zigistry login`

Authenticate with Zigistry for publishing and enhanced features.

```bash
zion zigistry login                  # Setup authentication
```

#### `zion zigistry publish [--sign]`

Publish packages to Zigistry with optional cryptographic signing.

```bash
zion zigistry publish                # Publish current package
zion zigistry publish --sign         # Publish with signing
```

#### `zion zigistry status [package]`

Show Zigistry connection status or detailed package information.

```bash
zion zigistry status                 # Show connection status
zion zigistry status mypackage       # Package-specific stats
```

#### `zion zigistry analytics [package]`

View comprehensive package statistics and trends.

```bash
zion zigistry analytics              # Overall registry stats
zion zigistry analytics mypackage    # Package-specific analytics
```

#### `zion zigistry search <query>`

Enhanced Zigistry search with metadata and ratings.

```bash
zion zigistry search game            # Search with enhanced metadata
```

#### `zion zigistry trending`

Discover trending packages on Zigistry.

```bash
zion zigistry trending               # Show popular packages
```

#### `zion zigistry info <package>`

Get detailed package information including ratings and statistics.

```bash
zion zigistry info zig-clap          # Comprehensive package info
```

### Enhanced `zion add` - Multi-Registry Support

The `add` command now supports multiple registries with intelligent resolution.

#### Enhanced Options

```bash
zion add <package> [options]
zion add <package1> <package2> ... [options]
```

**New Options:**
- `--prefer-ziglibs` - Prefer Ziglibs packages when available
- `--version, -v <ver>` - Install specific version
- `--registry, -r <reg>` - Use specific registry

**Examples:**
```bash
zion add raylib --prefer-ziglibs     # Prefer Ziglibs version
zion add httpz --registry zigistry   # From specific registry
zion add crypto json logging         # Multiple packages
zion add zig-clap --version 0.8.0    # Specific version
```

**Features:**
- Multi-registry package resolution
- Ziglibs quality preference
- Smart suggestions for typos
- Parallel package processing

## 🚀 Enhanced Commands in v1.1.0

### Enhanced `zion zig` - Advanced Zig Version Management

The Zig manager now includes cross-platform support and enhanced IDE integration.

#### New Subcommands

**`zion zig status`** - Comprehensive environment status
```bash
zion zig status                      # Complete Zig environment overview
```

**`zion zig which`** - Path helpers for IDE integration
```bash
zion zig which                       # Show path to current Zig binary
```

**`zion zig update`** - Update version index
```bash
zion zig update                      # Update available versions list
```

#### Enhanced Features

- **Cross-platform support** - Linux, macOS, Windows
- **Development build support** - Install dev builds and nightly versions
- **IDE integration helpers** - JSON output for editor integrations
- **Async downloads** - Fast downloads with zsync
- **System integration** - Respects package managers (pacman, brew)

**Enhanced Examples:**
```bash
zion zig install 0.12.0-dev.3180+83e578a18  # Dev builds
zion zig current --json                      # JSON for IDEs
zion zig status                              # Environment overview
```

### Enhanced `zion zls` - Deep ZLS Integration

Advanced ZLS integration with real-time dependency management and IDE optimization.

#### New Subcommands

**`zion zls deps [--watch]`** - Real-time dependency monitoring
```bash
zion zls deps                        # Show dependency status
zion zls deps --watch                # Live monitoring for IDE
```

**`zion zls completions`** - Generate completion data
```bash
zion zls completions                 # Generate package completions
```

**`zion zls analyze`** - Project analysis for optimization
```bash
zion zls analyze                     # Analyze for ZLS optimization
```

**`zion zls imports [--optimize]`** - Smart import management
```bash
zion zls imports                     # Analyze import usage
zion zls imports --optimize          # Optimize imports
```

**`zion zls setup <editor>`** - Editor-specific setup
```bash
zion zls setup neovim                # Setup for Neovim
zion zls setup vscode                # Setup for VS Code
zion zls setup emacs                 # Setup for Emacs
zion zls setup helix                 # Setup for Helix
```

#### Enhanced Features

- **Real-time dependency health** - Live monitoring in editor
- **Smart import optimization** - Remove unused, optimize organization  
- **Package name completion** - Auto-complete package names in editor
- **Visual dependency trees** - IDE integration for dependency visualization
- **Comprehensive health checks** - Deep ZLS environment analysis

## 🚀 New Commands in v0.8.0

### `zion zig` - Zig Version Management

Complete Zig version lifecycle management with `anyzig`-like functionality.

#### `zion zig list [--remote] [--prerelease]`

Lists installed Zig versions and optionally shows available remote versions.

```bash
zion zig list                    # Show installed versions
zion zig list --remote           # Show available stable versions  
zion zig list --remote --prerelease  # Include development versions
```

**Example output:**
```
🔧 Installed Zig Versions:
  🖥️  system (0.15.0-dev.889+b8ac740a1) - /usr/bin/zig
  → 🦎 0.14.1 (active)
    🦎 0.13.0

💡 Use 'zion zig list --remote' to see available versions
```

#### `zion zig install <version>`

Installs a specific Zig version from official sources.

```bash
zion zig install 0.14.1                     # Install stable release
zion zig install 0.15.0-dev.936+fc2c1883b  # Install development build
zion zig install master                     # Install latest development
```

**What it does:**
- Downloads from official ziglang.org sources (x86_64-linux)
- Extracts to `~/.zion/zig-versions/<version>/`
- Verifies integrity of downloaded archives
- Provides usage instructions after installation

**Supported versions:**
- `0.14.1`, `0.13.0`, `0.12.1`, `0.11.0` (stable releases)
- `0.15.0-dev.936+fc2c1883b` (development builds)
- `master` (latest development)

#### `zion zig use <version|system>`

Switches between Zig versions or back to system installation.

```bash
zion zig use 0.14.1              # Switch to managed version
zion zig use system              # Switch to system Zig (/usr/bin/zig)
```

**System Integration:**
- Automatically detects Arch Linux package manager installations
- Seamlessly switches between system and managed versions
- Updates PATH and environment as needed

#### `zion zig current`

Shows detailed information about current Zig installation.

```bash
zion zig current
```

**Example output:**
```
🔧 Zig Version Status:
🖥️  System Zig: /usr/bin/zig
    Version: 0.15.0-dev.889+b8ac740a1
🦎 Managed Zig: 0.14.1 (active)
📁 Active Path: /home/user/.zion/zig-versions/0.14.1/zig
📊 Active Version Details:
0.14.1
```

#### `zion zig remove <version>`

Removes an installed Zig version.

```bash
zion zig remove 0.13.0           # Remove specific version
```

#### `zion zig clean`

Cleans up old and unused Zig versions.

```bash
zion zig clean
```

#### `zion zig default <version>`

Sets a version as the default and updates shell profiles.

```bash
zion zig default 0.14.1
```

---

### `zion zls` - ZLS (Zig Language Server) Integration

Comprehensive ZLS management, configuration, and diagnostics.

#### `zion zls doctor`

Performs comprehensive health check of ZLS installation and configuration.

```bash
zion zls doctor
```

**Example output:**
```
🩺 ZLS Doctor - Health Check
==============================
🔍 ZLS Binary: ✅ Found at /home/user/.local/share/nvim/mason/bin/zls
📊 ZLS Version: 0.14.0
    ✅ Compatible with current Zig
🦎 Zig Version: 0.15.0-dev.889+b8ac740a1
    ✅ Supported version
⚙️  ZLS Config: ⚠️  Not Found (using defaults)
📁 Project Root: ✅ Zig project detected (build.zig found)
    ✅ build.zig.zon found
🌍 Environment: ✅ ZLS in PATH

📋 Summary:
⚠️  ZLS is functional but has 1 warning(s).
💡 Consider running 'zion zls config' to optimize.

🔗 Editor Integration:
  Neovim:  :LspInfo to check ZLS status
  VSCode:  Install 'ziglang.vscode-zig' extension
  Emacs:   Use zig-mode with lsp-mode
```

**What it checks:**
- ZLS binary location and accessibility
- Version compatibility between ZLS and Zig
- Configuration file existence and validity
- Project structure (build.zig, build.zig.zon)
- Environment setup (PATH, editor integration)

#### `zion zls install`

Provides platform-specific ZLS installation guidance.

```bash
zion zls install
```

**Installation options provided:**
- Package manager instructions (Arch: `pacman -S zls`)
- Pre-built binary downloads from GitHub releases
- Build-from-source instructions
- Editor-specific installation (Mason, etc.)

#### `zion zls config`

Generates optimal ZLS configuration file.

```bash
zion zls config
```

**What it does:**
- Creates `~/.config/zls/zls.json` with optimal settings
- Enables semantic tokens, inlay hints, snippets
- Configures build-on-save and style warnings
- Provides editor-specific integration tips

**Generated config example:**
```json
{
  "enable_semantic_tokens": true,
  "enable_inlay_hints": true,
  "enable_snippets": true,
  "warn_style": true,
  "highlight_global_var_declarations": true,
  "enable_build_on_save": false,
  "build_on_save_step": "check",
  "prefer_ast_check_as_child_process": true
}
```

#### `zion zls which`

Shows the path to the currently active ZLS binary.

```bash
zion zls which
```

#### `zion zls version`

Shows detailed ZLS version information.

```bash
zion zls version
```

#### `zion zls restart`

Provides instructions for restarting ZLS in various editors.

```bash
zion zls restart
```

---

### `zion setup` - "One Nation Under Zig" Setup System

Complete Zig development environment setup and verification.

#### `zion setup all`

Performs complete Zig development environment setup with interactive prompts.

```bash
zion setup all
```

**What it does:**
1. Installs latest stable Zig version
2. Sets up ZLS (Zig Language Server)
3. Configures shell integration (PATH, completions)
4. Sets up development tools and directories
5. Verifies complete setup

**Interactive experience:**
- Prompts for confirmation before each step
- Provides progress feedback and status updates
- Offers rollback on failures
- Generates setup verification report

#### `zion setup zig [--version=X.Y.Z] [--skip-install]`

Sets up Zig version management.

```bash
zion setup zig                   # Install latest stable
zion setup zig --version=0.14.1  # Install specific version
zion setup zig --skip-install    # Setup without installing
```

#### `zion setup zls`

Sets up ZLS installation and configuration.

```bash
zion setup zls
```

#### `zion setup shell [--zsh|--bash|--fish]`

Sets up shell integration with PATH and completions.

```bash
zion setup shell                 # Auto-detect shell
zion setup shell --zsh           # Force zsh setup
zion setup shell --bash          # Force bash setup
```

**What it configures:**
- Adds `~/.local/bin` to PATH in shell profile
- Installs shell completions (zsh, bash, fish)
- Creates backup of existing configurations
- Provides manual setup instructions as fallback

#### `zion setup nvim`

Sets up Neovim integration with zion.nvim plugin.

```bash
zion setup nvim
```

**Provides:**
- Plugin installation instructions for lazy.nvim/packer
- Example configuration files
- LSP integration setup
- Telescope integration examples

#### `zion setup tools`

Sets up and verifies essential development tools.

```bash
zion setup tools
```

**Checks and configures:**
- `git`, `curl`, `tar`, `unzip` availability
- Creates development directories
- Sets up tool configurations

#### `zion setup verify`

Comprehensive verification of complete setup.

```bash
zion setup verify
```

**Verification includes:**
- Zig installation and PATH accessibility
- ZLS installation and functionality
- Shell completions installation
- Project root detection capabilities
- Development tools availability

---

### `zion workspace` - Cargo-style Workspace Management

Multi-package project management with shared configuration.

#### `zion workspace init`

Initializes a new Zig workspace for multi-package projects.

```bash
zion workspace init
```

**Creates:**
- `zion-workspace.toml` - Workspace configuration file
- `packages/` - Directory for workspace packages
- `target/` - Shared build output directory

**Example workspace structure:**
```
my-workspace/
├── zion-workspace.toml
├── packages/
│   ├── mylib/
│   └── myapp/
└── target/
```

#### `zion workspace add <package-name>`

Adds a new package to the workspace.

```bash
zion workspace add mylib         # Add library package
zion workspace add myapp         # Add application package
```

**What it does:**
- Creates `packages/<package-name>/` directory
- Generates basic package structure (src/, build.zig)
- Creates template main.zig or lib.zig
- Updates workspace configuration
- Provides package-specific build.zig template

#### `zion workspace list`

Lists all packages in the current workspace.

```bash
zion workspace list
```

**Example output:**
```
Workspace Members:
  packages/mylib/
  packages/myapp/
  packages/shared/
```

#### `zion workspace build`

Builds all packages in the workspace.

```bash
zion workspace build
```

**Build process:**
- Iterates through all workspace members
- Builds each package in dependency order
- Reports build status for each package
- Aggregates build results and errors

#### `zion workspace test`

Runs tests for all packages in the workspace.

```bash
zion workspace test
```

#### `zion workspace clean`

Cleans build artifacts for all workspace packages.

```bash
zion workspace clean
```

**Cleans:**
- Shared `target/` directory
- Individual package `.zig-cache/` directories
- Individual package `zig-out/` directories

---

## Exit Codes

| Code | Description           |
|------|-----------------------|
| 0    | Success               |
| 1    | General error         |
| 2    | File not found        |
| 3    | Invalid command usage |

## Environment Variables

Zion doesn't currently use any environment variables, but they may be added in future versions.