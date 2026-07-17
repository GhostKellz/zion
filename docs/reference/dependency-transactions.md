# Dependency Transaction Invariants

Zion treats dependency mutation as one recoverable operation across four pieces
of project state:

- `build.zig.zon` records the selected artifact URL and Zig hash.
- `zion.lock` records the same artifact identity plus its resolved version,
  registry, constraint, checksum, and source provenance.
- `.zion/deps/<name>/` or `.zion/dev-deps/<name>/` contains only the artifact
  represented by those metadata entries.
- The platform Zion cache is immutable input to a project transaction. A failed
  project mutation does not rewrite or reinterpret the cached artifact.

For `add` and `update`, Zion resolves the source, downloads it, checks the
registry hash when one is supplied, performs required signature verification,
and validates archive layout before changing project metadata. Extraction goes
to a private `.zion/staging/dependency-*` directory. The manifest and lockfile
are each written to a same-directory file, synchronized, and atomically renamed.
Only then is the staged dependency renamed into place.

Before mutation, the private staging directory receives a recovery journal with
the prior manifest, lockfile, and installed-directory state. A completed
transaction writes a synchronized commit marker before removing its journal. If
a process is interrupted earlier, the next dependency transaction restores the
prior files and directory before starting new work.

`remove` is idempotent: removing an absent package succeeds without mutation.
Development dependencies use `.zion/dev-deps/`. Automatic transitive and
optional dependency installation is intentionally rejected until its selection
and lock semantics are defined; users must add required dependencies explicitly.
