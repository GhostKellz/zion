#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

metadata="src/command_metadata.zig"
matrix="docs/reference/command-capabilities.md"

mapfile -t commands < <(
    awk '
        /^[[:space:]]*\.\{ \.name = "/ && $0 !~ /\.visible = false/ {
            line = $0
            sub(/^.*\.name = "/, "", line)
            sub(/".*$/, "", line)
            print line
        }
    ' "$metadata"
)

if [[ ${#commands[@]} -eq 0 ]]; then
    echo "No command metadata entries found" >&2
    exit 1
fi

for command in "${commands[@]}"; do
    rg -Fq "command, \"$command\"" src/main.zig || {
        echo "Dispatch is missing metadata command: $command" >&2
        exit 1
    }
    rg -Fq "| \`$command\` |" "$matrix" || {
        echo "Capability matrix is missing command: $command" >&2
        exit 1
    }
    rg -Fq "$command" release/man/zion.1 || {
        echo "Man page is missing command: $command" >&2
        exit 1
    }
    for completion in release/completions/zion.bash release/completions/zion.zsh release/completions/zion.fish; do
        rg -Fq "$command" "$completion" || {
            echo "$completion is missing command: $command" >&2
            exit 1
        }
    done
done

echo "Command dispatch, help metadata, docs, man page, and completions are in parity."
