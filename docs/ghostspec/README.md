# GhostSpec Integration Overview

This document captures the current state of the GhostSpec integration inside Zion. It summarizes the helper module, the CLI surface area, and the supporting assets added during the September 2025 iteration.

## Key Components

- **Helper module** — `src/ghostspec_integration.zig` orchestrates dependency management, build wiring, suite scaffolding, artifact layout creation, and shelling out to `zig build ghostspec-test` workflows.
- **Starter template** — `src/templates/ghostspec_suite.zig` is embedded into the helper and provides a batteries-included suite covering property tests, fuzzing, benchmarking, and mocking examples.
- **Artifact layout bootstrap** — `.zion/ghostspec/{corpus,crashes,reports}` are created on demand with `.gitkeep` placeholders so repositories can opt in to tracking harness output.
- **Compatibility data** — `data/ghostspec-compat.json` is surfaced by the `zion ghostspec info` command to highlight supported Zig and ZLS versions.

## CLI Subcommands

| Command | Purpose |
| --- | --- |
| `zion ghostspec bootstrap` | Installs the dependency, wires `build.zig`, ensures artifact directories, and drops the starter suite. |
| `zion ghostspec install [--no-wire] [--scaffold] [--force]` | Adds or updates the dependency with optional re-wiring and scaffolding controls. |
| `zion ghostspec update` | Refreshes GhostSpec to the latest compatible release while reusing the install pipeline. |
| `zion ghostspec uninstall` | Removes GhostSpec and leaves follow-up cleanup to the user. |
| `zion ghostspec wire` | Injects the GhostSpec build steps if they are missing. |
| `zion ghostspec scaffold [dest] [--force]` | Writes the embedded suite to `tests/ghostspec_suite.zig` or a custom location. |
| `zion ghostspec run` | Runs the aggregated GhostSpec suite via `zig build ghostspec-test`. |
| `zion ghostspec fuzz` | Executes focused fuzzing workflows (automatically sets the test filter). |
| `zion ghostspec bench` | Drives benchmarking targets with metrics capture. |
| `zion ghostspec report` | Generates JSON reports under `.zion/ghostspec/reports/latest.json` unless overridden. |
| `zion ghostspec ci` | Runs the CI-tuned profile when budgets and fail-fast are required. |
| `zion ghostspec info` | Prints compatibility data from `data/ghostspec-compat.json`. |
| `zion ghostspec docs` | Emits curated upstream documentation links. |

## Quick Start Flow

1. **Bootstrap** — `zion ghostspec bootstrap`
2. **Execute suites** — `zion ghostspec run` (add `-- --test-filter ghostspec/fuzz:` to target a category).
3. **Analyze output** — Inspect `.zion/ghostspec/reports/latest.json` or rerun with `zion ghostspec report --format json --report-path <path>`.
4. **Iterate** — Use `zion ghostspec fuzz -- --seed 42` for reproducible fuzzing or `zion ghostspec bench` for performance tracking.

## Implementation Notes

- All filesystem mutations and allocator interactions inside `executeWorkflow` now conform to Zig 0.16’s `std.ArrayList` API and unify errors through the `CommandFailed` error set so CLI messaging remains consistent.
- The helper ensures build wiring by inserting the snippet exposed through `ghostspec_integration.buildSnippet()` only when GhostSpec is missing from `build.zig`.
- Scaffolding respects `--force` to avoid clobbering existing suites, and it creates intermediate directories on the fly so nested destinations work out of the box.

## Next Ideas

- Author walkthrough videos or asciicasts demonstrating `zion ghostspec fuzz` and `zion ghostspec bench` flows.
- Add automated regression tests that invoke the helper with a fake build graph to ensure wiring detection remains stable as `build.zig` evolves.
- Extend the compatibility data pipeline to sync GhostSpec release notes into a local cache for offline usage.
