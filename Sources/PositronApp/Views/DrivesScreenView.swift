// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

// MARK: - SCREEN 4: POSITRON EXTERNAL STORAGE, DISK IMAGES & STEAM DRIVES

struct DrivesScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 1. POSITRON SUPPORT FILES & DISK IMAGE STORAGE CARD
                PositronStorageDashboardCard(vm: vm)

                // 2. STEAM GAME LIBRARY DRIVES SECTION
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Steam Game Library Drives")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(PositronTheme.primaryText(colorScheme))
                        Text("Where Steam downloads game assets (steamapps/common). Positron automatically cleans AppleDouble ._* files on ExFAT libraries.")
                            .font(.caption)
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    }
                    Spacer()
                    Button {
                        vm.addExternalSteamLibrary()
                    } label: {
                        Label("Add Steam Library…", systemImage: "externaldrive.badge.plus")
                    }
                    .glassActionButton(prominent: false)
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
                                        BadgePill(text: "EXFAT SAFE MODE", color: .purple, icon: "bolt.shield.fill")
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

struct PositronStorageDashboardCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel

    var body: some View {
        let snap = vm.storageSnapshot
        let cfg = snap.config
        let isExternal = cfg.mode != .internalSSD
        let accent = isExternal ? PositronTheme.accentPurple(colorScheme) : PositronTheme.accentCyan(colorScheme)
        let displayPath = cfg.externalContainerPath ?? PositronStorageManager.supportDir.path(percentEncoded: false)

        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: isExternal ? "externaldrive.badge.icloud" : "internaldrive.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 48, height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("Positron Support Files & Disk Image Storage")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(PositronTheme.primaryText(colorScheme))

                        BadgePill(
                            text: cfg.mode.displayTitle.uppercased(),
                            color: isExternal ? .purple : .cyan,
                            icon: isExternal ? "opticaldiscdrive.fill" : "internaldrive"
                        )

                        if isExternal {
                            BadgePill(
                                text: snap.isMounted ? "MOUNTED & READY" : (snap.isDriveConnected ? "UNMOUNTED" : "DRIVE UNPLUGGED"),
                                color: snap.isMounted ? .green : .orange,
                                icon: snap.isMounted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                        }
                    }

                    Text("Store Wine prefixes, CrossOver runtimes, game icons, and bridge caches on an external drive to keep your Mac SSD free. ExFAT drives automatically use an APFS Sparse Disk Image (.sparsebundle) so POSIX symlinks and zero-copy templates work natively.")
                        .font(.caption)
                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .font(.caption2)
                            .foregroundStyle(PositronTheme.mutedText(colorScheme))
                        Text(displayPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                // Total Size & Free Space Metric Box
                VStack(alignment: .trailing, spacing: 3) {
                    Text(snap.formattedTotal)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(PositronTheme.primaryText(colorScheme))
                    Text("Used by Positron")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    if let free = snap.formattedAvailable {
                        BadgePill(text: "\(free) FREE ON DRIVE", color: .green)
                    }
                }
            }

            if vm.isStorageBusy {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(vm.storageBusyMessage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PositronTheme.primaryText(colorScheme))
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.14)))
            } else {
                // Action Toolbar
                HStack(spacing: 10) {
                    Button {
                        vm.chooseAndMovePositronStorage()
                    } label: {
                        Label(
                            isExternal ? "Change External Drive / Image…" : "Move Positron Storage to External Drive…",
                            systemImage: "externaldrive.fill.badge.arrow.right"
                        )
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isExternal ? .purple : .cyan)

                    if isExternal && !snap.isMounted {
                        Button {
                            vm.mountExternalPositronStorage()
                        } label: {
                            Label("Mount Storage Image", systemImage: "eject.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }

                    if cfg.mode == .externalSparseBundle && snap.isDriveConnected {
                        Button {
                            vm.compactExternalPositronImage()
                        } label: {
                            Label("Compact Disk Image", systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        .glassActionButton()
                        .help("Reclaim unused space inside PositronStorage.sparsebundle on the external drive")
                    }

                    if snap.backupBytes > 0 {
                        Button {
                            vm.cleanupOldBackups()
                        } label: {
                            Label("Clean Old Backups (\(snap.formattedBackups))", systemImage: "trash")
                        }
                        .glassActionButton()
                        .help("Delete old pfx.previous-* backup snapshots while keeping all active prefixes and saves")
                    }

                    Spacer()

                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: URL(filePath: displayPath).deletingLastPathComponent().path(percentEncoded: false))
                    }
                    .controlSize(.small)
                    .glassActionButton()

                    if isExternal {
                        Button {
                            vm.movePositronStorageBackToInternal()
                        } label: {
                            Label("Move Back to Internal SSD", systemImage: "internaldrive")
                        }
                        .controlSize(.small)
                        .glassActionButton()
                    }
                }
            }

            Divider().opacity(0.5)

            // Per-Folder Breakdown Grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 9) {
                ForEach(snap.items.prefix(6)) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(PositronTheme.primaryText(colorScheme))
                                .lineLimit(1)
                            Text("Positron/\(item.id)")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(PositronTheme.mutedText(colorScheme))
                        }
                        Spacer()
                        Text(item.formattedSize)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(PositronTheme.tileFill(colorScheme, isSelected: false, accent: accent))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(PositronTheme.tileBorder(colorScheme, isSelected: false, accent: accent), lineWidth: 0.8)
                    )
                }
            }
        }
        .padding(20)
        .glassCard(cornerRadius: 16, tint: isExternal ? .purple : .cyan)
    }
}
