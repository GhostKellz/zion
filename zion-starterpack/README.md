# GhostSpec × Zion Starter Pack

This starter pack collects the pieces Zion needs to ship a first-class "ghostspec" experience. Everything below is source-of-truth for wiring the GhostSpec RC1 channel into Zion wrappers, even though that channel is currently served from the public `main` branch.

---

## Stable Archive & Package Identity

- **Release version**: manifest reports `0.9.0-beta.1` (internal RC1 channel)
- **Minimum Zig**: 0.16.0-dev.164 (per `build.zig.zon`)
- **Archive to pin**: `https://github.com/ghostkellz/ghostspec/archive/refs/heads/main.tar.gz`
- **Hashing**: Run `zig fetch --save --hash <url>` (using the archive above) and commit the generated multihash to `build.zig.zon`. Zion should surface the hash in its lock workflow so downstream projects get reproducible builds.

There is no public RC1 tag yet—the GhostSpec team is tracking the channel internally. Zion MUST pin the exact `main` tarball hash in `build.zig.zon` until GhostSpec publishes a tag, at which point this starter pack will be updated.

## Helper API Contract

The GhostSpec Zig module exposes a small, stable surface dedicated to CLI integrators:

| Symbol | Description |
| --- | --- |
| `ghostspec.zion.manifest()` | Returns the static `Manifest` struct (shown in `src/integration/zion.zig`) describing commands, wrappers, release info, and doc links. Zion reads this during boot to populate `zion ghostspec <command>` help. |
| `ghostspec.zion.printSummary(writer)` | Convenience helper that streams the manifest summary to any `std.io.Writer`. Zion uses it for `zion ghostspec info`. |
| `ghostspec.zion.commandByName(name)` | Lookup utility backing `zion ghostspec commands <name>`. Returns null when a command is not supported. |
| `ghostspec.zion.addBuildSteps(b, dep, opts)` | Registers GhostSpec with a consumer build graph, returning `{ module, test_step }`. Zion should call this when scaffolding build.zig integrations. |

### Build Wiring Reference

```zig
const std = @import("std");
const ghostspec = b.dependency("ghostspec", .{});

const artifacts = ghostspec.zion.addBuildSteps(b, ghostspec, .{
    .step_name = "ghostspec-test",
    .step_description = "Run GhostSpec test suites",
});

// expose the module when wiring executables
exe.root_module.addImport("ghostspec", artifacts.module);
```

### Manifest Structure

```zig
const manifest = ghostspec.zion.manifest();
_ = manifest.version;         // "0.9.0-beta.1"
_ = manifest.release_channel; // "rc1"

for (manifest.commands) |cmd| {
    std.debug.print("{s}: {s}\n", .{ cmd.name, cmd.description });
}
```

This manifest is semver-stable for RC1 consumers. New commands or wrappers will be additive, and the version string will remain `0.9.0-beta.1` until the GhostSpec team promotes a new channel.

## Zion Command Expectations

Zion should project the following behavior (see dedicated `COMMANDS.md`):

- `zion ghostspec install` → runs the fetch command above, asks GhostSpec to register build steps, and writes `build.zig.zon` hash entries.
- `zion ghostspec scaffold` → drops the canonical GhostSpec test suite template (see `templates/` in this starter pack).
- `zion ghostspec info` → prints the manifest summary via `ghostspec.zion.printSummary`.
- `zion ghostspec run` → shells out to `zig build ghostspec-test` and relays progress.

## Support & Updates

- Manifest lives at `ghostspec/src/integration/zion.zig`
- Release artifacts tracked in `SPECTRA_RC1.md`
- Collaboration contact: `ghostspec@ghostkellz.dev`

The GhostSpec team will update this starter pack for future release channels (RC2, GA). Zion should treat these docs as authoritative for the internal RC1 channel until a public tag is available.
