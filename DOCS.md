# Zion Documentation

This document provides comprehensive information about Zion's architecture, advanced features, and development.

## Table of Contents

- [Architecture](#architecture)
- [v0.4.0 Features](#v040-features)
- [File Formats](#file-formats)
- [Dependency Resolution](#dependency-resolution)
- [Version Management](#version-management)
- [Build Integration](#build-integration)
- [Configuration](#configuration)
- [Development](#development)
- [Troubleshooting](#troubleshooting)

## Architecture

### Overview

Zion is built with a modular architecture that separates concerns:

```
src/
├── main.zig              # CLI entry point and command dispatch
├── root.zig              # Library root, exports commands module
├── commands/             # Command implementations
│   ├── mod.zig          # Commands module exports
│   ├── init.zig         # Project initialization
│   ├── add.zig          # Add dependencies (core feature)
│   ├── remove.zig       # Remove dependencies with cleanup
│   ├── update.zig       # Update dependencies to latest versions
│   ├── list.zig         # List all dependencies with status
│   ├── info.zig         # Show detailed package information
│   ├── fetch.zig        # Fetch dependencies with version support (v0.4.0)
│   ├── pin.zig          # Pin dependencies to versions (v0.4.0)
│   ├── unpin.zig        # Unpin dependencies (v0.4.0)
│   ├── repair.zig       # Repair broken hashes (v0.4.0)
│   ├── check.zig        # Health auditing (v0.4.0)
│   ├── build.zig        # Build project
│   ├── clean.zig        # Clean artifacts
│   ├── lock.zig         # Lock file management
│   ├── version.zig      # Version display
│   └── help.zig         # Help text
├── github.zig           # GitHub API integration (v0.4.0)
├── manifest.zig         # build.zig.zon parsing and manipulation
├── lockfile.zig         # zion.lock file handling
└── downloader.zig       # HTTP downloads and caching
```

## v0.4.0 Features

### 🧠 Smart Manifest & Hash Automation

v0.4.0 introduces **"Hands-Off Manifest"** management that eliminates manual hash editing forever:

#### GitHub Integration (`github.zig`)

The new GitHub integration module provides:
- **Release Discovery**: Automatic detection of GitHub releases and tags
- **Version Resolution**: Smart matching of version specifications (v1.0.0, 1.0.0, etc.)
- **Tarball URL Generation**: Automatic URL construction for specific versions
- **API Fallbacks**: Graceful fallback to main/master branch when no releases exist

Key functions:
```zig
pub fn fetchPackageVersions(allocator: Allocator, package_ref: []const u8) ![]PackageVersion
pub fn getLatestVersion(allocator: Allocator, package_ref: []const u8) !PackageVersion
pub fn findVersion(allocator: Allocator, package_ref: []const u8, target_version: []const u8) !PackageVersion
```

#### Pin/Unpin System

**Version Pinning** provides reproducible builds:
- Pin dependencies to specific tags/releases
- Automatic version discovery and validation
- Seamless switching between pinned and latest versions
- Lock file integration with pinned version tracking

**Workflow:**
```bash
zion add mitchellh/libxev      # Add latest version
zion pin libxev@0.2.0         # Pin to specific version
zion unpin libxev             # Switch back to latest
```

#### Repair System

**Automatic Hash Repair** solves the most common Zig dependency problem:
- Detects hash mismatches automatically
- Re-downloads and recalculates hashes
- Updates both manifest and lock files atomically
- Provides detailed repair reports

**Use cases:**
- Upstream repository changes
- Corrupted cache files
- Manual manifest edits gone wrong
- Package update conflicts

#### Health Auditing

**Comprehensive Dependency Health Checks**:
- URL accessibility verification
- Hash integrity validation
- Package structure analysis
- Lock file consistency checks
- Update availability detection
- Project structure validation

**Health Status Levels:**
- ✅ **Healthy**: All checks pass
- ⚠️ **Warning**: Minor issues, project still functional
- ❌ **Error**: Critical issues requiring attention

### Core Components

#### 1. Manifest System (`manifest.zig`)

The `ZonFile` struct handles:
- Parsing `build.zig.zon` files (Zig Object Notation)
- Managing project metadata (name, version)
- Handling dependencies with URLs and hashes
- Saving updated manifests

#### 2. Lock File System (`lockfile.zig`)

The `LockFile` struct provides:
- Deterministic dependency resolution
- Timestamp tracking for cache invalidation
- JSON-based storage format
- Version conflict detection

#### 3. Download System (`downloader.zig`)

Features include:
- GitHub tarball resolution
- SHA256 hash verification
- HTTP downloads via curl (robust against Zig stdlib changes)
- Automatic retry with wget fallback
- Caching to `.zion/cache/`

#### 4. Package Extraction

The add command includes:
- Tarball extraction using system `tar`
- Directory structure validation
- Conflict resolution (overwrites existing packages)
- Package structure validation (checks for build.zig, src/)

## Version Management

### v0.4.0 Version Resolution

Zion v0.4.0 introduces sophisticated version management that automatically handles GitHub releases and tags:

#### Version Specification Formats

**Supported formats:**
- `package@1.0.0` - Exact version match
- `package@v1.0.0` - Version with v-prefix
- `package@latest` - Latest release (default)
- `package@main` - Main/master branch
- `package` - Implies latest version

#### Version Discovery Process

1. **Release Check**: First checks GitHub releases API
2. **Tag Fallback**: Falls back to tags API if no releases
3. **Branch Fallback**: Uses main/master branch if no tags
4. **Smart Matching**: Handles both `v1.0.0` and `1.0.0` formats

#### Pin/Unpin Workflow

**Pinning Process:**
```bash
zion pin libxev@0.2.0
```
1. Validates package exists in project
2. Discovers available versions from GitHub
3. Downloads and verifies specific version
4. Updates manifest with new URL and hash
5. Updates lock file with pin information
6. Extracts package to deps directory

**Unpinning Process:**
```bash
zion unpin libxev
```
1. Fetches latest version from GitHub
2. Downloads and verifies latest version
3. Updates manifest to track latest
4. Removes pin from lock file
5. Extracts latest package to deps directory

#### Lock File Enhancements

The lock file now tracks pinned versions:
```json
{
  "version": "1.0",
  "packages": {
    "libxev": {
      "url": "https://github.com/mitchellh/libxev/archive/refs/tags/v0.2.0.tar.gz",
      "hash": "abc123...",
      "pinned_version": "v0.2.0",
      "updated": "2024-12-26T10:30:00Z"
    }
  }
}
```

## File Formats

### build.zig.zon

Zion uses Zig's native `.zon` format for project manifests:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .libxev = .{
            .url = "https://github.com/mitchellh/libxev/archive/refs/heads/main.tar.gz",
            .hash = "1220abc123...",
        },
        .zig_clap = .{
            .url = "https://github.com/Hejsil/zig-clap/archive/refs/heads/master.tar.gz", 
            .hash = "1220def456...",
        },
    },
}
```

### zion.lock

The lock file uses JSON for wider tool compatibility:

```json
{
  "packages": [
    {
      "name": "libxev",
      "url": "https://github.com/mitchellh/libxev/archive/refs/heads/main.tar.gz",
      "hash": "1220abc123def456...",
      "timestamp": 1701234567
    }
  ]
}
```

## Dependency Resolution

### Current Strategy

Zion currently uses a simple "latest commit" strategy:
1. Resolves `username/repo` to GitHub tarball URL
2. Downloads from `main` or `master` branch
3. Calculates SHA256 hash for reproducibility
4. Stores exact URL and hash in manifest

### Directory Layout

```
project/
├── .zion/
│   ├── cache/                 # Downloaded tarballs
│   │   ├── username_repo.tar.gz
│   │   └── ...
│   └── deps/                  # Extracted packages
│       ├── libxev/
│       │   ├── build.zig
│       │   ├── src/
│       │   └── ...
│       └── zig_clap/
│           ├── build.zig
│           └── src/
├── build.zig                  # ← Auto-modified by zion
├── build.zig.zon             # ← Updated by zion add
└── zion.lock                  # ← Maintained by zion
```

## Build Integration

### Automatic build.zig Modification

When you run `zion add package`, the build.zig file is automatically updated to include the new dependency.

#### Smart Injection

Zion looks for injection points in this order:

1. **Marker-based**: If your build.zig contains:
   ```zig
   // zion:deps - dependencies will be added below this line
   ```
   Dependencies are injected after this line.

2. **Heuristic-based**: Zion tries to find a good location:
   - After module creation (`const mod = b.addModule(...)`)
   - Before executable creation (`const exe = b.addExecutable(...)`)

3. **Fallback**: If automatic injection fails, manual instructions are provided.

#### Generated Code

For a package named `libxev`, Zion generates:

```zig
// Added by zion add libxev
const libxev_mod = b.addModule("libxev", .{
    .root_source_file = b.path(".zion/deps/libxev/src/root.zig"),
    .target = target,
    .optimize = optimize,
});
```

### Manual Integration

If automatic integration fails, add dependencies to your executable's imports:

```zig
const exe = b.addExecutable(.{
    .name = "my-app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "libxev", .module = libxev_mod },
            // ... other imports
        },
    }),
});
```

### Dependency Removal

The `zion remove` command provides comprehensive cleanup:

1. **Validation**: Checks that the package exists in `build.zig.zon`
2. **Manifest cleanup**: Removes from `build.zig.zon` and `zion.lock`
3. **Build script cleanup**: Automatically removes auto-generated blocks from `build.zig`
4. **File cleanup**: Deletes the package directory from `.zion/deps/`

**Smart removal logic:**
- Identifies blocks added by `zion add` using comment markers
- Removes entire module definition blocks automatically
- Warns about manual dependencies that need manual removal
- Provides fallback instructions when automatic removal fails

**Example workflow:**
```bash
# Add a dependency
zion add mitchellh/libxev

# Later, remove it completely
zion remove libxev
# or use the short alias
zion rm libxev
```

### Dependency Updates

The `zion update` command provides intelligent dependency updating:

1. **Smart hash comparison**: Only updates packages when content actually changes
2. **Selective updating**: Preserves unchanged dependencies to save time
3. **Manifest synchronization**: Updates both `build.zig.zon` and `zion.lock` atomically
4. **Extraction optimization**: Only re-extracts packages that have changed
5. **Progress reporting**: Shows real-time status and comprehensive summary

**Update strategy:**
- Re-downloads each dependency from its original GitHub URL
- Computes new SHA256 hash and compares with current
- Updates manifest files only when hash changes
- Maintains reproducible builds with exact version tracking

**Example update workflow:**
```bash
# Check for and apply all updates
zion update

# Output shows exactly what changed:
# 📦 Checking libxev...
#   🔄 Hash changed! Updating...
# 📦 Checking zig-clap...
#   ✓ Up to date
# 
# 📋 Update Summary:
# 🔄 Updated packages (1): libxev
# ✅ Up-to-date packages (1): zig-clap
```

### Dependency Inspection

Zion provides powerful commands for inspecting and understanding your dependency tree:

#### Package Listing (`zion list`)

The `list` command provides both human-readable and machine-readable views of your dependencies:

**Table format:**
- Clean overview of all dependencies with installation status
- Repository information extracted from GitHub URLs
- Summary statistics showing installed vs missing packages
- Hash mismatch detection for sync issues

**JSON format:**
- Complete dependency metadata for tooling integration
- Installation status and file paths
- Timestamp and version information from lock file
- Repository owner/name extraction for each package

```bash
# Human-readable table
zion list

# Machine-readable JSON
zion list --json | jq '.[] | select(.installed == false)'
```

#### Package Details (`zion info`)

The `info` command provides comprehensive details about individual packages:

**Key features:**
- Complete package metadata (name, URL, hash, status)
- Lock file integration showing timestamps and versions
- Hash validation between manifest and lock file
- Repository information parsing from GitHub URLs
- Package structure validation (build.zig, src/ directory)
- Contextual command suggestions based on package state

**Use cases:**
- Debugging dependency issues
- Verifying package installation
- Understanding package origins and versions
- Checking for sync issues between manifest and lock file

```bash
# Get detailed info about a specific package
zion info libxev

# Check if a package needs updating
zion info package_name | grep "Hash Mismatch"
```

## Configuration

Currently, Zion uses minimal configuration and relies on conventions:

- **Cache directory**: `.zion/cache/` (relative to project root)
- **Dependencies directory**: `.zion/deps/` (relative to project root)
- **Manifest file**: `build.zig.zon` (project root)
- **Lock file**: `zion.lock` (project root)

Future versions may support global configuration files.

## Development

### Building Zion

```bash
# Debug build
zig build

# Release build  
zig build -Doptimize=ReleaseSafe

# Run tests
zig build test
```

### Zig Compatibility

Zion is built for **Zig 0.15.0-dev** and later. Key compatibility considerations:

- **JSON API**: Uses the new `std.json.parseFromSlice()` API
- **Process API**: Uses the current `std.process.Child` API
- **File System**: Uses `fs.max_path_bytes` (not `MAX_PATH_BYTES`)
- **HTTP**: Avoids unstable `std.http` in favor of system curl

### Adding New Commands

1. Create `src/commands/newcommand.zig`
2. Implement the command function:
   ```zig
   pub fn newcommand(allocator: std.mem.Allocator) !void {
       // Implementation
   }
   ```
3. Export in `src/commands/mod.zig`:
   ```zig
   pub const newcommand = @import("newcommand.zig").newcommand;
   ```
4. Add to `src/main.zig` command dispatch
5. Update help text in `src/commands/help.zig`
6. Document in `COMMANDS.md` and `DOCS.md`

### Command Implementation Examples

**Simple command (no arguments):**
```zig
pub fn version(allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("zion {s}\n", .{@import("../root.zig").ZION_VERSION});
}
```

**Complex command with file manipulation:**
```zig
pub fn remove(allocator: Allocator, package_name: []const u8) !void {
    // 1. Validate inputs
    // 2. Load and modify manifest files
    // 3. Clean up file system
    // 4. Provide user feedback
}
```

## Troubleshooting

### Common Issues

#### "curl not found"
Zion requires `curl` for HTTP downloads. Install curl:
- **Ubuntu/Debian**: `apt install curl`
- **macOS**: `brew install curl` (usually pre-installed)
- **Windows**: Install from https://curl.se/windows/

#### "tar not found"  
Zion requires `tar` for package extraction:
- **Ubuntu/Debian**: `apt install tar` (usually pre-installed)
- **macOS**: Pre-installed
- **Windows**: Install Git for Windows or use WSL

#### "Could not find good injection point in build.zig"
Add this marker to your build.zig where you want dependencies:
```zig
// zion:deps - dependencies will be added below this line
```

#### "Found manual dependency in build.zig - please remove manually"
This warning appears when `zion remove` finds a dependency that wasn't added by `zion add`. You'll need to manually remove:
```zig
// Remove these lines manually:
const libxev_mod = b.addModule("libxev", .{ ... });
// And any corresponding imports in your executable
```

#### Package structure validation warnings
```
⚠️  Warning: No build.zig found in package. This may not be a valid Zig package.
⚠️  Warning: No src/ directory found. Package structure may be non-standard.
```

This indicates the downloaded package might not be a standard Zig package. You can still use it, but integration may require manual work.

### Debug Mode

For verbose output during development, use debug builds:
```bash
zig build -Doptimize=Debug
```

### Cache Issues

If you encounter cache corruption:
```bash
zion clean        # Remove cached downloads
zion clean --all  # Remove everything including lock file
```

## Future Enhancements

Planned features for future versions:

- **Semantic versioning**: Support for version ranges like `^1.2.0`
- **Selective updates**: `zion update package_name` to update specific packages
- **Update policies**: Pin specific packages to avoid updates
- **Git dependencies**: Direct git repository support with commit/tag targeting
- **Private registries**: Support for private package registries
- **Workspaces**: Multi-package repository support
- **Feature flags**: Optional dependency compilation
- **Cross-platform builds**: Better Windows support
- **Package publishing**: `zion publish` command
- **Package search**: `zion search` functionality

## Contributing

See the main README.md for contribution guidelines.