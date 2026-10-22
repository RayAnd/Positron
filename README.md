# Positron — Steam Play for macOS

[![License: MIT](https://img.shields.io/badge/License-MIT-cyan.svg)](LICENSE)
[![Platform: macOS 15+ (Apple Silicon)](https://img.shields.io/badge/macOS-15.0%2B%20(arm64)-blue.svg)](Package.swift)
[![CI](https://github.com/RayAnd/Positron/actions/workflows/ci.yml/badge.svg)](https://github.com/RayAnd/Positron/actions/workflows/ci.yml)
[![Ko-fi](https://img.shields.io/badge/Support%20on-Ko--fi-FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/rayand)
[![GitHub Sponsors](https://img.shields.io/badge/Sponsor%20on-GitHub-EA4AAA?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/RayAnd)

**Positron** is a free, open-source macOS Steam Play compatibility layer and native SwiftUI control center for Apple Silicon Macs. It lets the native macOS Steam client download, configure, and launch Windows-only Steam games—as well as standalone non-Steam `.exe` games—using your installed CrossOver (Stable or Preview) or Wine/FEX runtime, while keeping native macOS Steam games running natively.

---

## Highlights

- **Positron.app as Your Single Source of Truth**
  - Manage per-game CPU translators (**Rosetta 2 `x86_64`** vs **FEX `ARM64EC`**), graphics backends (**D3DMetal**, **DXMT**, **DXVK**, **WineD3D**), synchronization (**Msync** / **Esync**), **Launch in Fullscreen**, **Retina High-DPI**, **Metal HUD**, and Wine prefixes in one unified interface.
  - Automatically hides Steam's redundant in-app Compatibility tab while enabling the green **Install / Play** button for every Windows game in your Steam library.
- **130+ Game Preset Library with Switchable Fixes**
  - Ships with **51 hand-tuned game presets** and **80+ engine-derived presets** across DirectX 12, DirectX 11, DirectX 9, and Vulkan titles.
  - **Every applied fix is individually toggleable ON or OFF** in the UI—including game-specific runtime patches, individual `WINEDLLOVERRIDES`, environment flags, and global launch safeguards.
- **Native macOS Game Protection**
  - Automatically detects games that ship native macOS `.app` bundles (such as *Cyberpunk 2077*, *Baldur's Gate 3*, and *Metro Exodus*) and excludes them from Windows compatibility routing so they always run as native macOS binaries.
- **External Drive & ExFAT Support**
  - Discovers Steam libraries across internal APFS SSDs and external drives (`APFS`, `ExFAT`, `HFS+`).
  - Automatically redirects `ExFAT` Wine prefixes onto your internal APFS SSD (`~/Library/Application Support/Positron/prefixes/<appid>`), mounts the external Steam library as drive `S:`, and strips macOS `._*` AppleDouble resource-fork files before launch so games never crash or kernel-panic on external drives.
- **Live Download Detection & Non-Steam `.exe` Game Launcher**
  - Watches your `steamapps/` folders in real time—newly downloaded Steam games appear in **Installed Games** automatically within ~2 seconds of installation completing.
  - Add any non-Steam Windows game (`.exe`) via **Add Non-Steam Game…** to give it its own isolated prefix, auto-analyzed preset, and one-click **Launch Game** button.
- **Integrated Wine Prefix Toolkit**
  - Launch `winecfg`, `regedit`, `control`, `uninstaller`, or custom `.exe` / `.msi` / `.bat` installers inside any game's prefix, open `Drive C:` or `Save Games` in Finder, or rebuild a prefix while preserving all `steamuser` saves.

---

## Requirements

- **Mac**: Apple Silicon (`M1` / `M2` / `M3` / `M4` series, `arm64`)
- **OS**: macOS 15.0 (Sequoia) or newer
- **Steam**: Native [macOS Steam client](https://store.steampowered.com/about/) installed at `/Applications/Steam.app`
- **Translation Runtime**: [CrossOver](https://www.codeweavers.com/crossover) (26.x Stable or 27.x Preview) installed in `/Applications`

---

## Quick Start

1. **Download & Install**
   - Download the latest **`Positron-macOS-arm64.dmg`** (or **`.zip`**) from [**Releases**](../../releases), open it, and drag **`Positron.app`** to `/Applications`.
   - On first launch, if macOS Gatekeeper prompts that the app is ad-hoc signed, clear the quarantine attribute in Terminal:
     ```bash
     xattr -cr /Applications/Positron.app
     ```
2. **Enable Positron in Steam (One Click)**
   - Open **`Positron.app`**. If Positron is not yet active in Steam, click **Enable Positron in Steam** in the top banner (or on the **Steam Setup** tab).
   - Positron stages its runtime bridge, registers your CrossOver Rosetta & FEX engines in Steam, signs `Steam.app`, and restarts Steam automatically.
3. **Configure & Play Your Games**
   - In Steam, install any Windows game (use the Windows filter icon in your Steam Library if needed).
   - Once downloaded, the game appears automatically in **`Positron.app` → Installed Games**.
   - Select the game, review or customize its **Suggested Best Profile** and **Game Fixes**, and click **Apply & Play in Steam**.

---

## Built-In Game Fixes (Toggleable in UI)

Every runtime fix and DLL/environment override can be switched **ON** or **OFF** per game inside **Installed Games → Game Fixes**:

| Game | AppID | Recommended Pipeline | Built-in Toggleable Fix |
| :--- | :--- | :--- | :--- |
| **The Witcher 3: Wild Hunt — Remastered** | `292030` | Rosetta 2 + D3DMetal (DX12) | Links `bin/x64 -> x64_dx12`, stages the MIT-licensed stream-output PSO #15 proxy (`amd_fidelityfx_loader_dx12.dll`) + SDR colour-space hook (`dinput8.dll`), bypasses `REDprelauncher.exe`, and disables `winspool.drv`. |
| **Red Dead Redemption 2** | `1174180` | Rosetta 2 + D3DMetal (DX12) + Esync | Disables D3DMetal's broken DLSS-to-MetalFX bridge (`nvngx=d`, `D3DM_ENABLE_METALFX=0`), clamps NaN/Inf shader samples, and configures `system.xml` for DX12 SDR + TAA High to eliminate 3D world blinking. |
| **Fallout 76** | `1151340` | Rosetta 2 + DXMT (DX11) + Msync | Pins CrossOver 26.3 Rosetta (avoiding FEX `xtajit64.dll` 1 MB stack overflow), keeps `Fallout76.exe` on DXMT despite its bundled `libcef.dll`, uses `xaudio2_7=n,b`, and syncs fullscreen preferences to `Fallout76Prefs.ini`. |
| **Heroes of Might and Magic: Olden Era** | `3105440` | Rosetta 2 + D3DMetal + Standard DPI | Uses D3DMetal on Rosetta 2 for Media Foundation `.mp4` video playback, keeps Retina scaling off, and runs the prefix on internal APFS while cleaning `._*` files on ExFAT drives. |
| **STAR WARS: The Old Republic** | `1286830` | Rosetta 2 (WoW64) + WineD3D | Detects the 32-bit CEF `launcher.exe` (`libcef.dll`), forces `WineD3D` + builtin `vulkan-1=b;libglesv2=b`, and disables the overlay shim so bundled SwiftShader DLLs cannot make the launcher window invisible. |
| **Atomic Heart** | `668580` | Rosetta 2 + D3DMetal (DX12) + AVX | Configures Rosetta 2 AVX + D3DMetal for Unreal Engine 4 DX12 rendering with `xaudio2_9=n,b` and native VC++ runtime overrides. |
| **Fallout 2** | `38410` | Rosetta 2 (32-bit) + WineD3D | Forces `ddraw=n,b;dinput=n,b;dinput8=n,b` so the bundled High-Resolution Patch (`f2_res` / `sfall`) loads cleanly. |

---

## Frequently Asked Questions (FAQ)

> For the complete troubleshooting and technical FAQ, see [**`docs/FAQ.md`**](docs/FAQ.md).

### Does Positron modify my native macOS Steam games?
**No.** Positron inspects both a curated native-Mac exclusion list (*Cyberpunk 2077*, *Baldur's Gate 3*, *Metro Exodus*, etc.) and each game's installation folder in `steamapps/common/`. Any game shipping a native macOS `.app` bundle is excluded from Positron's Windows compatibility catalog and runs natively on macOS.

### When should I choose Rosetta 2 vs. FEX ARM64EC?
- **Rosetta 2 (`x86_64`)** is the most compatible choice and is **required** for:
  - All **DirectX 12** games using Apple **D3DMetal (GPTK)**
  - Games requiring **AVX / AVX2 / F16C** instruction advertising (`ROSETTA_ADVERTISE_AVX=1`)
  - **32-bit (`i386`)** games and 32-bit CEF launchers
  - Games with small 1 MB PE stack reserves or heavy anti-tamper unpackers (e.g., *Fallout 76*)
- **FEX (`ARM64EC`)** uses CrossOver Preview's native `arm64` Wine loader with FEX JIT translation and pairs best with **DXMT** on clean 64-bit DirectX 11 games.

### When should I choose D3DMetal vs. DXMT vs. WineD3D vs. DXVK?
- **D3DMetal (Apple GPTK)**: Best for **DirectX 12** games (*The Witcher 3 DX12*, *Red Dead Redemption 2*, *Elden Ring*, *Atomic Heart*, UE5 titles) and Unity games that need Media Foundation shared texture handles. Requires **Rosetta 2**.
- **DXMT**: Native Metal implementation of **DirectX 11** (*Fallout 76*, *Fallout 4*, *Skyrim SE*, *Frostpunk*, *Dark Souls III*). Works on both **Rosetta 2** and **FEX** and defaults to a safe 120 FPS cap on Apple Silicon.
- **WineD3D**: Best for **32-bit CEF launchers** (*STAR WARS: The Old Republic*) and classic **DirectX 9 / DirectDraw** titles (*Fallout 2*, *Source* engine classics).
- **DXVK**: Translates DirectX 9/10/11 to Vulkan over MoltenVK; useful for Vulkan-native or idTech titles.

### Can I store my Steam Library on an external ExFAT drive?
**Yes.** Wine prefixes themselves cannot run reliably on `ExFAT` (which lacks POSIX symlinks/hardlinks and creates macOS `._*` AppleDouble files that crash games). Positron solves this automatically via two built-in safeguards:
1. **Internal APFS Shadow Prefix**: Your game's large asset files stay on the external drive (mapped as `S:`), while its small Wine prefix runs on your internal APFS SSD at `~/Library/Application Support/Positron/prefixes/<appid>`.
2. **AppleDouble (`._*`) Cleanup**: Before launching a game on `/Volumes/*`, Positron runs `dot_clean -m` and removes stray `._*` files so game engines scanning `.zip` / `.ba2` / `.pak` archives never crash.

### How do I launch non-Steam Windows games (`.exe`)?
Click **Add Non-Steam Game…** at the bottom-left of the **Installed Games** tab and select any Windows `.exe`. Positron assigns it a dedicated APFS prefix (`~/Library/Application Support/Positron/prefixes/<virtual-id>`), inspects its PE headers and engine DLLs to suggest a preset, and lets you start it directly with the green **Launch Game** button.

---

## Building from Source

```bash
# Clone the repository
git clone https://github.com/RayAnd/Positron.git
cd Positron

# Build C supervisor, Steam bridge dylib, Swift CLI, and signed out/Positron.app
make all

# Run all C and Swift test suites
make test

# Package distributable out/Positron-macOS-arm64.dmg and .zip
make package
```

---

## Project Documentation

- [**Architecture & Internals (`ARCHITECTURE.md`)**](ARCHITECTURE.md)
- [**Full FAQ & Troubleshooting (`docs/FAQ.md`)**](docs/FAQ.md)
- [**Contributing Guide (`CONTRIBUTING.md`)**](CONTRIBUTING.md)
- [**Code of Conduct (`CODE_OF_CONDUCT.md`)**](CODE_OF_CONDUCT.md)
- [**Security Policy (`SECURITY.md`)**](SECURITY.md)
- [**Changelog (`CHANGELOG.md`)**](CHANGELOG.md)
- [**Third-Party Open Source Notices (`THIRD_PARTY_NOTICES.md`)**](THIRD_PARTY_NOTICES.md)

---

## Support Positron ❤️

Positron is 100% free and open-source software ([MIT License](LICENSE)). If Positron helped you play your Windows library on macOS, voluntary contributions are always appreciated:

- ☕️ **Ko-fi (Apple Pay, Card, PayPal — No Login Needed):** [https://ko-fi.com/rayand](https://ko-fi.com/rayand)
- ❤️ **GitHub Sponsors:** [https://github.com/sponsors/RayAnd](https://github.com/sponsors/RayAnd)
