// SPDX-License-Identifier: MIT
import AppKit
import Darwin
import Foundation

public enum PrefixMigrationOutcome: String, Codable, Sendable, Equatable {
    case unchanged
    case initialized
    case runnerUpgraded
    case architectureTransitioned
}

public enum WineUtility: String, CaseIterable, Sendable, Identifiable {
    case winecfg = "winecfg"
    case regedit = "regedit"
    case control = "control"
    case taskmgr = "taskmgr"
    case uninstaller = "uninstaller"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .winecfg: return "Wine Settings (winecfg)"
        case .regedit: return "Registry Editor (regedit)"
        case .control: return "Control Panel"
        case .taskmgr: return "Task Manager"
        case .uninstaller: return "Add / Remove Programs"
        }
    }

    public var subtitle: String {
        switch self {
        case .winecfg: return "Windows version, DLL overrides, graphics, audio & drives"
        case .regedit: return "Inspect and edit Windows registry keys in this prefix"
        case .control: return "Configure game controllers and Windows applets"
        case .taskmgr: return "Monitor and terminate running Windows processes"
        case .uninstaller: return "Manage installed Windows redistributables and packages"
        }
    }

    public var icon: String {
        switch self {
        case .winecfg: return "slider.horizontal.below.rectangle"
        case .regedit: return "list.bullet.rectangle.portrait"
        case .control: return "gearshape.2"
        case .taskmgr: return "waveform.path.ecg.rectangle"
        case .uninstaller: return "shippingbox"
        }
    }
}

public struct PrefixStamp: Codable, Sendable, Equatable {
    public var runnerID: String
    public var architecture: String
    public var graphics: GraphicsBackend

    public init(runnerID: String, architecture: String, graphics: GraphicsBackend) {
        self.runnerID = runnerID
        self.architecture = architecture
        self.graphics = graphics
    }
}

public struct SteamLibraryFolder: Identifiable, Sendable, Equatable {
    public let id: String
    public let rootURL: URL
    public let label: String
    public let isExternal: Bool
    public let fileSystemType: String
    public let requiresShadowPrefix: Bool
    public let isConnected: Bool
    public let installedGamesCount: Int

    public var steamappsURL: URL { rootURL.appending(path: "steamapps") }
    public var compatdataURL: URL { steamappsURL.appending(path: "compatdata") }
}

public struct DiscoveredPrefix: Identifiable, Sendable, Equatable {
    public let appID: String
    public let gameTitle: String?
    public let compatDataURL: URL
    public let libraryLabel: String
    public let isExternalDrive: Bool
    public let usesShadowPrefix: Bool
    public let stamp: PrefixStamp?
    public let detectedPEArch: String?
    public let recordedBuild: String?
    public let snapshotCount: Int
    public let hasLaunchLog: Bool

    public var id: String { "\(libraryLabel):\(appID)" }
    public var pfxURL: URL { compatDataURL.appending(path: "pfx") }
    public var driveCURL: URL { pfxURL.appending(path: "drive_c") }
    public var steamuserURL: URL { pfxURL.appending(path: "drive_c/users/steamuser") }
    public var launchLogURL: URL { compatDataURL.appending(path: "notproton-run.log") }
    public var isFEXPrefix: Bool {
        stamp?.architecture == "arm64" || detectedPEArch?.contains("arm64") == true
    }
}

public struct PrefixMigrationResult: Sendable, Equatable {
    public let outcome: PrefixMigrationOutcome
    public let snapshotURL: URL?
    public let activeStamp: PrefixStamp
}

public enum PrefixToolError: LocalizedError {
    case noRunnerAvailable
    case wineLoaderMissing(String)
    case unsupportedExecutableExtension(String)
    case executableNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .noRunnerAvailable:
            return "No CrossOver or Wine engine is available to run this tool."
        case .wineLoaderMissing(let path):
            return "Wine loader executable not found at \(path)."
        case .unsupportedExecutableExtension(let ext):
            return "Unsupported file type .\(ext). Choose a Windows .exe, .msi, .bat, or .cmd file."
        case .executableNotFound(let path):
            return "File not found at \(path)."
        }
    }
}

