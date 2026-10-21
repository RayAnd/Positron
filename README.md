# Positron

[![License: MIT](https://img.shields.io/badge/License-MIT-cyan.svg)](LICENSE)
[![Platform: macOS 15+ (Apple Silicon)](https://img.shields.io/badge/macOS-15.0%2B%20(arm64)-blue.svg)](Package.swift)

**Positron** is an open-source, update-resilient, universal macOS Steam Play compatibility layer and native launch supervisor. It enables the native macOS Steam client to download, configure, and launch Windows games using **any** CrossOver build (Stable, Preview, or CXPatcher-modified), WhiskyWine, or custom Wine/FEX-Emu runner—while keeping native macOS Steam games running natively.

## Download & Installation (macOS Apple Silicon)

1. Download the latest **`Positron-macOS-arm64.dmg`** (or **`Positron-macOS-arm64.zip`**) from the [**Releases**](../../releases) page.
2. Open the `.dmg` and drag **`Positron.app`** to `/Applications`.
3. On first launch, clear the macOS quarantine attribute if prompted:
   ```bash
   xattr -cr /Applications/Positron.app
   ```
4. Launch **Positron**, click **Enable Positron in Steam**, and configure your installed Windows games from the **Installed Games** tab.

---

## Key Features

1. **Universal Runner Support (Zero SHA-256 Allowlists)**
   - Automatically discovers and analyzes *any* CrossOver, CrossOver Preview, WhiskyWine, or custom Wine installation on macOS.
   - Replaces static per-build `ntdll.dll` SHA-256 hash tables with a dynamic PE32/PE32+ (`x86_64`, `i386`, `aarch64`) export & code-cave analyzer.
2. **Update-Resilient Steam Integration (`positron-steam.dylib`)**
   - **Tiered Hook Groups**: Splits `steamclient.dylib` hooks into `CORE_COMPAT` (essential anchors) and `OPTIONAL_UX`. An optional signature change in a Steam Beta update never disables game launching.
   - **`LC_UUID` Resolved-Address Cache**: Caches resolved anchor RVAs by the Mach-O `LC_UUID` of `steamclient.dylib`, avoiding 30 MB binary scans on warm launches and supporting concurrent Stable/Beta Steam installations.
   - **Runtime `SteamClient` Store & Fiber Injection**: Replaces brittle regex replacements on minified Webpack JSX bundles with unminified `window.SteamClient` and MobX store hooks.
3. **Native `positron-run` Supervisor & 50+ Curated Game Presets**
   - **Offline Wine Registry Mutator**: Modifies `system.reg` and `user.reg` directly before `wineserver` starts—eliminating multiple `wineserver -k && wineserver -w` restart cycles before game launch.
   - **Seamless Prefix Auto-Migration**: Switching a game between CrossOver Rosetta (`x86_64`), CrossOver FEX (`arm64`), or different CrossOver versions automatically migrates the prefix in-place using APFS copy-on-write (`clonefile`) while preserving `steamuser` saves.
   - **32-Bit CEF Launcher Quirk Detection**: Automatically detects 32-bit Chromium Embedded Framework launchers (e.g., *STAR WARS: The Old Republic*) and routes them through `WineD3D` with builtin `vulkan-1=b;libglesv2=b` overrides so bundled SwiftShader DLLs never hijack the launcher window.
4. **External Drive Support (`APFS` & `ExFAT`)**
   - Automatically discovers external Steam libraries via `libraryfolders.vdf` without blocking startup on macOS TCC volume prompts, and creates APFS shadow prefixes for `ExFAT` drives.

---

## Building from Source

```bash
# Build Dobby, C libraries (positron-steam.dylib), supervisor (positron-run), and Positron.app
make all

# Run the complete C and Swift test suites
make test

# Package release archives (out/Positron-macOS-arm64.dmg, .zip, and SHA256SUMS.txt)
make package
```

## Release Flow (GitHub Actions)

Releases are built and published automatically by [`.github/workflows/release.yml`](.github/workflows/release.yml) whenever a version tag matching `v*` is pushed:

```bash
git tag -a v2.0.0 -m "Positron v2.0.0"
git push origin v2.0.0
```

---

## License

Positron is released under the [**MIT License**](LICENSE). See [**THIRD_PARTY_NOTICES.md**](THIRD_PARTY_NOTICES.md) for license details of bundled open-source dependencies (`Dobby` under Apache-2.0 and `cJSON` under MIT).
