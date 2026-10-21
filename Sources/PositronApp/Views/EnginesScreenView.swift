// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

// MARK: - SCREEN 3: TRANSLATION ENGINES

struct EnginesScreenView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Translation Engines")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(PositronTheme.primaryText(colorScheme))
                        Text("Positron discovers installed CrossOver, CrossOver Preview, and custom Wine runtimes and stages APFS copy-on-write clones with patched ntdll.dll.")
                            .font(.subheadline)
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    }
                    Spacer()
                    Button {
                        vm.addManualRunnerBundle()
                    } label: {
                        Label("Add Engine...", systemImage: "plus")
                    }
                    .glassActionButton(prominent: true)
                }

                VStack(spacing: 12) {
                    ForEach(vm.runners) { runner in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 14) {
                                Image(systemName: "cpu.fill")
                                    .font(.title2)
                                    .foregroundStyle(PositronTheme.accentCyan(colorScheme))
                                    .frame(width: 42, height: 42)
                                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(PositronTheme.accentCyan(colorScheme).opacity(0.15)))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(runner.displayName)
                                        .font(.headline)
                                        .foregroundStyle(PositronTheme.primaryText(colorScheme))
                                    Text(runner.rootURL.path(percentEncoded: false))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    if runner.supportsRosetta {
                                        BadgePill(text: "Rosetta 2", color: .blue)
                                    }
                                    if runner.supportsFEX {
                                        BadgePill(text: "FEX ARM64", color: .purple)
                                    }
                                    if runner.availableGraphicsBackends.contains(.d3dMetal) {
                                        BadgePill(text: "D3DMetal", color: .green)
                                    }
                                    if runner.availableGraphicsBackends.contains(.dxmt) {
                                        BadgePill(text: "DXMT", color: .cyan)
                                    }
                                }
                                Button("Show in Finder") {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: runner.rootURL.path(percentEncoded: false))
                                }
                                .controlSize(.small)
                                .glassActionButton()
                            }

                            if !runner.ntdllInspections.isEmpty {
                                Divider().opacity(0.5)
                                HStack(spacing: 14) {
                                    ForEach(runner.ntdllInspections, id: \.archDirectory) { pe in
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.shield.fill")
                                                .foregroundStyle(PositronTheme.accentGreen(colorScheme))
                                                .font(.caption2)
                                            Text("\(pe.archDirectory): ntdll (\(pe.machineHex))")
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .glassCard(cornerRadius: 15, tint: .cyan)
                    }
                }
            }
            .padding(24)
        }
    }
}

