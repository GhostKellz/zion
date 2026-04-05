# Zion Test Workflow Starter Pack

This starter pack documents the historical GhostSpec-era workflow that Zion has now absorbed into its own built-in testing surface.

Current status:
- `zion test ...` is the primary public interface
- no external testing-framework package dependency is required

What this pack is for now:
- reference material for the compatibility suite layout
- examples of the workflow conventions Zion still preserves
- migration notes for older docs and user habits

Current workflow expectations:
- `zion test bootstrap` prepares the compatibility layout and scaffold
- `zion test scaffold` writes `tests/zion_test_suite.zig`
- `zion test run` executes the compatibility suite with plain `zig test`
- `zion test report --open` generates and prints a JSON run report

Historical note:
- older versions of these docs described a separate GhostSpec package, manifest helpers, and build-step wiring
- that external integration has been removed from the shipped Zion build
