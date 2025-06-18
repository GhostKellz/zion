# Installing Zag on Arch Linux

This directory contains files for installing Zag on Arch Linux systems.

## Installation Methods

### Method 1: Automated Install Script (Recommended)

The easiest way to install Zag is to use the provided install script, which handles Zig version conflicts and properly installs the package:

```bash
chmod +x install.sh
./install.sh
```

This script:
1. Detects your existing Zig installation
2. Builds Zag using your system Zig
3. Creates and installs a proper package
4. Handles permissions and dependencies

### Method 2: Manual PKGBUILD

If you prefer to use `makepkg` directly with a modified PKGBUILD:

```bash
# Edit PKGBUILD to remove Zig dependency conflicts
sed -i 's/depends=.*$/depends=('"'"'curl'"'"' '"'"'tar'"'"')/' PKGBUILD
sed -i 's/makedepends=.*$/makedepends=('"'"'git'"'"')/' PKGBUILD

# Build without checking dependencies
makepkg -si --nocheck --nodeps
```

### Method 3: Manual Build Script

For complete control over the build and installation process:

```bash
chmod +x build.sh
./build.sh
```

This script:
1. Builds Zag using your system Zig
2. Offers options to install for current user or system-wide
3. Does not create a package

## Handling Zig Version Conflicts

If you see errors like:

```
:: zig-0.14.1-2 and zig-dev-bin-1:0.15.0_dev.822.gdd75e7bcb-1 are in conflict
```

It means you have a development version of Zig installed that conflicts with the standard Zig package. The scripts in this directory are designed to work around these conflicts by:

1. Using your existing Zig installation instead of requiring a specific version
2. Modifying dependencies to avoid conflicts
3. Building directly with your system's Zig compiler

## Verification

After installation, verify that Zag is working correctly:

```bash
zag version
zag help
```

## Uninstallation

To uninstall:

```bash
sudo pacman -R zag
```

## Troubleshooting

If you encounter issues with the installation:

1. Check your Zig installation with `zig version`
2. Try the manual build script for more control
3. If building fails, check Zig compatibility with Zag (requires Zig 0.11.0+)