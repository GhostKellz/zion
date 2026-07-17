#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-$repo_root/.scratch/release-artifacts}"
work_root="$output_dir/work"
version="$(sed -n 's/.*\.version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$repo_root/build.zig.zon" | head -1)"
arch="$(uname -m)"
host_uid="$(id -u)"
host_gid="$(id -g)"
rm -rf "$output_dir"
mkdir -p "$work_root/root" "$output_dir/packages"
cd "$repo_root"
zig build -Doptimize=ReleaseSafe
"$repo_root/scripts/stage-release-layout.sh" "$work_root/root"
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner -czf "$output_dir/packages/zion-$version-linux-$arch.tar.gz" -C "$work_root/root" .
mkdir -p "$work_root/arch"
cp -a "$work_root/root/." "$work_root/arch/"
cat > "$work_root/arch/.PKGINFO" <<EOF
pkgname = zion
pkgbase = zion
pkgver = $version-1
pkgdesc = A Zig project, toolchain, and dependency metadata utility
url = https://github.com/ghostkellz/zion
builddate = 0
packager = Zion local release gate
size = $(du -sb "$work_root/root" | cut -f1)
arch = $arch
license = MIT
depend = zig
depend = curl
depend = tar
depend = git
EOF
tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner --zstd -cf "$output_dir/packages/zion-$version-1-$arch.pkg.tar.zst" -C "$work_root/arch" .
mkdir -p "$work_root/deb/DEBIAN"
cp -a "$work_root/root/." "$work_root/deb/"
cat > "$work_root/deb/DEBIAN/control" <<EOF
Package: zion
Version: $version
Section: devel
Priority: optional
Architecture: amd64
Depends: zig, curl, tar, git
Maintainer: Christopher Kelley <ckelley@ghostkellz.sh>
Description: Zig project, toolchain, and dependency metadata utility
EOF
docker run --rm --network none -v "$work_root/deb:/package:ro" -v "$output_dir/packages:/out" debian:trixie-slim sh -ec "cp -a /package /work && dpkg-deb --root-owner-group --build /work /out/zion_${version}_amd64.deb"

mkdir -p "$work_root/rpm"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cat > "$work_root/rpm/SPECS/zion.spec" <<EOF
Name: zion
Version: $version
Release: 1
Summary: Zig project, toolchain, and dependency metadata utility
License: MIT
URL: https://github.com/ghostkellz/zion
BuildArch: $arch
Requires: zig, curl, tar, git

%description
Zig project, toolchain, and dependency metadata utility.

%install
mkdir -p %{buildroot}
cp -a /payload/. %{buildroot}/

%files
/usr/bin/zion
/usr/share/doc/zion
/usr/share/licenses/zion
/usr/share/man/man1/zion.1
/usr/share/bash-completion/completions/zion
/usr/share/zsh/site-functions/_zion
/usr/share/fish/vendor_completions.d/zion.fish
EOF
docker run --rm -e HOST_UID="$host_uid" -e HOST_GID="$host_gid" -v "$work_root/rpm:/work" -v "$work_root/root:/payload:ro" -v "$output_dir/packages:/out" alpine:3.24.1 sh -ec 'apk add --no-cache rpm >/dev/null && rpmbuild --define "_topdir /work" --define "__os_install_post %{nil}" -bb /work/SPECS/zion.spec >/dev/null && rpm -qip /work/RPMS/*/*.rpm >/dev/null && cp /work/RPMS/*/*.rpm /out/ && chown -R "$HOST_UID:$HOST_GID" /work /out'
tar -tzf "$output_dir/packages/zion-$version-linux-$arch.tar.gz" >/dev/null
tar --zstd -tf "$output_dir/packages/zion-$version-1-$arch.pkg.tar.zst" > "$work_root/arch-contents.txt"
grep -Fq './.PKGINFO' "$work_root/arch-contents.txt"
docker run --rm --network none -v "$output_dir/packages/zion_${version}_amd64.deb:/zion.deb:ro" debian:trixie-slim dpkg-deb --info /zion.deb >/dev/null
base_commit="$(git rev-parse HEAD)"
diff_hash="$(git diff --binary HEAD | sha256sum | cut -d' ' -f1)"
printf 'version=%s\nbase_commit=%s\nworktree_diff_sha256=%s\n' "$version" "$base_commit" "$diff_hash" > "$output_dir/PROVENANCE"
(cd "$output_dir" && sha256sum PROVENANCE packages/* > SHA256SUMS)
rm -rf "$work_root"
printf 'Release artifacts: %s\n' "$output_dir"
