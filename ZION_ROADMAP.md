# Zion Roadmap — Cargo on Steroids

_Last updated: 2025-09-24_

## Vision

Transform Zion from a fast package manager into the **end-to-end productivity platform for Zig**. Inspired by Cargo, but amplified for the realities of modern systems development—deep testing, environment orchestration, AI-assisted workflows, and enterprise readiness.

We organize the roadmap into staged releases. Each stage is incremental, customer-visible, and de-risks the next.

---

## Stage 1 — GhostSpec Integration (v0.8.0 "Spectral Foundations")

**Goal:** Make Zion the canonical way to adopt GhostSpec for property testing, fuzzing, benchmarking, and mocking.

| Theme | Deliverables |
| --- | --- |
| One-command enablement | `zion ghostspec bootstrap` + compatibility matrix + build wiring helpers |
| Execution UX | Async runners, progress streaming, failure reproduction commands |
| Scaffolding | Rich suite templates, fixtures, configuration management |
| Reporting | JSON/HTML artifacts, benchmark trend caching, CI formatting |
| Tooling glue | `zion setup ghostspec`, workspace-wide orchestration, Neovim integration, Zeke AI prompts |
| Documentation | Guides, recipes, migration tips, sample repos |

**Success Metrics**
- 80% of beta projects enable GhostSpec through Zion within five minutes.
- CI matrix (Linux/macOS/Windows) shows 100% pass rate for `zion ghostspec run`.
- Post-launch survey: ≥9/10 satisfaction for developer experience.

**Dependencies**
- GhostSpec RC1 APIs (`ghostspec.zion.*`).
- zsync async runtime stability.
- Zion performance & security modules (cache, signature verification).

Reference: `ghostspec-integration/OVERHAUL_PLAN.md` for detailed execution steps.

---

## Stage 2 — Developer Experience Superpowers (v0.9.0 "One Nation Under Zig")

**Goal:** Provide a turnkey Zig development environment that rivals Rust's `rustup` + Cargo + IDE tooling.

| Theme | Deliverables |
| --- | --- |
| Toolchain management | `zion zig install/use/list` with per-project `.zigversion`, mirror selection, health checks |
| IDE/Editor integration | `zion setup zls`, `zion setup nvim`, VS Code and Helix recipes, statusline widgets |
| Project templates | Template registry, interactive `zion template new`, remote template sources |
| Workspace management | First-class monorepo support, shared cache, cross-package testing |
| Diagnostics | `zion status` dashboards (deps health, testing, perf), auto-suggested fixes |

**Highlights**
- "One Nation Under Zig" setup wizard (quick/full/team/CI modes).
- Shell integration helpers (PATH, completions, environment variables).
- AI-assisted diagnostics via Zeke (optional).

**Exit Criteria**
- Zero-to-productive developer requires ≤ 2 commands.
- All first-party IDE integrations installable via Zion.
- Workspace adoption in top partner teams.

---

## Stage 3 — Ecosystem & Distribution (v1.0.0 "Ecosystem Prime")

**Goal:** Cement Zion as the distribution nerve center for Zig modules, documentation, and community workflows.

| Theme | Deliverables |
| --- | --- |
| Registry modernization | Multi-reg registry with trust policies, analytics, trending, publish pipelines |
| Docs & discoverability | Searchable package metadata, README previews, doc builds, linting |
| Team collaboration | Shared registries, policy enforcement (`zion policy`), org-wide cache mirrors |
| Security posture | SBOM generation, vulnerability scanning, signature attestation |
| Observability | `zion metrics` CLI, opt-in telemetry dashboards, plugin API |

**Partnerships**
- Zig Foundation for registry standards.
- GhostSpec & Zeke teams for joint release cycles.
- IDE maintainers for deep integration hooks.

**Outcome**
- Zion recognized as official—or de facto—package workflow for the Zig ecosystem.
- Full marketing push with docs, blog, community talks.

---

## Stage 4 — Intelligent Automation (v1.2.0+ "Intelligence Release")

**Goal:** Layer advanced automation and AI features to accelerate teams and enterprises.

| Theme | Deliverables |
| --- | --- |
| AI-assisted workflows | Zeke Ghostwriter integration (`zion ai suggest`, `zion ai review`, `zion ai optimize`) |
| Predictive quality | Flake detection, smart retries, suggested timeouts, reliability scoring |
| Enterprise governance | Audit trails, approvals, artifact signing infrastructure, SSO integration |
| Performance insights | Historical benchmark analytics, regression alerts, profile comparisons |
| Extensibility | Plugin system, public API, workflow automations (webhooks, templates) |

