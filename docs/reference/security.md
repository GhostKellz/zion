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

## Implemented Local Surfaces

- hash verification
- Ed25519 signing and verification primitives
- key generation and GPG keyring inspection
- policy-based allow/deny workflows

## Notes

- `zion policy audit --json` emits structured compliance output for automation
- keyring and verify commands are the right surfaces for signature-related debugging
- registry credentials should not be passed on argv when safer flows exist
