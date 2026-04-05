# Registry Reference

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
- use `zion registry test` or `zion registry health` to validate connectivity
- use `zion config` and environment variables to control registry defaults
