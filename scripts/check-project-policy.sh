#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

scan_targets=(
    src
    scripts
    release
    docs
    data
    README.md
    SECURITY.md
    TEST.zig.zon
    test_v1.0.7.sh
)

scan_globs=(
    --glob '*.zig'
    --glob '*.md'
    --glob '*.sh'
    --glob '*.zon'
    --glob '*.json'
    --glob '*.spec'
    --glob '*.1'
    --glob 'Dockerfile'
    --glob '!docs/archive/**'
)

failed=0
forbidden_temp_root='/'"tmp"

if rg -n -F "$forbidden_temp_root" "${scan_globs[@]}" "${scan_targets[@]}"; then
    echo "error: maintained project files must not depend on the system temporary directory" >&2
    failed=1
fi

if rg -n '0\.16(\.0)?|0\.17\.0-dev' "${scan_globs[@]}" \
    --glob '!build.zig.zon' "${scan_targets[@]}"; then
    echo "error: stale static Zig compatibility text found outside build.zig.zon" >&2
    failed=1
fi

if rg -n '0\.[0-9]+\.[0-9]+-dev(\.[0-9]+)?\+[[:alnum:]]+' "${scan_globs[@]}" \
    --glob '!build.zig.zon' "${scan_targets[@]}"; then
    echo "error: static Zig development snapshot found outside build.zig.zon" >&2
    failed=1
fi

if (( failed != 0 )); then
    exit 1
fi

echo "Project path and Zig-version policies passed."
