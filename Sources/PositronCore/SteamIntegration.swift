// SPDX-License-Identifier: MIT
import Darwin
import Foundation

public struct RegisteredCompatTool: Codable, Sendable, Equatable {
    public let toolName: String
    public let displayName: String
    public let runnerID: String
    public let translator: CPUTranslator
    public let toolDirectory: URL
}

public enum SteamIntegrationState: Sendable, Equatable {
    case steamMissing
    case stockSteam(toolsRegistered: Int)
    case positronInstalled(dylibPath: String, toolsRegistered: Int)
    case foreignDylibInstalled(dylibPath: String)

    public var summaryLabel: String {
        switch self {
        case .steamMissing:
            return "Steam.app Not Found"
        case .stockSteam(let count):
            return count > 0
                ? "Tools Installed in Steam (\(count) tool(s)) • Bundle Unmodified"
                : "Not Integrated (Stock Steam.app)"
        case .positronInstalled(_, let count):
            return "Integrated into Steam.app (\(count) Positron tool(s) active)"
        case .foreignDylibInstalled(let path):
            return "Foreign Dylib Injected (\(URL(filePath: path).lastPathComponent))"
        }
    }

    public var isPositronInjected: Bool {
        if case .positronInstalled = self { return true }
        return false
    }
}

public enum SteamIntegrationError: LocalizedError {
    case steamBundleNotFound(String)
    case infoPlistUnreadable(String)
    case bundledArtifactMissing(String)
    case codesignFailed(String)

    public var errorDescription: String? {
        switch self {
        case .steamBundleNotFound(let p): return "Steam.app not found at \(p)."
        case .infoPlistUnreadable(let p): return "Could not read or write \(p)."
        case .bundledArtifactMissing(let name): return "Missing Positron runtime component: \(name)."
        case .codesignFailed(let msg): return "Code-signing Steam.app failed: \(msg)"
        }
    }
}

public enum SteamIntegration {
    public static let defaultSteamApp = URL(filePath: "/Applications/Steam.app")

