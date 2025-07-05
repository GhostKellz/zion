#!/usr/bin/env bash
# Build RPM package for Zion
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Building RPM package for Zion...${NC}"

# Check dependencies
if ! command -v rpmbuild &> /dev/null; then
    echo -e "${RED}Error: rpmbuild is not installed${NC}"
    echo "Please install: sudo dnf install rpm-build rpmdevtools"
    exit 1
fi

# Create RPM build environment
RPMBUILD_DIR="$HOME/rpmbuild"
mkdir -p "$RPMBUILD_DIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# Create spec file
cat > "$RPMBUILD_DIR/SPECS/zion.spec" << 'EOF'
Name: zion
Version: 0.2.0
Release: dev%{?dist}
Summary: A modern, cargo-inspired package manager for Zig
License: MIT
URL: https://github.com/ghostkellz/zion
Source0: %{name}-%{version}.tar.gz
BuildArch: x86_64

Requires: zig curl tar git
BuildRequires: zig git

%description
Zion is a modern package manager for the Zig programming language that
provides seamless dependency management with automatic build integration.
It supports GitHub repositories and provides reproducible builds through
lock files.

%prep
%setup -q

%build
zig build -Doptimize=ReleaseSafe

%install
rm -rf %{buildroot}

# Install binary
install -Dm755 zig-out/bin/zion %{buildroot}%{_bindir}/zion

# Install documentation
install -Dm644 README.md %{buildroot}%{_docdir}/zion/README.md
install -Dm644 COMMANDS.md %{buildroot}%{_docdir}/zion/COMMANDS.md
install -Dm644 DOCS.md %{buildroot}%{_docdir}/zion/DOCS.md

# Install man page
install -Dm644 release/man/zion.1 %{buildroot}%{_mandir}/man1/zion.1

# Install shell completions
install -Dm644 release/completions/zion.bash %{buildroot}%{_datadir}/bash-completion/completions/zion
install -Dm644 release/completions/zion.zsh %{buildroot}%{_datadir}/zsh/site-functions/_zion
install -Dm644 release/completions/zion.fish %{buildroot}%{_datadir}/fish/vendor_completions.d/zion.fish

%files
%{_bindir}/zion
%{_docdir}/zion/
%{_mandir}/man1/zion.1*
%{_datadir}/bash-completion/completions/zion
%{_datadir}/zsh/site-functions/_zion
%{_datadir}/fish/vendor_completions.d/zion.fish

%changelog
* $(date "+%a %b %d %Y") Zion Team <maintainer@example.com> - 0.2.0-dev
- Initial RPM package
EOF

# Create source tarball
cd ../..
PKG_DIR="packages"
mkdir -p "$PKG_DIR"
TARBALL="$PKG_DIR/zion-0.2.0.tar.gz"

echo -e "${BLUE}Creating source tarball...${NC}"
git archive --format=tar.gz --prefix=zion-0.2.0/ HEAD > "$TARBALL"
cp "$TARBALL" "$RPMBUILD_DIR/SOURCES/"

# Build RPM
echo -e "${BLUE}Building RPM package...${NC}"
cd release/rpm
rpmbuild -ba "$RPMBUILD_DIR/SPECS/zion.spec"

# Copy built package
mkdir -p packages
cp "$RPMBUILD_DIR/RPMS/x86_64/zion-"*.rpm packages/

echo -e "${GREEN}RPM package created in packages/directory${NC}"
echo "Install with: sudo dnf install packages/zion-*.rpm"