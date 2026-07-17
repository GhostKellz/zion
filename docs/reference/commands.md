# Commands Reference

## Core

| Command | Description |
| --- | --- |
| `zion init` | Initialize a new Zig project |
| `zion add` | Add a dependency |
| `zion remove` | Remove a dependency |
| `zion update` | Update dependencies |
| `zion build` | Build the project |
| `zion run` | Run the project |
| `zion test` | Run tests or use the Zion-native test workflow |
| `zion doc` | Generate/open documentation |
| `zion help` | Show help |

## Package Management

These commands are experimental while real registry response handling and
transactional manifest updates are being completed.

```bash
zion add <package>
zion add <package>@<version>
zion add gh/owner/repo@v1.0.0
zion remove <package>
zion update
zion fetch
zion outdated
```

## Test Workflow

```bash
zion test
zion test bootstrap
zion test scaffold [--force]
zion test run [--suite <name>] [--seed <n>] [--cases <n>] [--include <text>] [--exclude <text>] [--failed-only]
zion test bench [--cases <n>] [--time-budget <ms>]
zion test ci [--ci-profile default|hardened]
zion test report --open [--include <text>]
```

Notes:
- `zion test` with regular flags remains the plain project test runner.
- Workflow artifacts live under `.zion/test/`.
- The scaffolded suite lives at `tests/zion_test_suite.zig`.

## Project Analysis

```bash
zion check
zion tree
zion why <package>
zion status
```

## Zig And Tooling

```bash
zion zig install <version>
zion zig use <version>
zion zig current
zion zls doctor
zion zls config
zion setup all
zion setup verify
```

## Security And Policy

```bash
zion policy init
zion policy audit --json
zion security keygen
zion verify
zion keyring status
```

## Reference Note

Curated Markdown reference docs are the maintained source of truth.

The old generated API docs were archived under `docs/archive/zdoc-api-reference/`.
