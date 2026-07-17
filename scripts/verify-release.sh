#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_root="$repo_root/.scratch"
run_root="$scratch_root/release-verify-$$"
cache_root="$repo_root/.zig-cache/release-verify-$$"
image_tag=""

cleanup() {
    if [[ -n "$image_tag" ]]; then docker image rm "$image_tag" >/dev/null 2>&1 || true; fi
    rm -rf "$run_root" "$cache_root"
    rmdir "$scratch_root" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$run_root" "$cache_root/global" "$cache_root/local"
cd "$repo_root"
export ZIG_GLOBAL_CACHE_DIR="$cache_root/global"
export ZIG_LOCAL_CACHE_DIR="$cache_root/local"

for command in zig git tar curl python3 docker; do
    command -v "$command" >/dev/null || { echo "missing release dependency: $command" >&2; exit 1; }
done

echo "[1/8] formatting and repository policies"
zig fmt --check build.zig test_build.zig src tests/*.zig
bash scripts/check-project-policy.sh
bash scripts/check-command-parity.sh
python3 scripts/check-doc-links.py
for script in scripts/*.sh release/**/*.sh; do bash -n "$script"; done

echo "[2/8] clean-cache debug build and representative tests"
zig build
zig build test

echo "[3/8] clean-cache ReleaseSafe build"
zig build -Doptimize=ReleaseSafe

echo "[4/8] binary and project-flow smoke checks"
version="$(sed -n 's/.*\.version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' build.zig.zon | head -1)"
[[ "$(zig-out/bin/zion version 2>&1)" == "zion $version" ]]
zig-out/bin/zion help >/dev/null
zig-out/bin/zion status >/dev/null
mkdir -p "$run_root/project"
(cd "$run_root/project" && "$repo_root/zig-out/bin/zion" init >/dev/null)
(cd "$run_root/project" && "$repo_root/zig-out/bin/zion" lock >/dev/null)
(cd "$run_root/project" && "$repo_root/zig-out/bin/zion" lock verify >/dev/null)
(cd "$run_root/project" && "$repo_root/zig-out/bin/zion" check >/dev/null)
(cd "$run_root/project" && "$repo_root/zig-out/bin/zion" remove absent-package >/dev/null)
mkdir -p "$run_root/security"
printf 'signed fixture\n' > "$run_root/security/package.tar.gz"
(cd "$run_root/security" && "$repo_root/zig-out/bin/zion" security keygen >/dev/null)
(cd "$run_root/security" && "$repo_root/zig-out/bin/zion" security sign package.tar.gz >/dev/null)
(cd "$run_root/security" && "$repo_root/zig-out/bin/zion" security verify package.tar.gz >/dev/null)
[[ "$(stat -c '%a' "$run_root/security/.zion/keys/private.key")" == "600" ]]

echo "[5/8] release metadata consistency"
bash scripts/check-release-consistency.sh
git diff --check
namcap release/arch/PKGBUILD

echo "[6/8] install layout, upgrade, and uninstall simulation"
mkdir -p "$run_root/install-root"
bash scripts/stage-release-layout.sh "$run_root/install-root"
test -x "$run_root/install-root/usr/bin/zion"
test -f "$run_root/install-root/usr/share/doc/zion/README.md"
test -f "$run_root/install-root/usr/share/man/man1/zion.1"
test -f "$run_root/install-root/usr/share/bash-completion/completions/zion"
test -f "$run_root/install-root/usr/share/zsh/site-functions/_zion"
test -f "$run_root/install-root/usr/share/fish/vendor_completions.d/zion.fish"
test -f "$run_root/install-root/usr/share/licenses/zion/LICENSE"
bash scripts/stage-release-layout.sh "$run_root/install-root"
rm -rf "$run_root/install-root"
test ! -e "$run_root/install-root"

echo "[7/8] package artifacts and checksums"
bash scripts/build-release-artifacts.sh "$run_root/artifacts"
(cd "$run_root/artifacts" && sha256sum -c SHA256SUMS)

echo "[8/8] non-root, network-disabled container artifact"
mkdir -p .scratch
sed "s/@VERSION@/$version/g" release/man/zion.1 > .scratch/zion.1
image_tag="zion-release-verify:$version-$$"
docker build --network none -f release/docker/Dockerfile -t "$image_tag" .
rm -f .scratch/zion.1
container_version="$(docker run --rm --network none "$image_tag" version 2>&1)"
[[ "$container_version" == "zion $version" ]]

echo "Local release gate passed for Zion $version"
