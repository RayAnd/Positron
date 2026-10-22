// SPDX-License-Identifier: MIT
import Foundation

/// A fix that compat_run.sh applies at launch. Every fix can be switched off per game through
/// GameProfile.disabledFixes, which profiles/<appid>.env exports as POSITRON_DISABLED_FIXES.
/// Game-scoped fixes also follow the per-game master switch (POSITRON_GAME_FIXES).
public struct RuntimeFix: Sendable, Identifiable, Equatable {
    public enum Scope: String, Sendable {
        case game
        case global
    }

    public let id: String
    public let title: String
    public let detail: String
    public let scope: Scope
    /// Empty means the fix can apply to any game.
    public let appIDs: Set<UInt32>

    public static func dllID(_ dll: String) -> String { "dll:\(dll)" }
    public static func envID(_ key: String) -> String { "env:\(key)" }

    public static let all: [RuntimeFix] = [
        RuntimeFix(
            id: "witcher3-dx12-fix", title: "Witcher 3 DX12 crash & HDR fix",
            detail: "Links bin/x64, stages the PSO proxy + SDR dinput8 hook, skips REDprelauncher.",
            scope: .game, appIDs: [292030]
        ),
        RuntimeFix(
            id: "rdr2-anti-flicker", title: "RDR2 anti-flicker",
            detail: "MetalFX/DLSS off, NaN clamp, esync, and SDR + TAA in system.xml.",
            scope: .game, appIDs: [1174180]
        ),
        RuntimeFix(
            id: "fo76-rosetta-pin", title: "Pin CrossOver 26.3 (Rosetta)",
            detail: "Fallout76.exe overflows its stack under FEX, so it always runs on 26.3 Rosetta.",
            scope: .game, appIDs: [1151340]
        ),
        RuntimeFix(
            id: "fo76-display-prefs", title: "Write display mode to Fallout76Prefs.ini",
            detail: "Applies the Launch in Fullscreen setting to the game's own INI.",
            scope: .game, appIDs: [1151340]
        ),
        RuntimeFix(
            id: "cef-launcher-wined3d", title: "CEF launcher window fix",
            detail: "Launchers beside libcef.dll get WineD3D and builtin vulkan-1 so their window is visible.",
            scope: .game, appIDs: []
        ),
        RuntimeFix(
            id: "exfat-appledouble-cleanup", title: "Remove ._ files on external drives",
            detail: "Deletes macOS AppleDouble files games can mistake for real data.",
            scope: .global, appIDs: []
        ),
        RuntimeFix(
            id: "apfs-shadow-prefix", title: "Keep the prefix on the internal SSD",
            detail: "Runs external-drive prefixes from Positron/prefixes. Turning off switches back to the drive's older prefix.",
            scope: .global, appIDs: []
        ),
        RuntimeFix(
            id: "dxmt-fps-cap", title: "Cap DXMT at 120 FPS",
            detail: "Protects Apple Silicon from uncapped loading scenes.",
            scope: .global, appIDs: []
        )
    ]

    public static func applicable(to appID: UInt32) -> [RuntimeFix] {
        all.filter { $0.appIDs.isEmpty || $0.appIDs.contains(appID) }
    }
}
