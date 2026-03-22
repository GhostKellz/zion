# Zion Technical Documentation

Comprehensive technical documentation for Zion, the Zig package manager.

## Table of Contents

- [Architecture](#architecture)
- [File Formats](#file-formats)
- [Dependency Resolution](#dependency-resolution)
- [Hash System](#hash-system)
- [Lock File](#lock-file)
- [Build Integration](#build-integration)
- [Configuration](#configuration)
- [Development](#development)

---

## Architecture

### Project Structure

```
src/
├── main.zig                    # CLI entry point
├── root.zig                    # Library exports and version
├── commands/
│   ├── mod.zig                 # Command module exports
│   ├── add.zig                 # Add dependencies
│   ├── remove.zig              # Remove dependencies
│   ├── update.zig              # Update dependencies
│   ├── fetch.zig               # Fetch dependencies
│   ├── lock.zig                # Lock file management
│   ├── hash.zig                # Hash operations
│   ├── init.zig                # Project initialization
│   ├── build.zig               # Build integration
│   ├── search.zig              # Package search
│   ├── pin.zig                 # Version pinning
│   ├── unpin.zig               # Version unpinning
│   ├── check.zig               # Health checks
│   ├── clean.zig               # Cleanup
│   └── ...
├── manifest.zig                # build.zig.zon parsing
├── lockfile.zig                # zion.lock management
├── downloader.zig              # Package downloads
├── github.zig                  # GitHub API integration
├── hash_conversion.zig         # Hash format conversion
├── semver.zig                  # Semantic versioning
├── version_resolver.zig        # Version constraint resolution
├── config.zig                  # Configuration management
├── registry.zig                # Registry client
└── security.zig                # Cryptographic operations
```

### Design Principles

1. **Zig-Native** - Built entirely in Zig, leveraging Zig 0.16+ APIs
2. **Arch Linux First** - Optimized for Arch with system integration
3. **Minimal Dependencies** - Self-contained with no external runtime dependencies
4. **Fast** - Sub-100ms response for most commands
5. **Secure** - Hash verification and optional package signing

---

## File Formats

### build.zig.zon

The package manifest file using Zig's ZON format.

```zig
.{
    .name = .myproject,
    .version = "0.1.0",
    .dependencies = .{
        .zsync = .{
            .url = "https://github.com/ghostkellz/zsync/archive/refs/tags/v0.7.8.tar.gz",
            .hash = "zsync-0.7.8-KAuheQufGABcQSjcE59uKuXJtH8PNSe39fxrTiFlsTYl",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

**Fields:**
- `.name` - Package identifier (Zig identifier format)
- `.version` - Semantic version string
- `.dependencies` - Map of dependency name to URL and hash
- `.paths` - Files/directories included in the package

### zion.lock

JSON lock file for reproducible builds.

```json
{
  "version": 2,
  "packages": [
    {
      "name": "zsync",
      "url": "https://github.com/ghostkellz/zsync/archive/refs/tags/v0.7.8.tar.gz",
      "hash": "zsync-0.7.8-KAuheQufGABcQSjcE59uKuXJtH8PNSe39fxrTiFlsTYl",
      "version": "0.7.8",
      "timestamp": 1710961234,
      "pinned": false
    }
  ]
}
```

**Package Fields:**
- `name` - Package identifier
- `url` - Download URL
- `hash` - Zig-native hash format
- `version` - Resolved version
- `timestamp` - When locked
- `pinned` - If true, skip auto-updates
- `version_constraint` - Original constraint (optional)

---

## Dependency Resolution

### Resolution Algorithm

1. **Parse Manifest** - Read `build.zig.zon` dependencies
2. **Check Lock** - Use locked versions if available
3. **Resolve Versions** - Query registries for matching versions
4. **Download** - Fetch packages to cache
5. **Verify** - Check hash integrity
6. **Update Lock** - Save resolved versions

### Version Constraints

Supported constraint formats:

| Format | Example | Meaning |
|--------|---------|---------|
| Exact | `1.2.3` | Exactly version 1.2.3 |
| Caret | `^1.2.3` | Compatible with 1.x.x |
| Tilde | `~1.2.3` | Compatible with 1.2.x |
| Range | `>=1.0.0 <2.0.0` | Within range |
| Any | `*` | Any version |

### Registry Priority

1. Custom registry (if configured)
2. GitHub (default)

---

## Hash System

### Zig Native Format

Zion uses Zig's native hash format:

```
{name}-{version}-{base64url_multihash}
```

Example:
```
zsync-0.7.8-KAuheQufGABcQSjcE59uKuXJtH8PNSe39fxrTiFlsTYl
```

**Components:**
- `name` - Package name
- `version` - Package version
- `base64url_multihash` - Base64url-encoded multihash

**Multihash Structure:**
- `0x12` - SHA256 algorithm identifier
- `0x20` - 32-byte digest length
- `<sha256_bytes>` - 32-byte SHA256 digest

### Hash Commands

```bash
# Generate hash for package
zion hash generate mitchellh/libxev@0.1.0

# Verify file hash
zion hash verify package.tar.gz <expected_hash>

# Update hashes in build.zig.zon
zion hash update --all

# Check all hashes
zion hash check
```

---

## Lock File

### Lock Management

```bash
# Create/update from build.zig.zon
zion lock

# Sync lock with ZON bidirectionally
zion lock sync

# Verify integrity (read-only)
zion lock verify

# Remove orphaned entries
zion lock clean
```

### Lock File Workflow

1. **Development** - Lock ensures reproducible builds
2. **CI/CD** - Use `zion lock verify` to check integrity
3. **Updates** - `zion update` then `zion lock sync`
4. **Cleanup** - `zion lock clean` after removing deps

---

## Build Integration

### With Zig Build System

Zion integrates with Zig's native build system:

```bash
# Fetch dependencies
zion fetch

# Build project
zig build
# or
zion build
```

### build.zig Integration

Dependencies are available via lazy dependency loading:

```zig
const zsync_dep = b.lazyDependency("zsync", .{
    .target = target,
    .optimize = optimize,
});

if (zsync_dep) |dep| {
    exe.root_module.addImport("zsync", dep.module("zsync"));
}
```

---

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ZION_CACHE_DIR` | Cache directory | `.zion/cache` |
| `ZION_REGISTRY_URL` | Custom registry | GitHub |
| `NO_COLOR` | Disable colors | unset |
| `ZION_NO_COLOR` | Zion color disable | unset |

### Directory Structure

```
project/
├── build.zig           # Build configuration
├── build.zig.zon       # Package manifest
├── zion.lock           # Locked versions
├── src/                # Source code
└── .zion/
    ├── cache/          # Downloaded packages
    └── deps/           # Extracted dependencies
```

---

## Development

### Building Zion

```bash
git clone https://github.com/ghostkellz/zion.git
cd zion
zig build -Doptimize=ReleaseSafe
```

### Running Tests

```bash
zig build test
```

### Code Style

- Follow Zig's standard style
- Use `zig fmt` for formatting
- Prefer explicit error handling
- Document public functions

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes with tests
4. Submit a pull request

---

## Troubleshooting

### Common Issues

**Hash mismatch:**
```bash
zion hash update <package>
# or
zion hash update --all
```

**Lock file out of sync:**
```bash
zion lock sync
```

**Corrupted cache:**
```bash
zion clean --all
zion fetch
```

**Network issues:**
Check your internet connection and retry. Zion uses curl with automatic retries.

### Debug Mode

For verbose output:
```bash
ZION_DEBUG=1 zion <command>
```

---

## Version History

See [CHANGELOG.md](CHANGELOG.md) for release notes.

Current version: **0.1.4**
