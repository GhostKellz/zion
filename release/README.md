# Zion Installation

This directory contains various files and scripts to install Zion on different Linux distributions.

## Quick Installation

For a quick installation on most Linux systems, use the installation script:

```bash
curl -sSL https://raw.githubusercontent.com/ghostkellz/zion/main/release/install.sh | bash
```

This installs Zion to `~/.local/bin/zion`.

## Installation Methods

### Generic Linux (User installation)

For user installation (doesn't require root):

```bash
./install.sh
```

This installs Zion to `~/.zion` and creates a symlink in `~/.local/bin`.

### System-wide Installation

For a system-wide installation (requires root):

```bash
sudo ./install-system.sh
```

This installs Zion to `/usr/local/bin`.

### Arch Linux Installation

To install on Arch Linux:

```bash
cd arch
makepkg -si
```

This builds and installs the package in one command.

### Debian/Ubuntu Installation

To build a Debian package:

```bash
cd debian
./build-deb.sh
```

Install the generated .deb file:

```bash
sudo dpkg -i debian/packages/zion_*.deb
```

### Fedora/RHEL Installation

To build an RPM package:

```bash
cd rpm
./build-rpm.sh
```

Install the generated .rpm file:

```bash
sudo dnf install rpm/packages/zion-*.rpm
```

## Requirements

- Zig 0.11.0 or newer
- curl
- tar
- git

## Verification

After installation, verify that Zion is working by running:

```bash
zion version
```

## Uninstallation

### User installation

```bash
rm ~/.local/bin/zion
rm -rf ~/.zion
```

### System-wide installation

```bash
sudo rm /usr/local/bin/zion
sudo rm -rf /usr/local/share/doc/zion
```

### Package manager installation

For Arch Linux:
```bash
sudo pacman -R zion
```

For Debian/Ubuntu:
```bash
sudo apt remove zion
```

For Fedora/RHEL:
```bash
sudo dnf remove zion
```