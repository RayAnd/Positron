# Positron — Frequently Asked Questions (FAQ) & Troubleshooting

## Table of Contents

1. [General & System Requirements](#1-general--system-requirements)
2. [Steam Setup & Bridge Updates](#2-steam-setup--bridge-updates)
3. [Choosing CPU & Graphics Settings](#3-choosing-cpu--graphics-settings)
4. [Game Fixes & Custom Presets](#4-game-fixes--custom-presets)
5. [External Drives (ExFAT & APFS)](#5-external-drives-exfat--apfs)
6. [Non-Steam Standalone Games (.exe)](#6-non-steam-standalone-games-exe)
7. [Wine Prefixes, Save Games & Utilities](#7-wine-prefixes-save-games--utilities)
8. [Troubleshooting Common Issues](#8-troubleshooting-common-issues)

---

## 1. General & System Requirements

### What does Positron do?
Positron integrates with the native macOS Steam client so you can download and play Windows-only Steam games directly inside macOS Steam (plus standalone non-Steam `.exe` games) using your installed CrossOver or Wine runtime. It provides a native macOS SwiftUI app (`Positron.app`) that acts as the single source of truth for per-game presets, toggleable game fixes, and Wine prefixes.

### Does Positron include CrossOver or Wine?
No. Positron discovers and uses the CrossOver (`CrossOver.app` or `CrossOver Preview.app`) or custom Wine runtime already installed on your Mac. This lets you upgrade CrossOver at any time without waiting for a hardcoded SHA-256 allowlist update.

### What happens to native macOS games in my Steam library?
Native macOS games (such as *Cyberpunk 2077*, *Baldur's Gate 3*, and *Metro Exodus*) **always run natively on macOS**. Positron automatically detects native `.app` bundles inside `steamapps/common/` and excludes them from Windows compatibility routing.

---

## 2. Steam Setup & Bridge Updates

### Why is Steam's built-in "Properties → Compatibility" tab hidden?
To prevent conflicting settings between Steam's UI and Positron's per-game presets, Positron hides Steam's Compatibility tab so **`Positron.app` is the single source of truth**. You still get the green **Install / Play** button and the Windows filter in your Steam library.

### How do I update the Positron bridge in Steam after updating Positron.app?
- **If Steam is closed** when you open `Positron.app`, Positron automatically updates and signs `Steam.app` in the background—no clicks needed.
- **If Steam is running**, `Positron.app` displays a top banner (**"Positron Bridge Update Ready"**) with a single **Update & Restart Steam** button that installs the new bridge, re-signs `Steam.app`, and restarts Steam automatically.

### How do I completely remove Positron and restore stock Steam.app?
Open **`Positron.app` → Steam Setup** and click **Restore Stock Steam** (or run `positron steam-restore` from the CLI). Positron restores your original `Steam.app/Contents/Info.plist`, removes the injected dylib and compatibility tools, clears the `steam.cfg` update lock, and re-signs `Steam.app`.

---

## 3. Choosing CPU & Graphics Settings

### Rosetta 2 (`x86_64`) vs. FEX (`ARM64EC`)
| Setting | Best For | Notes |
| :--- | :--- | :--- |
| **Rosetta 2 (`x86_64`)** | DirectX 12 games (**D3DMetal**), AVX/AVX2 games, 32-bit (`i386`) games/launchers, and games with 1 MB PE stack reserves (*Fallout 76*). | Most compatible; required whenever **D3DMetal** is selected. |
| **FEX (`ARM64EC`)** | Clean 64-bit DirectX 11 games paired with **DXMT** on CrossOver Preview 27+. | Lower CPU translation overhead on supported 64-bit DX11 titles; automatically disables D3DMetal and Rosetta AVX flags. |

### D3DMetal vs. DXMT vs. WineD3D vs. DXVK
- **D3DMetal (Apple GPTK)**: Required for **DirectX 12** titles (*The Witcher 3 DX12*, *Red Dead Redemption 2*, *Elden Ring*, *Atomic Heart*) and Unity games that rely on `IDXGIResource::GetSharedHandle` for Media Foundation `.mp4` video playback (*Heroes of Might and Magic: Olden Era*).
- **DXMT**: Native Metal renderer for **DirectX 11** (*Fallout 76*, *Fallout 4*, *Skyrim SE*, *Frostpunk*, *Dark Souls III*). Fast, low-stutter, and capped at 120 FPS by default.
- **WineD3D**: Best for **32-bit CEF launchers** (*STAR WARS: The Old Republic*) and classic **DirectX 9 / DirectDraw** games (*Fallout 2*).
- **DXVK**: Vulkan-on-MoltenVK renderer for older DirectX 9/10/11 or Vulkan titles (*DOOM 2016 / Eternal*).

### Msync vs. Esync
- **Msync** (Mach semaphores) is the fastest synchronization primitive on macOS and is the default for almost all games.
- **Esync** (eventfd synchronization) is recommended for *Red Dead Redemption 2* (`1174180`) to prevent frame-pacing and lighting flicker under D3DMetal.

---

## 4. Game Fixes & Custom Presets

### How do I turn a specific game fix on or off?
Select any game in **Installed Games** and scroll to the **Game Fixes** section in the left column:
- Use **Game-Specific Fixes** to toggle all patches, DLL overrides, and flags for that title on or off at once.
- Or toggle individual fixes (e.g., *Witcher 3 DX12 crash & HDR fix*, *RDR2 anti-flicker*, individual `DLL <name> = n,b` overrides, or `D3DM_*` flags) and **Launch Safeguards** (*Remove `._` files on external drives*, *Keep the prefix on the internal SSD*, *Cap DXMT at 120 FPS*) independently, then click **Apply Changes to Steam**.

### Where is the presets catalog stored on disk, and how can I add my own presets?
Positron stores your editable catalog at:
```
~/Library/Application Support/Positron/presets-catalog.json
```
You can also click **Save to Catalog** in the **Installed Games** footer to save your current game's settings into `presets-catalog.json`, or click **`presets-catalog.json`** to edit the JSON file directly.

---

## 5. External Drives (ExFAT & APFS)

### Why did my game crash or cause a kernel panic on an ExFAT external drive before Positron?
Two macOS behaviors break Windows games on `ExFAT` external drives:
1. macOS Finder/Spotlight creates hidden 4,096-byte AppleDouble resource-fork files (`._Core.zip`, `._*.ba2`, `._*.dll`) on non-APFS volumes. Many Windows games scan folders for `*.zip` or `*.ba2` and crash or enter an infinite error loop when they open a 4 KB `._*` file.
2. Wine prefixes require POSIX symlinks, hardlinks, and case-insensitive metadata that `ExFAT` does not support reliably.

Positron fixes both automatically:
- Before launching any game on `/Volumes/*`, Positron cleans `._*` AppleDouble files using `dot_clean -m` and `find -name '._*' -delete`.
- Positron automatically redirects external-drive `STEAM_COMPAT_DATA_PATH` prefixes onto your internal APFS SSD at `~/Library/Application Support/Positron/prefixes/<appid>` while mapping your external Steam library as Windows drive `S:`.

---

## 6. Non-Steam Standalone Games (.exe)

### How do I add and run a game downloaded outside Steam (GOG, Epic, itch.io, standalone folder)?
1. Open **`Positron.app` → Installed Games** and click **Add Non-Steam Game…** at the bottom of the left column.
2. Select the game's Windows `.exe` file.
3. Positron assigns it a stable virtual ID, inspects its PE headers and engine DLLs to recommend a preset, and creates an isolated Wine prefix at `~/Library/Application Support/Positron/prefixes/<virtual-id>`.
4. Adjust any preset settings or Wine prefix tools, then click **Launch Game**.

---

## 7. Wine Prefixes, Save Games & Utilities

### Where are my Wine prefixes and save games located?
- **Internal APFS & External-Drive Shadow Prefixes**:
  `~/Library/Application Support/Positron/prefixes/<appid>/pfx`
- **Save Games & Windows User Profile (`steamuser`)**:
  `~/Library/Application Support/Positron/prefixes/<appid>/pfx/drive_c/users/steamuser`
- You can open either folder in one click using **Open Drive C:** and **Open Save Games** in the **Wine Prefix & Utilities** panel.

### How do I install DirectX, VC++ redistributables, or mods into a game's prefix?
Select the game in **Installed Games** and click **Run .exe / .msi** under **Files, Installers & Maintenance** to run any `.exe`, `.msi`, `.bat`, or `.cmd` installer directly inside that game's Wine prefix.

### What happens if I switch a game between Rosetta 2 and FEX, or click "Rebuild Prefix (Keep Saves)"?
Positron automatically backs up the previous prefix to `pfx.previous-<timestamp>`, copies your `drive_c/users/steamuser` save games and `AppData`/`Documents` into a fresh prefix matching the new architecture, and re-stages the Steam bridge DLLs.

---

## 8. Troubleshooting Common Issues

### Where can I check diagnostic logs when a game fails to launch?
- **Per-Game Launch & Prefix Log**: Click **Launch Log** in the game's **Wine Prefix & Utilities** panel (or open `~/Library/Application Support/Positron/prefixes/<appid>/notproton-run.log`).
- **Wine Runtime / Renderer Log**: `~/Library/Application Support/Positron/launchers/<appid>/notproton-wine.log`
- **Steam Bridge Hook Log**: `~/Library/Application Support/Positron/positron-steam.log`

### A game's launcher window is invisible or black
If the game uses a 32-bit Chromium Embedded Framework (`libcef.dll`) launcher (like *STAR WARS: The Old Republic*), select **Rosetta 2 + WineD3D** and ensure the **CEF launcher window fix** toggle is **ON** in **Game Fixes**.

### In-game videos (`.mp4`) are black or skipped in a Unity game
Unity's `WindowsVideoMedia` player requires `IDXGIResource::GetSharedHandle` and `ID3D11Fence`, which DXMT does not implement. Switch the game's **Graphics Renderer** from **DXMT** to **D3DMetal (GPTK)** on **Rosetta 2** and click **Apply & Play in Steam**.