**Stretch Goals**
- Autonomous dependency update bot (`zion guardian`).
- Cloud-hosted cache & runner services.
- Marketplace for templates, command packs, and AI models.

---

## Cross-Cutting Investments

| Investment | Description | Target Stage |
| --- | --- | --- |
| Reliability & QA | Broaden CI matrix, nightly stress builds, fuzz the CLI itself. | All stages |
| Documentation excellence | Living docs site, search, versioning, tutorial series, community contributions. | 1-4 |
| Telemetry & privacy | Opt-in analytics with transparent governance. | Stage 2+ |
| Community programs | Office hours, sample repos, onboarding cohorts, contributor ladders. | Stage 1+ |
| Release process | Hardened verification scripts, reproducible builds, signed artifacts. | Stage 1+ |

---

## Timeline Snapshot (Tentative)

| Quarter | Milestone |
| --- | --- |
| Q4 2025 | v0.8.0 GhostSpec GA (Stage 1) |
| Q1 2026 | v0.9.0 Developer Experience & setup (Stage 2) |
| Q2 2026 | v1.0.0 Ecosystem Prime (Stage 3) |
| Q3 2026 | v1.1.0 polish & platform hardening |
| Q4 2026 | v1.2.0 Intelligence Release (Stage 4) |

(Timelines to be refined with team capacity planning; this snapshot communicates intent.)

---

## Open Questions & Next Actions

1. **Command taxonomy** — ensure growth doesn’t overwhelm the root namespace (consider groups or command packs).
2. **Workspace strategy** — align with upcoming Zig build system changes (0.16+).
3. **Security posture** — clarify roadmap for Sigstore/OIDC integration.
4. **Community governance** — determine process for accepting third-party templates and GhostSpec add-ons.
5. **Commercial strategy** — evaluate premium support or enterprise offerings once Stage 3 matures.

**Immediate follow-up**
- Socialize this roadmap with GhostSpec, Zeke, and registry squads.
- Create issue epics aligned with Stage 1 deliverables.
- Update public communications (README blurb, roadmap badge).

---

## Near-term Polish Sprint (Q4 2025)

**Objective:** Ship a focused refinement pass across Zion’s v0.8–v0.9 feature set so the experience feels production-ready ahead of the Stage 2 push.

| Track | Prioritized Improvements | Definition of Done |
| --- | --- | --- |
| Runtime polish | Finish Zig 0.16 migration (ArrayList, alloc/deinit parity), harden cancellation paths, ensure deterministic resource cleanup. | `zig build` + smoke tests clean on Linux/macOS/Windows; no lingering deprecated API usage (`rg` guardrail). |
| CLI UX | Revamp progress messaging, add contextual hints for `zion zig`/`zion search`, audit error surfaces for actionable guidance. | Adoption of new progress indicator helpers; UX review checklist signed off. |
| Performance | Implement cached registry lookups, batch HTTP enrichment, and `PerformanceReport.deinit` allocator cleanup to avoid leaks. | Benchmark harness shows ≥10% reduction in average registry search latency; leak checker passes. |
| Testing | Add regression coverage for `zion zig` alias/setup flows and GhostSpec bootstrap templates; introduce nightly CLI smoke matrix. | New tests wired into `zig build test`; nightly pipeline green 3 runs in a row. |
| Docs & onboarding | Expand GhostSpec quick-start, author “Zion setup playbook”, and backfill changelog entries for compatibility work. | Docs merged, published to docs site, and linked from README/INSTALL. |
| Release readiness | Automate release notes, verify signing scripts, and bake cache warmers into release archives. | `verify-release.sh` enhanced; dry-run release produces signed artifacts without manual intervention. |

**Key metrics to monitor**
- CLI latency (p95) per command bucket.
- Memory footprint during long-lived `zion search` sessions.
- Regression test pass rate and median runtime.
- Documentation task completion time during user testing.

**Owner matrix**
- Runtime & performance: Registry/async squads.
- CLI UX & docs: DX guild + GhostSpec liaison.
- Testing & release: Reliability crew.

---

Zion is on track to become the **cargo-on-steroids experience** for Zig—an opinionated, batteries-included toolchain that scales from solo hackers to enterprise platforms.
