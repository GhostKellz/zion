# Local Release Procedure

Zion does not use CI for release readiness. Run the local gate from the
repository root and review its output before changing Git state.

```bash
./scripts/verify-release.sh
```

The artifact builder records the current `HEAD` plus a SHA-256 digest of the
uncommitted diff. That identifies the exact reviewed worktree before a release
commit exists. After the full task list is complete and Git mutations are
explicitly approved, use this order:

1. Review `git status`, `git diff`, and the local gate output.
2. Create the release commit containing the reviewed worktree.
3. Run the local gate again from the clean release commit. Its provenance must
   contain only that commit ID, with an empty-diff digest.
4. Read the release version from `build.zig.zon` and create the corresponding
   signed tag at that exact commit.
5. Verify the tag signature locally.
6. Push only after explicit approval.
7. Publish only artifacts whose checksums were regenerated from the tagged
   commit, then verify the published checksums.

Do not commit, tag, push, sign, or publish as part of the verification script.
