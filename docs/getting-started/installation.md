# Installation

Zion tracks its minimum supported Zig toolchain in the repository manifest.

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

- A Zig toolchain satisfying `.minimum_zig_version` in `build.zig.zon`
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

Check the installed toolchain and the manifest requirement before building:

```bash
zig version
sed -n 's/.*\.minimum_zig_version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' build.zig.zon
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