public enum SteamLibraryDiscovery {
    public static func parseLibraryFoldersVDF(_ text: String) -> [String] {
        var paths: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("\"path\"") else { continue }
            let parts = trimmed.split(separator: "\"", omittingEmptySubsequences: false)
            if parts.count >= 4 {
                let rawPath = String(parts[3]).replacingOccurrences(of: "\\\\", with: "/")
                if !rawPath.isEmpty, !paths.contains(rawPath) {
                    paths.append(rawPath)
                }
            }
        }
        return paths
    }

    /// Parses libraryfolders.vdf to map each library folder path to the list of Steam AppIDs recorded in its "apps" section.
    public static func parseLibraryAppsVDF(_ text: String) -> [String: [UInt32]] {
        var result: [String: [UInt32]] = [:]
        var currentPath: String?
        var inAppsBlock = false
        var appsBraceDepth = 0

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("\"path\"") {
                let parts = trimmed.split(separator: "\"", omittingEmptySubsequences: false)
                if parts.count >= 4 {
                    let rawPath = String(parts[3]).replacingOccurrences(of: "\\\\", with: "/")
                    if !rawPath.isEmpty {
                        currentPath = rawPath
                        if result[rawPath] == nil { result[rawPath] = [] }
                    }
                }
            } else if trimmed == "\"apps\"" {
                inAppsBlock = true
                appsBraceDepth = 0
            } else if inAppsBlock {
                if trimmed == "{" {
                    appsBraceDepth += 1
                } else if trimmed == "}" {
                    appsBraceDepth -= 1
                    if appsBraceDepth <= 0 {
                        inAppsBlock = false
                    }
                } else if appsBraceDepth == 1, let path = currentPath {
                    let parts = trimmed.split(separator: "\"", omittingEmptySubsequences: false)
                    if parts.count >= 2, let appID = UInt32(parts[1]), appID != 228980 {
                        result[path, default: []].append(appID)
                    }
                }
            }
        }
        return result
    }

    /// Reads the kernel mount table via getmntinfo() without touching removable volume directories (zero TCC prompt).
    public static func mountedVolumesMap() -> [String: String] {
        var mntbuf: UnsafeMutablePointer<statfs>?
        let count = Int(getmntinfo(&mntbuf, MNT_NOWAIT))
        guard count > 0, let buf = mntbuf else { return [:] }
        var map: [String: String] = [:]
        for i in 0..<count {
            var entry = buf[i]
            let mntPath = withUnsafePointer(to: &entry.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                    String(cString: $0)
                }
            }
            let fsName = withUnsafePointer(to: &entry.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                    String(cString: $0)
                }
            }.lowercased()
            map[mntPath] = fsName
        }
        return map
    }

    /// Parses a Steam appmanifest_<appid>.acf file to extract the game's "installdir".
    public static func parseAppManifestInstallDir(at acfURL: URL) -> String? {
        guard let text = try? String(contentsOf: acfURL, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("\"installdir\"") else { continue }
            let parts = trimmed.split(separator: "\"", omittingEmptySubsequences: false)
            if parts.count >= 4 {
                let dir = String(parts[3])
                if !dir.isEmpty { return dir }
            }
        }
        return nil
    }

    /// Returns true if the game directory in steamapps/common/<installdir> contains a native macOS .app bundle
    /// (such as Cyberpunk2077.app or MetroExodus.app) and no Windows .exe binary, so it runs natively on macOS.
    public static func isNativeMacInstallation(at gameDirURL: URL) -> Bool {
        let fm = FileManager.default
        guard let topItems = try? fm.contentsOfDirectory(at: gameDirURL, includingPropertiesForKeys: nil) else {
            return false
        }
        var hasMacApp = false
        var hasWinExe = false
        for item in topItems where !item.lastPathComponent.hasPrefix("._") {
            let ext = item.pathExtension.lowercased()
            if ext == "app" { hasMacApp = true }
            if ext == "exe" { hasWinExe = true }
            if let subItems = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                for sub in subItems where !sub.lastPathComponent.hasPrefix("._") {
                    let subExt = sub.pathExtension.lowercased()
                    if subExt == "app" { hasMacApp = true }
                    if subExt == "exe" { hasWinExe = true }
                }
            }
        }
        return hasMacApp && !hasWinExe
    }

    /// Inspects an installed Windows game folder (.exe PE headers + engine DLLs) to automatically
    /// synthesize a recommended GamePresetInfo and GameProfile for games not yet in the curated catalog.
    public static func autoDetectPreset(
        forAppID appID: UInt32,
        title: String,
        in libraries: [SteamLibraryFolder]
    ) -> PresetCatalogEntry {
        let fm = FileManager.default
        var gameDir: URL?
        for lib in libraries where lib.isConnected && !lib.isExternal {
            let acf = lib.steamappsURL.appending(path: "appmanifest_\(appID).acf")
            if let installDir = parseAppManifestInstallDir(at: acf) {
                let candidate = lib.steamappsURL.appending(path: "common/\(installDir)")
                if fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
                    gameDir = candidate
                    break
                }
            }
        }

        var has32BitExe = false
        var has64BitExe = false
        var hasUnity = false
        var hasDX12 = false
        var hasUnreal = false
        var hasDDraw = false
        var hasXAudio = false

        if let dir = gameDir,
           let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            var scanned = 0
            while let fileURL = enumerator.nextObject() as? URL, scanned < 400 {
                scanned += 1
                let name = fileURL.lastPathComponent.lowercased()
                if name.hasPrefix("._") { continue }
                if name == "unityplayer.dll" { hasUnity = true }
                if name == "d3d12core.dll" || name == "d3d12.dll" || name.contains("dx12") { hasDX12 = true }
                if name == "ddraw.dll" { hasDDraw = true }
                if name.hasPrefix("xaudio2") { hasXAudio = true }
                if fileURL.path(percentEncoded: false).contains("Engine/Binaries/Win64") { hasUnreal = true }
                if fileURL.pathExtension.lowercased() == "exe",
                   !name.contains("crash"), !name.contains("unins"), !name.contains("redist") {
                    if let pe = UniversalPEAnalyzer.inspectNtdll(at: fileURL, archDirectory: "game") {
                        if pe.machineHex == "0x014c" { has32BitExe = true }
                        if pe.machineHex == "0x8664" { has64BitExe = true }
                    }
                }
            }
        }

        var profile = GameProfile(appID: appID, translator: .rosetta, graphics: .dxmt, sync: .msync)
        profile.dllOverrides["vcruntime140"] = "n,b"
        profile.dllOverrides["d3dcompiler_47"] = "n,b"
        if hasXAudio { profile.dllOverrides["xaudio2_7"] = "n,b" }

        let subtitle: String
        let summary: String
        let notes: String

        if has32BitExe && !has64BitExe {
            profile.translator = .rosetta
            profile.graphics = .wineD3D
            if hasDDraw {
                profile.dllOverrides["ddraw"] = "n,b"
                profile.dllOverrides["dinput"] = "n,b"
                profile.dllOverrides["dinput8"] = "n,b"
            }
            subtitle = "Auto-Detected 32-bit (i386) Windows Game"
            summary = "Rosetta 2 (32-bit) + WineD3D + Msync"
            notes = "Detected 32-bit i386 executable. Configured Rosetta 2 + WineD3D to avoid 32-bit Vulkan/FEX issues."
        } else if has32BitExe && has64BitExe {
            profile.translator = .rosetta
            profile.graphics = .wineD3D
            subtitle = "Auto-Detected 32-bit Launcher + 64-bit Client"
            summary = "Rosetta 2 (WoW64) + WineD3D + Msync"
            notes = "Detected a 32-bit launcher paired with a 64-bit game client. Configured Rosetta 2 WoW64 + WineD3D."
        } else if hasDX12 || hasUnreal {
            profile.translator = .rosetta
            profile.graphics = .d3dMetal
            profile.advertiseAVX = true
            subtitle = hasUnreal ? "Auto-Detected Unreal Engine • 64-bit DirectX 12" : "Auto-Detected 64-bit DirectX 12 Game"
            summary = "Rosetta 2 + D3DMetal (DX12) + AVX + Msync"
            notes = "Detected 64-bit DirectX 12 / Unreal Engine binaries. Configured Rosetta 2 with AVX and Apple D3DMetal."
        } else if hasUnity {
            profile.translator = .rosetta
            profile.graphics = .dxmt
            profile.retinaMode = false
            profile.extraEnvironment["DXMT_CONFIG"] = "d3d11.maxFrameRate=60"
            subtitle = "Auto-Detected Unity Engine • 64-bit DirectX 11"
            summary = "Rosetta 2 + DXMT (60 FPS Cap) + Msync"
            notes = "Detected UnityPlayer.dll (64-bit DirectX 11). Configured DXMT with a 60 FPS cap for smooth Apple Silicon frame pacing."
        } else {
            profile.translator = .rosetta
            profile.graphics = .dxmt
            profile.advertiseAVX = true
            subtitle = "Auto-Detected 64-bit DirectX 11 Game"
            summary = "Rosetta 2 + DXMT (DX11) + AVX + Msync"
            notes = "Detected 64-bit x86_64 executable. Configured Rosetta 2 + DXMT for DirectX 11 Metal acceleration."
        }

        let info = GamePresetInfo(
            appID: appID,
            title: title,
            subtitle: subtitle,
            recommendedSummary: summary,
            notes: notes
        )
        return PresetCatalogEntry(info: info, recommendedProfile: profile.sanitized())
    }

    /// Returns a map of [AppID: GameTitle] for all installed Windows-only games across the given libraries,
    /// automatically excluding native macOS games (like Cyberpunk 2077 and Metro Exodus) so they run natively!
    public static func discoverInstalledApps(
        in libraries: [SteamLibraryFolder],
        steamRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Steam")
    ) -> [UInt32: String] {
        let fm = FileManager.default
        var installed: [UInt32: String] = [:]

        // Load VDF apps map from internal Steam folder first (zero Removable Volumes TCC prompt)
        var vdfAppsByLibrary: [String: [UInt32]] = [:]
        for rel in ["steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"] {
            let vdfURL = steamRoot.appending(path: rel)
            if let text = try? String(contentsOf: vdfURL, encoding: .utf8) {
                let parsed = parseLibraryAppsVDF(text)
                for (k, v) in parsed where !v.isEmpty {
                    vdfAppsByLibrary[k] = v
                }
            }
        }

        for lib in libraries where lib.isConnected {
            let libKey = lib.rootURL.path(percentEncoded: false)
            if lib.isExternal, let appIDs = vdfAppsByLibrary[libKey], !appIDs.isEmpty {
                for appID in appIDs where appID != 228980 {
                    if GameQuirksDatabase.knownNativeMacAppIDs.contains(appID) { continue }
                    let curatedTitle = GameQuirksDatabase.presetInfo(forAppID: appID)?.title
                    let launcherTitle = resolveLauncherBundleTitle(forAppID: appID)
                    installed[appID] = curatedTitle ?? launcherTitle ?? "Steam Game (\(appID))"
                }
                continue
            }

            guard !lib.isExternal,
                  let entries = try? fm.contentsOfDirectory(at: lib.steamappsURL, includingPropertiesForKeys: nil) else {
                continue
            }
            for entry in entries where entry.lastPathComponent.hasPrefix("appmanifest_") && entry.pathExtension == "acf" {
                let numPart = entry.deletingPathExtension().lastPathComponent.dropFirst("appmanifest_".count)
                guard let appID = UInt32(numPart), appID != 228980 else { continue }
                if GameQuirksDatabase.knownNativeMacAppIDs.contains(appID) { continue }
                if let installDir = parseAppManifestInstallDir(at: entry) {
                    let gameDir = lib.steamappsURL.appending(path: "common/\(installDir)")
                    if isNativeMacInstallation(at: gameDir) { continue }
                }
                let name = parseAppManifestName(at: entry) ?? "Steam App \(appID)"
                installed[appID] = name
            }
        }
        return installed
    }

    private static func resolveLauncherBundleTitle(forAppID appID: UInt32) -> String? {
        let launcherDir = SteamIntegration.positronSupportDir.appending(path: "launchers/\(appID)")
        guard let items = try? FileManager.default.contentsOfDirectory(at: launcherDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        for item in items where item.pathExtension == "app" && !item.lastPathComponent.hasPrefix(".") {
            return item.deletingPathExtension().lastPathComponent
        }
        return nil
    }

    public static func parseAppManifestName(at acfURL: URL) -> String? {
        guard let text = try? String(contentsOf: acfURL, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("\"name\"") else { continue }
            let parts = trimmed.split(separator: "\"", omittingEmptySubsequences: false)
            if parts.count >= 4 {
                let name = String(parts[3])
                if !name.isEmpty { return name }
            }
        }
        return nil
    }

    public static func inspectVolume(at url: URL) -> (fsType: String, isExternal: Bool, needsShadow: Bool) {
        let rawPath = url.path(percentEncoded: false)
        let isExternal = rawPath.hasPrefix("/Volumes/")
        if isExternal {
            let parts = url.pathComponents
            if let volIdx = parts.firstIndex(of: "Volumes"), volIdx + 1 < parts.count {
                let mountPoint = "/Volumes/\(parts[volIdx + 1])"
                let mounted = mountedVolumesMap()
                if let fsRaw = mounted[mountPoint] {
                    switch fsRaw {
                    case "apfs": return ("APFS", true, false)
                    case "hfs": return ("HFS+", true, false)
                    case "exfat": return ("ExFAT", true, true)
                    case "ntfs", "ufsd_ntfs", "tuxera_ntfs", "msdos": return (fsRaw.uppercased(), true, true)
                    default: return (fsRaw.uppercased(), true, false)
                    }
                }
            }
        }

        var probe = rawPath
        var sfs = statfs()
        while statfs(probe, &sfs) != 0 {
            let parent = (probe as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == probe {
                _ = statfs("/", &sfs)
                break
            }
            probe = parent
        }

        let fsRaw = withUnsafePointer(to: &sfs.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }.lowercased()

        switch fsRaw {
        case "apfs":
            return ("APFS", isExternal, false)
        case "hfs":
            return ("HFS+", isExternal, false)
        case "exfat":
            return ("ExFAT", isExternal, true)
        case "ntfs", "ufsd_ntfs", "tuxera_ntfs", "msdos":
            return (fsRaw.uppercased(), isExternal, true)
        default:
            return (fsRaw.isEmpty ? "APFS" : fsRaw.uppercased(), isExternal, false)
        }
    }

    public static func discoverLibraries(
        steamRoot: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Steam"),
        extraLibraryPaths: [String] = [],
        scanMountedVolumes: Bool = false
    ) -> [SteamLibraryFolder] {
        let fm = FileManager.default
        var candidatePaths: [String] = [steamRoot.path(percentEncoded: false)]
        var vdfAppsByLibrary: [String: [UInt32]] = [:]

        let vdfCandidates = [
            steamRoot.appending(path: "steamapps/libraryfolders.vdf"),
            steamRoot.appending(path: "config/libraryfolders.vdf")
        ]
        for vdf in vdfCandidates {
            if let text = try? String(contentsOf: vdf, encoding: .utf8) {
                for path in parseLibraryFoldersVDF(text) where !candidatePaths.contains(path) {
                    candidatePaths.append(path)
                }
                for (k, v) in parseLibraryAppsVDF(text) where !v.isEmpty {
                    vdfAppsByLibrary[k] = v
                }
            }
        }

        if scanMountedVolumes, let volumes = try? fm.contentsOfDirectory(at: URL(filePath: "/Volumes"), includingPropertiesForKeys: nil) {
            for vol in volumes {
                for folderName in ["SteamLibrary", "SteamMacLibrary"] {
                    let extLib = vol.appending(path: folderName)
                    let extPath = extLib.path(percentEncoded: false)
                    if fm.fileExists(atPath: extLib.appending(path: "steamapps").path(percentEncoded: false)),
                       !candidatePaths.contains(extPath) {
                        candidatePaths.append(extPath)
                    }
                }
            }
        }

        for extra in extraLibraryPaths where !candidatePaths.contains(extra) {
            candidatePaths.append(extra)
        }

        let mounted = mountedVolumesMap()
        var results: [SteamLibraryFolder] = []
        var seen: Set<String> = []

        for raw in candidatePaths {
            let url = URL(filePath: raw).standardizedFileURL
            let key = url.path(percentEncoded: false)
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            let vol = inspectVolume(at: url)
            let connected: Bool
            let acfCount: Int

            if vol.isExternal && !scanMountedVolumes {
                let parts = url.pathComponents
                if let volIdx = parts.firstIndex(of: "Volumes"), volIdx + 1 < parts.count {
                    let mountPoint = "/Volumes/\(parts[volIdx + 1])"
                    connected = mounted[mountPoint] != nil
                } else {
                    connected = false
                }
                let apps = vdfAppsByLibrary[key] ?? []
                acfCount = apps.filter { !GameQuirksDatabase.knownNativeMacAppIDs.contains($0) }.count
                if !connected && acfCount == 0 {
                    continue
                }
            } else {
                connected = fm.fileExists(atPath: key)
                let steamapps = url.appending(path: "steamapps")
                let entries = (try? fm.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
                acfCount = entries.filter {
                    $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf"
                }.count
            }

            let label: String
            if vol.isExternal {
                let parts = url.pathComponents
                if let volIdx = parts.firstIndex(of: "Volumes"), volIdx + 1 < parts.count {
                    label = "External Drive (\(parts[volIdx + 1]))"
                } else {
                    label = "External Drive (\(url.lastPathComponent))"
                }
            } else {
                label = "Internal Mac SSD"
            }

            results.append(SteamLibraryFolder(
                id: key,
                rootURL: url,
                label: label,
                isExternal: vol.isExternal,
                fileSystemType: vol.fsType,
                requiresShadowPrefix: vol.needsShadow,
                isConnected: connected,
                installedGamesCount: acfCount
            ))
        }

        return results
    }
}

public enum PrefixManager {
    public static let stampFileName = "positron-prefix.json"

    public static func discoverSteamPrefixes(
        libraries: [SteamLibraryFolder] = SteamLibraryDiscovery.discoverLibraries(),
        includePositronShadowRoot: Bool = false
    ) -> [DiscoveredPrefix] {
        let fm = FileManager.default
        var found: [DiscoveredPrefix] = []

        for lib in libraries where lib.isConnected && !lib.isExternal {
            guard let items = try? fm.contentsOfDirectory(at: lib.compatdataURL, includingPropertiesForKeys: nil) else {
                continue
            }
            for item in items {
                let name = item.lastPathComponent
                guard !name.isEmpty, name.allSatisfy(\.isNumber) else { continue }
                let pfx = item.appending(path: "pfx")
                guard fm.fileExists(atPath: pfx.path(percentEncoded: false)) else { continue }

                let acfURL = lib.steamappsURL.appending(path: "appmanifest_\(name).acf")
                let acfTitle = SteamLibraryDiscovery.parseAppManifestName(at: acfURL)
                    ?? GameQuirksDatabase.presetInfo(forAppID: UInt32(name) ?? 0)?.title

                let stamp = readStamp(in: item)
                let buildRecord = (try? String(contentsOf: item.appending(path: "notproton-build"), encoding: .utf8))?
                    .components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces)
                let ntdllURL = pfx.appending(path: "drive_c/windows/system32/ntdll.dll")
                let peInfo = UniversalPEAnalyzer.inspectNtdll(at: ntdllURL, archDirectory: "system32")
                let peArch: String? = switch peInfo?.machineHex {
                case "0xaa64": "arm64 (FEX)"
                case "0x8664": "x86_64 (Rosetta)"
                case "0x014c": "i386"
                default: nil
                }
                let subItems = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []
                let snaps = subItems.filter {
                    $0.lastPathComponent.hasPrefix("steamuser.snapshot.") ||
                    $0.lastPathComponent.hasPrefix("pfx.previous-")
                }.count
                let hasLog = fm.fileExists(atPath: item.appending(path: "notproton-run.log").path(percentEncoded: false))

                found.append(DiscoveredPrefix(
                    appID: name,
                    gameTitle: acfTitle,
                    compatDataURL: item,
                    libraryLabel: lib.label,
                    isExternalDrive: lib.isExternal,
                    usesShadowPrefix: lib.requiresShadowPrefix,
                    stamp: stamp,
                    detectedPEArch: peArch,
                    recordedBuild: buildRecord,
                    snapshotCount: snaps,
                    hasLaunchLog: hasLog
                ))
            }
        }

        // Also discover internal APFS shadow prefixes in ~/Library/Application Support/Positron/prefixes/<appid>
        let shadowRoot = SteamIntegration.positronSupportDir.appending(path: "prefixes")
        if includePositronShadowRoot, let shadowItems = try? fm.contentsOfDirectory(at: shadowRoot, includingPropertiesForKeys: nil) {
            for item in shadowItems {
                let name = item.lastPathComponent
                guard !name.isEmpty, name.allSatisfy(\.isNumber) else { continue }
                let pfx = item.appending(path: "pfx")
                guard fm.fileExists(atPath: pfx.path(percentEncoded: false)) else { continue }
                let aid = UInt32(name) ?? 0
                let title = GameQuirksDatabase.presetInfo(forAppID: aid)?.title
                let stamp = readStamp(in: item)
                let buildRecord = (try? String(contentsOf: item.appending(path: "notproton-build"), encoding: .utf8))?
                    .components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces)
                let ntdllURL = pfx.appending(path: "drive_c/windows/system32/ntdll.dll")
                let peInfo = UniversalPEAnalyzer.inspectNtdll(at: ntdllURL, archDirectory: "system32")
                let peArch: String? = switch peInfo?.machineHex {
                case "0xaa64": "arm64 (FEX)"
                case "0x8664": "x86_64 (Rosetta)"
                case "0x014c": "i386"
                default: nil
                }
                let subItems = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? []
                let snaps = subItems.filter {
                    $0.lastPathComponent.hasPrefix("steamuser.snapshot.") ||
                    $0.lastPathComponent.hasPrefix("pfx.previous-")
                }.count
                let hasLog = fm.fileExists(atPath: item.appending(path: "notproton-run.log").path(percentEncoded: false))
                found.removeAll { $0.appID == name }
                found.append(DiscoveredPrefix(
                    appID: name,
                    gameTitle: title,
                    compatDataURL: item,
                    libraryLabel: "Internal APFS Shadow Prefix",
                    isExternalDrive: false,
                    usesShadowPrefix: true,
                    stamp: stamp,
                    detectedPEArch: peArch,
                    recordedBuild: buildRecord,
                    snapshotCount: snaps,
                    hasLaunchLog: hasLog
                ))
            }
        }

        return found.sorted { ($0.gameTitle ?? $0.appID) < ($1.gameTitle ?? $1.appID) }
    }

    /// Resolves (or constructs) the DiscoveredPrefix for an installed Steam game so Wine tools
    /// (winecfg, regedit, Drive C:, .exe/.msi installer) work directly from the unified Installed Games view.
    public static func resolvePrefix(
        forAppID appID: UInt32,
        gameTitle: String?,
        libraries: [SteamLibraryFolder],
        existingPrefixes: [DiscoveredPrefix]
    ) -> DiscoveredPrefix {
        let appIDStr = String(appID)
        if let existing = existingPrefixes.first(where: { $0.appID == appIDStr }) {
            return existing
        }
        let fm = FileManager.default
        let shadowCandidate = SteamIntegration.positronSupportDir.appending(path: "prefixes/\(appID)")
        let externalLib = libraries.first(where: { $0.isExternal && $0.isConnected })
        let installedLib = libraries.first { lib in
            !lib.isExternal && fm.fileExists(atPath: lib.steamappsURL.appending(path: "appmanifest_\(appID).acf").path(percentEncoded: false))
        } ?? externalLib ?? libraries.first
        let isExternal = installedLib?.isExternal ?? false
        let compatURL: URL
        let libLabel: String
        if isExternal || fm.fileExists(atPath: shadowCandidate.path(percentEncoded: false)) {
            compatURL = shadowCandidate
            libLabel = "\(installedLib?.label ?? "External Drive") -> Internal APFS Prefix"
        } else if let lib = installedLib {
            compatURL = lib.compatdataURL.appending(path: appIDStr)
            libLabel = lib.label
        } else {
            compatURL = shadowCandidate
            libLabel = "Internal Mac SSD"
        }
        let hasLog = fm.fileExists(atPath: compatURL.appending(path: "notproton-run.log").path(percentEncoded: false))
        return DiscoveredPrefix(
            appID: appIDStr,
            gameTitle: gameTitle,
            compatDataURL: compatURL,
            libraryLabel: libLabel,
            isExternalDrive: isExternal,
            usesShadowPrefix: isExternal,
            stamp: readStamp(in: compatURL),
            detectedPEArch: nil,
            recordedBuild: nil,
            snapshotCount: 0,
            hasLaunchLog: hasLog
        )
    }

    public static func resolvePrefixWineEnvironment(
        for prefix: DiscoveredPrefix,
        runners: [DiscoveredRunner]
    ) throws -> (loader: URL, server: URL, env: [String: String]) {
        let fm = FileManager.default
        let wantFEX = prefix.isFEXPrefix
        let posRunnersDir = SteamIntegration.positronSupportDir.appending(path: "runners")

        var chosenRoot: URL?
        if let build = prefix.recordedBuild, !build.isEmpty {
            let cloneCandidate = posRunnersDir.appending(path: "crossover-\(build)/CrossOver")
            if fm.fileExists(atPath: cloneCandidate.appending(path: "lib/wine").path(percentEncoded: false)) {
                chosenRoot = cloneCandidate
            }
        }
        if chosenRoot == nil {
            let fallbackBuild = wantFEX ? "27.0.0.41069-fex" : "26.3.0.39832"
            let cloneCandidate = posRunnersDir.appending(path: "crossover-\(fallbackBuild)/CrossOver")
            if fm.fileExists(atPath: cloneCandidate.appending(path: "lib/wine").path(percentEncoded: false)) {
                chosenRoot = cloneCandidate
            }
        }
        if chosenRoot == nil {
            chosenRoot = runners.first(where: { wantFEX ? $0.supportsFEX : $0.supportsRosetta })?.rootURL
                ?? runners.first?.rootURL
        }
        guard let root = chosenRoot else {
            throw PrefixToolError.noRunnerAvailable
        }

        let rootPath = root.path(percentEncoded: false)
        let armLoader = root.appending(path: "lib/wine/aarch64-unix/wine.app/Contents/MacOS/wine")
        let armServer = root.appending(path: "bin/wineserver-arm64")
        let x86Loader = root.appending(path: "lib/wine/x86_64-unix/wine")
        let x86Server = root.appending(path: "bin/wineserver")

        let loader: URL
        let server: URL
        let unixDir: String
        if wantFEX, fm.isExecutableFile(atPath: armLoader.path(percentEncoded: false)) {
            loader = armLoader
            server = armServer
            unixDir = "\(rootPath)/lib/wine/aarch64-unix"
        } else {
            loader = x86Loader
            server = fm.isExecutableFile(atPath: x86Server.path(percentEncoded: false))
                ? x86Server
                : root.appending(path: "bin/wineserver-x86")
            unixDir = "\(rootPath)/lib/wine/x86_64-unix"
        }

        guard fm.isExecutableFile(atPath: loader.path(percentEncoded: false)) else {
            throw PrefixToolError.wineLoaderMissing(loader.path(percentEncoded: false))
        }

        var env = ProcessInfo.processInfo.environment
        env["CX_ROOT"] = rootPath
        env["CX_HOME"] = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/CrossOver").path(percentEncoded: false)
        env["WINELOADER"] = loader.path(percentEncoded: false)
        env["WINESERVER"] = server.path(percentEncoded: false)
        env["WINEDLLPATH"] = "\(rootPath)/lib/wine/x86_64-windows:\(unixDir)"
        env["WINEPREFIX"] = prefix.pfxURL.path(percentEncoded: false)
        env["WINEMSYNC"] = "1"
        env["PATH"] = "\(rootPath)/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        return (loader, server, env)
    }

    public static func arguments(forExecutable url: URL) throws -> [String] {
        let path = url.path(percentEncoded: false)
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "exe":
            return [path]
        case "msi":
            return ["msiexec", "/i", path]
        case "bat", "cmd":
            return ["cmd.exe", "/c", path]
        default:
            throw PrefixToolError.unsupportedExecutableExtension(ext)
        }
    }

    public static func launchUtility(
        _ utility: WineUtility,
        in prefix: DiscoveredPrefix,
        runners: [DiscoveredRunner]
    ) throws {
        try? FileManager.default.createDirectory(at: prefix.driveCURL, withIntermediateDirectories: true)
        let resolved = try resolvePrefixWineEnvironment(for: prefix, runners: runners)
        let proc = Process()
        proc.executableURL = resolved.loader
        proc.arguments = [utility.rawValue]
        proc.environment = resolved.env
        proc.currentDirectoryURL = prefix.driveCURL
        try proc.run()
    }

    public static func runExecutable(
        _ executableURL: URL,
        in prefix: DiscoveredPrefix,
        runners: [DiscoveredRunner]
    ) throws {
        guard FileManager.default.fileExists(atPath: executableURL.path(percentEncoded: false)) else {
            throw PrefixToolError.executableNotFound(executableURL.path(percentEncoded: false))
        }
        let args = try arguments(forExecutable: executableURL)
        let resolved = try resolvePrefixWineEnvironment(for: prefix, runners: runners)
        let proc = Process()
        proc.executableURL = resolved.loader
        proc.arguments = args
        proc.environment = resolved.env
        proc.currentDirectoryURL = executableURL.deletingLastPathComponent()
        try proc.run()
    }

    public static func killWineServer(
        in prefix: DiscoveredPrefix,
        runners: [DiscoveredRunner]
    ) throws {
        let resolved = try resolvePrefixWineEnvironment(for: prefix, runners: runners)
        let proc = Process()
        proc.executableURL = resolved.server
        proc.arguments = ["-k"]
        proc.environment = resolved.env
        try proc.run()
        proc.waitUntilExit()
    }

    public static func rebuildPreservingSaves(_ prefix: DiscoveredPrefix, runners: [DiscoveredRunner]) throws -> URL {
        try? killWineServer(in: prefix, runners: runners)
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let backupURL = prefix.compatDataURL.appending(path: "pfx.previous-\(stamp)")

        try fm.moveItem(at: prefix.pfxURL, to: backupURL)
        try ensureSteamUserLayout(in: prefix.compatDataURL)

        let oldSteamUser = backupURL.appending(path: "drive_c/users/steamuser")
        let newSteamUser = prefix.steamuserURL
        if fm.fileExists(atPath: oldSteamUser.path(percentEncoded: false)) {
            try? fm.removeItem(at: newSteamUser)
            try fm.copyItem(at: oldSteamUser, to: newSteamUser)
        }
        try? fm.removeItem(at: prefix.compatDataURL.appending(path: "notproton-build"))
        return backupURL
    }

    public static func ensureSteamUserLayout(in compatDataURL: URL) throws {
        let fm = FileManager.default
        let pfx = compatDataURL.appending(path: "pfx")
        let requiredDirs = [
            "drive_c/users/steamuser/Documents",
            "drive_c/users/steamuser/Desktop",
            "drive_c/users/steamuser/AppData/Local",
            "drive_c/users/steamuser/AppData/Roaming",
            "drive_c/users/steamuser/Saved Games",
            "drive_c/windows/system32",
            "drive_c/windows/syswow64",
            "dosdevices"
        ]
        for rel in requiredDirs {
            try fm.createDirectory(at: pfx.appending(path: rel), withIntermediateDirectories: true)
        }

        let crossoverAlias = pfx.appending(path: "drive_c/users/crossover")
        if !fm.fileExists(atPath: crossoverAlias.path(percentEncoded: false)) {
            try? fm.createSymbolicLink(atPath: crossoverAlias.path(percentEncoded: false), withDestinationPath: "steamuser")
        }
    }

    public static func readStamp(in compatDataURL: URL) -> PrefixStamp? {
        let file = compatDataURL.appending(path: stampFileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(PrefixStamp.self, from: data)
    }

    public static func writeStamp(_ stamp: PrefixStamp, in compatDataURL: URL) throws {
        let file = compatDataURL.appending(path: stampFileName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(stamp)
        try data.write(to: file, options: .atomic)
    }

    public static func reconcileAndMigrate(
        compatDataURL: URL,
        targetStamp: PrefixStamp
    ) throws -> PrefixMigrationResult {
        try ensureSteamUserLayout(in: compatDataURL)
        let pfx = compatDataURL.appending(path: "pfx")

        guard let previous = readStamp(in: compatDataURL) else {
            try writeStamp(targetStamp, in: compatDataURL)
            return PrefixMigrationResult(outcome: .initialized, snapshotURL: nil, activeStamp: targetStamp)
        }

        let archChanged = previous.architecture != targetStamp.architecture
        let runnerChanged = previous.runnerID != targetStamp.runnerID

        guard archChanged || runnerChanged else {
            if previous.graphics != targetStamp.graphics {
                try writeStamp(targetStamp, in: compatDataURL)
            }
            return PrefixMigrationResult(outcome: .unchanged, snapshotURL: nil, activeStamp: targetStamp)
        }

        let steamuser = pfx.appending(path: "drive_c/users/steamuser")
        let snapshot = compatDataURL.appending(path: "steamuser.snapshot.\(previous.runnerID).\(previous.architecture)")
        try? FileManager.default.removeItem(at: snapshot)

        if clonefile(steamuser.path(percentEncoded: false), snapshot.path(percentEncoded: false), 0) != 0 {
            try FileManager.default.copyItem(at: steamuser, to: snapshot)
        }

        if archChanged {
            let staleNtdll = pfx.appending(path: "drive_c/windows/system32/ntdll.dll")
            try? FileManager.default.removeItem(at: staleNtdll)
        }
        try? FileManager.default.removeItem(at: pfx.appending(path: ".update-timestamp"))
        try writeStamp(targetStamp, in: compatDataURL)

        return PrefixMigrationResult(
            outcome: archChanged ? .architectureTransitioned : .runnerUpgraded,
            snapshotURL: snapshot,
            activeStamp: targetStamp
        )
    }
}
