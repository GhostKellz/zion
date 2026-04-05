Name:           zion
Version:        1.1.0
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
install -Dm644 docs/README.md %{buildroot}%{_docdir}/%{name}/README.md
install -Dm644 docs/getting-started/installation.md %{buildroot}%{_docdir}/%{name}/installation.md
install -Dm644 docs/reference/commands.md %{buildroot}%{_docdir}/%{name}/commands.md

# Install license
install -Dm644 LICENSE %{buildroot}%{_docdir}/%{name}/LICENSE

%files
%{_bindir}/zion
%{_docdir}/%{name}

%changelog
* Sat Apr 04 2026 Christopher Kelley <ckelley@ghostkellz.sh> - 1.1.0-1
- Zion-native runtime, testing, docs, and release surface refresh
