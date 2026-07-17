# Registry Reference

> Registry-backed network operations are experimental. The current client still
> contains placeholder response paths, so these commands are for development and
> configuration inspection rather than release automation.

## Commands

```bash
zion registry list
zion registry add <url>
zion registry remove <name>
zion registry test
zion registry health
```

## Security Rules

- remote insecure `http://` registries are rejected
- local insecure registries require explicit insecure allowance where supported
- authentication should prefer environment or stdin-oriented flows instead of argv tokens

## Notes

- use `zion registry list` to inspect configured registries
- `zion registry test` and `zion registry health` do not yet provide a
  release-grade connectivity guarantee
- use `zion config` and environment variables to control registry defaults
