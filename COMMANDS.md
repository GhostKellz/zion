# Zion Commands Reference

Complete command reference for Zion, the Zig package manager.

## Quick Reference

| Command | Description |
|---------|-------------|
| `zion init` | Initialize a new Zig project |
| `zion add` | Add a dependency |
| `zion remove` | Remove a dependency |
| `zion update` | Update dependencies |
| `zion fetch` | Fetch all dependencies |
| `zion lock` | Manage lock file |
| `zion hash` | Hash management |
| `zion build` | Build the project |
| `zion test` | Run tests |
| `zion run` | Run the project |
| `zion search` | Search for packages |
| `zion info` | Show package info |
| `zion check` | Check project health |
| `zion clean` | Clean build artifacts |

---

## Package Management

### `zion init`

Initialize a new Zig project with standard structure.

```bash
zion init [project-name]
```

Creates:
- `src/main.zig` - Entry point
- `build.zig` - Build configuration
- `build.zig.zon` - Package manifest

### `zion add`

Add a dependency to your project.

```bash
zion add <package>              # Add latest version
zion add <package>@<version>    # Add specific version
zion add owner/repo             # Add from GitHub
```

**Examples:**
```bash
zion add mitchellh/libxev
zion add ziglang/zig-clap@0.18.0
zion add ghostkellz/zsync
```

### `zion remove`

Remove a dependency from your project.

```bash
zion remove <package>
```

### `zion update`

Update dependencies to their latest versions.

```bash
zion update              # Update all
zion update <package>    # Update specific package
```

### `zion fetch`

Download and cache all dependencies.

```bash
zion fetch
```

### `zion outdated`

Check for outdated dependencies.

```bash
zion outdated
```

---

## Lock File Management

### `zion lock`

Manage the lock file (zion.lock).

```bash
zion lock              # Update lock file from build.zig.zon
zion lock sync         # Bidirectional sync between ZON and lock file
zion lock verify       # Check lock file integrity (read-only)
zion lock clean        # Remove stale entries not in build.zig.zon
zion lock help         # Show help
```

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| (none) | Create or update lock file from build.zig.zon |
| `sync` | Bidirectional sync - adds missing entries, reports orphans |
| `verify` | Read-only integrity check, exits with error if mismatch |
| `clean` | Remove lock entries not present in build.zig.zon |

---

## Hash Management

### `zion hash`

Manage package hashes for integrity verification.

```bash
zion hash generate <file|package[@version]>   # Generate SHA256 hash
zion hash verify <file> <expected_hash>       # Verify file against hash
zion hash update <package|--all>              # Update hash in build.zig.zon
zion hash check                               # Check all project hashes
```

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| `generate` | Calculate SHA256 hash for file or remote package |
| `verify` | Verify a file matches expected hash |
| `update` | Re-download and update hash in build.zig.zon |
| `check` | Verify all cached packages match ZON hashes |

**Examples:**
```bash
# Generate hash for remote package
zion hash generate mitchellh/libxev@0.1.0

# Update all dependency hashes
zion hash update --all

# Verify all hashes
zion hash check
```

---

## Version Pinning

### `zion pin`

Pin a dependency to a specific version.

```bash
zion pin <package>@<version>
```

### `zion unpin`

Unpin a dependency to track latest.

```bash
zion unpin <package>
```

---

## Build & Run

### `zion build`

Build the project using Zig's build system.

```bash
zion build [args...]
```

All arguments are passed to `zig build`.

### `zion test`

Run project tests.

```bash
zion test [args...]
```

### `zion run`

Run the project.

```bash
zion run [args...]
```

---

## Search & Discovery

### `zion search`

Search for packages across registries.

```bash
zion search <query>
```

### `zion info`

Show detailed information about a package.

```bash
zion info <package>
```

---

## Project Health

### `zion check`

Check project health and dependency status.

```bash
zion check
```

### `zion tree`

Display dependency tree.

```bash
zion tree
```

### `zion status`

Show project status overview.

```bash
zion status
```

---

## Maintenance

### `zion clean`

Clean build artifacts and cache.

```bash
zion clean           # Clean build artifacts
zion clean --all     # Clean everything including cache
```

### `zion repair`

Repair corrupted cache or dependencies.

```bash
zion repair
```

---

## Zig Version Management

### `zion zig`

Manage Zig installations.

```bash
zion zig install <version>    # Install a Zig version
zion zig use <version>        # Switch to a version
zion zig use system           # Use system Zig
zion zig list                 # List installed versions
zion zig current              # Show current version
```

### `zion zls`

ZLS (Zig Language Server) management.

```bash
zion zls doctor      # Health check
zion zls config      # Generate optimal config
zion zls install     # Installation guidance
```

---

## Setup & Configuration

### `zion setup`

Set up development environment.

```bash
zion setup all       # Complete environment setup
zion setup zig       # Just Zig management
zion setup verify    # Verify setup
```

### `zion config`

Manage Zion configuration.

```bash
zion config show
zion config set <key> <value>
```

---

## Help & Info

### `zion help`

Show help information.

```bash
zion help
zion help <command>
```

### `zion version`

Show Zion version.

```bash
zion version
```

---

## Advanced Commands

### `zion workspace`

Manage multi-package workspaces.

```bash
zion workspace init          # Initialize workspace
zion workspace add <name>    # Add package to workspace
zion workspace build         # Build all packages
```

### `zion publish`

Publish a package to a registry.

```bash
zion publish
```

### `zion security`

Security-related commands.

```bash
zion security keygen         # Generate signing keys
zion security sign <file>    # Sign a package
zion security verify <file>  # Verify signature
```

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `ZION_REGISTRY_URL` | Custom registry URL |
| `ZION_CACHE_DIR` | Custom cache directory |
| `NO_COLOR` | Disable colored output |
| `ZION_NO_COLOR` | Zion-specific color disable |

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | File not found |
| 4 | Network error |
| 5 | Hash verification failed |
