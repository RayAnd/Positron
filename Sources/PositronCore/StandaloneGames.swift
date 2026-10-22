// SPDX-License-Identifier: MIT
import Foundation

/// A Windows game installed outside Steam. Positron launches it through the same compatibility
/// tool and per-game preset (profiles/<id>.env) that Steam games use.
public struct StandaloneGame: Codable, Sendable, Identifiable, Equatable {
    public let id: UInt32
    public var title: String
    public var executablePath: String
    public var arguments: [String]

    public init(id: UInt32, title: String, executablePath: String, arguments: [String] = []) {
        self.id = id
        self.title = title
        self.executablePath = executablePath
        self.arguments = arguments
    }

    public var executableURL: URL { URL(filePath: executablePath) }
    public var gameDirectoryPath: String { (executablePath as NSString).deletingLastPathComponent }
    public var gameDirectory: URL { URL(filePath: gameDirectoryPath) }
}

public enum StandaloneGameError: LocalizedError {
    case notAWindowsExecutable(String)
    case executableMissing(String)
    case compatToolMissing(String)

    public var errorDescription: String? {
        switch self {
        case .notAWindowsExecutable(let path): return "\(path) is not a Windows .exe file."
        case .executableMissing(let path): return "The game executable is missing at \(path)."
        case .compatToolMissing(let tool): return "The Positron compatibility tool \(tool) is not installed. Open Steam Setup and enable Positron."
        }
    }
}

public enum StandaloneGameStore {
    /// Virtual AppIDs sit far above real Steam AppIDs and below Steam's shortcut range (bit 31 set).
    public static let virtualIDRange: ClosedRange<UInt32> = 1_000_000_000...1_999_999_999

    public static var storeURL: URL {
        SteamIntegration.positronSupportDir.appending(path: "standalone-games.json")
    }

    public static func isVirtualAppID(_ appID: UInt32) -> Bool {
        virtualIDRange.contains(appID)
    }

    /// Stable ID derived from the executable path (FNV-1a).
    public static func virtualAppID(forExecutablePath path: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in URL(filePath: path).standardizedFileURL.path(percentEncoded: false).utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return virtualIDRange.lowerBound + hash % 1_000_000_000
    }

    /// Steam's game ID form for a shortcut. compat_run.sh recognises it and treats the launch
    /// like a non-Steam shortcut (no SteamAppId for the game to check ownership against).
    public static func shortcutGameID(for appID: UInt32) -> UInt64 {
        (UInt64(appID) << 32) | 0x0200_0000
    }

    public static func load(from url: URL = storeURL) -> [StandaloneGame] {
        guard let data = try? Data(contentsOf: url),
              let games = try? JSONDecoder().decode([StandaloneGame].self, from: data) else {
            return []
        }
        return games
    }

    public static func save(_ games: [StandaloneGame], to url: URL = storeURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(games).write(to: url, options: .atomic)
    }

    @discardableResult
    public static func add(executable: URL, title: String? = nil, to url: URL = storeURL) throws -> StandaloneGame {
        let path = executable.standardizedFileURL.path(percentEncoded: false)
        guard executable.pathExtension.lowercased() == "exe" else {
            throw StandaloneGameError.notAWindowsExecutable(path)
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw StandaloneGameError.executableMissing(path)
        }
        var games = load(from: url)
        if let existing = games.first(where: { $0.executablePath == path }) {
            return existing
        }
        var id = virtualAppID(forExecutablePath: path)
        while games.contains(where: { $0.id == id }) {
            id = id == virtualIDRange.upperBound ? virtualIDRange.lowerBound : id + 1
        }
        let game = StandaloneGame(
            id: id,
            title: title ?? executable.deletingPathExtension().lastPathComponent,
            executablePath: path
        )
        games.append(game)
        try save(games, to: url)
        return game
    }

    public static func remove(id: UInt32, from url: URL = storeURL) throws {
        try save(load(from: url).filter { $0.id != id }, to: url)
    }

    public static func compatDataURL(for game: StandaloneGame) -> URL {
        SteamIntegration.positronSupportDir.appending(path: "prefixes/\(game.id)")
    }

    public static func launchEnvironment(
        for game: StandaloneGame,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var env = base
        env["STEAM_COMPAT_APP_ID"] = String(game.id)
        env["STEAM_COMPAT_DATA_PATH"] = compatDataURL(for: game).path(percentEncoded: false)
        env["STEAM_COMPAT_INSTALL_PATH"] = game.gameDirectoryPath
        env["STEAM_COMPAT_CLIENT_INSTALL_PATH"] = SteamIntegration.steamSupportDir
            .appending(path: "Steam.AppBundle/Steam/Contents/MacOS").path(percentEncoded: false)
        env["SteamGameId"] = String(shortcutGameID(for: game.id))
        env.removeValue(forKey: "SteamAppId")
        return env
    }

    /// Starts the game through compatibilitytools.d/<toolName>/run, exactly as Steam would.
    @discardableResult
    public static func launch(
        _ game: StandaloneGame,
        toolName: String,
        compatToolsRoot: URL = SteamIntegration.steamCompatToolsDir
    ) throws -> Process {
        let fm = FileManager.default
        guard fm.fileExists(atPath: game.executablePath) else {
            throw StandaloneGameError.executableMissing(game.executablePath)
        }
        let runScript = compatToolsRoot.appending(path: "\(toolName)/run")
        guard fm.isExecutableFile(atPath: runScript.path(percentEncoded: false)) else {
            throw StandaloneGameError.compatToolMissing(toolName)
        }
        try fm.createDirectory(at: compatDataURL(for: game), withIntermediateDirectories: true)
        let proc = Process()
        proc.executableURL = runScript
        proc.arguments = ["waitforexitandrun", game.executablePath] + game.arguments
        proc.environment = launchEnvironment(for: game)
        proc.currentDirectoryURL = game.gameDirectory
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        return proc
    }
}
