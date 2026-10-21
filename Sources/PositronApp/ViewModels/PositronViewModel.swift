// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

public enum PositronSection: String, CaseIterable, Identifiable {
    case installedGames = "Installed Games"
    case steamSetup = "Steam Setup"
    case engines = "Translation Engines"
    case drives = "Steam Drives"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .installedGames: return "Presets & Wine Prefixes"
        case .steamSetup: return "Bridge & Update Lock"
        case .engines: return "CrossOver & Wine Runtimes"
        case .drives: return "APFS & External Libraries"
        }
    }

    public var icon: String {
        switch self {
        case .installedGames: return "gamecontroller.fill"
        case .steamSetup: return "bolt.shield.fill"
        case .engines: return "cpu.fill"
        case .drives: return "externaldrive.fill.badge.checkmark"
        }
    }
}

public enum GameListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case activePreset = "Configured"
    case prefixReady = "Prefix Ready"

    public var id: String { rawValue }
}


@MainActor
@Observable
final class PositronViewModel {
    var selectedSection: PositronSection = .installedGames
    var runners: [DiscoveredRunner] = []
    var libraries: [SteamLibraryFolder] = []
    var prefixes: [DiscoveredPrefix] = []
    var installedApps: [UInt32: String] = [:]
    var registeredTools: [RegisteredCompatTool] = []
    var steamState: SteamIntegrationState = SteamIntegration.inspectState()

    var selectedAppID: UInt32 = 1151340
    var editingProfile: GameProfile = GameQuirksDatabase.defaultProfile(forAppID: 1151340)
    var statusBanner: String = "Ready"
    var isSteamInstalled: Bool = false
    var blockSteamUpdates: Bool = true
    var searchQuery: String = ""
    var gameFilter: GameListFilter = .all
    var customLibraryPaths: [String] = []
    var overrideColorScheme: ColorScheme? = nil

    let profileStore: GameProfileStore

