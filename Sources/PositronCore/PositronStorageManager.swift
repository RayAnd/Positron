// SPDX-License-Identifier: MIT
import Darwin
import Foundation

public enum PositronStorageMode: String, Codable, Sendable, Equatable {
    case internalSSD = "internal"
    case externalAPFSFolder = "external-folder"
    case externalSparseBundle = "external-sparsebundle"

    public var displayTitle: String {
        switch self {
        case .internalSSD:
            return "Internal Mac SSD"
        case .externalAPFSFolder:
            return "External APFS Drive Folder"
        case .externalSparseBundle:
            return "External Drive (APFS Sparse Disk Image)"
        }
    }
}

public struct PositronStorageConfig: Codable, Sendable, Equatable {
    public var mode: PositronStorageMode
    /// Path to external folder (for .externalAPFSFolder) or .sparsebundle (for .externalSparseBundle)
    public var externalContainerPath: String?
    /// Where the active APFS storage root lives when mounted (e.g. ~/.mounted-storage or /Volumes/Drive/PositronData)
    public var activeStorageRootPath: String?
    /// Maximum virtual capacity in GB when creating a sparsebundle (grows dynamically, uses only actual file size)
    public var sparseImageMaxGB: Int
    /// Heavy subdirectories managed and symlinked into activeStorageRootPath
    public var managedDirectories: [String]

    public static let defaultManagedDirectories: [String] = [
        "prefixes",
        "runners",
        "external-prefixes",
        "bridge",
        "fonts",
        "launchers",
        "shortcut-icons"
    ]

    public init(
        mode: PositronStorageMode = .internalSSD,
        externalContainerPath: String? = nil,
        activeStorageRootPath: String? = nil,
        sparseImageMaxGB: Int = 512,
        managedDirectories: [String] = PositronStorageConfig.defaultManagedDirectories
    ) {
        self.mode = mode
        self.externalContainerPath = externalContainerPath
        self.activeStorageRootPath = activeStorageRootPath
        self.sparseImageMaxGB = sparseImageMaxGB
        self.managedDirectories = managedDirectories
    }
}

public struct PositronFolderUsage: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let bytes: UInt64

    public init(id: String, label: String, bytes: UInt64) {
        self.id = id
        self.label = label
        self.bytes = bytes
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

public struct PositronStorageSnapshot: Sendable, Equatable {
    public let config: PositronStorageConfig
    public let isDriveConnected: Bool
    public let isMounted: Bool
    public let totalBytes: UInt64
    public let backupBytes: UInt64
    public let availableVolumeBytes: UInt64?
    public let items: [PositronFolderUsage]

    public init(
        config: PositronStorageConfig,
        isDriveConnected: Bool,
        isMounted: Bool,
        totalBytes: UInt64,
        backupBytes: UInt64,
        availableVolumeBytes: UInt64?,
        items: [PositronFolderUsage]
    ) {
        self.config = config
        self.isDriveConnected = isDriveConnected
        self.isMounted = isMounted
        self.totalBytes = totalBytes
        self.backupBytes = backupBytes
        self.availableVolumeBytes = availableVolumeBytes
        self.items = items
    }

    public var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    public var formattedBackups: String {
        ByteCountFormatter.string(fromByteCount: Int64(backupBytes), countStyle: .file)
    }

    public var formattedAvailable: String? {
        guard let avail = availableVolumeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(avail), countStyle: .file)
    }
}

public enum PositronStorageError: LocalizedError {
    case invalidDestination(String)
    case externalDriveDisconnected(String)
    case sparseBundleCreationFailed(String)
    case sparseBundleMountFailed(String)
    case migrationCopyFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .invalidDestination(let msg):
            return "Invalid storage destination: \(msg)"
        case .externalDriveDisconnected(let path):
            return "External storage drive is not connected at \(path)."
        case .sparseBundleCreationFailed(let err):
            return "Could not create APFS sparse disk image: \(err)"
        case .sparseBundleMountFailed(let err):
            return "Could not mount APFS sparse disk image: \(err)"
        case .migrationCopyFailed(let dir, let err):
            return "Failed while migrating '\(dir)': \(err)"
        }
    }
}

public final class PositronMigrationGuard: @unchecked Sendable {
    public static let shared = PositronMigrationGuard()
    private let lock = NSLock()
    private var busy = false

