// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

// MARK: - SCREEN 4: STEAM DRIVES

struct DrivesScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Steam Library Drives")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(PositronTheme.primaryText(colorScheme))
                        Text("Positron supports Steam libraries on internal APFS SSDs and external USB/Thunderbolt drives (with automatic APFS shadow prefixes and AppleDouble ._* cleanup for ExFAT).")
                            .font(.subheadline)
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    }
                    Spacer()
                    Button {
                        vm.addExternalSteamLibrary()
                    } label: {
                        Label("Add External Drive Library...", systemImage: "externaldrive.badge.plus")
                    }
                    .glassActionButton(prominent: true)
                }

                VStack(spacing: 12) {
                    ForEach(vm.libraries) { lib in
                        let accent = lib.isExternal ? PositronTheme.accentOrange(colorScheme) : PositronTheme.accentCyan(colorScheme)
                        HStack(spacing: 14) {
                            Image(systemName: lib.isExternal ? "externaldrive.fill.badge.checkmark" : "internaldrive.fill")
                                .font(.title2)
                                .foregroundStyle(accent)
                                .frame(width: 42, height: 42)
                                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(accent.opacity(0.15)))
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(lib.label)
                                        .font(.headline)
                                        .foregroundStyle(PositronTheme.primaryText(colorScheme))
                                    BadgePill(text: lib.fileSystemType.uppercased(), color: lib.isExternal ? .orange : .blue)
                                    if lib.requiresShadowPrefix {
                                        BadgePill(text: "APFS SHADOW PREFIX ACTIVE", color: .purple, icon: "bolt.shield.fill")
                                    }
                                }
                                Text(lib.rootURL.path(percentEncoded: false))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                            }
                            Spacer()
                            BadgePill(text: "\(lib.installedGamesCount) GAME(S)", color: .green)
                            Button("Open in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: lib.rootURL.path(percentEncoded: false))
                            }
                            .controlSize(.small)
                            .glassActionButton()
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 15, tint: lib.isExternal ? .orange : .cyan)
                    }
                }
            }
            .padding(24)
        }
    }
}