    init() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Positron")
        self.profileStore = GameProfileStore(storageDirectory: support)
        self.customLibraryPaths = UserDefaults.standard.stringArray(forKey: "PositronCustomSteamLibraries") ?? []
        _ = GameQuirksDatabase.loadCustomCatalog()
        refreshAll()
    }

    var installedGamesList: [GamePresetInfo] {
        var items: [GamePresetInfo] = []
        var seenAppIDs: Set<UInt32> = []
        for (appID, installedTitle) in installedApps {
            guard !seenAppIDs.contains(appID) else { continue }
            seenAppIDs.insert(appID)
            if let curated = GameQuirksDatabase.presetInfo(forAppID: appID) {
                items.append(curated)
            } else {
                let detected = SteamLibraryDiscovery.autoDetectPreset(forAppID: appID, title: installedTitle, in: libraries)
                items.append(detected.info)
            }
        }
        items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let filteredByChip = items.filter { game in
            switch gameFilter {
            case .all:
                return true
            case .activePreset:
                return hasAppliedPreset(for: game.appID)
            case .prefixReady:
                return isPrefixInitialized(for: game.appID)
            }
        }

        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return filteredByChip }
        return filteredByChip.filter {
            $0.title.lowercased().contains(q) ||
            $0.subtitle.lowercased().contains(q) ||
            String($0.appID).contains(q)
        }
    }

    var selectedPresetInfo: GamePresetInfo {
        if let curated = GameQuirksDatabase.presetInfo(forAppID: selectedAppID) {
            return curated
        }
        let title = installedApps[selectedAppID] ?? "Steam Game (\(selectedAppID))"
        return SteamLibraryDiscovery.autoDetectPreset(forAppID: selectedAppID, title: title, in: libraries).info
    }

    var recommendedProfileForSelected: GameProfile {
        let fallback: CPUTranslator = runners.contains(where: \.supportsFEX) ? .fex : .rosetta
        if GameQuirksDatabase.presetInfo(forAppID: selectedAppID) != nil {
            return GameQuirksDatabase.defaultProfile(forAppID: selectedAppID, preferredTranslator: fallback)
        } else {
            let title = installedApps[selectedAppID] ?? "Steam Game \(selectedAppID)"
            return SteamLibraryDiscovery.autoDetectPreset(forAppID: selectedAppID, title: title, in: libraries).recommendedProfile
        }
    }

    var isEditingMatchingRecommended: Bool {
        let rec = recommendedProfileForSelected.sanitized()
        let cur = editingProfile.sanitized()
        return cur.translator == rec.translator &&
            cur.graphics == rec.graphics &&
            cur.retinaMode == rec.retinaMode &&
            cur.disableHidraw == rec.disableHidraw
    }

    func saveCurrentGameToPresetsCatalog() {
        let entry = PresetCatalogEntry(info: selectedPresetInfo, recommendedProfile: editingProfile.sanitized())
        do {
            try GameQuirksDatabase.saveToCustomCatalog(entry)
            statusBanner = "Saved \(selectedPresetInfo.title) into presets-catalog.json."
        } catch {
            statusBanner = "Could not save to presets-catalog.json: \(error.localizedDescription)"
        }
    }

    func openPresetsCatalogJSON() {
        _ = GameQuirksDatabase.loadCustomCatalog()
        NSWorkspace.shared.open(GameQuirksDatabase.customCatalogURL)
    }

    var selectedGamePrefix: DiscoveredPrefix {
        PrefixManager.resolvePrefix(
            forAppID: selectedAppID,
            gameTitle: selectedPresetInfo.title,
            libraries: libraries,
            existingPrefixes: prefixes
        )
    }

    func isPrefixInitialized(for appID: UInt32) -> Bool {
        let pfx = PrefixManager.resolvePrefix(
            forAppID: appID,
            gameTitle: installedApps[appID],
            libraries: libraries,
            existingPrefixes: prefixes
        )
        return FileManager.default.fileExists(atPath: pfx.driveCURL.path(percentEncoded: false))
    }

    func refreshAll() {
        isSteamInstalled = FileManager.default.fileExists(atPath: "/Applications/Steam.app")
        steamState = SteamIntegration.inspectState()
        blockSteamUpdates = SteamIntegration.isSteamUpdateBlocked()
        runners = RunnerDiscovery.discoverAll()
        libraries = SteamLibraryDiscovery.discoverLibraries(extraLibraryPaths: customLibraryPaths)
        installedApps = SteamLibraryDiscovery.discoverInstalledApps(in: libraries)
        prefixes = PrefixManager.discoverSteamPrefixes(libraries: libraries, includePositronShadowRoot: true)
        if installedApps[selectedAppID] == nil, let firstID = installedApps.keys.sorted().first {
            selectedAppID = firstID
        }
        loadProfile(for: selectedAppID)
        let extCount = libraries.filter(\.isExternal).count
        statusBanner = "\(steamState.summaryLabel) • \(installedApps.count) Windows Game(s) across \(libraries.count) Drive(s) (\(extCount) External)"
    }

    func addExternalSteamLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Steam Library"
        panel.message = "Select a SteamLibrary folder on an external drive (containing a steamapps folder)."
        panel.directoryURL = URL(filePath: "/Volumes")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path(percentEncoded: false)
        if !customLibraryPaths.contains(path) {
            customLibraryPaths.append(path)
            UserDefaults.standard.set(customLibraryPaths, forKey: "PositronCustomSteamLibraries")
        }
        refreshAll()
        statusBanner = "Added Steam Library at \(path)"
    }

    func enableInSteam() {
        do {
            registeredTools = try SteamIntegration.installIntoSteam(
                runners: runners,
                blockUpdates: blockSteamUpdates
            )
            steamState = SteamIntegration.inspectState()
            blockSteamUpdates = SteamIntegration.isSteamUpdateBlocked()
            statusBanner = "Positron enabled in Steam with \(registeredTools.count) compatibility tool(s)."
        } catch {
            statusBanner = "Could not enable in Steam: \(error.localizedDescription)"
        }
    }

    func launchSteamTemporaryMode() {
        do {
            registeredTools = try SteamIntegration.launchSteamNonInvasive(runners: runners)
            steamState = SteamIntegration.inspectState()
            statusBanner = "Launched Steam with Positron active."
        } catch {
            statusBanner = "Could not launch Steam: \(error.localizedDescription)"
        }
    }

    func disableAndRestoreSteam() {
        do {
            try SteamIntegration.restoreStockSteam()
            registeredTools = []
            steamState = SteamIntegration.inspectState()
            blockSteamUpdates = SteamIntegration.isSteamUpdateBlocked()
            statusBanner = "Restored Steam.app to stock settings."
        } catch {
            statusBanner = "Restore failed: \(error.localizedDescription)"
        }
    }

    func toggleUpdateBlock(_ enabled: Bool) {
        do {
            try SteamIntegration.setSteamUpdateBlocked(enabled)
            blockSteamUpdates = SteamIntegration.isSteamUpdateBlocked()
            statusBanner = blockSteamUpdates
                ? "Steam self-update lock enabled (steam.cfg)."
                : "Steam self-update lock disabled."
        } catch {
            statusBanner = "Could not update steam.cfg: \(error.localizedDescription)"
        }
    }

    func loadProfile(for appID: UInt32) {
        selectedAppID = appID
        let fallback: CPUTranslator = runners.contains(where: \.supportsFEX) ? .fex : .rosetta
        editingProfile = profileStore.load(forAppID: appID, fallbackTranslator: fallback)
        if editingProfile.runnerID == nil {
            editingProfile.runnerID = runners.first?.id
        }
    }

    func hasAppliedPreset(for appID: UInt32) -> Bool {
        profileStore.hasSavedProfile(forAppID: appID)
    }

    func resetToRecommendedProfile() {
        editingProfile = recommendedProfileForSelected
        if editingProfile.runnerID == nil {
            editingProfile.runnerID = runners.first?.id
        }
        statusBanner = "Loaded recommended profile for \(selectedPresetInfo.title). Click 'Apply Preset to Steam' to activate."
    }

    func applySuggestedProfileToSteam() {
        resetToRecommendedProfile()
        saveCurrentProfile()
    }

    func saveCurrentProfile() {
        editingProfile = editingProfile.sanitized()
        do {
            let toolName = try SteamIntegration.applyProfileToSteam(
                editingProfile,
                runners: runners,
                profileStore: profileStore
            )
            statusBanner = "Applied \(selectedPresetInfo.title) to Steam → \(toolName) (\(editingProfile.graphics.rawValue.uppercased()))."
        } catch {
            statusBanner = "Failed to apply preset to Steam: \(error.localizedDescription)"
        }
    }

    func removeCurrentProfileFromSteam() {
        do {
            try SteamIntegration.removeProfileFromSteam(appID: selectedAppID, profileStore: profileStore)
            statusBanner = "Removed Positron preset override for \(selectedPresetInfo.title) in Steam."
        } catch {
            statusBanner = "Failed to remove preset: \(error.localizedDescription)"
        }
    }

    func addManualRunnerBundle() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Engine"
        panel.message = "Select a CrossOver.app bundle or custom Wine folder."
        panel.directoryURL = URL(filePath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let cxRoot = url.pathExtension == "app"
            ? url.appending(path: "Contents/SharedSupport/CrossOver")
            : url
        if let inspected = (url.pathExtension == "app"
            ? RunnerDiscovery.inspectCrossOverBundle(appURL: url, cxRoot: cxRoot)
            : RunnerDiscovery.inspectCustomWineRoot(
                rootURL: url,
                id: "custom-\(url.lastPathComponent.lowercased())",
                displayName: "Custom Wine (\(url.lastPathComponent))",
                kind: .customWine,
                bundleVersion: "custom",
                shortVersion: "Custom"
            )) {
            if !runners.contains(where: { $0.id == inspected.id }) {
                runners.append(inspected)
            }
            statusBanner = "Added engine: \(inspected.displayName)"
        } else {
            statusBanner = "Selected folder does not contain a valid Wine runtime."
        }
    }

    func launchUtility(_ utility: WineUtility, in prefix: DiscoveredPrefix) {
        do {
            try PrefixManager.launchUtility(utility, in: prefix, runners: runners)
            statusBanner = "Opened \(utility.title) for \(prefix.gameTitle ?? "AppID \(prefix.appID)")."
        } catch {
            statusBanner = "Could not launch \(utility.title): \(error.localizedDescription)"
        }
    }

    func chooseAndRunInstaller(in prefix: DiscoveredPrefix) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["exe", "msi", "bat", "cmd"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = "Run in Prefix"
        panel.message = "Select a Windows installer or program (.exe, .msi, .bat) to execute inside \(prefix.gameTitle ?? "AppID \(prefix.appID)")'s prefix."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PrefixManager.runExecutable(url, in: prefix, runners: runners)
            statusBanner = "Launched \(url.lastPathComponent) inside \(prefix.gameTitle ?? "AppID \(prefix.appID)") prefix."
        } catch {
            statusBanner = "Could not execute \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func stopWineProcesses(in prefix: DiscoveredPrefix) {
        try? PrefixManager.killWineServer(in: prefix, runners: runners)
        statusBanner = "Stopped all running Wine processes for \(prefix.gameTitle ?? "AppID \(prefix.appID)")."
    }

    func rebuildPrefix(in prefix: DiscoveredPrefix) {
        do {
            let backupURL = try PrefixManager.rebuildPreservingSaves(prefix, runners: runners)
            refreshAll()
            statusBanner = "Rebuilt prefix for \(prefix.gameTitle ?? "AppID \(prefix.appID)") (saves preserved; old prefix backed up to \(backupURL.lastPathComponent))."
        } catch {
            statusBanner = "Could not rebuild prefix: \(error.localizedDescription)"
        }
    }

    func badgeCount(for section: PositronSection) -> String? {
        switch section {
        case .installedGames:
            return "\(installedApps.count)"
        case .steamSetup:
            return steamState.isPositronInjected ? "ON" : nil
        case .engines:
            return "\(runners.count)"
        case .drives:
            return "\(libraries.count)"
        }
    }
}

