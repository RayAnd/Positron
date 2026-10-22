// SPDX-License-Identifier: MIT
import Foundation

/// How a game renders, which decides its default Positron pipeline.
public enum PresetRenderPath: String, Sendable, CaseIterable {
    case dx12
    case dx11
    case dx9
    case vulkan

    public var apiLabel: String {
        switch self {
        case .dx12: return "DirectX 12"
        case .dx11: return "DirectX 11"
        case .dx9: return "DirectX 9"
        case .vulkan: return "Vulkan"
        }
    }

    public var summary: String {
        switch self {
        case .dx12: return "Rosetta 2 + D3DMetal (DX12) + AVX + Msync"
        case .dx11: return "Rosetta 2 + DXMT (DX11) + AVX + Msync"
        case .dx9: return "Rosetta 2 + WineD3D (DX9) + Msync"
        case .vulkan: return "Rosetta 2 + Vulkan via MoltenVK + AVX + Msync"
        }
    }

    public var notes: String {
        switch self {
        case .dx12:
            return "Engine-based preset, not tested on this exact game: D3DMetal for DirectX 12 with Rosetta AVX. If it does not start, try DXMT."
        case .dx11:
            return "Engine-based preset, not tested on this exact game: DXMT for DirectX 11 on Rosetta 2. If it does not start, try D3DMetal."
        case .dx9:
            return "Engine-based preset, not tested on this exact game: WineD3D for DirectX 9. DXVK can be faster on some titles."
        case .vulkan:
            return "Engine-based preset, not tested on this exact game: native Vulkan through MoltenVK on Rosetta 2."
        }
    }

    public func apply(to profile: inout GameProfile) {
        profile.translator = .rosetta
        profile.sync = .msync
        switch self {
        case .dx12:
            profile.graphics = .d3dMetal
            profile.advertiseAVX = true
        case .dx11:
            profile.graphics = .dxmt
            profile.advertiseAVX = true
        case .dx9:
            profile.graphics = .wineD3D
        case .vulkan:
            profile.graphics = .dxvk
            profile.advertiseAVX = true
        }
    }
}

/// A popular Windows-only title whose preset is derived from its engine and graphics API.
public struct EnginePresetSpec: Sendable, Equatable {
    public let appID: UInt32
    public let title: String
    public let engine: String
    public let path: PresetRenderPath
    public let note: String?

    public var info: GamePresetInfo {
        GamePresetInfo(
            appID: appID,
            title: title,
            subtitle: "\(engine) • \(path.apiLabel)",
            recommendedSummary: path.summary,
            notes: note.map { "\(path.notes) \($0)" } ?? path.notes
        )
    }
}

extension GameQuirksDatabase {
    private static func spec(
        _ appID: UInt32, _ title: String, _ engine: String, _ path: PresetRenderPath, _ note: String? = nil
    ) -> EnginePresetSpec {
        EnginePresetSpec(appID: appID, title: title, engine: engine, path: path, note: note)
    }

