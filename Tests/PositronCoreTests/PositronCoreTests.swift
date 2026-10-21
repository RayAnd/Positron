// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import PositronCore

@Suite("PositronCore Universal Architecture Tests")
struct PositronCoreTests {

    @Test("GameProfile sanitizes FEX-incompatible settings and applies AppID quirks")
    func gameProfileSanitizationAndQuirks() {
        let rosettaProfile = GameQuirksDatabase.defaultProfile(forAppID: 1091500, preferredTranslator: .rosetta)
        #expect(rosettaProfile.graphics == .d3dMetal)
        #expect(rosettaProfile.advertiseAVX == true)
        #expect(rosettaProfile.dllOverrides["vcruntime140"] == "n,b")

        var fexProfile = rosettaProfile
        fexProfile.translator = .fex
        fexProfile.extraEnvironment["ROSETTA_ADVERTISE_AVX"] = "1"
        fexProfile.extraEnvironment["D3DM_ENABLE_METALFX"] = "1"
        let sanitized = fexProfile.sanitized()
        #expect(sanitized.graphics == .dxmt)
        #expect(sanitized.advertiseAVX == false)
        #expect(sanitized.extraEnvironment["ROSETTA_ADVERTISE_AVX"] == nil)
        #expect(sanitized.extraEnvironment["D3DM_ENABLE_METALFX"] == nil)

        let env = sanitized.buildLaunchEnvironment(
            runnerRoot: URL(filePath: "/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver"),
            prefixRoot: URL(filePath: "/tmp/compatdata/1091500")
        )
        #expect(env["CX_GRAPHICS_BACKEND"] == "dxmt")
        #expect(env["FEX_X87REDUCEDPRECISION"] == "1")
        #expect(env["ROSETTA_ADVERTISE_AVX"] == nil)
        #expect(env["WINEDLLOVERRIDES"]?.contains("lsteamclient=b") == true)
    }

    @Test("Curated presets for Witcher 3 Remaster, Fallout 76, and Heroes of Olden Era configure optimal settings")
    func curatedGameProfiles() {
        // 1. The Witcher 3: Wild Hunt (Next-Gen Remaster) - AppID 292030
        let witcher3 = GameQuirksDatabase.defaultProfile(forAppID: 292030, preferredTranslator: .fex)
        #expect(witcher3.translator == .rosetta)
        #expect(witcher3.graphics == .d3dMetal)
        #expect(witcher3.advertiseAVX == true)
        #expect(witcher3.dllOverrides["d3dcompiler_47"] == "n,b")

        // 2. Fallout 76 - AppID 1151340
        let fallout76 = GameQuirksDatabase.defaultProfile(forAppID: 1151340, preferredTranslator: .rosetta)
        #expect(fallout76.graphics == .dxmt)
        #expect(fallout76.dllOverrides["xaudio2_7"] == "n,b")
        #expect(fallout76.dllOverrides["vcruntime140"] == "n,b")

        // 3. Heroes of Might and Magic: Olden Era - AppID 3105440 (D3DMetal for MediaFoundation .mp4 shared texture handles)
        let oldenEra = GameQuirksDatabase.defaultProfile(forAppID: 3105440, preferredTranslator: .fex)
        #expect(oldenEra.translator == .rosetta)
        #expect(oldenEra.graphics == .d3dMetal)
        #expect(oldenEra.retinaMode == false)
        #expect(oldenEra.dllOverrides["d3dcompiler_47"] == "n,b")

        // 4. Fallout 2 - AppID 38410 (32-bit with sfall/f2_res ddraw=n,b)
        let fallout2 = GameQuirksDatabase.defaultProfile(forAppID: 38410, preferredTranslator: .fex)
        #expect(fallout2.translator == .rosetta)
        #expect(fallout2.dllOverrides["ddraw"] == "n,b")

        // 5. Frostpunk - AppID 323190 (64-bit DX11 -> DXMT)
        let frostpunk = GameQuirksDatabase.defaultProfile(forAppID: 323190, preferredTranslator: .fex)
        #expect(frostpunk.graphics == .dxmt)

        // 6. STAR WARS: The Old Republic - AppID 1286830 (32-bit launcher -> 64-bit client -> Rosetta + WineD3D)
        let swtor = GameQuirksDatabase.defaultProfile(forAppID: 1286830, preferredTranslator: .fex)
        #expect(swtor.translator == .rosetta)
        #expect(swtor.graphics == .wineD3D)

        // 7. Native macOS games (Cyberpunk 2077 = 1091500, Metro Exodus = 412020, BG3 = 1086940)
        //    are excluded from the Positron Windows compatibility catalog so they always run natively.
        #expect(GameQuirksDatabase.knownNativeMacAppIDs.contains(1091500))
        #expect(GameQuirksDatabase.knownNativeMacAppIDs.contains(412020))
        #expect(GameQuirksDatabase.presetInfo(forAppID: 1091500) == nil)
        #expect(GameQuirksDatabase.presetInfo(forAppID: 412020) == nil)
    }

