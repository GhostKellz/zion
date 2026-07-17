# Version is sourced from build.zig.zon (run rpmbuild from the repo root).
%global zion_version %(sed -n 's/.*\.version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' build.zig.zon 2>/dev/null | head -1)
%global zion_zig_version %(sed -n 's/.*\.minimum_zig_version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' build.zig.zon 2>/dev/null | head -1)
Name:           zion
Version:        %{zion_version}
Release:        1%{?dist}
Summary:        A development tool for Zig projects

License:        MIT
URL:            https://github.com/ghostkellz/zion
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  zig >= %{zion_zig_version}
BuildRequires:  git
Requires:       zig >= %{zion_zig_version}
Requires:       curl
Requires:       tar

%description
Zion provides project scaffolding, dependency metadata, toolchain helpers, and
a built-in test workflow for Zig projects.


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
