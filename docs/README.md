# Zion Documentation

Documentation for Zion, the Zig package manager.

## Quick Start

```bash
# Install
curl -sSL https://raw.githubusercontent.com/ghostkellz/zion/main/release/install.sh | bash

# Initialize a project
zion init myproject
cd myproject

# Add dependencies
zion add mitchellh/libxev

# Build
zion build
```

## Documentation

| Document | Description |
|----------|-------------|
| [Installation](INSTALL.md) | Installation guide for all platforms |
| [Commands](COMMANDS.md) | Complete command reference |
| [API Reference](api-reference/index.html) | Source code documentation |

## Common Tasks

### Add a dependency

```bash
zion add owner/repo              # Latest from GitHub
zion add owner/repo@v1.0.0       # Specific version
```

### Update dependencies

```bash
zion update                      # Update all
zion update <package>            # Update specific
```

### Manage hashes

```bash
zion hash update --all           # Update all hashes
zion hash check                  # Verify integrity
```

### Lock file operations

```bash
zion lock                        # Generate lock file
zion lock sync                   # Sync with build.zig.zon
zion lock verify                 # Verify integrity
```

### Version pinning

```bash
zion pin <package>@<version>     # Pin to version
zion unpin <package>             # Unpin
zion unpin <package> --to-main   # Track main branch
```

### Check for cycles

```bash
zion tree --check-cycles         # Detect circular dependencies
```

## Help

```bash
zion help                        # General help
zion help <command>              # Command-specific help
```
