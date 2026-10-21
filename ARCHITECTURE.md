# Positron Architecture

Positron is structured into four modular layers that work together to run Windows games inside the native macOS Steam client on Apple Silicon (`arm64`):

```text
Positron/
├── Sources/
│   ├── PositronCore/               # Core framework (Runner discovery, Steam VDF, Prefixes, Profiles)
│   │   ├── GameProfileStore.swift  # Per-AppID launch profiles, 50+ curated game presets & quirk rules
│   │   ├── PrefixManager.swift     # Non-blocking library discovery, APFS CoW prefix migration & Wine tools
│   │   ├── RunnerDiscovery.swift   # Dynamic PE32/PE32+ ntdll.dll inspection & CrossOver/Wine discovery
│   │   └── SteamIntegration.swift  # Steam VDF manipulation, compatibility tool staging & DYLD launch
│   ├── PositronApp/                # Native macOS SwiftUI + AppKit application
│   │   ├── PositronApp.swift       # App entry point & screenshot exporter
│   │   ├── Theme/                  # Adaptive Light & Dark Mode Liquid Glass theme system
│   │   ├── Services/               # Steam & Positron high-res icon and hero artwork loader
│   │   ├── ViewModels/             # Main-actor observable app state
│   │   ├── Components/             # Reusable Liquid Glass brand icon, badges, and interactive cards
│   │   └── Views/                  # InstalledGamesView, SteamSetupView, EnginesScreenView, DrivesScreenView
│   └── PositronCLI/                # Command-line interface (`positron status`, `doctor`, `profile`)
├── steam-bridge/                   # Universal (arm64 + x86_64) DYLD bridge (`positron-steam.dylib`)
│   ├── engine/                     # Mach-O anchor resolver, Dobby hooks, CEF webpatch, compat_run.sh
│   ├── include/                    # Public C headers for Mach-O, tiered resolver, and WebUI injection
│   ├── src/                        #LC_UUID cache, tiered hook groups, and WebUI injection implementation
│   └── tests/                      # Unit tests for Mach-O parsing, ARM64 xref resolution, and VDF generation
├── ntdll-patcher/                  # Dynamic PE32/PE32+ (`x86_64`, `i386`, `aarch64`) ntdll.dll analyzer
│   ├── include/
│   ├── src/
│   └── tests/
├── runner-supervisor/              # Native C17 launch supervisor (`positron-run`)
│   ├── include/
│   ├── src/                        # Offline Wine registry editor, APFS CoW prefix migrator, supervisor
│   └── tests/
├── Resources/                      # AppIcon.icns, Liquid Glass icon assets, and Steam client signature DBs
└── Tests/PositronCoreTests/        # Swift Testing suite for PositronCore
```

## 1. `steam-bridge` (`positron-steam.dylib`)
- **Tiered Hook Groups**: Separates `steamclient.dylib` hooks into `CORE_COMPAT` (essential Steam Play anchors) and `OPTIONAL_UX`. If a Steam Beta update shifts an optional UI symbol, Windows game launching remains unaffected.
- **`LC_UUID` Resolved-Address Cache**: Caches resolved anchor RVAs by the Mach-O `LC_UUID` of `steamclient.dylib`, avoiding 30 MB binary scans on warm launches.

## 2. `ntdll-patcher`
- Dynamically parses `x86_64`, `i386`, and `aarch64` `ntdll.dll` PE headers and export tables (`LdrLoadDll`, `NtCreateUserProcess`) without relying on static SHA-256 allowlists.

## 3. `runner-supervisor` (`positron-run`)
- Mutates `system.reg` and `user.reg` offline before `wineserver` starts, and performs APFS copy-on-write (`clonefile`) prefix auto-migration between Rosetta 2 and FEX ARM64EC while preserving `steamuser` saves.

## 4. `PositronCore` & `PositronApp`
- Provides a native macOS user interface with adaptive Light & Dark Mode Liquid Glass styling, automatic Steam artwork loading, 50+ curated game presets, 32-bit CEF launcher quirk detection, and external drive (`APFS` / `ExFAT` shadow prefix) management.