    @Test("PrefixManager seamlessly auto-migrates between Rosetta and FEX preserving saves")
    func prefixSeamlessMigration() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "positron-swift-prefix-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let stamp1 = PrefixStamp(runnerID: "crossover-26.3", architecture: "x86_64", graphics: .d3dMetal)
        let initRes = try PrefixManager.reconcileAndMigrate(compatDataURL: tmp, targetStamp: stamp1)
        #expect(initRes.outcome == .initialized)

        let saveFile = tmp.appending(path: "pfx/drive_c/users/steamuser/Documents/save.dat")
        try Data("SAVE_DATA_V1".utf8).write(to: saveFile)

        let stamp2 = PrefixStamp(runnerID: "crossover-preview-27.0", architecture: "arm64", graphics: .dxmt)
        let migRes = try PrefixManager.reconcileAndMigrate(compatDataURL: tmp, targetStamp: stamp2)
        #expect(migRes.outcome == .architectureTransitioned)
        #expect(migRes.snapshotURL != nil)

        let activeSave = try String(contentsOf: saveFile, encoding: .utf8)
        #expect(activeSave == "SAVE_DATA_V1")
        if let snap = migRes.snapshotURL {
            let snapSave = try String(contentsOf: snap.appending(path: "Documents/save.dat"), encoding: .utf8)
            #expect(snapSave == "SAVE_DATA_V1")
        }
    }

    @Test("SteamIntegration generates AutoCloud-compatible VDF manifests and manages steam.cfg")
    func steamCompatToolRegistrationAndUpdateBlock() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "positron-compattools-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let mockRunner = DiscoveredRunner(
            id: "crossover-preview-27.0",
            displayName: "CrossOver Preview 20261006",
            kind: .crossOverPreview,
            bundleVersion: "27.0.0.41069",
            shortVersion: "20261006",
            rootURL: URL(filePath: "/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver"),
            supportedTranslators: [.fex, .rosetta],
            availableGraphicsBackends: [.d3dMetal, .dxmt, .dxvk, .wineD3D],
            ntdllInspections: []
        )

        let tools = try SteamIntegration.registerCompatibilityTools(for: [mockRunner], in: tmp)
        #expect(tools.count == 2)
        #expect(tools.allSatisfy { $0.toolName.hasPrefix("positron-proton-") })
        #expect(tools.allSatisfy { $0.displayName.hasPrefix("Positron -") })

        let cfgURL = tmp.appending(path: "steam.cfg")
        #expect(SteamIntegration.isSteamUpdateBlocked(cfgURL: cfgURL) == false)
        try SteamIntegration.setSteamUpdateBlocked(true, cfgURL: cfgURL)
        #expect(SteamIntegration.isSteamUpdateBlocked(cfgURL: cfgURL) == true)
        try SteamIntegration.setSteamUpdateBlocked(false, cfgURL: cfgURL)
        #expect(SteamIntegration.isSteamUpdateBlocked(cfgURL: cfgURL) == false)
    }

    @Test("SteamLibraryDiscovery parses libraryfolders.vdf and resolves external drive prefixes")
    func externalSteamLibraryDiscovery() throws {
        let sampleVDF = """
        "libraryfolders"
        {
            "0"
            {
                "path"        "/Users/test/Library/Application Support/Steam"
            }
            "1"
            {
                "path"        "/Volumes/ExternalGamesSSD/SteamLibrary"
            }
        }
        """
        let parsed = SteamLibraryDiscovery.parseLibraryFoldersVDF(sampleVDF)
        #expect(parsed.count == 2)
        #expect(parsed.contains("/Volumes/ExternalGamesSSD/SteamLibrary"))

        // Create a mock external Steam library with an appmanifest_1151340.acf and compatdata prefix
        let tmpExt = FileManager.default.temporaryDirectory.appending(path: "positron-extlib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpExt) }
        let steamapps = tmpExt.appending(path: "steamapps")
        let pfx = steamapps.appending(path: "compatdata/1151340/pfx")
        try FileManager.default.createDirectory(at: pfx, withIntermediateDirectories: true)
        let acf = """
        "AppState"
        {
            "appid"        "1151340"
            "name"         "Fallout 76"
            "installdir"   "Fallout76"
        }
        """
        try Data(acf.utf8).write(to: steamapps.appending(path: "appmanifest_1151340.acf"))

        let libs = SteamLibraryDiscovery.discoverLibraries(steamRoot: tmpExt, scanMountedVolumes: false)
        #expect(!libs.isEmpty)
        #expect(libs[0].installedGamesCount == 1)

        let prefixes = PrefixManager.discoverSteamPrefixes(libraries: libs)
        #expect(prefixes.count == 1)
        #expect(prefixes[0].appID == "1151340")
        #expect(prefixes[0].gameTitle == "Fallout 76")
    }

    @Test("SteamIntegration updates CompatToolMapping in config.vdf and writes .env profile")
    func applyProfileToSteamConfigVDF() throws {
        let vdf = """
        "InstallConfigStore"
        {
        \t"Software"
        \t{
        \t\t"Valve"
        \t\t{
        \t\t\t"Steam"
        \t\t\t{
        \t\t\t\t"CompatToolMapping"
        \t\t\t\t{
        \t\t\t\t\t"1151340"
        \t\t\t\t\t{
        \t\t\t\t\t\t"name"\t\t"notproton-26.3"
        \t\t\t\t\t\t"config"\t\t""
        \t\t\t\t\t\t"priority"\t\t"250"
        \t\t\t\t\t}
        \t\t\t\t}
        \t\t\t}
        \t\t}
        \t}
        }
        """
        let updated = SteamIntegration.updateCompatToolMappingInVDFText(
            vdf,
            appID: 1151340,
            toolName: "positron-proton-crossover-preview-27.0.0.41069-fex"
        )
        #expect(updated.contains("positron-proton-crossover-preview-27.0.0.41069-fex"))
        #expect(!updated.contains("notproton-26.3"))

        let inserted = SteamIntegration.updateCompatToolMappingInVDFText(
            updated,
            appID: 3105440,
            toolName: "positron-proton-crossover-preview-27.0.0.41069-fex"
        )
        #expect(inserted.contains("\"3105440\""))

        let fallout76 = GameQuirksDatabase.defaultProfile(forAppID: 1151340, preferredTranslator: .rosetta)
        let envContent = fallout76.buildPositronEnvFileContent()
        #expect(envContent.contains("export CX_GRAPHICS_BACKEND=\"dxmt\""))
        #expect(envContent.contains("xaudio2_7=n,b"))
    }

    @Test("PrefixManager resolves installer arguments and rebuilds prefixes while preserving steamuser saves")
    func prefixToolsAndSavePreservingRebuild() throws {
        let exeArgs = try PrefixManager.arguments(forExecutable: URL(filePath: "/tmp/vc_redist.x64.exe"))
        #expect(exeArgs == ["/tmp/vc_redist.x64.exe"])

        let msiArgs = try PrefixManager.arguments(forExecutable: URL(filePath: "/tmp/physx.msi"))
        #expect(msiArgs == ["msiexec", "/i", "/tmp/physx.msi"])

        let batArgs = try PrefixManager.arguments(forExecutable: URL(filePath: "/tmp/setup.bat"))
        #expect(batArgs == ["cmd.exe", "/c", "/tmp/setup.bat"])

        let tmpCompat = FileManager.default.temporaryDirectory.appending(path: "positron-rebuild-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpCompat) }
        try PrefixManager.ensureSteamUserLayout(in: tmpCompat)
        let saveFile = tmpCompat.appending(path: "pfx/drive_c/users/steamuser/Saved Games/fallout76.sav")
        try Data("VAULT_76_SAVE".utf8).write(to: saveFile)

        let pfx = DiscoveredPrefix(
            appID: "1151340",
            gameTitle: "Fallout 76",
            compatDataURL: tmpCompat,
            libraryLabel: "External Drive (Game Drive)",
            isExternalDrive: true,
            usesShadowPrefix: false,
            stamp: nil,
            detectedPEArch: "x86_64 (Rosetta)",
            recordedBuild: "26.3.0.39832",
            snapshotCount: 0,
            hasLaunchLog: false
        )
        let backupURL = try PrefixManager.rebuildPreservingSaves(pfx, runners: [])
        #expect(FileManager.default.fileExists(atPath: backupURL.path(percentEncoded: false)))
        let preserved = try String(contentsOf: saveFile, encoding: .utf8)
        #expect(preserved == "VAULT_76_SAVE")
    }

    @Test("RunnerDiscovery dynamically inspects installed runners without SHA allowlists")
    func universalRunnerDiscovery() {
        let discovered = RunnerDiscovery.discoverAll()
        for runner in discovered {
            #expect(!runner.supportedTranslators.isEmpty)
            for ntdll in runner.ntdllInspections {
                #expect(ntdll.isReadyForDynamicBridge == true)
            }
        }
    }
}