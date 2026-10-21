// SPDX-License-Identifier: MIT
import Foundation

public enum SyncPrimitive: String, Codable, Sendable, CaseIterable {
    case msync = "msync"
    case esync = "esync"
    case none = "none"
}

public struct PresetCatalogEntry: Codable, Sendable, Identifiable, Equatable {
    public var info: GamePresetInfo
    public var recommendedProfile: GameProfile
    public var id: UInt32 { info.appID }

    public init(info: GamePresetInfo, recommendedProfile: GameProfile) {
        self.info = info
        self.recommendedProfile = recommendedProfile
    }
}

public struct GamePresetInfo: Codable, Sendable, Identifiable, Equatable {
    public let appID: UInt32
    public let title: String
    public let subtitle: String
    public let recommendedSummary: String
    public let notes: String

    public var id: UInt32 { appID }

    public init(appID: UInt32, title: String, subtitle: String, recommendedSummary: String, notes: String) {
        self.appID = appID
        self.title = title
        self.subtitle = subtitle
        self.recommendedSummary = recommendedSummary
        self.notes = notes
    }
}

public struct GameProfile: Codable, Sendable, Equatable {
    public var appID: UInt32
    public var runnerID: String?
    public var translator: CPUTranslator
    public var graphics: GraphicsBackend
    public var sync: SyncPrimitive
    public var retinaMode: Bool
    public var metalHUD: Bool
    public var advertiseAVX: Bool
    public var disableHidraw: Bool
    public var fexReducedPrecision: Bool
    public var dllOverrides: [String: String]
    public var extraEnvironment: [String: String]

    public init(
        appID: UInt32,
        runnerID: String? = nil,
        translator: CPUTranslator = .rosetta,
        graphics: GraphicsBackend = .d3dMetal,
        sync: SyncPrimitive = .msync,
        retinaMode: Bool = false,
        metalHUD: Bool = false,
        advertiseAVX: Bool = true,
        disableHidraw: Bool = false,
        fexReducedPrecision: Bool = true,
        dllOverrides: [String: String] = [:],
        extraEnvironment: [String: String] = [:]
    ) {
        self.appID = appID
        self.runnerID = runnerID
        self.translator = translator
        self.graphics = graphics
        self.sync = sync
        self.retinaMode = retinaMode
        self.metalHUD = metalHUD
        self.advertiseAVX = advertiseAVX
        self.disableHidraw = disableHidraw
        self.fexReducedPrecision = fexReducedPrecision
        self.dllOverrides = dllOverrides
        self.extraEnvironment = extraEnvironment
    }

    public func sanitized() -> GameProfile {
        var copy = self
        if copy.translator == .fex {
            if copy.graphics == .d3dMetal {
                copy.graphics = .dxmt
            }
            copy.advertiseAVX = false
            copy.extraEnvironment.removeValue(forKey: "ROSETTA_ADVERTISE_AVX")
            for k in copy.extraEnvironment.keys where k.hasPrefix("D3DM_") {
                copy.extraEnvironment.removeValue(forKey: k)
            }
        }
        return copy
    }

    public func buildLaunchEnvironment(runnerRoot: URL, prefixRoot: URL) -> [String: String] {
        let clean = sanitized()
        let rootPath = runnerRoot.path(percentEncoded: false)
        let pfxPath = prefixRoot.appending(path: "pfx").path(percentEncoded: false)

        var env: [String: String] = [
            "WINEPREFIX": pfxPath,
            "CX_ROOT": rootPath,
            "CX_GRAPHICS_BACKEND": clean.graphics.rawValue,
            "WINEDEBUG": "-all",
            "SteamAppId": String(clean.appID),
            "SteamGameId": String(clean.appID)
        ]

        switch clean.sync {
        case .msync:
            env["WINEMSYNC"] = "1"
        case .esync:
            env["WINEESYNC"] = "1"
        case .none:
            env["WINEMSYNC"] = "0"
        }

        if clean.translator == .fex {
            env["WINELOADER"] = "\(rootPath)/lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine"
            env["WINESERVER"] = "\(rootPath)/bin/wineserver-arm64"
            env["FEX_X87REDUCEDPRECISION"] = clean.fexReducedPrecision ? "1" : "0"
        } else {
            env["WINELOADER"] = "\(rootPath)/lib/wine/x86_64-unix/wine"
            env["WINESERVER"] = "\(rootPath)/bin/wineserver"
            if clean.advertiseAVX {
                env["ROSETTA_ADVERTISE_AVX"] = "1"
            }
        }

        if clean.metalHUD {
            env["MTL_HUD_ENABLED"] = "1"
            if clean.graphics == .dxmt {
                env["DXMT_HUD"] = "fps,devinfo"
            }
        }

        var overrides = [
            "steamclient=n",
            "steamclient64=n",
            "lsteamclient=b"
        ]
        for (dll, mode) in clean.dllOverrides.sorted(by: { $0.key < $1.key }) {
            overrides.append("\(dll)=\(mode)")
        }
        env["WINEDLLOVERRIDES"] = overrides.joined(separator: ";")

        for (k, v) in clean.extraEnvironment {
            env[k] = v
        }
        return env
    }

