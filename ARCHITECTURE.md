# Positron Architecture

Positron is organized into four modular layers that work together to run Windows Steam games and standalone Windows executables on Apple Silicon macOS:

```
┌────────────────────────────────────────────────────────────────────────────┐
│ 1. Positron.app (SwiftUI) & positron CLI                                   │
│    • Unified Installed Games inspector (Hero Card + 2-Column Bento Grid)   │
│    • 130+ Preset Catalog (51 Hand-Tuned + 80+ Engine Presets)              │
│    • Per-Game Toggleable Fixes (RuntimeFix + DLL & Env Overrides)          │
│    • Live SteamLibraryWatcher (DispatchSourceFileSystemObject on steamapps)│
│    • Standalone Non-Steam .exe Game Manager & Direct Launcher              │
└───────────────────────────────────────┬────────────────────────────────────┘
                                        │
┌───────────────────────────────────────▼────────────────────────────────────┐
│ 2. PositronCore (Swift 6 Framework)                                        │
│    • RunnerDiscovery: Dynamic PE32/PE32+/ARM64EC ntdll.dll inspection      │
│    • GameProfileStore: Per-game .json + .env generation & fix switches     │
│    • SteamIntegration: Info.plist injection, VDF mapping & auto-updates    │
│    • PrefixManager: APFS clonefile migration, winecfg/regedit & installers │
└───────────────────────────────────────┬────────────────────────────────────┘
                                        │
┌───────────────────────────────────────▼────────────────────────────────────┐
│ 3. positron-steam.dylib (Universal arm64/x86_64 C17 Steam Bridge)          │
│    • Tiered Mach-O signature resolver + LC_UUID RVA cache                  │
│    • Thread-safe CCompatManager hooks (live preset apply on Steam thread)  │
│    • WebUI transport routes & sp.js patch (hides Steam Compatibility tab)  │
└───────────────────────────────────────┬────────────────────────────────────┘
                                        │
┌───────────────────────────────────────▼────────────────────────────────────┐
│ 4. compat_run.sh & positron-run (Launch Supervisor & Runtime Fix Engine)   │
│    • Enforces Positron preset over stale Steam LaunchOptions               │
│    • Evaluates fix_on / game_fix_on switches from POSITRON_DISABLED_FIXES  │
│    • Redirects ExFAT /Volumes/* prefixes to internal APFS shadow prefixes  │
│    • Cleans macOS ._* AppleDouble files & stages game-specific DLL fixes   │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Universal Runner Discovery & Dynamic `ntdll.dll` Patcher (`ntdll-patcher/`)

Instead of maintaining a brittle SHA-256 hash allowlist of specific CrossOver builds, Positron parses the PE32 (`i386`), PE32+ (`x86_64`), and ARM64EC (`aarch64`) headers of any installed Wine/CrossOver `ntdll.dll`:
- Locates `LdrLoadDll` in the Export Address Table (`IMAGE_DIRECTORY_ENTRY_EXPORT`).
- Finds or appends an executable code cave to trigger `lsteamclient.dll` initialization on process startup.

---

## 2. Update-Resilient Steam Bridge (`steam-bridge/`)

`positron-steam.dylib` is injected into `/Applications/Steam.app` via `LSEnvironment.DYLD_INSERT_LIBRARIES`:
- **Mach-O Signature Resolver**: Resolves `CCompatManager`, `CUserShortcuts`, and `CWebUITransport` symbols in `steamclient.dylib` and `steamui.dylib`.
- **Thread-Safe Live Preset Apply**: When `Positron.app` applies a preset, it writes `~/Library/Application Support/Positron/pending-apply.tsv`. `hook_CCompatManager_BIsEnabled` and `hook_FindToolForTargetApp` consume `pending-apply.tsv` directly on Steam's own thread—eliminating cross-thread heap corruption in `tier0`.
- **Single Source of Truth UI Patch (`webpatch.c`)**: Enables the Windows library filter and green Install/Play button in Steam while hiding Steam's in-app Compatibility properties tab so `Positron.app` owns all per-game settings.

---

## 3. Switchable Fix Engine & Launch Script (`steam-bridge/engine/feats/compat_run.sh`)

Every launch through `compatibilitytools.d/positron-proton-*/run` executes the embedded `compat_run.sh` supervisor:
1. **Single-Source-of-Truth Environment Scrub**: Before sourcing `~/Library/Application Support/Positron/profiles/<appid>.env`, `compat_run.sh` clears any stale `CX_GRAPHICS_BACKEND`, `WINEMSYNC`, `WINEESYNC`, `D3DM_*`, or `DXMT_*` variables left over in Steam's per-game Launch Options.
2. **Per-Fix Switches (`fix_on` & `game_fix_on`)**: Each game-specific patch (`witcher3-dx12-fix`, `rdr2-anti-flicker`, `fo76-rosetta-pin`, `fo76-display-prefs`, `cef-launcher-wined3d`) and global safeguard (`exfat-appledouble-cleanup`, `apfs-shadow-prefix`, `dxmt-fps-cap`) checks `POSITRON_GAME_FIXES` and `POSITRON_DISABLED_FIXES` before executing.
3. **macOS Game Mode Bundle**: Wraps the Wine loader in a per-game macOS `.app` bundle under `~/Library/Application Support/Positron/launchers/<appid>/` with the game's icon and `LSApplicationCategoryType = public.app-category.games` so macOS Game Mode activates automatically.
