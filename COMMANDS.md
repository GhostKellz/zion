# Zion Commands Documentation

This document provides detailed information about all available commands in the Zion package manager.

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

## Exit Codes

| Code | Description           |
|------|-----------------------|
| 0    | Success               |
| 1    | General error         |
| 2    | File not found        |
| 3    | Invalid command usage |

## Environment Variables

Zion doesn't currently use any environment variables, but they may be added in future versions.