    public func resolvedCompatToolName(among runners: [DiscoveredRunner]) -> String {
        let clean = sanitized()
        let matchingRunner: DiscoveredRunner?
        if let wantedID = clean.runnerID,
           let found = runners.first(where: { $0.id == wantedID && $0.supportedTranslators.contains(clean.translator) }) {
            matchingRunner = found
        } else {
            matchingRunner = runners.first(where: { $0.kind == .crossOverPreview && $0.supportedTranslators.contains(clean.translator) })
                ?? runners.first(where: { $0.supportedTranslators.contains(clean.translator) })
                ?? runners.first
        }
        guard let runner = matchingRunner else {
            return "positron-proton-default-\(clean.translator.rawValue)"
        }
        let actualTranslator = runner.supportedTranslators.contains(clean.translator)
            ? clean.translator
            : (runner.supportedTranslators.first ?? .rosetta)
        return "positron-proton-\(runner.id)-\(actualTranslator.rawValue)"
    }

    public func buildSteamLaunchOptionsString() -> String {
        let clean = sanitized()
        var parts: [String] = []
        parts.append("CX_GRAPHICS_BACKEND=\(clean.graphics.rawValue)")
        parts.append("WINEMSYNC=\(clean.sync == .msync ? "1" : "0")")
        if clean.translator == .fex {
            parts.append("FEX_X87REDUCEDPRECISION=\(clean.fexReducedPrecision ? "1" : "0")")
        } else if clean.advertiseAVX {
            parts.append("ROSETTA_ADVERTISE_AVX=1")
        }
        if clean.retinaMode {
            parts.append("NOTPROTON_RETINA=1")
        }
        if clean.metalHUD {
            parts.append("MTL_HUD_ENABLED=1")
            if clean.graphics == .dxmt {
                parts.append("DXMT_HUD=fps,devinfo")
            }
        }
        if clean.disableHidraw {
            parts.append("NOTPROTON_DISABLE_HIDRAW=1")
        }
        return parts.joined(separator: " ") + " %command%"
    }

