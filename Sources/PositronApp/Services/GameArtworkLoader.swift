// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

// MARK: - Steam & Positron Artwork Resolver

@MainActor
final class GameArtworkLoader {
    static let shared = GameArtworkLoader()

    private var iconCache: [UInt32: NSImage] = [:]
    private var heroCache: [UInt32: NSImage] = [:]
    private var checkedIcons: Set<UInt32> = []
    private var checkedHeroes: Set<UInt32> = []

    private let home = FileManager.default.homeDirectoryForCurrentUser

    func iconImage(for appID: UInt32) -> NSImage? {
        if checkedIcons.contains(appID) {
            return iconCache[appID]
        }
        checkedIcons.insert(appID)

        let launcherICNS = home.appending(path: "Library/Application Support/Positron/launchers/\(appID)/game.icns")
        if FileManager.default.fileExists(atPath: launcherICNS.path(percentEncoded: false)),
           let img = NSImage(contentsOf: launcherICNS) {
            iconCache[appID] = img
            return img
        }

        let cacheDir = home.appending(path: "Library/Application Support/Steam/appcache/librarycache/\(appID)")
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for url in entries where url.pathExtension.lowercased() == "jpg" {
                let name = url.deletingPathExtension().lastPathComponent
                if name.count == 40, let img = NSImage(contentsOf: url) {
                    iconCache[appID] = img
                    return img
                }
            }
        }
        return nil
    }

    func heroImage(for appID: UInt32) -> NSImage? {
        if checkedHeroes.contains(appID) {
            return heroCache[appID]
        }
        checkedHeroes.insert(appID)

        let cacheDir = home.appending(path: "Library/Application Support/Steam/appcache/librarycache/\(appID)")
        let preferredNames = ["library_hero.jpg", "library_header.jpg", "header.jpg"]

        for name in preferredNames {
            let candidate = cacheDir.appending(path: name)
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)),
               let img = NSImage(contentsOf: candidate) {
                heroCache[appID] = img
                return img
            }
        }

        if let subdirs = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for name in preferredNames {
                for dir in subdirs {
                    let candidate = dir.appending(path: name)
                    if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)),
                       let img = NSImage(contentsOf: candidate) {
                        heroCache[appID] = img
                        return img
                    }
                }
            }
        }
        return nil
    }
}

