# Configuration Reference

## Overview

Zion configuration is exposed through command flows and environment variables.

## Commands

```bash
zion config show
zion config set <key> <value>
zion config init --lua
```

## Common Environment Variables

| Variable | Description |
| --- | --- |
| `ZION_REGISTRY_URL` | Override registry URL |
| `ZION_REGISTRY_TOKEN` | Registry authentication token |
| `ZIGISTRY_TOKEN` | Zigistry authentication token |
| `ZION_CACHE_DIR` | Override cache location |
| `NO_COLOR` | Disable colored output |
| `ZION_NO_COLOR` | Zion-specific color disable |

## Notes

- Token values should be passed through environment or stdin-oriented flows where supported.
- `zion status` and `zion debug` are useful when validating config behavior.

## Storage Paths

- Zig compilation uses Zig's built-in local and global caches.
- `ZION_CACHE_DIR` overrides Zion's package and registry cache.
- Without an override, Zion uses `XDG_CACHE_HOME/zion`, the platform user cache,
  or `$HOME/.cache/zion` in that order.
- Project-local transient operations use `.zion/staging/` and remove their
  operation directory when finished.
- Repository tests and release checks use the ignored `.scratch/` directory and
  remove the paths they create.
- Zion does not use the system temporary directory as a fallback.
