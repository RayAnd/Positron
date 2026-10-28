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

    @Test("Curated presets for Witcher 3 Remaster, RDR2, Atomic Heart, Fallout 76, and Heroes of Olden Era configure optimal settings")
    func curatedGameProfiles() {
        // 1. The Witcher 3: Wild Hunt (Next-Gen Remaster) - AppID 292030
        let witcher3 = GameQuirksDatabase.defaultProfile(forAppID: 292030, preferredTranslator: .fex)
        #expect(witcher3.translator == .rosetta)
        #expect(witcher3.graphics == .d3dMetal)
        #expect(witcher3.advertiseAVX == true)
        #expect(witcher3.dllOverrides["winspool.drv"] == "d")
        #expect(witcher3.dllOverrides["dinput8"] == "n,b")
        #expect(witcher3.dllOverrides["amd_fidelityfx_loader_dx12"] == "n,b")
        #expect(witcher3.dllOverrides["d3dcompiler_47"] == "n,b")

        // 2. Red Dead Redemption 2 - AppID 1174180 (Anti-flicker: nvngx=d, MetalFX=0, NaN/Inf clamp, esync)
        let rdr2 = GameQuirksDatabase.defaultProfile(forAppID: 1174180, preferredTranslator: .fex)
        #expect(rdr2.translator == .rosetta)
        #expect(rdr2.graphics == .d3dMetal)
        #expect(rdr2.sync == .esync)
        #expect(rdr2.dllOverrides["nvngx"] == "d")
        #expect(rdr2.extraEnvironment["D3DM_ENABLE_METALFX"] == "0")
        #expect(rdr2.extraEnvironment["D3DM_SAMPLE_NAN_TO_ZERO"] == "1")
        #expect(rdr2.extraEnvironment["D3DM_FLUSH_POS_INF_TO_NAN"] == "1")

        // 3. Atomic Heart - AppID 668580 (Unreal Engine 4 DX12 + Rosetta AVX + xaudio2_9)
        let atomicHeart = GameQuirksDatabase.defaultProfile(forAppID: 668580, preferredTranslator: .fex)
        #expect(atomicHeart.translator == .rosetta)
        #expect(atomicHeart.graphics == .d3dMetal)
        #expect(atomicHeart.advertiseAVX == true)
        #expect(atomicHeart.dllOverrides["xaudio2_9"] == "n,b")
        #expect(GameQuirksDatabase.presetInfo(forAppID: 668580)?.title == "Atomic Heart")

        // 4. Fallout 76 - AppID 1151340 (Forces Rosetta 2 because 1 MB PE stack reserve overflows FEX xtajit64.dll)
        let fallout76 = GameQuirksDatabase.defaultProfile(forAppID: 1151340, preferredTranslator: .fex)
        #expect(fallout76.translator == .rosetta)
        #expect(fallout76.graphics == .dxmt)
        #expect(fallout76.advertiseAVX == true)

        // 5. Heroes of Might and Magic: Olden Era - AppID 3105440 (D3DMetal for MediaFoundation .mp4 shared texture handles)
        let oldenEra = GameQuirksDatabase.defaultProfile(forAppID: 3105440, preferredTranslator: .fex)
        #expect(oldenEra.translator == .rosetta)
        #expect(oldenEra.graphics == .d3dMetal)
        #expect(oldenEra.retinaMode == false)
        #expect(oldenEra.dllOverrides["d3dcompiler_47"] == "n,b")

        // 6. Fallout 2 - AppID 38410 (32-bit with sfall/f2_res ddraw=n,b)
        let fallout2 = GameQuirksDatabase.defaultProfile(forAppID: 38410, preferredTranslator: .fex)
        #expect(fallout2.translator == .rosetta)
        #expect(fallout2.dllOverrides["ddraw"] == "n,b")

        // 7. Frostpunk - AppID 323190 (64-bit DX11 -> DXMT)
        let frostpunk = GameQuirksDatabase.defaultProfile(forAppID: 323190, preferredTranslator: .fex)
        #expect(frostpunk.graphics == .dxmt)

        // 8. STAR WARS: The Old Republic - AppID 1286830 (32-bit launcher -> 64-bit client -> Rosetta + WineD3D)
        let swtor = GameQuirksDatabase.defaultProfile(forAppID: 1286830, preferredTranslator: .fex)
        #expect(swtor.translator == .rosetta)
        #expect(swtor.graphics == .wineD3D)

        // 9. Native macOS games (Cyberpunk 2077 = 1091500, Metro Exodus = 412020, BG3 = 1086940)
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
        #expect(prefixes.count >= 1)
        #expect(prefixes.contains(where: { $0.appID == "1151340" && $0.gameTitle == "Fallout 76" }))
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


    @Test("Game fixes switch off individually or all at once, and old profiles keep them on")
    func switchableGameFixes() throws {
        var rdr2 = GameQuirksDatabase.defaultProfile(forAppID: 1174180, preferredTranslator: .rosetta)
        #expect(rdr2.effectiveDllOverrides["nvngx"] == "d")
        #expect(rdr2.effectiveEnvironment["D3DM_ENABLE_METALFX"] == "0")

        rdr2.disabledFixes = [RuntimeFix.dllID("nvngx"), "rdr2-anti-flicker"]
        #expect(rdr2.effectiveDllOverrides["nvngx"] == nil)
        #expect(rdr2.effectiveDllOverrides["vulkan-1"] == "n,b")
        let partial = rdr2.buildPositronEnvFileContent()
        #expect(!partial.contains("nvngx=d"))
        #expect(partial.contains("export POSITRON_DISABLED_FIXES=\" dll:nvngx rdr2-anti-flicker \""))
        #expect(partial.contains("export POSITRON_GAME_FIXES=\"1\""))

        rdr2.gameFixesEnabled = false
        #expect(rdr2.effectiveDllOverrides.isEmpty)
        #expect(rdr2.effectiveEnvironment.isEmpty)
        let off = rdr2.buildPositronEnvFileContent()
        #expect(off.contains("export POSITRON_GAME_FIXES=\"0\""))
        #expect(!off.contains("D3DM_ENABLE_METALFX"))

        let legacyJSON = #"{"appID":1151340,"translator":"rosetta","graphics":"dxmt","sync":"msync","dllOverrides":{"xaudio2_7":"n,b"}}"#
        let legacy = try JSONDecoder().decode(GameProfile.self, from: Data(legacyJSON.utf8))
        #expect(legacy.gameFixesEnabled == true)
        #expect(legacy.disabledFixes.isEmpty)
        #expect(legacy.effectiveDllOverrides["xaudio2_7"] == "n,b")

        #expect(RuntimeFix.applicable(to: 292030).contains { $0.id == "witcher3-dx12-fix" })
        #expect(!RuntimeFix.applicable(to: 990080).contains { $0.id == "witcher3-dx12-fix" })
    }

    @Test("Preset library covers 100+ unique Windows-only titles with engine-based pipelines")
    func presetLibraryCoverage() {
        let ids = GameQuirksDatabase.catalog.map(\.appID)
        #expect(ids.count >= 100)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { !GameQuirksDatabase.knownNativeMacAppIDs.contains($0) })

        let hogwarts = GameQuirksDatabase.defaultProfile(forAppID: 990080, preferredTranslator: .fex)
        #expect(hogwarts.translator == .rosetta)
        #expect(hogwarts.graphics == .d3dMetal)
        let tf2 = GameQuirksDatabase.defaultProfile(forAppID: 440, preferredTranslator: .fex)
        #expect(tf2.graphics == .wineD3D)
        #expect(GameQuirksDatabase.isHandTuned(292030))
        #expect(!GameQuirksDatabase.isHandTuned(990080))
    }

    @Test("Non-Steam games get stable virtual IDs, persist, and launch as Steam shortcuts")
    func standaloneGames() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "positron-standalone-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let gameDir = tmp.appending(path: "My Game")
        try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        let exe = gameDir.appending(path: "MyGame.exe")
        try Data("MZ".utf8).write(to: exe)
        let store = tmp.appending(path: "standalone-games.json")

        let game = try StandaloneGameStore.add(executable: exe, to: store)
        #expect(StandaloneGameStore.isVirtualAppID(game.id))
        #expect(game.title == "MyGame")
        #expect(try StandaloneGameStore.add(executable: exe, to: store) == game)
        #expect(StandaloneGameStore.load(from: store) == [game])

        let env = StandaloneGameStore.launchEnvironment(for: game, base: ["SteamAppId": "730"])
        #expect(env["STEAM_COMPAT_APP_ID"] == String(game.id))
        #expect(env["STEAM_COMPAT_INSTALL_PATH"] == gameDir.path(percentEncoded: false))
        #expect(env["SteamAppId"] == nil)
        #expect((UInt64(env["SteamGameId"] ?? "0") ?? 0) & 0xFFFF_FFFF == 0x0200_0000)

        #expect(throws: StandaloneGameError.self) {
            try StandaloneGameStore.add(executable: gameDir.appending(path: "readme.txt"), to: store)
        }
        try StandaloneGameStore.remove(id: game.id, from: store)
        #expect(StandaloneGameStore.load(from: store).isEmpty)
    }

    @Test("Games still downloading in Steam stay hidden until the manifest says fully installed")
    func appManifestInstallState() throws {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "positron-acf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let downloading = tmp.appending(path: "appmanifest_1.acf")
        try Data("\"AppState\"\n{\n\t\"appid\"\t\t\"1\"\n\t\"StateFlags\"\t\t\"1026\"\n}\n".utf8).write(to: downloading)
        let installed = tmp.appending(path: "appmanifest_2.acf")
        try Data("\"AppState\"\n{\n\t\"appid\"\t\t\"2\"\n\t\"StateFlags\"\t\t\"4\"\n}\n".utf8).write(to: installed)
        #expect(SteamLibraryDiscovery.parseAppManifestStateFlags(at: downloading) == 1026)
        #expect(!SteamLibraryDiscovery.isFullyInstalled(manifestAt: downloading))
        #expect(SteamLibraryDiscovery.isFullyInstalled(manifestAt: installed))
    }

    @Test("PositronStorageManager relocates support directories to external folder and APFS sparsebundle and restores cleanly")
    func externalStorageAndSparseBundleRelocation() throws {
        let fm = FileManager.default
        let sandbox = fm.temporaryDirectory.appending(path: "positron-storage-test-\(UUID().uuidString)")
        let fakeSupport = sandbox.appending(path: "InternalSupport")
        let fakeExternalDrive = sandbox.appending(path: "ExternalDrive")
        try fm.createDirectory(at: fakeSupport.appending(path: "prefixes/1151340/pfx"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeSupport.appending(path: "prefixes/1151340/pfx.previous-20261022"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeSupport.appending(path: "runners/crossover-26.3"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeSupport.appending(path: "launchers/1151340"), withIntermediateDirectories: true)
        try fm.createDirectory(at: fakeExternalDrive, withIntermediateDirectories: true)

        let saveMarker = fakeSupport.appending(path: "prefixes/1151340/pfx/save.txt")
        let oldBackup = fakeSupport.appending(path: "prefixes/1151340/pfx.previous-20261022/old.bin")
        let iconMarker = fakeSupport.appending(path: "launchers/1151340/game.icns")
        try Data("VAULT_76_SAVE".utf8).write(to: saveMarker)
        try Data(repeating: 0xAA, count: 8192).write(to: oldBackup)
        try Data("ICON_DATA".utf8).write(to: iconMarker)

        defer {
            let mountURL = fakeSupport.appending(path: ".mounted-storage")
            if PositronStorageManager.isMountPointActive(mountURL) {
                let p = Process()
                p.executableURL = URL(filePath: "/usr/bin/hdiutil")
                p.arguments = ["detach", mountURL.path(percentEncoded: false), "-force"]
                try? p.run()
                p.waitUntilExit()
            }
            try? fm.removeItem(at: sandbox)
        }

        // 1. Relocate to an APFS Sparse Disk Image (.sparsebundle) — simulating an ExFAT external drive
        let sparseCfg = try PositronStorageManager.relocateStorage(
            to: fakeExternalDrive,
            preferSparseBundle: true,
            maxImageSizeGB: 2,
            baseSupportDir: fakeSupport
        )
        #expect(sparseCfg.mode == .externalSparseBundle)
        #expect(sparseCfg.externalContainerPath?.hasSuffix("PositronStorage.sparsebundle") == true)
        #expect(PositronStorageManager.isMountPointActive(fakeSupport.appending(path: ".mounted-storage")))

        // Internal prefixes & launchers paths are now symlinks, and data is readable through them
        var st = stat()
        #expect(lstat(fakeSupport.appending(path: "prefixes").path(percentEncoded: false), &st) == 0)
        #expect((st.st_mode & S_IFMT) == S_IFLNK)
        #expect(try String(contentsOf: saveMarker, encoding: .utf8) == "VAULT_76_SAVE")
        #expect(try String(contentsOf: iconMarker, encoding: .utf8) == "ICON_DATA")

        let envFile = try String(contentsOf: fakeSupport.appending(path: "storage-env.sh"), encoding: .utf8)
        #expect(envFile.contains("POSITRON_STORAGE_MODE=\"external-sparsebundle\""))

        // 2. Clean old prefix backups inside the mounted sparsebundle
        let freed = PositronStorageManager.cleanupOldPrefixBackups(baseSupportDir: fakeSupport)
        #expect(freed > 0)
        #expect(!fm.fileExists(atPath: oldBackup.path(percentEncoded: false)))
        #expect(try String(contentsOf: saveMarker, encoding: .utf8) == "VAULT_76_SAVE")

        // 3. Move back to Internal SSD and verify symlinks become real directories again with intact saves
        try PositronStorageManager.moveBackToInternalSSD(baseSupportDir: fakeSupport)
        #expect(!PositronStorageManager.isMountPointActive(fakeSupport.appending(path: ".mounted-storage")))
        #expect(lstat(fakeSupport.appending(path: "prefixes").path(percentEncoded: false), &st) == 0)
        #expect((st.st_mode & S_IFMT) == S_IFDIR)
        #expect(try String(contentsOf: saveMarker, encoding: .utf8) == "VAULT_76_SAVE")
        #expect(try String(contentsOf: iconMarker, encoding: .utf8) == "ICON_DATA")
    }
}
