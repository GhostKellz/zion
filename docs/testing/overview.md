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

Run hardened CI profile:

```bash
zion test ci --ci-profile hardened
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