    public var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return busy
    }

    public func setBusy(_ value: Bool) {
        lock.lock()
        busy = value
        lock.unlock()
    }
}

public enum PositronStorageManager {
    public static var supportDir: URL {
        SteamIntegration.positronSupportDir
    }

    public static var configURL: URL {
        supportDir.appending(path: "storage-config.json")
    }

    public static var shellEnvURL: URL {
        supportDir.appending(path: "storage-env.sh")
    }

    public static var defaultMountPointURL: URL {
        supportDir.appending(path: ".mounted-storage")
    }

    public static func loadConfig(from url: URL = configURL) -> PositronStorageConfig {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PositronStorageConfig.self, from: data) else {
            return PositronStorageConfig()
        }
        return decoded
    }

    public static func saveConfig(
        _ config: PositronStorageConfig,
        configFile: URL = configURL,
        shellEnvFile: URL = shellEnvURL
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFile, options: .atomic)

        let shellContent = buildShellEnvContent(for: config)
        try Data(shellContent.utf8).write(to: shellEnvFile, options: .atomic)
    }

    public static func buildShellEnvContent(for config: PositronStorageConfig) -> String {
        guard config.mode != .internalSSD,
              let container = config.externalContainerPath,
              let root = config.activeStorageRootPath else {
            return "# Positron storage: internal SSD\nPOSITRON_STORAGE_MODE=\"internal\"\n"
        }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
             .replacingOccurrences(of: "$", with: "\\$")
             .replacingOccurrences(of: "`", with: "\\`")
        }
        return "# Positron external storage auto-generated config\n" +
               "POSITRON_STORAGE_MODE=\"\(esc(config.mode.rawValue))\"\n" +
               "POSITRON_STORAGE_CONTAINER=\"\(esc(container))\"\n" +
               "POSITRON_STORAGE_ROOT=\"\(esc(root))\"\n"
    }

    /// Checks whether a given mountpoint is currently mounted as a distinct volume from its parent directory.
    public static func isMountPointActive(_ mountURL: URL) -> Bool {
        let path = mountURL.path(percentEncoded: false)
        let parent = mountURL.deletingLastPathComponent().path(percentEncoded: false)
        var stMount = stat()
        var stParent = stat()
        guard stat(path, &stMount) == 0, stat(parent, &stParent) == 0 else {
            return false
        }
        return stMount.st_dev != stParent.st_dev
    }

    /// Ensures external storage (including an APFS sparsebundle on an ExFAT drive) is mounted if the drive is connected.
    @discardableResult
    public static func ensureMounted(config: PositronStorageConfig = loadConfig()) throws -> Bool {
        let fm = FileManager.default
        switch config.mode {
        case .internalSSD:
            return true
        case .externalAPFSFolder:
            guard let root = config.activeStorageRootPath else { return false }
            return fm.fileExists(atPath: root)
        case .externalSparseBundle:
            guard let bundlePath = config.externalContainerPath,
                  let mountPath = config.activeStorageRootPath else { return false }
            let mountURL = URL(filePath: mountPath)
            if isMountPointActive(mountURL) {
                return true
            }
            guard fm.fileExists(atPath: bundlePath) else {
                return false
            }
            try fm.createDirectory(at: mountURL, withIntermediateDirectories: true)
            let (status, err) = runProcess(
                "/usr/bin/hdiutil",
                arguments: ["attach", "-nobrowse", "-mountpoint", mountPath, bundlePath]
            )
            if status != 0 && !isMountPointActive(mountURL) {
                throw PositronStorageError.sparseBundleMountFailed(err)
            }
            return isMountPointActive(mountURL)
        }
    }

    /// Chooses whether a destination URL on an external drive needs an APFS .sparsebundle (ExFAT/NTFS/FAT)
    /// or can use a direct APFS folder (or attaches an existing .sparsebundle if selected directly).
    public static func resolvePlan(
        for selectedURL: URL,
        preferSparseBundle: Bool = false,
        maxSizeGB: Int = 512,
        mountPointURL: URL = defaultMountPointURL
    ) throws -> PositronStorageConfig {
        let standardized = selectedURL.standardizedFileURL
        let rawPath = standardized.path(percentEncoded: false)
        if rawPath == "/" || rawPath.hasPrefix(supportDir.standardizedFileURL.path(percentEncoded: false)) {
            throw PositronStorageError.invalidDestination("Choose an external drive or a folder outside Positron's internal support directory.")
        }

        if standardized.pathExtension.lowercased() == "sparsebundle" || standardized.pathExtension.lowercased() == "sparseimage" {
            return PositronStorageConfig(
                mode: .externalSparseBundle,
                externalContainerPath: rawPath,
                activeStorageRootPath: mountPointURL.path(percentEncoded: false),
                sparseImageMaxGB: maxSizeGB
            )
        }

        let volInfo = SteamLibraryDiscovery.inspectVolume(at: standardized)
        if preferSparseBundle || volInfo.needsShadow || volInfo.fsType.uppercased() != "APFS" {
            let bundleURL = standardized.appending(path: "PositronStorage.sparsebundle")
            return PositronStorageConfig(
                mode: .externalSparseBundle,
                externalContainerPath: bundleURL.path(percentEncoded: false),
                activeStorageRootPath: mountPointURL.path(percentEncoded: false),
                sparseImageMaxGB: maxSizeGB
            )
        } else {
            let folderURL = standardized.lastPathComponent == "PositronStorage"
                ? standardized
                : standardized.appending(path: "PositronStorage")
            return PositronStorageConfig(
                mode: .externalAPFSFolder,
                externalContainerPath: folderURL.path(percentEncoded: false),
                activeStorageRootPath: folderURL.path(percentEncoded: false),
                sparseImageMaxGB: maxSizeGB
            )
        }
    }

    /// Relocates all heavy Positron directories (prefixes, runners, bridge, fonts, launchers, icons)
    /// onto the selected external drive (creating & mounting an APFS .sparsebundle automatically on ExFAT),
    /// replaces the internal folders with symlinks, and frees the internal SSD space.
    public static func relocateStorage(
        to destinationURL: URL,
        preferSparseBundle: Bool = false,
        maxImageSizeGB: Int = 512,
        baseSupportDir: URL = supportDir,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) throws -> PositronStorageConfig {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: "Positron External Storage Migration"
        )
        PositronMigrationGuard.shared.setBusy(true)
        defer {
            PositronMigrationGuard.shared.setBusy(false)
            ProcessInfo.processInfo.endActivity(activity)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: baseSupportDir, withIntermediateDirectories: true)

        let mountURL = baseSupportDir.appending(path: ".mounted-storage")
        let plan = try resolvePlan(
            for: destinationURL,
            preferSparseBundle: preferSparseBundle,
            maxSizeGB: maxImageSizeGB,
            mountPointURL: mountURL
        )

        guard let containerPath = plan.externalContainerPath,
              let targetRootPath = plan.activeStorageRootPath else {
            throw PositronStorageError.invalidDestination("Missing container path.")
        }

        stopAllRunningWineServers()

        // 1. Create or attach the external APFS sparsebundle / folder
        if plan.mode == .externalSparseBundle {
            onProgress?("Preparing APFS Sparse Disk Image on \(destinationURL.lastPathComponent)…")
            if isMountPointActive(mountURL) {
                _ = runProcess("/usr/bin/hdiutil", arguments: ["detach", mountURL.path(percentEncoded: false), "-force"])
            }
            if !fm.fileExists(atPath: containerPath) {
                try fm.createDirectory(
                    at: URL(filePath: containerPath).deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let (st, err) = runProcess(
                    "/usr/bin/hdiutil",
                    arguments: [
                        "create",
                        "-size", "\(plan.sparseImageMaxGB)g",
                        "-type", "SPARSEBUNDLE",
                        "-fs", "APFS",
                        "-volname", "PositronStorage",
                        containerPath
                    ]
                )
                if st != 0 {
                    throw PositronStorageError.sparseBundleCreationFailed(err)
                }
            }
            _ = try ensureMounted(config: plan)
        } else {
            try fm.createDirectory(atPath: targetRootPath, withIntermediateDirectories: true)
        }

        let targetRootURL = URL(filePath: targetRootPath).standardizedFileURL

        // 2. Migrate each heavy directory via atomic .migrating-<dir> staging (preserving Wine hardlinks!)
        let totalSteps = plan.managedDirectories.count
        for (idx, dirName) in plan.managedDirectories.enumerated() {
            let stepLabel = "Step \(idx + 1)/\(totalSteps): Moving \(dirName)"
            onProgress?("\(stepLabel)…")

            let localEntry = baseSupportDir.appending(path: dirName)
            let localPath = localEntry.path(percentEncoded: false)
            let remoteDir = targetRootURL.appending(path: dirName)
            let remotePath = remoteDir.path(percentEncoded: false)
            let remoteStaging = targetRootURL.appending(path: ".migrating-\(dirName)")

            // Clean up any leftover staging directory from a previously interrupted copy
            try? fm.removeItem(at: remoteStaging)

            var isSymlink = false
            var exists = false
            var lstatBuf = stat()
            if lstat(localPath, &lstatBuf) == 0 {
                exists = true
                isSymlink = (lstatBuf.st_mode & S_IFMT) == S_IFLNK
            }

            if isSymlink {
                let resolvedOld = localEntry.resolvingSymlinksInPath().standardizedFileURL
                if resolvedOld != remoteDir, fm.fileExists(atPath: resolvedOld.path(percentEncoded: false)) {
                    try fm.createDirectory(at: remoteStaging, withIntermediateDirectories: true)
                    try copyDirectoryPreservingHardlinks(
                        from: resolvedOld,
                        to: remoteStaging,
                        stepLabel: stepLabel,
                        onProgress: onProgress
                    )
                    try? fm.removeItem(at: remoteDir)
                    try fm.moveItem(at: remoteStaging, to: remoteDir)
                } else {
                    try fm.createDirectory(at: remoteDir, withIntermediateDirectories: true)
                }
                try? fm.removeItem(atPath: localPath)
            } else if exists {
                try fm.createDirectory(at: remoteStaging, withIntermediateDirectories: true)
                try copyDirectoryPreservingHardlinks(
                    from: localEntry,
                    to: remoteStaging,
                    stepLabel: stepLabel,
                    onProgress: onProgress
                )
                try? fm.removeItem(at: remoteDir)
                try fm.moveItem(at: remoteStaging, to: remoteDir)
                try fm.removeItem(atPath: localPath)
            } else {
                try fm.createDirectory(at: remoteDir, withIntermediateDirectories: true)
            }

            try fm.createSymbolicLink(atPath: localPath, withDestinationPath: remotePath)
        }

        try saveConfig(
            plan,
            configFile: baseSupportDir.appending(path: "storage-config.json"),
            shellEnvFile: baseSupportDir.appending(path: "storage-env.sh")
        )
        return plan
    }

    /// Moves all Positron support files from external storage back onto the internal Mac SSD
    /// and detaches any mounted sparsebundle.
    public static func moveBackToInternalSSD(
        baseSupportDir: URL = supportDir,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) throws {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled, .suddenTerminationDisabled],
            reason: "Positron Restore Storage to Internal SSD"
        )
        PositronMigrationGuard.shared.setBusy(true)
        defer {
            PositronMigrationGuard.shared.setBusy(false)
            ProcessInfo.processInfo.endActivity(activity)
        }
        let fm = FileManager.default
        let current = loadConfig(from: baseSupportDir.appending(path: "storage-config.json"))
        guard current.mode != .internalSSD else { return }

        let mounted = try ensureMounted(config: current)
        if !mounted {
            throw PositronStorageError.externalDriveDisconnected(current.externalContainerPath ?? "External Drive")
        }

        stopAllRunningWineServers()

        for dirName in current.managedDirectories {
            let localEntry = baseSupportDir.appending(path: dirName)
            let localPath = localEntry.path(percentEncoded: false)
            var lstatBuf = stat()
            guard lstat(localPath, &lstatBuf) == 0 else { continue }
            let isSymlink = (lstatBuf.st_mode & S_IFMT) == S_IFLNK
            guard isSymlink else { continue }

            let resolvedSource = localEntry.resolvingSymlinksInPath()
            let stagingLocal = baseSupportDir.appending(path: ".restoring-\(dirName)")
            try? fm.removeItem(at: stagingLocal)
            try fm.createDirectory(at: stagingLocal, withIntermediateDirectories: true)

            if fm.fileExists(atPath: resolvedSource.path(percentEncoded: false)) {
                do {
                    try copyDirectoryPreservingHardlinks(
                        from: resolvedSource,
                        to: stagingLocal,
                        stepLabel: "Restoring \(dirName) to Internal SSD",
                        onProgress: onProgress
                    )
                } catch {
                    try? fm.removeItem(at: stagingLocal)
                    throw error
                }
            }
            try fm.removeItem(atPath: localPath)
            try fm.moveItem(at: stagingLocal, to: localEntry)
        }

        if current.mode == .externalSparseBundle, let mountPath = current.activeStorageRootPath {
            _ = runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPath, "-force"])
        }

        let reset = PositronStorageConfig(mode: .internalSSD)
        try saveConfig(
            reset,
            configFile: baseSupportDir.appending(path: "storage-config.json"),
            shellEnvFile: baseSupportDir.appending(path: "storage-env.sh")
        )
    }

    /// Reclaims unused space from PositronStorage.sparsebundle using hdiutil compact.
    public static func compactSparseBundle(baseSupportDir: URL = supportDir) throws {
        let current = loadConfig(from: baseSupportDir.appending(path: "storage-config.json"))
        guard current.mode == .externalSparseBundle,
              let bundlePath = current.externalContainerPath,
              let mountPath = current.activeStorageRootPath else { return }

        stopAllRunningWineServers()
        if isMountPointActive(URL(filePath: mountPath)) {
            _ = runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPath, "-force"])
        }
        let (st, err) = runProcess("/usr/bin/hdiutil", arguments: ["compact", bundlePath, "-batteryallowed"])
        _ = try? ensureMounted(config: current)
        if st != 0 {
            throw PositronStorageError.sparseBundleMountFailed(err)
        }
    }

    /// Removes old prefix backup folders (pfx.previous-* and steamuser.snapshot.*) to reclaim gigabytes of space.
    @discardableResult
    public static func cleanupOldPrefixBackups(baseSupportDir: URL = supportDir) -> UInt64 {
        let fm = FileManager.default
        let prefixesDir = baseSupportDir.appending(path: "prefixes").resolvingSymlinksInPath()
        guard let appDirs = try? fm.contentsOfDirectory(at: prefixesDir, includingPropertiesForKeys: nil) else {
            return 0
        }
        var freed: UInt64 = 0
        for appDir in appDirs {
            guard let items = try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                let name = item.lastPathComponent
                if name.hasPrefix("pfx.previous-") || name.hasPrefix("steamuser.snapshot.") {
                    freed += directoryLogicalSize(at: item)
                    try? fm.removeItem(at: item)
                }
            }
        }
        return freed
    }

    /// Computes a storage usage breakdown across Positron's directories without hanging on unplugged volumes.
    public static func inspectStorage(baseSupportDir: URL = supportDir) -> PositronStorageSnapshot {
        let fm = FileManager.default
        let config = loadConfig(from: baseSupportDir.appending(path: "storage-config.json"))

        let isConnected: Bool
        let isMounted: Bool
        switch config.mode {
        case .internalSSD:
            isConnected = true
            isMounted = true
        case .externalAPFSFolder:
            let p = config.activeStorageRootPath ?? ""
            isConnected = !p.isEmpty && fm.fileExists(atPath: p)
            isMounted = isConnected
        case .externalSparseBundle:
            let c = config.externalContainerPath ?? ""
            let m = config.activeStorageRootPath ?? ""
            isConnected = !c.isEmpty && fm.fileExists(atPath: c)
            isMounted = !m.isEmpty && isMountPointActive(URL(filePath: m))
        }

        let labels: [(String, String)] = [
            ("prefixes", "Game Wine Prefixes"),
            ("runners", "CrossOver / Wine Runtimes"),
            ("external-prefixes", "External Shadow Prefixes"),
            ("bridge", "Steam Bridge & DLLs"),
            ("fonts", "Windows Fonts Cache"),
            ("launchers", "Game Launcher Bundles & Icons"),
            ("profiles", "Presets & Profiles")
        ]

        var items: [PositronFolderUsage] = []
        var total: UInt64 = 0
        for (dir, label) in labels {
            let url = baseSupportDir.appending(path: dir).resolvingSymlinksInPath()
            let size = (isMounted || config.mode == .internalSSD) ? directoryDiskSize(at: url) : 0
            total += size
            items.append(PositronFolderUsage(id: dir, label: label, bytes: size))
        }

        // Measure reclaimable pfx.previous-* / steamuser.snapshot.* backups
        var backupBytes: UInt64 = 0
        if isMounted || config.mode == .internalSSD {
            let prefixesDir = baseSupportDir.appending(path: "prefixes").resolvingSymlinksInPath()
            if let appDirs = try? fm.contentsOfDirectory(at: prefixesDir, includingPropertiesForKeys: nil) {
                for appDir in appDirs {
                    if let subs = try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: nil) {
                        for sub in subs {
                            let n = sub.lastPathComponent
                            if n.hasPrefix("pfx.previous-") || n.hasPrefix("steamuser.snapshot.") {
                                backupBytes += directoryDiskSize(at: sub)
                            }
                        }
                    }
                }
            }
        }

        // Free space on the backing volume (for sparsebundle, check the external drive hosting the .sparsebundle!)
        let freeSpaceProbeURL: URL
        if let container = config.externalContainerPath, config.mode != .internalSSD {
            freeSpaceProbeURL = URL(filePath: container).deletingLastPathComponent()
        } else {
            freeSpaceProbeURL = baseSupportDir
        }
        let avail = try? freeSpaceProbeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
            .map { UInt64(max(0, $0)) }

        return PositronStorageSnapshot(
            config: config,
            isDriveConnected: isConnected,
            isMounted: isMounted,
            totalBytes: total,
            backupBytes: backupBytes,
            availableVolumeBytes: avail ?? nil,
            items: items.sorted { $0.bytes > $1.bytes }
        )
    }

    /// Uses fast physical block accounting (du -sk) so APFS clonefile hardlinks are counted accurately without hanging.
    private static func directoryDiskSize(at url: URL) -> UInt64 {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let proc = Process()
        proc.executableURL = URL(filePath: "/usr/bin/du")
        proc.arguments = ["-sk", path]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            if let line = String(data: data, encoding: .utf8)?.split(whereSeparator: \.isWhitespace).first,
               let kb = UInt64(line) {
                return kb * 1024
            }
        } catch {}
        return directoryLogicalSize(at: url)
    }

    private static func directoryLogicalSize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: []
        ) else { return 0 }
        var sum: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let vals = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
                sum += UInt64(vals.totalFileAllocatedSize ?? vals.fileAllocatedSize ?? 0)
            }
        }
        return sum
    }

    /// Streams directory contents using bsdtar so Wine template hardlinks (ln -h), symlinks, and permissions
    /// are preserved 1:1 (avoiding multi-GB hardlink duplication) while reporting live copied size!
    private static func copyDirectoryPreservingHardlinks(
        from srcURL: URL,
        to dstURL: URL,
        stepLabel: String,
        onProgress: (@Sendable (String) -> Void)?
    ) throws {
        let srcPath = srcURL.path(percentEncoded: false)
        let dstPath = dstURL.path(percentEncoded: false)
        let proc = Process()
        proc.executableURL = URL(filePath: "/bin/sh")
        proc.arguments = [
            "-c",
            "/usr/bin/tar --no-mac-metadata -cf - -C \"$1\" . | /usr/bin/tar -xpf - -C \"$2\"",
            "positron-copy",
            srcPath,
            dstPath
        ]
        let errPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = errPipe
        try proc.run()

        while proc.isRunning {
            Thread.sleep(forTimeInterval: 1.0)
            if proc.isRunning, let onProgress {
                let copied = directoryDiskSize(at: dstURL)
                if copied > 0 {
                    let fmt = ByteCountFormatter.string(fromByteCount: Int64(copied), countStyle: .file)
                    onProgress("\(stepLabel) — \(fmt) copied… Keep drive connected.")
                }
            }
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "tar exit \(proc.terminationStatus)"
            throw PositronStorageError.migrationCopyFailed(srcURL.lastPathComponent, errText)
        }
    }

    private static func stopAllRunningWineServers() {
        _ = runProcess("/usr/bin/pkill", arguments: ["-TERM", "-x", "wineserver"])
        _ = runProcess("/usr/bin/pkill", arguments: ["-TERM", "-x", "wineserver-arm64"])
        _ = runProcess("/usr/bin/pkill", arguments: ["-TERM", "-x", "wineserver-x86"])
        Thread.sleep(forTimeInterval: 0.4)
    }

    private static func runProcess(_ executable: String, arguments: [String]) -> (Int32, String) {
        let proc = Process()
        proc.executableURL = URL(filePath: executable)
        proc.arguments = arguments
        let errPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = errPipe
        do {
            try proc.run()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (proc.terminationStatus, errText)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
