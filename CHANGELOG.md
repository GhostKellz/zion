# Changelog

All notable changes to Zion will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.4] - 2026-03-21 - "Hash Automation & Lock Enhancements"

### Added
- `zion hash update <package>` - Re-download and update hash in build.zig.zon
- `zion hash update --all` - Batch update all dependency hashes
- `zion hash check` - Verify all cached packages match ZON hashes
- `zion lock sync` - Bidirectional sync between ZON and lockfile
- `zion lock verify` - Check lock file integrity (read-only)
- `zion lock clean` - Remove stale lockfile entries not in build.zig.zon
- New `hash_conversion.zig` module for Zig-native hash format conversion
- Lock file help command: `zion lock help`

### Changed
- `zion lock` now supports subcommands (default behavior unchanged)
- Hash commands support Zig 0.16+ native format (name-version-base64url)
- Consistent version numbering across all documentation

### Fixed
- Version numbers now consistent across README, CHANGELOG, and build.zig.zon

---

## [0.1.3] - 2026-03-15 - "Semver & Security"

### Added
- Full semantic versioning support with constraint parsing
- Security hardening for package verification
- Version constraint fields in lock file

### Changed
- Clean file naming conventions throughout codebase

### Fixed
- Zig 0.16.0-dev.2736 compatibility updates

---

## [0.1.2] - 2026-03-10 - "Zig 0.16.0 Compatibility"

### Added
- Full Zig 0.16.0 compatibility
- Accessibility features (NO_COLOR support)
- Enhanced error messages

### Changed
- Updated std.Io, std.c, and pthread API usage for Zig 0.16.0

### Fixed
- Dependency hash updates for phantom package

---

## [0.1.1] - 2026-03-05

### Fixed
- Dependency hash updates for zsync and deps

---

## [0.1.0] - 2026-03-01 - "Initial Release"

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
