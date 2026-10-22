# Contributing to Positron

Thank you for your interest in contributing to **Positron**! Community contributions—especially new game presets, runtime quirk fixes, bug reports, and UI/engine improvements—are very welcome.

---

## 1. Development Environment

- **Hardware**: Apple Silicon Mac (`arm64`)
- **OS**: macOS 15.0 (Sequoia) or newer
- **Toolchain**: Xcode 16+ / Swift 6.0+, `clang` (C17), `cmake`, `python3`

### Building & Running Tests Locally

```bash
# Build Dobby, C supervisor, Steam bridge dylib, Swift CLI, and signed out/Positron.app
make all

# Run all 3 C test suites and the Swift Testing suite
make test
```

Before opening a pull request, ensure both `make all` and `make test` pass with zero errors and that `sh -n steam-bridge/engine/feats/compat_run.sh` succeeds.

---

## 2. Adding or Updating a Game Preset

Game presets live in two places inside `Sources/PositronCore/`:

1. **Hand-Tuned Game Quirks (`Sources/PositronCore/GameProfileStore.swift`)**:
   - Add a `GamePresetInfo` entry to `GameQuirksDatabase.curatedCatalog` with the Steam `appID`, `title`, engine `subtitle`, `recommendedSummary`, and technical `notes`.
   - Add a matching rule in `GameQuirksDatabase.knownQuirks[appID]` specifying `translator` (`.rosetta` or `.fex`), `graphics` (`.d3dMetal`, `.dxmt`, `.wineD3D`, or `.dxvk`), `sync` (`.msync` or `.esync`), `dllOverrides`, and `extraEnvironment`.
   - If the game requires Rosetta 2 (`x86_64`), include its `appID` in `forceRosettaIDs`.
2. **Engine-Derived Presets (`Sources/PositronCore/EnginePresets.swift`)**:
   - For popular titles that follow standard engine rules (`dx12`, `dx11`, `dx9`, `vulkan`), add a `spec(appID, "Title", "Engine", .dx12)` line to `GameQuirksDatabase.enginePresetSpecs`.
3. **Switchable Runtime Fixes (`Sources/PositronCore/RuntimeFixes.swift` & `steam-bridge/engine/feats/compat_run.sh`)**:
   - Any pre-launch script fix added to `compat_run.sh` **must** be gated with `if game_fix_on <fix-id>; then ... fi` and registered in `RuntimeFix.all` (`Sources/PositronCore/RuntimeFixes.swift`) so users can toggle it ON or OFF in the UI.

---

## 3. Pull Request Checklist

- [ ] `make all && make test` passes cleanly on macOS arm64.
- [ ] Any new game-specific fix in `compat_run.sh` is registered in `RuntimeFix.all` and respects `game_fix_on` / `fix_on`.
- [ ] Native macOS games are never forced onto the Windows compatibility layer.
- [ ] Third-party code or DLLs include clear open-source license headers and attribution in `THIRD_PARTY_NOTICES.md`.
