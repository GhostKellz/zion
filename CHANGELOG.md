# Changelog

All notable changes to Zion will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.8] - 2026-03-30 - "Cycle Detection & Branch Tracking"

### Added
- `zion unpin --to-main` - Track repository's default branch instead of releases
- `zion tree --check-cycles` - Detect circular dependencies in dependency graph
- `zion tree --duplicates` - Highlight duplicate dependencies
- `zion tree --depth=N` - Limit tree display depth
- Cycle detection module with DFS-based graph analysis
- Rich error context with "Did you mean?" suggestions (Levenshtein distance)
- Registry resilience with circuit breaker, exponential backoff, health tracking
- Default branch detection via GitHub API

### Changed
- Real Ed25519 cryptographic signing (replaced mock implementation)
- Improved error messages with actionable suggestions
- Documentation reorganization

---

## [1.0.7] - 2026-03-21 - "Hash Automation & Lock Enhancements"

### Added
- `zion hash update <package>` - Re-download and update hash in build.zig.zon
- `zion hash update --all` - Batch update all dependency hashes
- `zion hash check` - Verify all cached packages match ZON hashes
- `zion lock sync` - Bidirectional sync between ZON and lockfile
- `zion lock verify` - Check lock file integrity (read-only)
- `zion lock clean` - Remove stale lockfile entries not in build.zig.zon
- Hash conversion module for Zig-native hash format

### Changed
- `zion lock` now supports subcommands (default behavior unchanged)
- Hash commands support Zig 0.16+ native format

---

## [1.0.6] - 2026-03-15 - "Semver & Security"

### Added
- Full semantic versioning support with constraint parsing
- Security hardening for package verification
- Version constraint fields in lock file

### Fixed
- Zig 0.16.0-dev.2736 compatibility updates

---

## [1.0.5] - 2026-03-10 - "Zig 0.16.0 Compatibility"

### Added
- Full Zig 0.16.0 compatibility
- Accessibility features (NO_COLOR support)
- Enhanced error messages

### Changed
- Updated std.Io, std.c, and pthread API usage for Zig 0.16.0

---

## [1.0.0] - 2026-03-01 - "Initial Release"

### Added
- Core package management: add, remove, update, fetch
- GitHub integration for package resolution
- Lock file support (zion.lock)
- Hash verification for package integrity
- Pin/unpin commands for version control
- Workspace support
- ZLS integration
- Multi-registry support
- Cryptographic package signing
- Zig version management
- Complete development environment setup
