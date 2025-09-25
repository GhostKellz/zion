# GhostSpec × Zion Integration Status (RC1)

_Last sync: 2025-09-25_

## Deliverables Checklist

| Track | GhostSpec Commitment | Status | Artifact |
| --- | --- | --- | --- |
| Helper APIs | Document manifest helpers, build wiring, release archive | ✅ | `README.md` (sections: Stable Archive & Helper API Contract) |
| Scaffolding | Provide canonical starter suites + scaffold instructions | ✅ | `templates/ghostspec_suite.zig`, `templates/README.md` |
| Runtime | Define command entry points, output schema, exit codes | ✅ | `RUNTIME.md` |
| Compatibility | Seed `ghostspec-compat.json` for Zion warnings | ✅ | `../data/ghostspec-compat.json` |
| Communication | Summarize status, contacts, and follow-ups | ✅ | _this file_ |

## Next Actions

1. **W2 (Zion)**: Wire `ghostspec.zion.addBuildSteps` into the helper module; confirm scaffold file lands under `tests/`.
2. **W3 (GhostSpec)**: Share any updates to JSON schema or runner options once async orchestration PRs arrive.
3. **W4 (Joint)**: Review Zion docs against `RUNTIME.md` to ensure messaging matches RC1 behavior.
4. **W5 (Joint)**: Plan beta telemetry channel; decide on data slice to push back (candidate: summary.success_rate, failures).

## Communication Threads

- Primary contact: `ghostspec@ghostkellz.dev`
- Async stand-up: `#ghostspec-integration` on Zion Discord (Tuesdays)
- Escalations: GitHub issues tagged `ghostspec-integration`

## Change Log

- **2025-09-25**: Initial starter pack scaffolding, runtime contract, and compatibility matrix published.
