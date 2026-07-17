#!/usr/bin/env bash
# Build RPM package for Zion
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Building RPM package for Zion...${NC}"

# Single source of truth: pull version from build.zig.zon
VERSION="$(sed -n 's/.*\.version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' ../../build.zig.zon | head -1)"
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: could not read version from build.zig.zon${NC}"
    exit 1
fi

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
cat > "$RPMBUILD_DIR/SPECS/zion.spec" << EOF
Name: zion
Version: ${VERSION}
Release: dev%{?dist}
Summary: A development tool for Zig projects
License: MIT
URL: https://github.com/ghostkellz/zion
Source0: %{name}-%{version}.tar.gz
BuildArch: x86_64

Requires: zig curl tar git
BuildRequires: zig git

%description
Zion provides project scaffolding, dependency metadata, toolchain helpers,
and a built-in test workflow for Zig projects.

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
install -Dm644 docs/README.md %{buildroot}%{_docdir}/zion/README.md
install -Dm644 docs/getting-started/installation.md %{buildroot}%{_docdir}/zion/installation.md
install -Dm644 docs/reference/commands.md %{buildroot}%{_docdir}/zion/commands.md

# Install man page
sed "s/@VERSION@/%{version}/g" release/man/zion.1 > zion.1.rendered
install -Dm644 zion.1.rendered %{buildroot}%{_mandir}/man1/zion.1

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
* $(date "+%a %b %d %Y") Zion Team <maintainer@example.com> - ${VERSION}-1
- Zion-native runtime, testing, docs, and packaging refresh
EOF

# Create source tarball
cd ../..
PKG_DIR="packages"
mkdir -p "$PKG_DIR"
TARBALL="$PKG_DIR/zion-${VERSION}.tar.gz"

echo -e "${BLUE}Creating source tarball...${NC}"
git archive --format=tar.gz --prefix=zion-${VERSION}/ HEAD > "$TARBALL"
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
