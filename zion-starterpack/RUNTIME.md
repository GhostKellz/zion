# Runtime Expectations for Zion Integrations

This document explains how Zion should invoke GhostSpec workflows, interpret their outputs, and map exit codes into the CLI UX. It covers RC1 scope and will be revised alongside future manifest updates.

---

## Canonical Entry Points

| Workflow | Invocation | Notes |
| --- | --- | --- |
| Run suites | `zig build ghostspec-test` | Primary entry surfaced by `ghostspec.zion.addBuildSteps`. Accepts extra arguments via `zig build ghostspec-test -- <zig-test-flags>`. |
| Filter suites | `zig build ghostspec-test -- --test-filter <pattern>` | Zig forwards everything after `--` to the underlying `zig test` runner. Zion should expose this as `--filter`. |
| List tests | `zig build ghostspec-test -- --test-list` | Use for `zion ghostspec list`. Outputs test names recognized by the Zig test runner. |
| Fuzz focus | `zig build ghostspec-test -- --test-filter ghostspec/fuzz:` | Starter template prefixes fuzz cases with `ghostspec/fuzz:` so Zion can target them. |
| Benchmark focus | `zig build ghostspec-test -- --test-filter ghostspec/bench:` | Same pattern for benchmarks. |

GhostSpec does **not** ship a standalone binary in RC1; the build graph step is the supported integration path.

## Exit Codes

| Exit Code | Meaning | Zion Handling |
| --- | --- | --- |
| `0` | All suites passed, no timeouts/errors. | Report success. |
| `1` | Test failure, panic, or assertion failure bubbled from `zig test`. | Mark run as failed; surface the standard output. |
| `2` | Invocation misuse (invalid flag, malformed filter). | Treat as configuration error; prompt the user to check arguments. |
| `>= 128` | Process terminated by signal (rare on Windows). | Surface as infrastructure error and suggest rerun. |

Zig currently returns `1` for any test failure. Additional exit codes appear when the process is terminated (e.g., `130` on SIGINT). Zion should preserve the raw code for diagnostics even while mapping into UX buckets.

## Output Contracts

### Human-Readable Logs

GhostSpec leans on Zig’s testing harness, printing per-test status followed by an emoji-rich summary. Zion can show the raw stream for interactive sessions or keep the final summary lines for transcripts.

Example tail section:

```
✅ Test Summary
══════════════════════════════════════
Total tests:     12
Passed:          12 (100.0%)

⏱️  Performance
Total duration:  1.24s
Average test:    42.11ms
```

### JSON Artifact

GhostSpec’s `reporter.TestReport` exposes `exportJson(writer)` for machine consumption. Zion can compile a lightweight harness that imports `ghostspec`, calls the project’s suites via `ghostspec.test_runner`, and writes the JSON artifact under `.zion/ghostspec/run.json`.

Schema outline:

```json
{
  "summary": {
    "total": <u32>,
    "passed": <u32>,
    "failed": <u32>,
    "skipped": <u32>,
    "timeout": <u32>,
    "errors": <u32>,
    "success_rate": <float>,
    "total_duration_ms": <u64>,
    "average_test_ms": <float>
  },
  "results": [
    {
      "name": "ghostspec/property: addition is commutative",
      "status": "passed" | "failed" | "skipped" | "timeout" | "err",
      "duration_ms": <u64>,
      "error_message": <string?>
    }
  ]
}
```

All fields are present even when zero. Additional attributes (`stdout`, `stderr`, `memory_usage`) are available inside `ghostspec.test_reporter.TestExecutionResult` should Zion need richer telemetry; they can be appended later without breaking clients.

### JUnit XML

`ghostspec.test_reporter.exportJUnit(writer)` emits standards-compliant JUnit XML for CI pipelines. Zion may add an optional `--format=junit` flag to dump the XML alongside JSON.

### Location of Artifacts

- Default run cache: `.zion/ghostspec/run.json`
- Optional JUnit export: `.zion/ghostspec/run.junit.xml`
- Fuzzer corpus/crashes: `.zion/ghostspec/{corpus,crashes}/`

Zion is responsible for creating the directories before writing artifacts.

## Error Taxonomy

| Category | Detection | Zion Message |
| --- | --- | --- |
| Test failure | JSON `status != passed` | “GhostSpec suites failed” plus counterexamples. |
| Timeout | JSON `status == timeout` | Highlight offending tests; suggest `--timeout-ms` override (future flag). |
| Runner error | JSON `status == err` | Show `error_message`; classify as environment issue. |
| Configuration | Exit code `2` or stderr containing `invalid option` | Prompt to inspect CLI arguments or `build.zig` wiring. |

## Next Steps for Automation

- Wire `zion ghostspec run --format json` to invoke the compiled harness, call `report.exportJson`, and store the artifact.
- Extend telemetry uplinks to forward selected summary fields (`total`, `passed`, `failed`, `success_rate`).
- For RC1, surface human logs + JSON; HTML dashboards can arrive post-GA.
