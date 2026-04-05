# Runtime Expectations For Zion Test Workflow Compatibility

This document describes the current Zion-native testing workflow that preserves the old compatibility suite conventions.

## Canonical Entry Points

| Workflow | Invocation | Notes |
| --- | --- | --- |
| Run project tests | `zion test` | Plain test execution path. |
| Run compatibility suite | `zion test run` | Runs `tests/zion_test_suite.zig` through `zig test`. |
| Filter compatibility suite | `zion test run --suite property` | Maps suite names to compatibility test prefixes. |
| Fuzz-style focus | `zion test fuzz` | Filters to `zion/fuzz:` tests. |
| Benchmark-style focus | `zion test bench` | Filters to `zion/bench:` tests. |
| Report generation | `zion test report --open` | Runs the suite and emits JSON to `.zion/test/reports/run.json`. |

## Exit Behavior

- `0` means the workflow passed
- non-zero means test or invocation failure
- Zion forwards the underlying `zig test` output directly

## Artifact Locations

- Workflow report JSON: `.zion/test/reports/run.json`
- Workflow working directories: `.zion/test/{corpus,crashes,reports}/`

## Scope

This is intentionally a lightweight Zion-owned workflow layer.

It does not currently promise:
- a standalone property-testing engine
- a separate fuzzing engine
- a dedicated benchmark framework
- a dynamic mocking library
