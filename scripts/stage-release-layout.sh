#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 ]]; then echo "usage: $0 DESTDIR" >&2; exit 2; fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$1"
version="$(sed -n 's/.*\.version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$repo_root/build.zig.zon" | head -1)"
[[ -n "$version" ]] || { echo "could not read project version" >&2; exit 1; }
[[ -x "$repo_root/zig-out/bin/zion" ]] || { echo "build zig-out/bin/zion first" >&2; exit 1; }
install -Dm755 "$repo_root/zig-out/bin/zion" "$dest/usr/bin/zion"
install -Dm644 "$repo_root/README.md" "$dest/usr/share/doc/zion/README.md"
install -Dm644 "$repo_root/docs/README.md" "$dest/usr/share/doc/zion/docs-index.md"
install -Dm644 "$repo_root/docs/getting-started/installation.md" "$dest/usr/share/doc/zion/installation.md"
install -Dm644 "$repo_root/docs/reference/commands.md" "$dest/usr/share/doc/zion/commands.md"
install -Dm644 "$repo_root/LICENSE" "$dest/usr/share/licenses/zion/LICENSE"
install -Dm644 "$repo_root/release/completions/zion.bash" "$dest/usr/share/bash-completion/completions/zion"
install -Dm644 "$repo_root/release/completions/zion.zsh" "$dest/usr/share/zsh/site-functions/_zion"
install -Dm644 "$repo_root/release/completions/zion.fish" "$dest/usr/share/fish/vendor_completions.d/zion.fish"
mkdir -p "$dest/usr/share/man/man1"
sed "s/@VERSION@/$version/g" "$repo_root/release/man/zion.1" > "$dest/usr/share/man/man1/zion.1"
chmod 644 "$dest/usr/share/man/man1/zion.1"
