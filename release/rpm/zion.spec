Name:           zion
Version:        0.3.0
Release:        1%{?dist}
Summary:        A modern package manager for Zig

License:        MIT
URL:            https://github.com/yourusername/zag
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  zig >= 0.11.0
BuildRequires:  git
Requires:       zig >= 0.11.0
Requires:       curl
Requires:       tar

%description
Zag is a modern, cargo-inspired package manager for the Zig programming language. 
It provides seamless dependency management with automatic build integration, 
making Zig project development as smooth as possible.

Features:
- Automatic dependency management
- Smart build integration
- Package extraction
- Reproducible builds with lock files
- GitHub integration
- Project scaffolding
- Clean command for removing build artifacts

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
install -Dm644 COMMANDS.md %{buildroot}%{_docdir}/%{name}/COMMANDS.md
install -Dm644 DOCS.md %{buildroot}%{_docdir}/%{name}/DOCS.md

# Install license if it exists
if [ -f LICENSE ]; then
  install -Dm644 LICENSE %{buildroot}%{_docdir}/%{name}/LICENSE
fi

%files
%{_bindir}/zion
%{_docdir}/%{name}

%changelog
* Mon Mar 11 2024 Christopher Kelley <ckelley@ghostkellz.sh>  - 0.1.0-1
- Initial package