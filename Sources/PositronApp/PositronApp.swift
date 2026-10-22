// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

@MainActor
enum PositronScreenshotExporter {
    static func exportAllIfRequested(vm: PositronViewModel) {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--export-screenshots"), idx + 1 < args.count else {
            return
        }
        let outDir = URL(filePath: args[idx + 1])
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard let window = NSApplication.shared.windows.first(where: { $0.frame.width > 400 }) else {
                return
            }
            window.setContentSize(NSSize(width: 1280, height: 860))

            let captures: [(String, NSAppearance.Name, ColorScheme, () -> Void)] = [
                ("positron-light-01-installed-games-fallout76.png", .aqua, .light, {
                    vm.selectedSection = .installedGames
                    vm.loadProfile(for: 1151340)
                }),
                ("positron-light-02-installed-games-swtor.png", .aqua, .light, {
                    vm.selectedSection = .installedGames
                    vm.loadProfile(for: 1286830)
                }),
                ("positron-light-03-steam-setup.png", .aqua, .light, {
                    vm.selectedSection = .steamSetup
                }),
                ("positron-dark-01-installed-games-fallout76.png", .darkAqua, .dark, {
                    vm.selectedSection = .installedGames
                    vm.loadProfile(for: 1151340)
                }),
                ("positron-dark-02-steam-drives.png", .darkAqua, .dark, {
                    vm.selectedSection = .drives
                })
            ]

            for (filename, appName, scheme, configure) in captures {
                NSApp.appearance = NSAppearance(named: appName)
                window.appearance = NSAppearance(named: appName)
                vm.overrideColorScheme = scheme
                configure()
                try? await Task.sleep(for: .milliseconds(450))
                if let contentView = window.contentView?.superview ?? window.contentView {
                    contentView.layoutSubtreeIfNeeded()
                    let bounds = contentView.bounds
                    if let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds) {
                        contentView.cacheDisplay(in: bounds, to: rep)
                        if let png = rep.representation(using: .png, properties: [:]) {
                            try? png.write(to: outDir.appending(path: filename))
                        }
                    }
                }
            }
            NSApp.appearance = nil
            window.appearance = nil
            vm.overrideColorScheme = nil
            vm.selectedSection = .installedGames
            vm.loadProfile(for: 1151340)
        }
    }
}

@main
struct PositronAppMain: App {
    @State private var viewModel = PositronViewModel()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = iconImage
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Positron") {
            ContentView(vm: viewModel)
                .preferredColorScheme(viewModel.overrideColorScheme)
                .onAppear {
                    PositronScreenshotExporter.exportAllIfRequested(vm: viewModel)
                }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Support Positron ❤️…") {
                    viewModel.showSupportSheet = true
                }
                .keyboardShortcut("D", modifiers: [.command, .shift])

                Button("Buy a Coffee on Ko-fi…") {
                    viewModel.openKofiSupport()
                }

                Button("Sponsor on GitHub…") {
                    viewModel.openGitHubSponsors()
                }
            }
        }
    }
}
