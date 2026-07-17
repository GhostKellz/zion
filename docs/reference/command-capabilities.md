# Command Capability Matrix

`src/command_metadata.zig` is authoritative for top-level names, aliases,
summaries, visibility, and maturity. General help is rendered from that source;
the local `zig build command-parity` check prevents dispatch, this matrix, the
man page, and shell completions from silently drifting.

Stable means the local command surface is supported. Experimental commands may
perform network, package, editor, or toolchain operations whose compatibility is
still evolving. Reserved commands return guidance and do not claim an
implementation. Compatibility-only commands are hidden from general help.

| Command | Status | Implementation and test boundary |
| --- | --- | --- |
| `init` | Stable | Local project scaffolding; unit-tested modules |
| `add` | Experimental | Registry resolution plus journaled dependency transaction |
| `remove` | Stable | Idempotent journaled metadata and directory removal |
| `update` | Experimental | Provenance-based release resolution and journaled replacement |
| `list` | Stable | Local manifest inspection |
| `info` | Stable | Local and registry metadata inspection |
| `fetch` | Experimental | Network artifact fetch and cache |
| `pin` | Experimental | Exact-reference metadata mutation |
| `unpin` | Experimental | Release or default-branch tracking metadata |
| `repair` | Experimental | Hash and metadata repair |
| `check` | Stable | Local project health checks |
| `build` | Stable | Zig build delegation |
| `clean` | Stable | Local artifact cleanup |
| `lock` | Stable | Lock creation and verification |
| `hash` | Stable | Local hash generation and verification |
| `run` | Stable | Zig run delegation |
| `test` | Stable | Zig tests and Zion workflow tests |
| `tree` | Stable | Local dependency visualization |
| `why` | Stable | Local dependency explanation |
| `policy` | Stable | Local trust-policy management |
| `target` | Stable | Local target metadata |
| `doc` | Stable | Zig documentation delegation |
| `outdated` | Experimental | Registry-backed release comparison |
| `nvim` | Experimental | Editor integration helpers; package search is not stable |
| `config` | Stable | Local configuration inspection and generation |
| `security` | Experimental | Signing and trust helpers |
| `performance` | Experimental | Local measurements only; no benchmark guarantee |
| `debug` | Experimental | Local diagnostic helpers |
| `zig` | Experimental | Local and remote toolchain management |
| `search` | Experimental | Bounded registry search |
| `registry` | Experimental | Registry configuration and connectivity |
| `template` | Reserved | Guidance only |
| `fmt` | Reserved | Guidance to use `zig fmt` directly |
| `analyze` | Reserved | Guidance to use `tree`, `why`, and `check` |
| `publish` | Experimental | Registry publication and optional signing |
| `search-interactive` | Experimental | Interactive registry search |
| `interface` | Compatibility-only | Compatibility interface |
| `verify` | Experimental | Detached-signature verification |
| `cache` | Stable | Platform cache inspection and cleanup |
| `tui` | Experimental | Terminal interface |
| `status` | Stable | Local project summary |
| `setup` | Stable | Setup guidance and verification |
| `zls` | Experimental | Local ZLS integration |
| `workspace` | Experimental | Workspace metadata and delegation |
| `keyring` | Experimental | Local GPG trust management |
| `version` | Stable | Build-manifest-derived version output |
| `help` | Stable | Generated from command metadata |
