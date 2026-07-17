# Testing Overview

Zion ships a built-in testing workflow through `zion test`.

## Canonical Paths

- suite: `tests/zion_test_suite.zig`
- reports: `.zion/test/reports/run.json`
- failed cases: `.zion/test/reports/failed.txt`

## Common Flows

Scaffold the suite:

```bash
zion test scaffold --force
```

Run the full workflow suite:

```bash
zion test run
```

Run with reproducible controls:

```bash
zion test run --seed 123 --cases 32 --include property
```

Run benchmark-focused workflow:

```bash
zion test bench --cases 50 --time-budget 250
```

Generate a structured report:

```bash
zion test report --open --include fuzz
```

## Behavior Notes

- `--seed`, `--cases`, and `--time-budget` are real workflow controls.
- `--include`, `--exclude`, and `--failed-only` are real per-test workflow filters.
- The current scaffold uses a lightweight Zion-native compatibility implementation.
- `zion test --filter ...` is still the plain project test runner path.

## Current Limits

- corpus/crash replay is not fully implemented yet
- the in-tree property and benchmark helper modules are not yet the sole execution backbone of the generated suite

## Repository Gate Inventory

`zig build test` is the authoritative repository test step. It executes tests
reachable from `src/root.zig` and `src/main.zig`, the maintained command alias
suite in `src/tests/active_test_runner.zig`, the loopback registry fixture, and
the isolated dependency-transaction fixture. The fixture server covers success,
authentication, redirects, timeouts, malformed JSON, response limits, rate
limits, and retry recovery without internet access. Transaction fixtures cover
rollback and interrupted-write recovery under `.scratch/`.

The old `src/tests/*` zsync suites are retained only as historical migration
input and are not test authority. `test_build.zig` no longer references removed
zsync or phantom packages.
