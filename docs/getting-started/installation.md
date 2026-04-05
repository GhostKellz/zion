# Installation

Install Zion on a current Zig 0.16.0-dev workflow.

## Quick Install

System-wide:

```bash
curl -fsSL https://zion.cktech.sh | sudo bash
```

User-only:

```bash
curl -fsSL https://zion.cktech.sh | bash
```

## Requirements

- Zig 0.16.0-dev
- curl
- tar
- git

## From Source

```bash
git clone https://github.com/ghostkellz/zion.git
cd zion
zig build -Doptimize=ReleaseSafe
zig build install
```

## Verification

```bash
zion --version
zion help
zion test info
```

## Uninstall

Generic user install:

```bash
rm ~/.local/bin/zion
```

System-wide install:

```bash
sudo rm /usr/local/bin/zion
```

Remove Zion data:

```bash
rm -rf ~/.zion
```
