# GhostSpec × Zion Collaboration Guide

_Last updated: 2025-09-25_

Welcome! This guide shares how the Zion team plans to deliver first-class GhostSpec workflows and what support we need from the GhostSpec maintainers. It complements the internal Zion roadmap (`ghostspec-integration/OVERHAUL_PLAN.md`) and keeps communication tight as we march toward GhostSpec RC1 adoption inside Zion.

---

## 1. Vision at a Glance

- **One-command enablement.** `zion ghostspec bootstrap` should set up dependencies, wire the build graph, seed starter suites, and prime CI in under 30 seconds.
- **Native developer experience.** Every common GhostSpec task (install, run, fuzz, bench, report) must feel like a built-in Zion workflow with smart defaults.
- **Insightful feedback loops.** Runs surface structured artifacts (JSON/HTML), highlight flake patterns, and plug into Zion’s performance dashboards.
- **Ecosystem alignment.** Integration should dovetail with GhostSpec’s release cadence and RFCs, while keeping Zig 0.16+ compatibility front and center.

---

## 2. What Zion Is Building

| Track | Zion Deliverable | Status |
| --- | --- | --- |
| Foundation | GhostSpec integration helper module (install/remove, build wiring, scaffolding, executor) | 🔄 in progress |
| Command Suite | `zion ghostspec` subcommands: bootstrap, install, update, uninstall, wire, scaffold | ⏳ planned |
| Execution Orchestration | Async runners for `run`, `fuzz`, `bench`, `report`, `ci`; result caching under `.zion/ghostspec/` | ⏳ planned |
| Documentation | CLI help, quick-start docs, walkthrough prompts, upgrade notes | ⏳ planned |
| Compatibility | `ghostspec-compat.json` warnings, Zig/ZLS version gating, `--force` escape hatches | ✅ initial version |
| Quality | Integration tests, CI steps, telemetry hooks for beta feedback | ⏳ planned |

---

## 3. Inputs Needed from GhostSpec Maintainers

### 3.1 Package & Build Integration
- **Stable archive references.** Confirm tarball URLs/tags to use for RC1 and upcoming releases. Provide hash update notifications when archives change.
- **Module wiring contract.** Document the expected imports (e.g., `ghostspec.zion` manifest APIs, core `ghostspec` module names) so our helper can wire `build.zig` reliably.
- **Build step helpers.** If GhostSpec exposes helper functions (e.g., `ghostspec.zion.addBuildSteps`), ensure signatures and options are finalized. Share examples for workspace-wide wiring.

### 3.2 Scaffolding Templates
- **Canonical starter suites.** Supply or bless the template set we should scaffold (property test, fuzz focus, benchmark, mock example). Provide guidance on layout, naming, and future-proofing knobs.
- **Config defaults.** Specify required config files (if any) that bootstrap should drop into `.zion/ghostspec/` or project roots.

### 3.3 Runtime Expectations
- **CLI entry points.** Confirm the command invocations and flags we should wrap (e.g., `zig build ghostspec-test`, standalone GhostSpec binary, or `ghostspec run ...`).
- **Output format.** Share JSON schemas or log contract for run/fuzz/bench outputs so we can parse into Zion’s result store.
- **Exit codes and error taxonomy.** Enumerate exit statuses and error messages to map into Zion’s UX (success, flaky, hard failure, config issues, etc.).

### 3.4 Compatibility Signals
- **Version matrix ownership.** Validate `data/ghostspec-compat.json` entries and keep it updated when GhostSpec adds/removes Zig/ZLS support.
- **Migration notices.** Flag breaking changes early (e.g., renamed commands, new config requirements) so we can communicate them via `zion ghostspec info` and docs.

### 3.5 Collaboration Channels
- **Point of contact.** Identify who on the GhostSpec side can review PRs touching shared APIs and answer quick questions.
- **Release cadence.** Share the RC timeline and release checklist so Zion can sync docs and marketing.
- **Beta feedback loop.** Decide how we funnel telemetry/bug reports back to the GhostSpec team (issue labels, shared dashboard, etc.).

---

## 4. Coordination Timeline

| Week | Zion Focus | Ask for GhostSpec Team |
| --- | --- | --- |
| W1 | Helper module & bootstrap skeleton | ✅ Confirm module/API contracts, share starter templates |
| W2 | Core subcommands wired | 🔄 Review build wiring approach, validate scaffold output |
| W3 | Async run/fuzz/bench orchestration | 🔄 Provide run command spec, output schema, error handling notes |
| W4 | Docs, walkthrough, workspace integration | 🔄 Co-author docs sections, align messaging |
| W5 | Tests, CI, beta rollout prep | 🔄 Agree on telemetry sharing and launch checklist |

Dates will flex with RC milestones; we’ll update this table weekly in sync meetings or async updates in `GSPEC_GUIDE.md`.

---

## 5. Risks & Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Zig nightly drift | Integration breaks on new Zig builds | Maintain compatibility matrix, gate bootstrap with warnings, offer `--force` escape hatch |
| Diverging build wiring | Users end up with inconsistent `build.zig` patches | Ship GhostSpec-provided helper APIs or AST patches; ensure idempotent wiring with dry-run mode |
| Long-running fuzz in CI | Pipelines stall or time out | Define CI profiles in `ghostspec-compat.json` with budgets, expose `--time-budget`/`--max-cases` flags |
| Documentation lag | Devs confused by stale instructions | Share doc updates with GhostSpec team before release; set explicit doc owners |

---

## 6. Next Actions Checklist

- [ ] GhostSpec team validates helper APIs and shares any missing hooks.
- [ ] Zion implements helper module and surfaces PR for review.
- [ ] GhostSpec team approves scaffolding templates and runtime expectations.
- [ ] Zion ships core subcommands behind a beta flag and features toggle.
- [ ] Joint dry run across Linux/macOS/Windows to sign off on RC readiness.

---

## 7. Contact & Communication

- **Zion core maintainers:** `@ghostkellz`, `@cktechdev`, `@zion-release-squad`
- **Preferred channel:** `#ghostspec-integration` on the Zion Discord (async updates every Tuesday).
- **Escalations:** Open GitHub issues with label `ghostspec-integration` for blocking problems.

Let’s build the smoothest GhostSpec experience together. Ping us anytime if you need deeper context or want to walk through the helper contracts live.