    public func buildPositronEnvFileContent() -> String {
        let clean = sanitized()
        var lines: [String] = [
            "# Positron auto-generated game profile for AppID \(clean.appID)",
            "export CX_GRAPHICS_BACKEND=\"\(clean.graphics.rawValue)\"",
            "export WINEMSYNC=\"\(clean.sync == .msync ? "1" : "0")\""
        ]
        if clean.translator == .fex {
            lines.append("export FEX_X87REDUCEDPRECISION=\"\(clean.fexReducedPrecision ? "1" : "0")\"")
        } else {
            lines.append("export ROSETTA_ADVERTISE_AVX=\"\(clean.advertiseAVX ? "1" : "0")\"")
        }
        lines.append("export NOTPROTON_RETINA=\"\(clean.retinaMode ? "1" : "0")\"")
        if clean.metalHUD {
            lines.append("export MTL_HUD_ENABLED=\"1\"")
            if clean.graphics == .dxmt {
                lines.append("export DXMT_HUD=\"fps,devinfo\"")
            }
        }
        if clean.disableHidraw {
            lines.append("export NOTPROTON_DISABLE_HIDRAW=\"1\"")
        }
        if !clean.dllOverrides.isEmpty {
            let ov = clean.dllOverrides.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ";")
            lines.append("export WINEDLLOVERRIDES=\"\(ov);${WINEDLLOVERRIDES:-}\"")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum GameQuirksDatabase {
    /// Games that ship native 64-bit macOS ports on Steam and should NEVER be forced
    /// onto the Positron Windows compatibility layer.
    public static let knownNativeMacAppIDs: Set<UInt32> = [
        1091500, // Cyberpunk 2077 (Native Apple Silicon macOS port)
        412020,  // Metro Exodus (Native macOS port)
        1086940  // Baldur's Gate 3 (Native macOS port)
    ]

    /// Comprehensive 50-game library of Windows-only Steam games with best-known Positron profiles.
    public static let catalog: [GamePresetInfo] = [
        GamePresetInfo(appID: 292030, title: "The Witcher 3: Wild Hunt — Remastered", subtitle: "REDengine 3 • 64-bit DirectX 12 & DirectX 11", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + Msync + AVX", notes: "Uses D3DMetal for the Next-Gen DirectX 12 executable (bin/x64_dx12/witcher3.exe) with AVX and native VC++ runtime overrides."),
        GamePresetInfo(appID: 1151340, title: "Fallout 76", subtitle: "Creation Engine • 64-bit DirectX 11 Online", recommendedSummary: "Rosetta 2 + DXMT (DX11) + XAudio2 Fix", notes: "Uses DXMT for low-stutter DirectX 11 translation and native xaudio2_7 + vcruntime140 overrides so audio and Bethesda.net login work cleanly."),
        GamePresetInfo(appID: 3105440, title: "Heroes of Might and Magic: Olden Era", subtitle: "Unity 6 Engine • 64-bit DirectX 11 + Media Foundation Video", recommendedSummary: "Rosetta 2 + D3DMetal + Standard DPI + Internal APFS Prefix", notes: "Uses D3DMetal on Rosetta 2 so IDXGIResource::GetSharedHandle and D3D11Fence work for .mp4 intro/campaign videos, while purging exFAT ._* files and keeping Retina scaling off."),
        GamePresetInfo(appID: 1174180, title: "Red Dead Redemption 2", subtitle: "RAGE Engine • 64-bit DirectX 12 / Vulkan", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Enables Rosetta AVX instruction advertising and D3DMetal for RDR2.exe and Rockstar Games Launcher stability."),
        GamePresetInfo(appID: 1286830, title: "STAR WARS: The Old Republic", subtitle: "HeroEngine • 32-bit CEF Launcher -> 64-bit Retail Client", recommendedSummary: "Rosetta 2 (WoW64) + WineD3D + CEF Launcher Fix", notes: "Uses Rosetta 2 + WineD3D and appends --disable-gpu --disable-gpu-compositing to launcher.exe (libcef.dll) so the launcher window renders visibly without a cross-process D3D11 swapchain."),
        GamePresetInfo(appID: 323190, title: "Frostpunk", subtitle: "Liquid Engine • 64-bit DirectX 11", recommendedSummary: "FEX ARM64 / Rosetta + DXMT (DX11) + Msync", notes: "Uses DXMT for fast native Metal DirectX 11 rendering on Frostpunk.exe with vcruntime140 and d3dcompiler_47 overrides."),
        GamePresetInfo(appID: 38410, title: "Fallout 2", subtitle: "Fallout Engine (32-bit i386) • DirectDraw + High-Res Patch", recommendedSummary: "Rosetta 2 (32-bit) + ddraw=n,b (sfall / High-Res Patch)", notes: "Forces native ddraw.dll (ddraw=n,b) so Fallout 2's bundled High-Resolution Patch (f2_res / sfall) loads instead of Wine's builtin DirectDraw."),
        GamePresetInfo(appID: 1245620, title: "ELDEN RING", subtitle: "FromSoftware Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + Msync + AVX", notes: "Configures D3DMetal, native VC++ runtime overrides, and AVX support for Shadow of the Erdtree & base game."),
        GamePresetInfo(appID: 377160, title: "Fallout 4", subtitle: "Creation Engine • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 / FEX + DXMT (DX11) + XAudio2 Fix", notes: "Uses DXMT for high-FPS DirectX 11 rendering and xaudio2_7=n,b so dialogue audio never drops."),
        GamePresetInfo(appID: 489830, title: "The Elder Scrolls V: Skyrim Special Edition", subtitle: "Creation Engine • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 / FEX + DXMT (DX11) + XAudio2 Fix", notes: "Configures DXMT and xaudio2_7=n,b for Creation Engine audio and smooth frame pacing."),
        GamePresetInfo(appID: 1716740, title: "Starfield", subtitle: "Creation Engine 2 • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX + XAudio2", notes: "Requires Rosetta AVX advertising and D3DMetal for DirectX 12 Shader Model 6.6."),
        GamePresetInfo(appID: 374320, title: "DARK SOULS III", subtitle: "FromSoftware Engine • 64-bit DirectX 11", recommendedSummary: "FEX / Rosetta + DXMT (DX11) + Msync", notes: "Runs at locked 60 FPS under DXMT with native vcruntime140 and d3dcompiler_47 overrides."),
        GamePresetInfo(appID: 814380, title: "Sekiro: Shadows Die Twice", subtitle: "FromSoftware Engine • 64-bit DirectX 11", recommendedSummary: "FEX / Rosetta + DXMT (DX11) + Controller Hidraw Fix", notes: "Uses DXMT for ultra-low input latency DirectX 11 rendering and controller hidraw fix."),
        GamePresetInfo(appID: 1888160, title: "ARMORED CORE VI FIRES OF RUBICON", subtitle: "FromSoftware Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + Msync + AVX", notes: "Uses D3DMetal and Rosetta AVX for 64-bit DirectX 12 rendering."),
        GamePresetInfo(appID: 1363080, title: "Manor Lords", subtitle: "Unreal Engine 5 • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for Unreal Engine 5 DirectX 12 city-builder rendering."),
        GamePresetInfo(appID: 813780, title: "Age of Empires II: Definitive Edition", subtitle: "Genie Engine • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 + DXMT (DX11) + vcruntime140=n,b", notes: "Uses DXMT and native VC++ runtime overrides (vcruntime140=n,b;msvcp140=n,b) to prevent multiplayer desyncs."),
        GamePresetInfo(appID: 1466860, title: "Age of Empires IV", subtitle: "Essence Engine 5 • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Requires Rosetta AVX and D3DMetal for Essence Engine 5 DirectX 12 rendering."),
        GamePresetInfo(appID: 2215430, title: "Ghost of Tsushima DIRECTOR'S CUT", subtitle: "Sucker Punch / Nixxes Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Requires Rosetta AVX/F16C instruction advertising and D3DMetal."),
        GamePresetInfo(appID: 1593500, title: "God of War", subtitle: "Santa Monica Engine • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 + DXMT (DX11) + AVX", notes: "Uses DXMT and Rosetta AVX for high-framerate DirectX 11 rendering."),
        GamePresetInfo(appID: 2322010, title: "God of War Ragnarök", subtitle: "Santa Monica Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for DirectX 12 Shader Model 6.6."),
        GamePresetInfo(appID: 1151640, title: "Horizon Zero Dawn Complete Edition", subtitle: "Decima Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for Decima Engine DirectX 12 rendering."),
        GamePresetInfo(appID: 2420110, title: "Horizon Forbidden West Complete Edition", subtitle: "Decima Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Requires Rosetta AVX/F16C and D3DMetal for Decima Engine DirectX 12."),
        GamePresetInfo(appID: 1817070, title: "Marvel's Spider-Man Remastered", subtitle: "Insomniac / Nixxes Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for DirectX 12 asset streaming."),
        GamePresetInfo(appID: 1817190, title: "Marvel's Spider-Man: Miles Morales", subtitle: "Insomniac / Nixxes Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for DirectX 12 rendering."),
        GamePresetInfo(appID: 1888930, title: "The Last of Us Part I", subtitle: "Naughty Dog Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for DirectX 12 shader compilation."),
        GamePresetInfo(appID: 379430, title: "Kingdom Come: Deliverance", subtitle: "CryEngine • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 + DXMT (DX11) + AVX", notes: "Uses DXMT and AVX for CryEngine DirectX 11 performance."),
        GamePresetInfo(appID: 1771300, title: "Kingdom Come: Deliverance II", subtitle: "CryEngine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for DirectX 12 rendering."),
        GamePresetInfo(appID: 582010, title: "Monster Hunter: World", subtitle: "MT Framework • 64-bit DirectX 11 / 12", recommendedSummary: "Rosetta 2 + DXMT (DX11) + Msync", notes: "Uses DXMT for DirectX 11 stability and low shader compilation stutter."),
        GamePresetInfo(appID: 1446780, title: "MONSTER HUNTER RISE", subtitle: "RE Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for RE Engine DirectX 12."),
        GamePresetInfo(appID: 2246340, title: "Monster Hunter Wilds", subtitle: "RE Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for RE Engine DirectX 12."),
        GamePresetInfo(appID: 2344520, title: "Diablo IV", subtitle: "Blizzard Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for DirectX 12 rendering."),
        GamePresetInfo(appID: 899770, title: "Last Epoch", subtitle: "Unity Engine • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 + DXMT (DX11) + Msync", notes: "Uses DXMT for fast DirectX 11 action-RPG rendering."),
        GamePresetInfo(appID: 2694490, title: "Path of Exile 2", subtitle: "Grinding Gear Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for DirectX 12 rendering."),
        GamePresetInfo(appID: 2358720, title: "Black Myth: Wukong", subtitle: "Unreal Engine 5 • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for Unreal Engine 5 DirectX 12."),
        GamePresetInfo(appID: 2054970, title: "Dragon's Dogma 2", subtitle: "RE Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for RE Engine DirectX 12."),
        GamePresetInfo(appID: 2050650, title: "Resident Evil 4 (2023)", subtitle: "RE Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for RE Engine DirectX 12."),
        GamePresetInfo(appID: 883710, title: "Resident Evil 2", subtitle: "RE Engine • 64-bit DirectX 11 / 12", recommendedSummary: "Rosetta 2 + DXMT (DX11) + AVX", notes: "Uses DXMT and Rosetta AVX for smooth RE Engine rendering."),
        GamePresetInfo(appID: 1196590, title: "Resident Evil Village", subtitle: "RE Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for DirectX 12 rendering."),
        GamePresetInfo(appID: 271590, title: "Grand Theft Auto V", subtitle: "RAGE Engine • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 + DXMT (DX11) + AVX", notes: "Uses DXMT and Rosetta AVX for RAGE Engine DirectX 11 and Rockstar Launcher."),
        GamePresetInfo(appID: 782330, title: "DOOM Eternal", subtitle: "idTech 7 • 64-bit Vulkan", recommendedSummary: "Rosetta 2 + DXVK (Vulkan) + AVX", notes: "Uses Vulkan / MoltenVK with Rosetta AVX for idTech 7."),
        GamePresetInfo(appID: 379720, title: "DOOM (2016)", subtitle: "idTech 6 • 64-bit Vulkan", recommendedSummary: "Rosetta 2 + DXVK (Vulkan) + AVX", notes: "Uses Vulkan / MoltenVK with Rosetta AVX for idTech 6."),
        GamePresetInfo(appID: 1687950, title: "Persona 5 Royal", subtitle: "Atlus Engine • 64-bit DirectX 11", recommendedSummary: "FEX / Rosetta + DXMT (DX11) + Msync", notes: "Uses DXMT and Msync for locked 60/120 FPS DirectX 11 rendering."),
        GamePresetInfo(appID: 2161700, title: "Persona 3 Reload", subtitle: "Unreal Engine 4 • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for Unreal Engine 4 DirectX 12."),
        GamePresetInfo(appID: 2679460, title: "Metaphor: ReFantazio", subtitle: "Atlus Engine • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 + DXMT (DX11) + AVX", notes: "Uses DXMT and Rosetta AVX for fast DirectX 11 rendering."),
        GamePresetInfo(appID: 1235140, title: "Yakuza: Like a Dragon", subtitle: "Dragon Engine • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 + DXMT (DX11) + AVX", notes: "Uses DXMT and Rosetta AVX for Dragon Engine DirectX 11."),
        GamePresetInfo(appID: 2072450, title: "Like a Dragon: Infinite Wealth", subtitle: "Dragon Engine • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for Dragon Engine DirectX 12."),
        GamePresetInfo(appID: 524220, title: "NieR:Automata", subtitle: "PlatinumEngine • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 + DXMT (DX11) + Msync", notes: "Uses DXMT and Msync for smooth 60 FPS DirectX 11 rendering."),
        GamePresetInfo(appID: 1172380, title: "STAR WARS Jedi: Fallen Order", subtitle: "Unreal Engine 4 • 64-bit DirectX 11", recommendedSummary: "Rosetta 2 + DXMT (DX11) + AVX", notes: "Uses DXMT and Rosetta AVX for Unreal Engine 4 DirectX 11."),
        GamePresetInfo(appID: 1774580, title: "STAR WARS Jedi: Survivor", subtitle: "Unreal Engine 4 • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for DirectX 12 rendering."),
        GamePresetInfo(appID: 553850, title: "HELLDIVERS 2", subtitle: "Autodesk Stingray • 64-bit DirectX 12", recommendedSummary: "Rosetta 2 + D3DMetal (DX12) + AVX", notes: "Uses D3DMetal and Rosetta AVX for DirectX 12 rendering.")
    ]

    private static let dx12RosettaRule: @Sendable (inout GameProfile) -> Void = { profile in
        profile.translator = .rosetta
        profile.graphics = .d3dMetal
        profile.advertiseAVX = true
        profile.sync = .msync
        profile.dllOverrides["vcruntime140"] = "n,b"
        profile.dllOverrides["vcruntime140_1"] = "n,b"
        profile.dllOverrides["msvcp140"] = "n,b"
        profile.dllOverrides["d3dcompiler_47"] = "n,b"
    }

    private static let dx11DxmtRule: @Sendable (inout GameProfile) -> Void = { profile in
        profile.graphics = .dxmt
        profile.advertiseAVX = true
        profile.sync = .msync
        profile.dllOverrides["vcruntime140"] = "n,b"
        profile.dllOverrides["vcruntime140_1"] = "n,b"
        profile.dllOverrides["msvcp140"] = "n,b"
        profile.dllOverrides["d3dcompiler_47"] = "n,b"
    }

    public static let knownQuirks: [UInt32: (title: String, apply: @Sendable (inout GameProfile) -> Void)] = [
        292030: ("The Witcher 3: Wild Hunt — Remastered", { profile in
            if profile.translator == .rosetta { profile.graphics = .d3dMetal }
            profile.advertiseAVX = true
            profile.sync = .msync
            profile.dllOverrides["vcruntime140"] = "n,b"
            profile.dllOverrides["vcruntime140_1"] = "n,b"
            profile.dllOverrides["msvcp140"] = "n,b"
            profile.dllOverrides["d3dcompiler_47"] = "n,b"
        }),
        1151340: ("Fallout 76", { profile in
            profile.graphics = .dxmt
            profile.advertiseAVX = true
            profile.sync = .msync
            profile.dllOverrides["xaudio2_7"] = "n,b"
            profile.dllOverrides["vcruntime140"] = "n,b"
            profile.dllOverrides["vcruntime140_1"] = "n,b"
            profile.dllOverrides["msvcp140"] = "n,b"
            profile.dllOverrides["d3dcompiler_47"] = "n,b"
        }),
        3105440: ("Heroes of Might and Magic: Olden Era", { profile in
            profile.translator = .rosetta
            profile.graphics = .d3dMetal
            profile.retinaMode = false
            profile.sync = .msync
            profile.dllOverrides["vcruntime140"] = "n,b"
            profile.dllOverrides["vcruntime140_1"] = "n,b"
            profile.dllOverrides["d3dcompiler_47"] = "n,b"
        }),
        1174180: ("Red Dead Redemption 2", { profile in
            profile.translator = .rosetta
            profile.graphics = .d3dMetal
            profile.advertiseAVX = true
            profile.dllOverrides["vulkan-1"] = "n,b"
            profile.dllOverrides["vcruntime140"] = "n,b"
            profile.dllOverrides["d3dcompiler_47"] = "n,b"
        }),
        1286830: ("STAR WARS: The Old Republic", { profile in
            profile.translator = .rosetta
            profile.graphics = .wineD3D
            profile.sync = .msync
            profile.dllOverrides["vulkan-1"] = "b"
            profile.dllOverrides["vcruntime140"] = "n,b"
            profile.dllOverrides["msvcp140"] = "n,b"
            profile.dllOverrides["d3dcompiler_47"] = "n,b"
        }),
        323190: ("Frostpunk", dx11DxmtRule),
        38410: ("Fallout 2", { profile in
            profile.translator = .rosetta
            profile.graphics = .wineD3D
            profile.sync = .msync
            profile.dllOverrides["ddraw"] = "n,b"
            profile.dllOverrides["dinput"] = "n,b"
            profile.dllOverrides["dinput8"] = "n,b"
        }),
        1091500: ("Cyberpunk 2077", dx12RosettaRule),
        1245620: ("ELDEN RING", dx12RosettaRule),
        377160: ("Fallout 4", { profile in
            dx11DxmtRule(&profile)
            profile.dllOverrides["xaudio2_7"] = "n,b"
        }),
        489830: ("The Elder Scrolls V: Skyrim Special Edition", { profile in
            dx11DxmtRule(&profile)
            profile.dllOverrides["xaudio2_7"] = "n,b"
        }),
        1716740: ("Starfield", { profile in
            dx12RosettaRule(&profile)
            profile.dllOverrides["xaudio2_9"] = "n,b"
        }),
        374320: ("DARK SOULS III", dx11DxmtRule),
        814380: ("Sekiro: Shadows Die Twice", { profile in
            dx11DxmtRule(&profile)
            profile.disableHidraw = true
        }),
        1888160: ("ARMORED CORE VI FIRES OF RUBICON", dx12RosettaRule),
        1363080: ("Manor Lords", dx12RosettaRule),
        813780: ("Age of Empires II: Definitive Edition", dx11DxmtRule),
        1466860: ("Age of Empires IV", dx12RosettaRule),
        2215430: ("Ghost of Tsushima DIRECTOR'S CUT", dx12RosettaRule),
        1593500: ("God of War", dx11DxmtRule),
        2322010: ("God of War Ragnarök", dx12RosettaRule),
        1151640: ("Horizon Zero Dawn Complete Edition", dx12RosettaRule),
        2420110: ("Horizon Forbidden West Complete Edition", dx12RosettaRule),
        1817070: ("Marvel's Spider-Man Remastered", dx12RosettaRule),
        1817190: ("Marvel's Spider-Man: Miles Morales", dx12RosettaRule),
        1888930: ("The Last of Us Part I", dx12RosettaRule),
        379430: ("Kingdom Come: Deliverance", dx11DxmtRule),
        1771300: ("Kingdom Come: Deliverance II", dx12RosettaRule),
        582010: ("Monster Hunter: World", dx11DxmtRule),
        1446780: ("MONSTER HUNTER RISE", dx12RosettaRule),
        2246340: ("Monster Hunter Wilds", dx12RosettaRule),
        2344520: ("Diablo IV", dx12RosettaRule),
        899770: ("Last Epoch", dx11DxmtRule),
        2694490: ("Path of Exile 2", dx12RosettaRule),
        2358720: ("Black Myth: Wukong", dx12RosettaRule),
        2054970: ("Dragon's Dogma 2", dx12RosettaRule),
        2050650: ("Resident Evil 4 (2023)", dx12RosettaRule),
        883710: ("Resident Evil 2", dx11DxmtRule),
        1196590: ("Resident Evil Village", dx12RosettaRule),
        271590: ("Grand Theft Auto V", dx11DxmtRule),
        782330: ("DOOM Eternal", { profile in
            profile.translator = .rosetta
            profile.graphics = .dxvk
            profile.advertiseAVX = true
            profile.sync = .msync
            profile.dllOverrides["vulkan-1"] = "n,b"
        }),
        379720: ("DOOM (2016)", { profile in
            profile.translator = .rosetta
            profile.graphics = .dxvk
            profile.advertiseAVX = true
            profile.sync = .msync
            profile.dllOverrides["vulkan-1"] = "n,b"
        }),
        1687950: ("Persona 5 Royal", dx11DxmtRule),
        2161700: ("Persona 3 Reload", dx12RosettaRule),
        2679460: ("Metaphor: ReFantazio", dx11DxmtRule),
        1235140: ("Yakuza: Like a Dragon", dx11DxmtRule),
        2072450: ("Like a Dragon: Infinite Wealth", dx12RosettaRule),
        524220: ("NieR:Automata", dx11DxmtRule),
        1172380: ("STAR WARS Jedi: Fallen Order", dx11DxmtRule),
        1774580: ("STAR WARS Jedi: Survivor", dx12RosettaRule),
        553850: ("HELLDIVERS 2", dx12RosettaRule)
    ]

    public static var customCatalogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Positron/presets-catalog.json")
    }

    /// Loads user/community presets from ~/Library/Application Support/Positron/presets-catalog.json,
    /// seeding the file with the built-in 50-game catalog on first use so users can add new games easily.
    public static func loadCustomCatalog(at url: URL = customCatalogURL) -> [PresetCatalogEntry] {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([PresetCatalogEntry].self, from: data),
           decoded.count >= catalog.count {
            return decoded
        }
        let seeded = catalog.map { item in
            PresetCatalogEntry(
                info: item,
                recommendedProfile: builtInDefaultProfile(forAppID: item.appID, preferredTranslator: .rosetta)
            )
        }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(seeded) {
            try? data.write(to: url, options: .atomic)
        }
        return seeded
    }

    /// Appends or updates a game preset entry inside ~/Library/Application Support/Positron/presets-catalog.json.
    public static func saveToCustomCatalog(_ entry: PresetCatalogEntry, at url: URL = customCatalogURL) throws {
        var entries = loadCustomCatalog(at: url)
        if let idx = entries.firstIndex(where: { $0.info.appID == entry.info.appID }) {
            entries[idx] = entry
        } else {
            entries.append(entry)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try data.write(to: url, options: .atomic)
    }

    public static func presetInfo(forAppID appID: UInt32) -> GamePresetInfo? {
        if let builtIn = catalog.first(where: { $0.appID == appID }) {
            return builtIn
        }
        return loadCustomCatalog().first(where: { $0.info.appID == appID })?.info
    }

    public static func builtInDefaultProfile(forAppID appID: UInt32, preferredTranslator: CPUTranslator = .rosetta) -> GameProfile {
        let forceRosettaIDs: Set<UInt32> = [
            292030, 3105440, 1091500, 1174180, 1245620, 1286830, 38410, 412020,
            1716740, 1888160, 1363080, 1466860, 2215430, 2322010, 1151640, 2420110,
            1817070, 1817190, 1888930, 1771300, 1446780, 2246340, 2344520, 2694490,
            2358720, 2054970, 2050650, 1196590, 782330, 379720, 2161700, 2072450,
            1774580, 553850
        ]
        let chosenTranslator: CPUTranslator = forceRosettaIDs.contains(appID) ? .rosetta : preferredTranslator
        var profile = GameProfile(
            appID: appID,
            translator: chosenTranslator,
            graphics: chosenTranslator == .fex ? .dxmt : .d3dMetal
        )
        if let quirk = knownQuirks[appID] {
            quirk.apply(&profile)
        }
        return profile.sanitized()
    }

    public static func defaultProfile(forAppID appID: UInt32, preferredTranslator: CPUTranslator = .rosetta) -> GameProfile {
        if knownQuirks[appID] != nil || catalog.contains(where: { $0.appID == appID }) {
            return builtInDefaultProfile(forAppID: appID, preferredTranslator: preferredTranslator)
        }
        if let custom = loadCustomCatalog().first(where: { $0.info.appID == appID }) {
            return custom.recommendedProfile.sanitized()
        }
        return builtInDefaultProfile(forAppID: appID, preferredTranslator: preferredTranslator)
    }
}

public final class GameProfileStore: Sendable {
    public let storageDirectory: URL

    public init(storageDirectory: URL) {
        self.storageDirectory = storageDirectory
    }

    public func profileURL(forAppID appID: UInt32) -> URL {
        storageDirectory.appending(path: "profiles/\(appID).json")
    }

    public func envURL(forAppID appID: UInt32) -> URL {
        storageDirectory.appending(path: "profiles/\(appID).env")
    }

    public func hasSavedProfile(forAppID appID: UInt32) -> Bool {
        FileManager.default.fileExists(atPath: envURL(forAppID: appID).path(percentEncoded: false))
            || FileManager.default.fileExists(atPath: profileURL(forAppID: appID).path(percentEncoded: false))
    }

    public func removeProfile(forAppID appID: UInt32) {
        try? FileManager.default.removeItem(at: profileURL(forAppID: appID))
        try? FileManager.default.removeItem(at: envURL(forAppID: appID))
    }

    public func save(_ profile: GameProfile) throws {
        let url = profileURL(forAppID: profile.appID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile.sanitized())
        try data.write(to: url, options: .atomic)
        let envURL = storageDirectory.appending(path: "profiles/\(profile.appID).env")
        try Data(profile.buildPositronEnvFileContent().utf8).write(to: envURL, options: .atomic)
    }

    public func load(forAppID appID: UInt32, fallbackTranslator: CPUTranslator = .rosetta) -> GameProfile {
        let url = profileURL(forAppID: appID)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(GameProfile.self, from: data) {
            return decoded.sanitized()
        }
        return GameQuirksDatabase.defaultProfile(forAppID: appID, preferredTranslator: fallbackTranslator)
    }
}
