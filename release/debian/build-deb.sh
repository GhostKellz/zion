#!/usr/bin/env bash
# Build Debian package for Zion
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Building Debian package for Zion...${NC}"

# Check dependencies
for cmd in dpkg-deb fakeroot; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd is not installed${NC}"
        echo "Please install: sudo apt install dpkg-dev fakeroot"
        exit 1
    fi
done

# Create package directory structure
PKG_DIR="packages"
DEB_DIR="$PKG_DIR/zion_0.2.0-dev_amd64"

rm -rf "$PKG_DIR"
mkdir -p "$DEB_DIR"/{DEBIAN,usr/bin,usr/share/doc/zion,usr/share/man/man1}
mkdir -p "$DEB_DIR"/usr/share/{bash-completion/completions,zsh/site-functions,fish/vendor_completions.d}

# Create control file
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: zion
Version: 0.2.0-dev
Section: devel
Priority: optional
Architecture: amd64
Depends: zig, curl, tar, git
Maintainer: Zion Team <maintainer@example.com>
Description: A modern, cargo-inspired package manager for Zig
 Zion is a modern package manager for the Zig programming language that
 provides seamless dependency management with automatic build integration.
 It supports GitHub repositories and provides reproducible builds through
 lock files.
Homepage: https://github.com/ghostkellz/zion
EOF

# Build the project
cd ../..
echo -e "${BLUE}Building Zion...${NC}"
zig build -Doptimize=ReleaseSafe

# Copy files
cd release/debian
cp "../../zig-out/bin/zion" "$DEB_DIR/usr/bin/"
cp "../../README.md" "$DEB_DIR/usr/share/doc/zion/"
cp "../../COMMANDS.md" "$DEB_DIR/usr/share/doc/zion/"
cp "../../DOCS.md" "$DEB_DIR/usr/share/doc/zion/"
cp "../man/zion.1" "$DEB_DIR/usr/share/man/man1/"
cp "../completions/zion.bash" "$DEB_DIR/usr/share/bash-completion/completions/zion"
cp "../completions/zion.zsh" "$DEB_DIR/usr/share/zsh/site-functions/_zion"
cp "../completions/zion.fish" "$DEB_DIR/usr/share/fish/vendor_completions.d/zion.fish"

# Set permissions
chmod 755 "$DEB_DIR/usr/bin/zion"
chmod 644 "$DEB_DIR/usr/share/doc/zion/"*
chmod 644 "$DEB_DIR/usr/share/man/man1/zion.1"

# Build package
echo -e "${BLUE}Creating Debian package...${NC}"
fakeroot dpkg-deb --build "$DEB_DIR"

echo -e "${GREEN}Debian package created: $PKG_DIR/zion_0.2.0-dev_amd64.deb${NC}"
echo "Install with: sudo dpkg -i $PKG_DIR/zion_0.2.0-dev_amd64.deb"