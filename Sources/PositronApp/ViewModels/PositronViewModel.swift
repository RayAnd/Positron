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
    var standaloneGames: [StandaloneGame] = []
    var isBridgeUpdateNeeded: Bool = false
    var isSteamRunning: Bool = false
    var showSupportSheet: Bool = false
    let funding = PositronFundingConfig.current()

    @ObservationIgnored private var detectedCache: [UInt32: PresetCatalogEntry] = [:]
    @ObservationIgnored private var libraryWatcher: SteamLibraryWatcher?

    let profileStore: GameProfileStore

    init() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/Positron")
        self.profileStore = GameProfileStore(storageDirectory: support)
        self.customLibraryPaths = UserDefaults.standard.stringArray(forKey: "PositronCustomSteamLibraries") ?? []
        _ = GameQuirksDatabase.loadCustomCatalog()
        refreshAll()
        libraryWatcher = SteamLibraryWatcher { [weak self] in
            self?.refreshInstalledGames()
        }
        libraryWatcher?.watch(libraries.filter(\.isConnected).map(\.steamappsURL))
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
                items.append(detectedEntry(for: appID, title: installedTitle).info)
            }
        }
        for game in standaloneGames where !seenAppIDs.contains(game.id) {
            seenAppIDs.insert(game.id)
            items.append(detectedEntry(for: game.id, title: game.title).info)
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
        return detectedEntry(for: selectedAppID, title: displayTitle(for: selectedAppID)).info
    }

    var recommendedProfileForSelected: GameProfile {
        let fallback: CPUTranslator = runners.contains(where: \.supportsFEX) ? .fex : .rosetta
        if GameQuirksDatabase.presetInfo(forAppID: selectedAppID) != nil {
            return GameQuirksDatabase.defaultProfile(forAppID: selectedAppID, preferredTranslator: fallback)
        } else {
            return detectedEntry(for: selectedAppID, title: displayTitle(for: selectedAppID)).recommendedProfile
        }
    }

    var isEditingMatchingRecommended: Bool {
        let rec = recommendedProfileForSelected.sanitized()
        let cur = editingProfile.sanitized()
        return cur.translator == rec.translator &&
            cur.graphics == rec.graphics &&
            cur.sync == rec.sync &&
            cur.fullscreenMode == rec.fullscreenMode &&
            cur.gameFixesEnabled == rec.gameFixesEnabled &&
            Set(cur.disabledFixes) == Set(rec.disabledFixes) &&
            cur.retinaMode == rec.retinaMode &&
            cur.disableHidraw == rec.disableHidraw &&
            cur.dllOverrides == rec.dllOverrides &&
            cur.extraEnvironment == rec.extraEnvironment
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
            existingPrefixes: prefixes,
            preferPositronPrefix: isStandalone(selectedAppID)
        )
    }

    func isPrefixInitialized(for appID: UInt32) -> Bool {
        let pfx = PrefixManager.resolvePrefix(
            forAppID: appID,
            gameTitle: installedApps[appID],
            libraries: libraries,
            existingPrefixes: prefixes,
            preferPositronPrefix: isStandalone(appID)
        )
        return FileManager.default.fileExists(atPath: pfx.driveCURL.path(percentEncoded: false))
    }

    func refreshAll() {
        isSteamInstalled = FileManager.default.fileExists(atPath: "/Applications/Steam.app")
        runners = RunnerDiscovery.discoverAll()
        steamState = SteamIntegration.inspectState()
        if steamState.isPositronInjected {
            SteamIntegration.syncBundledFixesAndTools(runners: runners)
            _ = SteamIntegration.autoUpdateSteamBridgeIfClosed(runners: runners)
        }
        isSteamRunning = SteamIntegration.isSteamRunning()
        isBridgeUpdateNeeded = SteamIntegration.isBridgeUpdatePending()
        blockSteamUpdates = SteamIntegration.isSteamUpdateBlocked()
        rescanLibraries()
        if !isKnownGame(selectedAppID), let firstID = installedApps.keys.sorted().first ?? standaloneGames.first?.id {
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
            isSteamRunning = SteamIntegration.isSteamRunning()
            isBridgeUpdateNeeded = SteamIntegration.isBridgeUpdatePending()
            statusBanner = isSteamRunning
                ? "Updated Positron bridge in Steam.app and restarted Steam (\(registeredTools.count) tool(s) active)."
                : "Positron enabled in Steam.app (\(registeredTools.count) tool(s) ready)."
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
        if !profileStore.hasSavedProfile(forAppID: appID), GameQuirksDatabase.presetInfo(forAppID: appID) == nil {
            editingProfile = recommendedProfileForSelected
        }
        if editingProfile.runnerID == nil {
            editingProfile.runnerID = runners.first?.id
        }
    }

    func hasAppliedPreset(for appID: UInt32) -> Bool {
        profileStore.hasSavedProfile(forAppID: appID)
    }

    var hasUnsavedProfileEdits: Bool {
        guard hasAppliedPreset(for: selectedAppID) else { return true }
        let saved = profileStore.load(forAppID: selectedAppID, fallbackTranslator: editingProfile.translator).sanitized()
        let cur = editingProfile.sanitized()
        return saved.translator != cur.translator ||
            saved.graphics != cur.graphics ||
            saved.sync != cur.sync ||
            saved.fullscreenMode != cur.fullscreenMode ||
            saved.retinaMode != cur.retinaMode ||
            saved.metalHUD != cur.metalHUD ||
            saved.advertiseAVX != cur.advertiseAVX ||
            saved.disableHidraw != cur.disableHidraw ||
            saved.gameFixesEnabled != cur.gameFixesEnabled ||
            Set(saved.disabledFixes) != Set(cur.disabledFixes) ||
            saved.dllOverrides != cur.dllOverrides ||
            saved.extraEnvironment != cur.extraEnvironment
    }

    /// One-click helper: enables/updates the bridge if needed, and opens or restarts Steam.app.
    func openOrSyncSteam() {
        if !steamState.isPositronInjected || isBridgeUpdateNeeded {
            enableInSteam()
            if !SteamIntegration.isSteamRunning() {
                _ = try? Process.run(URL(filePath: "/usr/bin/open"), arguments: [SteamIntegration.defaultSteamApp.path(percentEncoded: false)])
                isSteamRunning = true
            }
            return
        }
        _ = try? Process.run(URL(filePath: "/usr/bin/open"), arguments: [SteamIntegration.defaultSteamApp.path(percentEncoded: false)])
        isSteamRunning = true
        statusBanner = "Opened Steam.app with Positron active."
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

    @discardableResult
    func saveCurrentProfile() -> Bool {
        editingProfile = editingProfile.sanitized()
        if isStandalone(selectedAppID) {
            do {
                try profileStore.save(editingProfile)
                statusBanner = "Saved preset for \(selectedPresetInfo.title)."
                return true
            } catch {
                statusBanner = "Could not save preset: \(error.localizedDescription)"
                return false
            }
        }
        do {
            let toolName = try SteamIntegration.applyProfileToSteam(
                editingProfile,
                runners: runners,
                profileStore: profileStore
            )
            statusBanner = "Applied \(selectedPresetInfo.title) to Steam → \(toolName) (\(editingProfile.graphics.rawValue.uppercased()))."
            return true
        } catch {
            statusBanner = "Failed to apply preset to Steam: \(error.localizedDescription)"
            return false
        }
    }

    func removeCurrentProfileFromSteam() {
        if isStandalone(selectedAppID) {
            profileStore.removeProfile(forAppID: selectedAppID)
            statusBanner = "Removed the saved preset for \(selectedPresetInfo.title)."
            return
        }
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

    // MARK: - Library scanning

    private func rescanLibraries() {
        libraries = SteamLibraryDiscovery.discoverLibraries(extraLibraryPaths: customLibraryPaths, scanMountedVolumes: true)
        installedApps = SteamLibraryDiscovery.discoverInstalledApps(in: libraries)
        standaloneGames = StandaloneGameStore.load()
        prefixes = PrefixManager.discoverSteamPrefixes(libraries: libraries, includePositronShadowRoot: true)
        detectedCache = [:]
        libraryWatcher?.watch(libraries.filter(\.isConnected).map(\.steamappsURL))
    }

    /// Called by the watcher when a steamapps folder changes, a drive mounts, or the app comes forward.
    /// Keeps the current (possibly unsaved) preset edits.
    func refreshInstalledGames() {
        let before = Set(installedApps.keys)
        _ = SteamIntegration.autoUpdateSteamBridgeIfClosed(runners: runners)
        isSteamRunning = SteamIntegration.isSteamRunning()
        isBridgeUpdateNeeded = SteamIntegration.isBridgeUpdatePending()
        rescanLibraries()
        let added = installedApps.filter { !before.contains($0.key) }.values.sorted()
        if !added.isEmpty {
            statusBanner = "New game ready: \(added.joined(separator: ", "))"
        }
        if !isKnownGame(selectedAppID), let firstID = installedApps.keys.sorted().first ?? standaloneGames.first?.id {
            loadProfile(for: firstID)
        }
    }

    func isKnownGame(_ appID: UInt32) -> Bool {
        installedApps[appID] != nil || isStandalone(appID)
    }

    func isStandalone(_ appID: UInt32) -> Bool {
        standaloneGame(for: appID) != nil
    }

    func standaloneGame(for appID: UInt32) -> StandaloneGame? {
        standaloneGames.first { $0.id == appID }
    }

    func displayTitle(for appID: UInt32) -> String {
        standaloneGame(for: appID)?.title ?? installedApps[appID] ?? "Steam Game (\(appID))"
    }

    /// Preset synthesized by inspecting the game's files; cached because folder scans are slow.
    func detectedEntry(for appID: UInt32, title: String) -> PresetCatalogEntry {
        if let cached = detectedCache[appID] { return cached }
        let entry: PresetCatalogEntry
        if let game = standaloneGame(for: appID) {
            let raw = SteamLibraryDiscovery.autoDetectPreset(forAppID: appID, title: game.title, gameDirectory: game.gameDirectory)
            entry = PresetCatalogEntry(
                info: GamePresetInfo(
                    appID: appID,
                    title: game.title,
                    subtitle: "Non-Steam • \(raw.info.subtitle)",
                    recommendedSummary: raw.info.recommendedSummary,
                    notes: raw.info.notes
                ),
                recommendedProfile: raw.recommendedProfile
            )
        } else {
            entry = SteamLibraryDiscovery.autoDetectPreset(forAppID: appID, title: title, in: libraries)
        }
        detectedCache[appID] = entry
        return entry
    }

    // MARK: - Fix switches

    func isFixEnabled(_ id: String) -> Bool {
        editingProfile.isFixEnabled(id)
    }

    func setFix(_ id: String, enabled: Bool) {
        var disabled = Set(editingProfile.disabledFixes)
        if enabled {
            disabled.remove(id)
        } else {
            disabled.insert(id)
        }
        editingProfile.disabledFixes = disabled.sorted()
    }

    // MARK: - Launching

    /// Steam games: applies the preset, then asks Steam to start the game.
    /// Non-Steam games: saves the preset and launches through the Positron compatibility tool.
    func playSelectedGame() {
        if let game = standaloneGame(for: selectedAppID) {
            launchStandalone(game)
            return
        }
        guard saveCurrentProfile(), let url = URL(string: "steam://rungameid/\(selectedAppID)") else { return }
        NSWorkspace.shared.open(url)
        statusBanner = "Starting \(selectedPresetInfo.title) in Steam with its Positron preset."
    }

    func launchStandalone(_ game: StandaloneGame) {
        editingProfile = editingProfile.sanitized()
        do {
            try profileStore.save(editingProfile)
            SteamIntegration.syncBundledFixesAndTools(runners: runners)
            let tool = editingProfile.resolvedCompatToolName(among: runners)
            try StandaloneGameStore.launch(game, toolName: tool)
            statusBanner = "Launching \(game.title) with \(tool). Log: Positron/prefixes/\(game.id)/notproton-run.log"
        } catch {
            statusBanner = "Could not launch \(game.title): \(error.localizedDescription)"
        }
    }

    func addStandaloneGame() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "exe")].compactMap { $0 }
        panel.prompt = "Add Game"
        panel.message = "Choose the Windows game executable (.exe) to run with Positron."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let game = try StandaloneGameStore.add(executable: url)
            rescanLibraries()
            loadProfile(for: game.id)
            statusBanner = "Added \(game.title). Check its preset, then press Launch Game."
        } catch {
            statusBanner = "Could not add game: \(error.localizedDescription)"
        }
    }

    func removeSelectedStandaloneGame() {
        guard let game = standaloneGame(for: selectedAppID) else { return }
        do {
            try StandaloneGameStore.remove(id: game.id)
        } catch {
            statusBanner = "Could not remove \(game.title): \(error.localizedDescription)"
            return
        }
        profileStore.removeProfile(forAppID: game.id)
        rescanLibraries()
        if let firstID = installedApps.keys.sorted().first ?? standaloneGames.first?.id {
            loadProfile(for: firstID)
        }
        statusBanner = "Removed \(game.title) from Positron. Its prefix in Positron/prefixes/\(game.id) was kept."
    }

    func openKofiSupport() {
        if let url = URL(string: funding.kofiURL) {
            NSWorkspace.shared.open(url)
            statusBanner = "Opened Ko-fi support page in browser. Thank you for supporting Positron!"
        }
    }

    func openGitHubSponsors() {
        if let url = URL(string: funding.githubSponsorsURL) {
            NSWorkspace.shared.open(url)
            statusBanner = "Opened GitHub Sponsors page in browser. Thank you for supporting Positron!"
        }
    }

    func openGitHubRepo() {
        if let url = URL(string: funding.githubRepoURL) {
            NSWorkspace.shared.open(url)
        }
    }

    func badgeCount(for section: PositronSection) -> String? {
        switch section {
        case .installedGames:
            return "\(installedApps.count + standaloneGames.count)"
        case .steamSetup:
            return steamState.isPositronInjected ? "ON" : nil
        case .engines:
            return "\(runners.count)"
        case .drives:
            return "\(libraries.count)"
        }
    }
}

