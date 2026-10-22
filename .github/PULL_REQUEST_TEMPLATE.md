## Summary

<!-- Briefly describe what this PR changes and why -->

## Checklist

- [ ] `make all && make test` passes on macOS Apple Silicon (`arm64`)
- [ ] `sh -n steam-bridge/engine/feats/compat_run.sh` passes (if `compat_run.sh` was modified)
- [ ] Any new game-specific runtime fix is registered in `RuntimeFix.all` and gated behind `game_fix_on` / `fix_on`
- [ ] Third-party attributions in `THIRD_PARTY_NOTICES.md` updated if applicable
