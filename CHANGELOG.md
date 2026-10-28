# Changelog

All notable changes to **Positron** are documented in this file.

## [2.1.0] - 2026-10-28

### Added
- **External Positron Storage & APFS Sparse Disk Images (`PositronStorageManager`)**:
  - Move all large Positron support directories (`prefixes`, `runners`, `external-prefixes`, `bridge`, `fonts`, `launchers`, and `shortcut-icons`) off your internal Mac SSD onto any external drive.
  - **Automatic APFS Sparse Disk Image (`.sparsebundle`) on `ExFAT` Drives**: Automatically creates, mounts, and manages a dynamic `PositronStorage.sparsebundle` APFS volume when an `ExFAT` external drive is chosen—preserving native POSIX symlinks, hardlinks, permissions, and zero-copy APFS `clonefile` prefix templates while using zero internal SSD space.
  - **Automatic Mounting at Launch**: Both `Positron.app` (on startup and USB drive attach) and `compat_run.sh` (on Steam game launch) automatically mount `PositronStorage.sparsebundle`, and alert clearly if the external drive is disconnected.
  - **Storage Dashboard in `Steam Drives`**: Displays total Positron storage size, free drive capacity, per-folder usage breakdown, one-click **Move Positron Storage to External Drive…**, **Compact Disk Image** (`hdiutil compact`), **Clean Old Backups** (`pfx.previous-*`), and **Move Back to Internal SSD**.

## [2.0.0] - 2026-10-22

### Added
- **Unified `Positron.app` SwiftUI Control Center**:
  - Combined Game Presets and Wine Prefix Tools into a single **Installed Games** master-detail view with a photographic Hero Banner, Suggested Best Profile card, and 2-column Bento grid.
  - **131-Game Preset Library**: 51 hand-tuned game presets + 80 engine-based presets across DirectX 12, DirectX 11, DirectX 9, and Vulkan.
  - **Switchable Per-Game Fixes (`RuntimeFix`)**: Master switch + individual toggles for every game-specific runtime patch, DLL override (`WINEDLLOVERRIDES`), environment flag, and global safeguard (`exfat-appledouble-cleanup`, `apfs-shadow-prefix`, `dxmt-fps-cap`).
  - **Per-Game Fullscreen Config (`NOTPROTON_FULLSCREEN`)**: Launches games in fullscreen at full display resolution by default, configurable per game.
  - **Live Steam Download Watcher (`SteamLibraryWatcher`)**: Monitors all `steamapps/` directories and volume mounts so newly downloaded Steam games appear automatically within ~2 seconds.
  - **One-Click "Apply & Play in Steam" & Non-Steam `.exe` Game Launcher (`StandaloneGameStore`)**: Launch Steam games directly from `Positron.app` or add/configure/launch standalone Windows `.exe` games.
  - **Automatic & One-Click Bridge Updates**: Silently updates `Steam.app` when Steam is closed, or shows a guided 1-click **Update & Restart Steam** banner when Steam is running.
- **Built-in Game Runtime Fixes**:
  - *The Witcher 3: Wild Hunt — Remastered (`292030`)*: Bundled MIT-licensed stream-output PSO #15 proxy (`amd_fidelityfx_loader_dx12.dll`) + SDR colour-space hook (`dinput8.dll`) and `bin/x64 -> x64_dx12` link.
  - *Red Dead Redemption 2 (`1174180`)*: D3DMetal anti-flicker configuration (`nvngx=d`, `D3DM_ENABLE_METALFX=0`, NaN/Inf shader clamp, `esync`, and `system.xml` SDR + TAA High).
  - *Fallout 76 (`1151340`)*: CrossOver 26.3 Rosetta 2 pin (preventing FEX `xtajit64.dll` 1 MB stack overflow), DXMT preservation alongside bundled `libcef.dll`, and `Fallout76Prefs.ini` fullscreen sync.
  - *Heroes of Might and Magic: Olden Era (`3105440`)*: D3DMetal on Rosetta 2 for Media Foundation `.mp4` intro videos + internal APFS shadow prefix and ExFAT `._*` AppleDouble cleanup.
  - *STAR WARS: The Old Republic (`1286830`)*: 32-bit CEF launcher detection (`WineD3D` + builtin `vulkan-1=b;libglesv2=b` so bundled SwiftShader DLLs never hide the launcher window).

### Fixed
- Fixed a cross-thread race in `positron-steam.dylib` by moving live `pending-apply.tsv` polling off the background loader thread onto Steam's own `CCompatManager` hooks.
- Fixed stale per-game Steam `LaunchOptions` overriding Positron presets by scrubbing preset-owned environment variables before sourcing `profiles/<appid>.env`.
