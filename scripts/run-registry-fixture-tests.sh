#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 REGISTRY_FIXTURE_BINARY TRANSACTION_FIXTURE_BINARY ZION_BINARY" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
registry_test_binary="$(realpath "$1")"
transaction_test_binary="$(realpath "$2")"
zion_binary="$(realpath "$3")"
scratch_root="$repo_root/.scratch"
fixture_root="$scratch_root/registry-fixture-$$"
port_file="$fixture_root/port"
server_pid=""

cleanup() {
    if [[ -n "$server_pid" ]]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -rf "$fixture_root"
    rmdir "$scratch_root" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p "$fixture_root"
python3 "$repo_root/tests/registry_fixture_server.py" "$port_file" &
server_pid=$!

for _ in {1..100}; do
    [[ -s "$port_file" ]] && break
    kill -0 "$server_pid" 2>/dev/null || {
        echo "registry fixture server exited before startup" >&2
        exit 1
    }
    sleep 0.01
done

[[ -s "$port_file" ]] || {
    echo "registry fixture server did not publish a port" >&2
    exit 1
}

"$registry_test_binary" "http://127.0.0.1:$(<"$port_file")"

transaction_root="$fixture_root/transaction"
mkdir -p "$transaction_root"
"$transaction_test_binary" "$transaction_root"

cli_root="$fixture_root/cli"
mkdir -p "$cli_root" "$fixture_root/cache"
base_url="http://127.0.0.1:$(<"$port_file")"
(
    cd "$cli_root"
    export ZION_REGISTRY_URL="$base_url"
    export ZION_DISABLE_GITHUB_FALLBACK=1
    export ZION_CONCURRENT_DOWNLOADS=1
    export XDG_CACHE_HOME="$fixture_root/cache"
    "$zion_binary" init >/dev/null
    "$zion_binary" update --dry-run >/dev/null
    "$zion_binary" add fixture/package >/dev/null
    "$zion_binary" search package --registry=custom >/dev/null
    "$zion_binary" lock verify >/dev/null
    "$zion_binary" check >/dev/null
    "$zion_binary" remove package >/dev/null
)
