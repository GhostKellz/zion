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