    public static var positronSupportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Positron")
    }

    public static var steamSupportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Steam")
    }

    public static var steamCompatToolsDir: URL {
        steamSupportDir.appending(path: "compatibilitytools.d")
    }

    public static var steamCfgFile: URL {
        steamSupportDir.appending(path: "steam.cfg")
    }

    public static var deployedBridgeRecordURL: URL {
        positronSupportDir.appending(path: "bin/deployed-positron-steam.dylib")
    }

    public static func isSteamRunning() -> Bool {
        let check = Process()
        check.executableURL = URL(filePath: "/usr/bin/pgrep")
        check.arguments = ["-x", "steam_osx"]
        try? check.run()
        check.waitUntilExit()
        return check.terminationStatus == 0
    }

    /// Returns true if Positron is integrated into Steam.app but the bundled positron-steam.dylib
    /// inside Positron.app is newer/different than the last dylib deployed into Steam.app.
    public static func isBridgeUpdatePending(
        steamApp: URL = defaultSteamApp,
        resourceURL: URL? = Bundle.main.resourceURL
    ) -> Bool {
        guard inspectState(steamApp: steamApp).isPositronInjected,
              let res = resourceURL else { return false }
        let bundledDylib = res.appending(path: "positron-steam.dylib")
        guard let bundledData = try? Data(contentsOf: bundledDylib) else { return false }
        guard let deployedData = try? Data(contentsOf: deployedBridgeRecordURL) else { return true }
        return bundledData != deployedData
    }

    /// If Positron is enabled in Steam and Steam is currently closed, silently updates
    /// Steam.app's positron-steam.dylib and compatibilitytools.d scripts in the background.
    @discardableResult
    public static func autoUpdateSteamBridgeIfClosed(
        runners: [DiscoveredRunner],
        steamApp: URL = defaultSteamApp
    ) -> Bool {
        guard inspectState(steamApp: steamApp).isPositronInjected,
              isBridgeUpdatePending(steamApp: steamApp),
              !isSteamRunning() else {
            return false
        }
        let blocked = isSteamUpdateBlocked()
        _ = try? installIntoSteam(runners: runners, steamApp: steamApp, blockUpdates: blocked)
        return !isBridgeUpdatePending(steamApp: steamApp)
    }

    public static func inspectState(
        steamApp: URL = defaultSteamApp,
        compatToolsRoot: URL = steamCompatToolsDir
    ) -> SteamIntegrationState {
        let fm = FileManager.default
        guard fm.fileExists(atPath: steamApp.path(percentEncoded: false)) else {
            return .steamMissing
        }

        let entries = (try? fm.contentsOfDirectory(at: compatToolsRoot, includingPropertiesForKeys: nil)) ?? []
        let positronTools = entries.filter { $0.lastPathComponent.hasPrefix("positron-proton-") }.count

        let plistURL = steamApp.appending(path: "Contents/Info.plist")
        if let data = try? Data(contentsOf: plistURL),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let env = dict["LSEnvironment"] as? [String: Any],
           let insert = env["DYLD_INSERT_LIBRARIES"] as? String,
           !insert.isEmpty {
            if insert.contains("positron-steam.dylib") {
                return .positronInstalled(dylibPath: insert, toolsRegistered: positronTools)
            } else {
                return .foreignDylibInstalled(dylibPath: insert)
            }
        }

        return .stockSteam(toolsRegistered: positronTools)
    }

    public static func isSteamUpdateBlocked(cfgURL: URL = steamCfgFile) -> Bool {
        guard let text = try? String(contentsOf: cfgURL, encoding: .utf8) else { return false }
        return text.components(separatedBy: .newlines).contains {
            $0.trimmingCharacters(in: .whitespaces).lowercased() == "bootstrapperinhibitupdateonlaunch=enable"
        }
    }

    public static func setSteamUpdateBlocked(_ blocked: Bool, cfgURL: URL = steamCfgFile) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: cfgURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: cfgURL, encoding: .utf8)) ?? ""
        var lines = existing.components(separatedBy: .newlines).filter {
            !$0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("bootstrapperinhibitupdateonlaunch=")
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        if blocked {
            lines.append("BootStrapperInhibitUpdateOnLaunch=enable")
        }
        let output = lines.isEmpty ? "" : (lines.joined(separator: "\n") + "\n")
        if output.isEmpty {
            try? fm.removeItem(at: cfgURL)
        } else {
            try Data(output.utf8).write(to: cfgURL, options: .atomic)
        }
    }

    /// Stages positron-run and positron-steam.dylib into ~/Library/Application Support/Positron/bin
    public static func stageRuntimeBinaries(
        fromResourceURL resourceURL: URL? = Bundle.main.resourceURL,
        supportDir: URL = positronSupportDir
    ) throws -> (dylib: URL, supervisor: URL) {
        let fm = FileManager.default
        let binDir = supportDir.appending(path: "bin")
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)

        let dstDylib = binDir.appending(path: "positron-steam.dylib")
        let dstSupervisor = binDir.appending(path: "positron-run")

        if let res = resourceURL {
            let srcDylib = res.appending(path: "positron-steam.dylib")
            let srcSup = res.appending(path: "positron-run")
            if fm.fileExists(atPath: srcDylib.path(percentEncoded: false)) {
                try? fm.removeItem(at: dstDylib)
                try fm.copyItem(at: srcDylib, to: dstDylib)
            }
            if fm.fileExists(atPath: srcSup.path(percentEncoded: false)) {
                try? fm.removeItem(at: dstSupervisor)
                try fm.copyItem(at: srcSup, to: dstSupervisor)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstSupervisor.path(percentEncoded: false))
            }
            let srcSigs = res.appending(path: "signatures/macos.arm64")
            let dstSigs = supportDir.appending(path: "signatures/macos.arm64")
            if let sigFiles = try? fm.contentsOfDirectory(at: srcSigs, includingPropertiesForKeys: nil) {
                try fm.createDirectory(at: dstSigs, withIntermediateDirectories: true)
                for sig in sigFiles where sig.pathExtension == "json" {
                    let target = dstSigs.appending(path: sig.lastPathComponent)
                    try? fm.removeItem(at: target)
                    try? fm.copyItem(at: sig, to: target)
                }
            }
            let srcFixes = res.appending(path: "fixes/witcher3")
            let dstFixes = supportDir.appending(path: "fixes/witcher3")
            if let fixFiles = try? fm.contentsOfDirectory(at: srcFixes, includingPropertiesForKeys: nil) {
                try fm.createDirectory(at: dstFixes, withIntermediateDirectories: true)
                for fix in fixFiles {
                    let target = dstFixes.appending(path: fix.lastPathComponent)
                    try? fm.removeItem(at: target)
                    try? fm.copyItem(at: fix, to: target)
                }
            }
        }
        return (dstDylib, dstSupervisor)
    }

    /// Registers all discovered runners directly into Steam's compatibilitytools.d folder.
    public static func registerCompatibilityTools(
        for runners: [DiscoveredRunner],
        in compatToolsRoot: URL = steamCompatToolsDir,
        supervisorBinaryPath: String = "/usr/local/bin/positron-run"
    ) throws -> [RegisteredCompatTool] {
        let fm = FileManager.default
        try fm.createDirectory(at: compatToolsRoot, withIntermediateDirectories: true)

        var registered: [RegisteredCompatTool] = []
        var toolListLines: [String] = []

        let bundledRunURL = Bundle.main.resourceURL?.appending(path: "run")
        for runner in runners where runner.kind != .whiskyWine {
            // Map runner to its patched clone build ID under ~/Library/Application Support/Positron/runners/crossover-<build>
            let runnerBuildID = runner.supportsFEX ? "\(runner.bundleVersion)-fex" : runner.bundleVersion
            for translator in runner.supportedTranslators {
                let toolName = "positron-proton-\(runner.id)-\(translator.rawValue)"
                let displayName = "Positron - \(runner.displayName) [\(translator.rawValue.uppercased())]"
                let toolDir = compatToolsRoot.appending(path: toolName)
                try fm.createDirectory(at: toolDir, withIntermediateDirectories: true)

                let compatVDF = """
                "compatibilitytools"
                {
                  "compat_tools"
                  {
                    "\(toolName)"
                    {
                      "install_path" "."
                      "display_name" "\(displayName)"
                      "from_oslist" "windows"
                      "to_oslist" "macos"
                    }
                  }
                }
                """

                let manifestVDF = """
                "manifest"
                {
                  "version" "2"
                  "commandline" "/run %verb%"
                }
                """

                try Data(compatVDF.utf8).write(to: toolDir.appending(path: "compatibilitytool.vdf"), options: .atomic)
                try Data(manifestVDF.utf8).write(to: toolDir.appending(path: "toolmanifest.vdf"), options: .atomic)
                try Data("\(translator.rawValue)\n".utf8).write(to: toolDir.appending(path: "flavor"), options: .atomic)
                try Data("\(runnerBuildID)\n".utf8).write(to: toolDir.appending(path: "build"), options: .atomic)

                let runURL = toolDir.appending(path: "run")
                if let bundledRunURL, fm.fileExists(atPath: bundledRunURL.path(percentEncoded: false)) {
                    try? fm.removeItem(at: runURL)
                    try fm.copyItem(at: bundledRunURL, to: runURL)
                } else {
                    let fallback = """
                    #!/bin/sh
                    exec "\(supervisorBinaryPath)" "$@"
                    """
                    try Data(fallback.utf8).write(to: runURL, options: .atomic)
                }
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runURL.path(percentEncoded: false))

                registered.append(
                    RegisteredCompatTool(
                        toolName: toolName,
                        displayName: displayName,
                        runnerID: runner.id,
                        translator: translator,
                        toolDirectory: toolDir
                    )
                )
                toolListLines.append("\(toolName)\t\(runnerBuildID)\t\(translator.rawValue)\t\(displayName)")
            }
        }

        if compatToolsRoot.standardizedFileURL == steamCompatToolsDir.standardizedFileURL {
            let supportToolsFile = positronSupportDir.appending(path: "tools")
            try? fm.createDirectory(at: positronSupportDir, withIntermediateDirectories: true)
            let toolsText = toolListLines.joined(separator: "\n") + (toolListLines.isEmpty ? "" : "\n")
            try? Data(toolsText.utf8).write(to: supportToolsFile, options: .atomic)
        }

        return registered
    }

    /// Full Steam.app integration: stages runtime binaries, registers compatibility tools in Steam,
    /// backs up Steam.app/Contents/Info.plist, injects positron-steam.dylib via LSEnvironment,
    /// and ad-hoc signs Steam.app.
    public static func installIntoSteam(
        runners: [DiscoveredRunner],
        steamApp: URL = defaultSteamApp,
        compatToolsRoot: URL = steamCompatToolsDir,
        blockUpdates: Bool = true
    ) throws -> [RegisteredCompatTool] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: steamApp.path(percentEncoded: false)) else {
            throw SteamIntegrationError.steamBundleNotFound(steamApp.path(percentEncoded: false))
        }

        let staged = try stageRuntimeBinaries()
        guard fm.fileExists(atPath: staged.dylib.path(percentEncoded: false)) else {
            throw SteamIntegrationError.bundledArtifactMissing("positron-steam.dylib")
        }

        let tools = try registerCompatibilityTools(
            for: runners,
            in: compatToolsRoot,
            supervisorBinaryPath: staged.supervisor.path(percentEncoded: false)
        )

        let deployedDylib = steamApp.appending(path: "Contents/MacOS/positron-steam.dylib")
        try? fm.removeItem(at: deployedDylib)
        try fm.copyItem(at: staged.dylib, to: deployedDylib)
        try? fm.removeItem(at: deployedBridgeRecordURL)
        try? fm.copyItem(at: staged.dylib, to: deployedBridgeRecordURL)

        let plistURL = steamApp.appending(path: "Contents/Info.plist")
        let backupURL = positronSupportDir.appending(path: "backups/Info.plist.stock")
        if !fm.fileExists(atPath: backupURL.path(percentEncoded: false)) {
            try fm.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: plistURL, to: backupURL)
        }

        guard let rawPlist = try? Data(contentsOf: plistURL),
              var dict = try? PropertyListSerialization.propertyList(from: rawPlist, format: nil) as? [String: Any]
        else {
            throw SteamIntegrationError.infoPlistUnreadable(plistURL.path(percentEncoded: false))
        }

        var env = (dict["LSEnvironment"] as? [String: Any]) ?? [:]
        env["DYLD_INSERT_LIBRARIES"] = deployedDylib.path(percentEncoded: false)
        env["STEAM_EXTRA_COMPAT_TOOLS_PATHS"] = compatToolsRoot.path(percentEncoded: false)
        dict["LSEnvironment"] = env

        let updatedData = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try updatedData.write(to: plistURL, options: .atomic)

        if blockUpdates {
            try setSteamUpdateBlocked(true)
        }

        try signSteamBundle(steamApp, dylib: deployedDylib)
        restartSteamIfRunning(steamApp: steamApp)
        return tools
    }

    /// Non-invasive mode: installs compatibility tools into ~/Library/Application Support/Steam/compatibilitytools.d
    /// and launches Steam with DYLD_INSERT_LIBRARIES without altering /Applications/Steam.app on disk.
    public static func launchSteamNonInvasive(
        runners: [DiscoveredRunner],
        steamApp: URL = defaultSteamApp,
        compatToolsRoot: URL = steamCompatToolsDir
    ) throws -> [RegisteredCompatTool] {
        let staged = try stageRuntimeBinaries()
        let tools = try registerCompatibilityTools(
            for: runners,
            in: compatToolsRoot,
            supervisorBinaryPath: staged.supervisor.path(percentEncoded: false)
        )

        let steamExe = steamApp.appending(path: "Contents/MacOS/steam_osx")
        let proc = Process()
        proc.executableURL = steamExe
        var env = ProcessInfo.processInfo.environment
        env["DYLD_INSERT_LIBRARIES"] = staged.dylib.path(percentEncoded: false)
        env["STEAM_EXTRA_COMPAT_TOOLS_PATHS"] = compatToolsRoot.path(percentEncoded: false)
        proc.environment = env
        try proc.run()
        return tools
    }

    /// Restores /Applications/Steam.app to stock and removes Positron compatibility tools from Steam.
    public static func restoreStockSteam(
        steamApp: URL = defaultSteamApp,
        compatToolsRoot: URL = steamCompatToolsDir
    ) throws {
        let fm = FileManager.default
        let deployedDylib = steamApp.appending(path: "Contents/MacOS/positron-steam.dylib")
        try? fm.removeItem(at: deployedDylib)

        let plistURL = steamApp.appending(path: "Contents/Info.plist")
        let backupURL = positronSupportDir.appending(path: "backups/Info.plist.stock")
        if fm.fileExists(atPath: backupURL.path(percentEncoded: false)) {
            let data = try Data(contentsOf: backupURL)
            try data.write(to: plistURL, options: .atomic)
        } else if let rawPlist = try? Data(contentsOf: plistURL),
                  var dict = try? PropertyListSerialization.propertyList(from: rawPlist, format: nil) as? [String: Any] {
            if var env = dict["LSEnvironment"] as? [String: Any] {
                env.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
                env.removeValue(forKey: "STEAM_EXTRA_COMPAT_TOOLS_PATHS")
                dict["LSEnvironment"] = env.isEmpty ? nil : env
            }
            let updatedData = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try updatedData.write(to: plistURL, options: .atomic)
        }

        if let items = try? fm.contentsOfDirectory(at: compatToolsRoot, includingPropertiesForKeys: nil) {
            for item in items where item.lastPathComponent.hasPrefix("positron-proton-") {
                try? fm.removeItem(at: item)
            }
        }

        try? setSteamUpdateBlocked(false)
        if fm.fileExists(atPath: steamApp.path(percentEncoded: false)) {
            try signSteamBundle(steamApp, dylib: nil)
        }
    }

    public static func registerWithLaunchServices(steamApp: URL = defaultSteamApp) {
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        if FileManager.default.isExecutableFile(atPath: lsregister) {
            let p = Process()
            p.executableURL = URL(filePath: lsregister)
            p.arguments = ["-f", steamApp.path(percentEncoded: false)]
            try? p.run()
            p.waitUntilExit()
        }
    }

    public static func restartSteamIfRunning(steamApp: URL = defaultSteamApp) {
        registerWithLaunchServices(steamApp: steamApp)
        guard isSteamRunning() else { return }

        // Ask Steam to exit cleanly first (SIGTERM), then finish any stragglers after a short grace period.
        _ = try? Process.run(URL(filePath: "/usr/bin/pkill"), arguments: ["-TERM", "-x", "steam_osx"])
        for _ in 0..<12 {
            if !isSteamRunning() { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        if isSteamRunning() {
            _ = try? Process.run(URL(filePath: "/usr/bin/pkill"), arguments: ["-9", "-x", "steam_osx"])
            _ = try? Process.run(URL(filePath: "/usr/bin/pkill"), arguments: ["-9", "-f", "Steam.AppBundle/Steam"])
            Thread.sleep(forTimeInterval: 0.8)
        }
        _ = try? Process.run(URL(filePath: "/usr/bin/open"), arguments: [steamApp.path(percentEncoded: false)])
    }

    /// Applies a GameProfile directly to Steam:
    /// 1. Saves profiles/<appid>.json and profiles/<appid>.env
    /// 2. Updates CompatToolMapping in ~/Library/Application Support/Steam/config/config.vdf
    /// 3. Enqueues <appid>\t<toolName> in ~/Library/Application Support/Positron/pending-apply.tsv
    ///    so a running Steam instance immediately updates CCompatManager and the Steam UI!
    /// Ensures bundled runtime scripts (compat_run.sh) and game-fix DLLs (e.g. fixes/witcher3)
    /// from Positron.app/Contents/Resources are always staged into ~/Library/Application Support/Positron
    /// and ~/Library/Application Support/Steam/compatibilitytools.d.
    public static func syncBundledFixesAndTools(runners: [DiscoveredRunner]) {
        guard Bundle.main.resourceURL != nil else { return }
        if let staged = try? stageRuntimeBinaries() {
            _ = try? registerCompatibilityTools(
                for: runners,
                in: steamCompatToolsDir,
                supervisorBinaryPath: staged.supervisor.path(percentEncoded: false)
            )
        }
    }

    @discardableResult
    public static func applyProfileToSteam(
        _ profile: GameProfile,
        runners: [DiscoveredRunner],
        profileStore: GameProfileStore,
        configVDFURL: URL = steamSupportDir.appending(path: "config/config.vdf")
    ) throws -> String {
        syncBundledFixesAndTools(runners: runners)
        let sanitized = profile.sanitized()
        try profileStore.save(sanitized)
        let toolName = sanitized.resolvedCompatToolName(among: runners)

        // 1. Update config.vdf CompatToolMapping on disk
        if FileManager.default.fileExists(atPath: configVDFURL.path(percentEncoded: false)) {
            try? updateCompatToolMappingInConfigVDF(appID: sanitized.appID, toolName: toolName, configVDFURL: configVDFURL)
        }

        // 2. Queue live apply command for positron-steam.dylib inside running steam_osx
        let pendingURL = positronSupportDir.appending(path: "pending-apply.tsv")
        try FileManager.default.createDirectory(at: positronSupportDir, withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: pendingURL, encoding: .utf8)) ?? ""
        let newLine = "\(sanitized.appID)\t\(toolName)\n"
        try Data((existing + newLine).utf8).write(to: pendingURL, options: .atomic)

        return toolName
    }

    /// Removes a per-game preset from Positron and clears its CompatToolMapping in Steam.
    public static func removeProfileFromSteam(
        appID: UInt32,
        profileStore: GameProfileStore,
        configVDFURL: URL = steamSupportDir.appending(path: "config/config.vdf")
    ) throws {
        profileStore.removeProfile(forAppID: appID)
        if let text = try? String(contentsOf: configVDFURL, encoding: .utf8) {
            let pattern = "\\n?[ \\t]*\"\(appID)\"\\s*\\{[^}]*\\}"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
                if cleaned != text {
                    try? Data(cleaned.utf8).write(to: configVDFURL, options: .atomic)
                }
            }
        }
        let pendingURL = positronSupportDir.appending(path: "pending-apply.tsv")
        try FileManager.default.createDirectory(at: positronSupportDir, withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: pendingURL, encoding: .utf8)) ?? ""
        try Data((existing + "\(appID)\t\n").utf8).write(to: pendingURL, options: .atomic)
    }

    /// Rewrites or inserts an AppID entry inside the "CompatToolMapping" block of Steam's config.vdf.
    public static func updateCompatToolMappingInConfigVDF(
        appID: UInt32,
        toolName: String,
        configVDFURL: URL
    ) throws {
        guard let text = try? String(contentsOf: configVDFURL, encoding: .utf8) else { return }
        let updated = updateCompatToolMappingInVDFText(text, appID: appID, toolName: toolName)
        if updated != text {
            try Data(updated.utf8).write(to: configVDFURL, options: .atomic)
        }
    }

    public static func updateCompatToolMappingInVDFText(
        _ text: String,
        appID: UInt32,
        toolName: String
    ) -> String {
        let appKey = "\"\(appID)\""
        let lines = text.components(separatedBy: "\n")
        guard let mappingIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "\"CompatToolMapping\"" }) else {
            return text
        }
        guard let openBraceIdx = lines[(mappingIdx + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "{" }) else {
            return text
        }

        // Find matching closing brace of CompatToolMapping block
        var depth = 0
        var closeBraceIdx: Int?
        var existingAppIdx: Int?
        var existingAppEndIdx: Int?

        for i in openBraceIdx..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed == "{" {
                depth += 1
            } else if trimmed == "}" {
                depth -= 1
                if depth == 1 && existingAppIdx != nil && existingAppEndIdx == nil {
                    existingAppEndIdx = i
                }
                if depth == 0 {
                    closeBraceIdx = i
                    break
                }
            } else if depth == 1 && trimmed == appKey {
                existingAppIdx = i
            }
        }

        guard let closeIdx = closeBraceIdx else { return text }
        let indent = "\t\t\t\t\t"
        let entryLines = [
            "\(indent)\"\(appID)\"",
            "\(indent){",
            "\(indent)\t\"name\"\t\t\"\(toolName)\"",
            "\(indent)\t\"config\"\t\t\"\"",
            "\(indent)\t\"priority\"\t\t\"250\"",
            "\(indent)}"
        ]

        var result = lines
        if let start = existingAppIdx, let end = existingAppEndIdx, end >= start {
            result.replaceSubrange(start...end, with: entryLines)
        } else {
            result.insert(contentsOf: entryLines, at: closeIdx)
        }
        return result.joined(separator: "\n")
    }

    private static func signSteamBundle(_ steamApp: URL, dylib: URL?) throws {
        func runCodesign(_ target: URL) throws {
            let proc = Process()
            proc.executableURL = URL(filePath: "/usr/bin/codesign")
            proc.arguments = ["-f", "-s", "-", target.path(percentEncoded: false)]
            let pipe = Pipe()
            proc.standardError = pipe
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                let err = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if err.contains("detritus") {
                    _ = try? Process.run(URL(filePath: "/usr/bin/xattr"), arguments: ["-cr", steamApp.path(percentEncoded: false)])
                    let retry = Process()
                    retry.executableURL = URL(filePath: "/usr/bin/codesign")
                    retry.arguments = ["-f", "-s", "-", target.path(percentEncoded: false)]
                    try retry.run()
                    retry.waitUntilExit()
                    if retry.terminationStatus == 0 { return }
                }
                throw SteamIntegrationError.codesignFailed(err.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        if let dylib {
            try runCodesign(dylib)
        }
        let steamOSX = steamApp.appending(path: "Contents/MacOS/steam_osx")
        if FileManager.default.fileExists(atPath: steamOSX.path(percentEncoded: false)) {
            try runCodesign(steamOSX)
        }
        try runCodesign(steamApp)
    }
}

public struct PositronFundingConfig: Codable, Sendable, Equatable {
    public var kofiURL: String
    public var githubSponsorsURL: String
    public var githubRepoURL: String

    public static let defaultConfig = PositronFundingConfig(
        kofiURL: "https://ko-fi.com/rayand",
        githubSponsorsURL: "https://github.com/sponsors/RayAnd",
        githubRepoURL: "https://github.com/RayAnd/Positron"
    )

    public static var configFileURL: URL {
        SteamIntegration.positronSupportDir.appending(path: "funding.json")
    }

    public static func current() -> PositronFundingConfig {
        if let data = try? Data(contentsOf: configFileURL),
           let decoded = try? JSONDecoder().decode(PositronFundingConfig.self, from: data) {
            return decoded
        }
        return defaultConfig
    }
}