    /// Popular Windows-only Steam titles without a native macOS build, excluding games whose
    /// kernel or Easy Anti-Cheat blocks Wine.
    public static let enginePresetSpecs: [EnginePresetSpec] = [
        spec(990080, "Hogwarts Legacy", "Unreal Engine 4", .dx12),
        spec(1623730, "Palworld", "Unreal Engine 5", .dx12),
        spec(962130, "Grounded", "Unreal Engine 4", .dx12),
        spec(934700, "Dead Island 2", "Unreal Engine 4", .dx12),
        spec(534380, "Dying Light 2 Stay Human", "C-Engine", .dx12),
        spec(1659420, "UNCHARTED: Legacy of Thieves Collection", "Naughty Dog Engine", .dx12),
        spec(1895880, "Ratchet & Clank: Rift Apart", "Insomniac Engine", .dx12),
        spec(1817230, "Hi-Fi RUSH", "Unreal Engine 4", .dx12),
        spec(1448440, "Wo Long: Fallen Dynasty", "Koei Tecmo Engine", .dx12),
        spec(1293830, "Forza Horizon 4", "ForzaTech", .dx12),
        spec(1551360, "Forza Horizon 5", "ForzaTech", .dx12),
        spec(526870, "Satisfactory", "Unreal Engine 5", .dx12),
        spec(1250410, "Microsoft Flight Simulator (2020)", "Asobo Engine", .dx12),
        spec(1182900, "A Plague Tale: Requiem", "Asobo Engine", .dx12),
        spec(870780, "Control Ultimate Edition", "Northlight", .dx12),
        spec(1850570, "DEATH STRANDING DIRECTOR'S CUT", "Decima", .dx12),
        spec(1252330, "DEATHLOOP", "Void Engine", .dx12),
        spec(1778820, "TEKKEN 8", "Unreal Engine 5", .dx12),
        spec(1364780, "Street Fighter 6", "RE Engine", .dx12),
        spec(1029690, "Sniper Elite 5", "Asura", .dx12),
        spec(1627720, "Lies of P", "Unreal Engine 4", .dx12),
        spec(1462040, "FINAL FANTASY VII REMAKE INTERGRADE", "Unreal Engine 4", .dx12),
        spec(2909400, "FINAL FANTASY VII REBIRTH", "Unreal Engine 4", .dx12),
        spec(2515020, "FINAL FANTASY XVI", "Square Enix Engine", .dx12),
        spec(2124490, "SILENT HILL 2", "Unreal Engine 5", .dx12),
        spec(1971870, "Mortal Kombat 1", "Unreal Engine 4", .dx12),
        spec(1659040, "HITMAN World of Assassination", "Glacier 2", .dx12),
        spec(1286680, "Tiny Tina's Wonderlands", "Unreal Engine 4", .dx12),
        spec(1244460, "Jurassic World Evolution 2", "Cobra", .dx12),
        spec(2623190, "The Elder Scrolls IV: Oblivion Remastered", "Unreal Engine 5", .dx12),
        spec(730, "Counter-Strike 2", "Source 2", .dx11, "VAC matchmaking under Wine is at your own risk."),
        spec(1966720, "Lethal Company", "Unity", .dx11),
        spec(1326470, "Sons of the Forest", "Unity", .dx11),
        spec(242760, "The Forest", "Unity", .dx11),
        spec(739630, "Phasmophobia", "Unity", .dx11),
        spec(1604030, "V Rising", "Unity", .dx11),
        spec(427410, "Abiotic Factor", "Unreal Engine 4", .dx11),
        spec(239140, "Dying Light", "C-Engine", .dx11),
        spec(1259420, "Days Gone", "Unreal Engine 4", .dx11),
        spec(2138710, "Sifu", "Unreal Engine 4", .dx11),
        spec(1325200, "Nioh 2 – The Complete Edition", "Koei Tecmo Engine", .dx11),
        spec(1328670, "Mass Effect Legendary Edition", "Unreal Engine 3", .dx11, "Needs the EA app, which installs on first launch."),
        spec(805550, "Assetto Corsa Competizione", "Unreal Engine 4", .dx11),
        spec(244210, "Assetto Corsa", "Kunos Engine", .dx11),
        spec(244850, "Space Engineers", "VRAGE", .dx11),
        spec(1142710, "Total War: WARHAMMER III", "Warscape", .dx11),
        spec(1158310, "Crusader Kings III", "Clausewitz", .dx11),
        spec(976730, "Halo: The Master Chief Collection", "Blam!", .dx11, "Choose to play without anti-cheat; Easy Anti-Cheat does not run under Wine."),
        spec(230410, "Warframe", "Evolution Engine", .dx11),
        spec(548430, "Deep Rock Galactic", "Unreal Engine 4", .dx11),
        spec(752590, "A Plague Tale: Innocence", "Asobo Engine", .dx11),
        spec(1139900, "Ghostrunner", "Unreal Engine 4", .dx11),
        spec(480490, "Prey", "CryEngine", .dx11),
        spec(403640, "Dishonored 2", "Void Engine", .dx11),
        spec(1237970, "Titanfall 2", "Source", .dx11, "Needs the EA app, which installs on first launch."),
        spec(1426210, "It Takes Two", "Unreal Engine 4", .dx11, "Needs the EA app, which installs on first launch."),
        spec(1113560, "NieR Replicant ver.1.22474487139...", "Toylogic Engine", .dx11),
        spec(1113000, "Persona 4 Golden", "Atlus Engine", .dx11),
        spec(1382330, "Persona 5 Strikers", "Koei Tecmo Engine", .dx11),
        spec(952060, "Resident Evil 3", "RE Engine", .dx11),
        spec(418370, "Resident Evil 7 Biohazard", "RE Engine", .dx11),
        spec(976310, "Mortal Kombat 11", "Unreal Engine 3", .dx11),
        spec(1366540, "Dyson Sphere Program", "Unity", .dx11),
        spec(949230, "Cities: Skylines II", "Unity", .dx11),
        spec(703080, "Planet Zoo", "Cobra", .dx11),
        spec(233860, "Kenshi", "OGRE", .dx11),
        spec(261550, "Mount & Blade II: Bannerlord", "TaleWorlds Engine", .dx11),
        spec(1030840, "Mafia: Definitive Edition", "Illusion Engine", .dx11),
        spec(1030830, "Mafia II: Definitive Edition", "Illusion Engine", .dx11),
        spec(1110910, "Mortal Shell", "Unreal Engine 4", .dx11),
        spec(440, "Team Fortress 2", "Source", .dx9),
        spec(620, "Portal 2", "Source", .dx9),
        spec(220, "Half-Life 2", "Source", .dx9),
        spec(362890, "Black Mesa", "Source", .dx9),
        spec(22380, "Fallout: New Vegas", "Gamebryo", .dx9),
        spec(22370, "Fallout 3: Game of the Year Edition", "Gamebryo", .dx9),
        spec(22330, "The Elder Scrolls IV: Oblivion GOTY", "Gamebryo", .dx9),
        spec(12210, "Grand Theft Auto IV: The Complete Edition", "RAGE", .dx9),
        spec(1203620, "Enshrouded", "Holistic Engine", .vulkan),
        spec(612880, "Wolfenstein II: The New Colossus", "idTech 6", .vulkan)
    ]
}
