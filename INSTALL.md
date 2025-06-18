# Installing Zion

This document provides installation instructions for the Zion package manager on various platforms.

## Quick Installation

For a quick installation on most Linux systems:

```bash
curl -sSL https://raw.githubusercontent.com/ghostkellz/zion/main/release/install.sh | bash
```

This installs Zion locally to `~/.local/bin/zion`.

## Requirements

- Zig 0.11.0 or newer
- curl
- tar
- git

## Installation Methods

### From Source (Generic)

```bash
# Clone the repository
git clone https://github.com/ghostkellz/zion.git
cd zion

# Build the project
zig build -Doptimize=ReleaseSafe

# Install (user installation)
cp zig-out/bin/zion ~/.local/bin/

# Or system-wide installation (requires root)
sudo cp zig-out/bin/zion /usr/local/bin/
```

### Arch Linux

#### Using PKGBUILD

```bash
git clone https://github.com/yourusername/zion.git
cd zion/release/arch
makepkg -si
```

#### Using AUR (once available)

```bash
# Using yay
yay -S zion

# Or using paru
paru -S zion
```

### Debian/Ubuntu

```bash
git clone https://github.com/yourusername/zion.git
cd zion/release/debian
./build-deb.sh
sudo dpkg -i debian/packages/zion_*.deb
```

### Fedora/RHEL/CentOS

```bash
git clone https://github.com/yourusername/zion.git
cd zion/release/rpm
./build-rpm.sh
sudo dnf install rpm/packages/zion-*.rpm
```

### Docker

You can also use Zion via Docker:

```bash
# Pull the image
docker pull ghostkellz/zion:latest

# Run a command
docker run --rm ghostkellz/zion:latest help

# Use in a project directory
docker run --rm -v $(pwd):/workspace -w /workspace ghostkellz/zion:latest init
```

Or build the Docker image yourself:

```bash
git clone https://github.com/ghostkellz/zion.git
cd zion/release/docker
./build-docker.sh
```

## Shell Completions

Zion provides shell completion scripts for bash, zsh, and fish.

### Bash Completion

```bash
# System-wide
sudo cp release/completions/zion.bash /usr/share/bash-completion/completions/zion

# Or user-only
mkdir -p ~/.local/share/bash-completion/completions/
cp release/completions/zion.bash ~/.local/share/bash-completion/completions/zion
```

### Zsh Completion

```bash
# System-wide
sudo cp release/completions/zion.zsh /usr/share/zsh/site-functions/_zion

# Or user-only
mkdir -p ~/.zsh/completions/
cp release/completions/zion.zsh ~/.zsh/completions/_zion
echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
```

### Fish Completion

```bash
# User installation
mkdir -p ~/.config/fish/completions/
cp release/completions/zion.fish ~/.config/fish/completions/
```

## Manual Pages

To install the manual page:

```bash
# System-wide
sudo cp release/man/zion.1 /usr/local/share/man/man1/
sudo mandb

# Or user-only
mkdir -p ~/.local/share/man/man1/
cp release/man/zion.1 ~/.local/share/man/man1/
```

Then you can access the manual with:

```bash
man zion
```

## Verification

After installation, verify that Zion is working correctly:

```bash
zion --version
zion help
```

## Uninstallation

### Generic installation

```bash
# If installed to ~/.local/bin
rm ~/.local/bin/zion

# If installed system-wide
sudo rm /usr/local/bin/zion
```

### Package manager installation

```bash
# Arch Linux
sudo pacman -R zion

# Debian/Ubuntu
sudo apt remove zion

# Fedora/RHEL
sudo dnf remove zion
```

### Complete cleanup

To remove all Zion data (including cached packages):

```bash
rm -rf ~/.zion
```