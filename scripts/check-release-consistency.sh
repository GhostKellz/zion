#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
version="$(sed -n 's/.*\.version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' build.zig.zon | head -1)"
[[ -n "$version" ]] || { echo "missing manifest version" >&2; exit 1; }
grep -Fq "## [$version]" CHANGELOG.md
[[ "$(zig-out/bin/zion version 2>&1)" == "zion $version" ]]
grep -Fq '@VERSION@' release/man/zion.1
! grep -Fq "Zion $version" release/man/zion.1
grep -Eq "^pkgver=$version$" release/arch/PKGBUILD
grep -Fq $'\tpkgver = '"$version" release/arch/.SRCINFO
grep -Fq 'build.zig.zon' release/debian/build-deb.sh
grep -Fq 'build.zig.zon' release/rpm/zion.spec
base_commit="$(git rev-parse HEAD)"
diff_hash="$(git diff --binary HEAD | sha256sum | cut -d' ' -f1)"
if [[ -n "$(git status --short)" ]]; then provenance="$base_commit+worktree.$diff_hash"; else provenance="$base_commit"; fi
printf 'Release consistency: OK (version=%s provenance=%s)\n' "$version" "$provenance"
