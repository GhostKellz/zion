# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.1.x   | :white_check_mark: |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in Zion, please report it responsibly:

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Email security concerns to: **security@cktech.sh**
3. Include as much detail as possible:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

You can expect:
- Acknowledgment within 48 hours
- Status update within 7 days
- Credit in the security advisory (unless you prefer anonymity)

## Security Features

Zion includes several security features to protect your development workflow:

### Package Integrity

- **SHA-256 Hash Verification** - All downloaded packages are verified against their declared hashes
- **Provenance Tracking** - Lockfile records origin URL, download timestamp, and verification status
- **Hash Requirements** - Policy engine can enforce hash presence via `require_hash: true`

### Cryptographic Signing

- **Ed25519 Signatures** - Packages can be signed with Ed25519 keys
- **Key Generation** - `zion security keygen` creates secure key pairs
- **Signature Verification** - `zion security verify` validates package signatures
- **Trust Store** - Manage trusted signers with `zion keyring trust <fingerprint>`
- **Trust-Based Verification** - Signing keys must be explicitly trusted before accepting signatures

### Tarball Extraction Security (v1.1.1+)

- **Path Traversal Protection** - Validates all archive entries before extraction
- **Symlink Blocking** - Rejects symlinks that could escape extraction directory
- **Hardlink/Device Blocking** - Rejects potentially dangerous archive entries
- **Permission Stripping** - Uses `--no-same-owner` and `--no-same-permissions`

### Policy Engine

- **Allow/Deny Lists** - Control which sources can be used
- **Pattern Matching** - Wildcards for flexible rules (e.g., `github.com/trusted-org/*`)
- **Audit Mode** - `zion policy audit` checks all dependencies against policy
- **CI Integration** - JSON output for automated compliance checking

### Best Practices

```bash
# Initialize a policy file
zion policy init

# Require hashes for all packages
# Edit zion.policy.json: "require_hash": true

# Audit before deploying
zion policy audit --json

# Trust a package publisher's key
zion keyring trust <fingerprint>

# Add package with signature verification
zion add mypackage --verify-signatures

# Verify package signatures manually
zion security verify package.tar.gz
```

## Security Considerations

### Supply Chain

- Always verify package hashes match expected values
- Use `zion policy` to restrict package sources
- Review dependency trees with `zion tree` and `zion why`
- Pin versions in production: `zion pin package@version`

### Network Security

- All downloads use HTTPS
- Zion respects system CA certificates
- Set `SSL_CERT_FILE` for custom CA bundles in corporate environments

### Local Security

- Keys stored in `~/.zion/keys/` - protect with appropriate permissions
- Cache stored in `~/.zion/cache/` - can be cleared with `zion clean --all`
- No credentials stored in plaintext

## Dependency Security

Zion now ships with a Zion-owned core workflow surface and no required external package dependencies in `build.zig.zon`.

All dependencies are hash-pinned in `build.zig.zon`.

## Security Updates

Security updates are released as patch versions (e.g., 1.1.1) and announced via:
- GitHub Releases
- GitHub Security Advisories

Subscribe to releases to stay informed of security updates.
