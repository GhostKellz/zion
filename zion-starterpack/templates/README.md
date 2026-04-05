# Zion Test Workflow Templates

These templates back the Zion-native testing workflow.

Primary template:
- `zion_test_suite.zig`

Canonical scaffold target:
- `tests/zion_test_suite.zig`

Implementation note:
- the embedded template file now lives at `src/templates/zion_test_suite.zig`
- the generated suite path and public workflow naming are Zion-native

When Zion runs `zion test scaffold`:
1. Write `tests/zion_test_suite.zig` unless it already exists and `--force` is not set
2. Ensure `.zion/test/reports/` and related workflow directories exist
3. Print follow-up guidance for `zion test run` and `zion test report --open`

What the template demonstrates:
- deterministic randomized testing in plain Zig
- crash-free input handling examples
- lightweight benchmark-style loops
- handwritten fake/stub patterns instead of dynamic mocking infrastructure
