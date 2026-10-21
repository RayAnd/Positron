// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

// MARK: - SCREEN 2: STEAM SETUP

struct SteamSetupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel
    @State private var showAdvanced = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero Glass Banner
                HStack(spacing: 22) {
                    PositronBrandIcon(size: 86)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("Steam Play for macOS")
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .foregroundStyle(PositronTheme.primaryText(colorScheme))
                            BadgePill(
                                text: vm.steamState.isPositronInjected ? "BRIDGE ACTIVE" : "READY TO ENABLE",
                                color: vm.steamState.isPositronInjected ? .green : .cyan,
                                icon: vm.steamState.isPositronInjected ? "checkmark.shield.fill" : "bolt.fill"
                            )
                        }
                        Text("Positron injects a native ARM64/x86_64 Steam Play bridge into macOS Steam so Windows games download, launch, and sync cloud saves directly inside Steam—while native Mac games continue running natively.")
                            .font(.subheadline)
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 12) {
                            Button {
                                vm.enableInSteam()
                            } label: {
                                Label(
                                    vm.steamState.isPositronInjected ? "Update Positron in Steam" : "Enable Positron in Steam",
                                    systemImage: "bolt.fill"
                                )
                            }
                            .glassActionButton(prominent: true)
                            .controlSize(.large)

                            Button {
                                vm.launchSteamTemporaryMode()
                            } label: {
                                Label("Launch Steam Now", systemImage: "play.fill")
                            }
                            .glassActionButton()
                            .controlSize(.large)

                            if vm.steamState.isPositronInjected {
                                Button(role: .destructive) {
                                    vm.disableAndRestoreSteam()
                                } label: {
                                    Text("Restore Stock Steam")
                                }
                                .glassActionButton()
                                .controlSize(.large)
                            }
                        }
                        .padding(.top, 2)
                    }
                    Spacer()
                }
                .padding(22)
                .glassCard(cornerRadius: 16, tint: .cyan)

                // Interactive Overview Stat Cards
                HStack(spacing: 14) {
                    Button {
                        vm.selectedSection = .installedGames
                    } label: {
                        SimpleStatPill(
                            title: "Installed Windows Games",
                            value: "\(vm.installedApps.count) Detected",
                            icon: "gamecontroller.fill",
                            accent: PositronTheme.accentCyan(colorScheme)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        vm.selectedSection = .engines
                    } label: {
                        SimpleStatPill(
                            title: "Translation Engines",
                            value: "\(vm.runners.count) Ready",
                            icon: "cpu.fill",
                            accent: PositronTheme.accentPurple(colorScheme)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        vm.selectedSection = .drives
                    } label: {
                        SimpleStatPill(
                            title: "Steam Library Drives",
                            value: "\(vm.libraries.count) Connected",
                            icon: "externaldrive.fill.badge.checkmark",
                            accent: PositronTheme.accentGreen(colorScheme)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // 3-Step Workflow
                VStack(alignment: .leading, spacing: 12) {
                    Text("How Positron Works")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(PositronTheme.primaryText(colorScheme))
                    HStack(alignment: .top, spacing: 14) {
                        StepCard(
                            number: "1",
                            title: "Install in Steam",
                            detail: "Install any Windows or Mac game in Steam. Native Mac games run natively; Windows games appear automatically in Installed Games."
                        )
                        StepCard(
                            number: "2",
                            title: "Apply Game Preset",
                            detail: "Select an installed Windows game, pick Rosetta 2 or FEX ARM64 + D3DMetal/DXMT/WineD3D, and click Apply Preset to Steam."
                        )
                        StepCard(
                            number: "3",
                            title: "Manage Prefix & Tools",
                            detail: "Launch winecfg, regedit, Drive C:, or custom .exe/.msi installers directly inside each game's isolated Wine prefix."
                        )
                    }
                }

                DisclosureGroup("Advanced Steam Integration Settings", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(
                            "Prevent Steam from overwriting Positron on startup (steam.cfg self-update lock)",
                            isOn: Binding(
                                get: { vm.blockSteamUpdates },
                                set: { vm.toggleUpdateBlock($0) }
                            )
                        )
                        .foregroundStyle(PositronTheme.primaryText(colorScheme))
                        HStack(spacing: 10) {
                            Button("Open compatibilitytools.d in Finder") {
                                NSWorkspace.shared.selectFile(
                                    nil,
                                    inFileViewerRootedAtPath: SteamIntegration.steamCompatToolsDir.path(percentEncoded: false)
                                )
                            }
                            .glassActionButton()
                            Button("Restore Stock Steam.app") {
                                vm.disableAndRestoreSteam()
                            }
                            .glassActionButton()
                        }
                    }
                    .padding(.top, 10)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PositronTheme.primaryText(colorScheme))
                .padding(14)
                .glassCard(cornerRadius: 14, tint: .cyan)
            }
            .padding(24)
        }
    }
}

struct StepCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let number: String
    let title: String
    let detail: String

    var body: some View {
        let accent = PositronTheme.accentCyan(colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(number)
                    .font(.caption.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(accent.opacity(0.18)))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PositronTheme.primaryText(colorScheme))
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(cornerRadius: 14, tint: .cyan)
    }
}

struct SimpleStatPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let value: String
    let icon: String
    var accent: Color = .cyan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(PositronTheme.primaryText(colorScheme))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(PositronTheme.mutedText(colorScheme))
        }
        .padding(14)
        .glassCard(cornerRadius: 14, tint: accent)
    }
}

