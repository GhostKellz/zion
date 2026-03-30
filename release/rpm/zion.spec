Name:           zion
Version:        1.0.8
Release:        1%{?dist}
Summary:        A modern package manager for Zig

License:        MIT
URL:            https://github.com/ghostkellz/zion
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  zig >= 0.16.0
BuildRequires:  git
Requires:       zig >= 0.16.0
Requires:       curl
Requires:       tar

%description
Zion is a modern, cargo-inspired package manager for the Zig programming language.
It provides seamless dependency management with automatic build integration,
making Zig project development as smooth as possible.

Features:
- Automatic dependency management
- Smart build integration
- Package extraction
- Reproducible builds with lock files
- GitHub integration
- Project scaffolding
- Zig version management
- ZLS integration

%prep
%autosetup -n %{name}-%{version}

%build
zig build -Doptimize=ReleaseSafe

%install
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_docdir}/%{name}

# Install binary
install -Dm755 zig-out/bin/zion %{buildroot}%{_bindir}/zion

# Install documentation
install -Dm644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -Dm644 docs/COMMANDS.md %{buildroot}%{_docdir}/%{name}/COMMANDS.md
install -Dm644 docs/INSTALL.md %{buildroot}%{_docdir}/%{name}/INSTALL.md

# Install license
install -Dm644 LICENSE %{buildroot}%{_docdir}/%{name}/LICENSE

%files
%{_bindir}/zion
%{_docdir}/%{name}

%changelog
* Sun Mar 30 2026 Christopher Kelley <ckelley@ghostkellz.sh> - 1.0.8-1
- Cycle detection and branch tracking release
- Add zion unpin --to-main for default branch tracking
- Add zion tree --check-cycles for dependency cycle detection
- Real Ed25519 cryptographic signing
- Registry resilience improvements
