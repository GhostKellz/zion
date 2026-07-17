# Installing Zion on Arch Linux

This directory contains Arch Linux packaging and helper scripts for Zion.

## Methods

### PKGBUILD

```bash
cd release/arch
makepkg -si
```

### Installer Helper

```bash
cd release/arch
chmod +x install.sh
./install.sh
```

### Manual Build Helper

```bash
cd release/arch
chmod +x build.sh
./build.sh
```

## Requirements

- A Zig toolchain satisfying `.minimum_zig_version` in `build.zig.zon`
- pacman
- makepkg
- git
- curl
- tar

## Verification

```bash
zion version
zion help
zion test info
```
