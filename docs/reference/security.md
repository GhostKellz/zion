# Security Reference

## Commands

```bash
zion security keygen
zion security trust <key>
zion verify
zion keyring status
zion keyring list
zion keyring archver
zion policy init
zion policy audit --json
```

## Coverage

- hash verification
- package signing and trust management
- key generation and keyring inspection
- policy-based allow/deny workflows

## Notes

- `zion policy audit --json` is the CI-friendly compliance path
- keyring and verify commands are the right surfaces for signature-related debugging
- registry credentials should not be passed on argv when safer flows exist
