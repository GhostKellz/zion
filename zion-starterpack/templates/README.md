# GhostSpec Scaffolding Templates

Zion should copy these files when a project runs `zion ghostspec scaffold`. The goal is to leave developers with an immediately runnable GhostSpec experience that exercises every primary feature (property testing, fuzzing, benchmarking, mocking) while hinting at best practices.

## Files

| File | Purpose |
| --- | --- |
| `ghostspec_suite.zig` | Canonical starter suite containing a property test, fuzz target, benchmark, and mock example. Designed to live under `tests/` or `src/tests/` depending on project layout. |

## Suggested Layout

```
project-root/
  build.zig
  build.zig.zon
  src/
    ... existing modules ...
  tests/
    ghostspec_suite.zig   # ← place scaffold here
  .zion/
    ghostspec/
      corpus/             # seeded by Zion when running fuzzers
      crashes/            # populated on failure
```

## Scaffold Script Checklist

When Zion runs `zion ghostspec scaffold`:

1. Ensure `zig fetch --save https://github.com/ghostkellz/ghostspec/archive/refs/heads/main.tar.gz` has been executed (or re-run with `--hash` to update the lock entry). Until GhostSpec publishes a public RC1 tag, Zion should pin the hash of this `main` tarball.
2. Call `ghostspec.zion.addBuildSteps` inside the consumer `build.zig` if it has not already been wired.
3. Write `tests/ghostspec_suite.zig` from this template, guarding against overwriting existing files unless `--force` is provided.
4. Create `.zion/ghostspec/corpus/` and `.zion/ghostspec/crashes/` directories with a `.gitkeep` where appropriate so the layout survives in source control.
5. Print follow-up instructions (e.g., `zig build ghostspec-test`, `zion ghostspec run`) to confirm the workspace is ready.

The template is intentionally verbose—projects can prune sections they do not need, but this ensures every integration path works out of the box during Zion’s guided bootstrap.
