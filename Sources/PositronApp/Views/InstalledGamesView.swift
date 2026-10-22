// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

// MARK: - SCREEN 1: UNIFIED INSTALLED GAMES (HERO BANNER + BENTO GRID)

struct InstalledGamesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel
    @State private var showTechDetails = false
    @State private var showLibrarySheet = false

    var body: some View {
        HStack(spacing: 0) {
            // LEFT COLUMN: INSTALLED GAMES LIST (CUSTOM HIGH-CONTRAST CARDS IN LIGHT & DARK MODE)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Installed Games")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(PositronTheme.primaryText(colorScheme))
                        Text("\(vm.installedApps.count) Windows titles across \(vm.libraries.count) drive(s)")
                            .font(.caption2)
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    }
                    Spacer()
                    Button {
                        vm.refreshAll()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    }
                    .buttonStyle(.borderless)
                    .help("Scan Steam libraries for installed games")
                }

                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                        .font(.caption)
                    TextField("Search title, engine, AppID...", text: $vm.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(PositronTheme.primaryText(colorScheme))
                    if !vm.searchQuery.isEmpty {
                        Button {
                            vm.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .glassCard(cornerRadius: 10, tint: .cyan)

                // Filter Chips
                HStack(spacing: 6) {
                    ForEach(GameListFilter.allCases) { filter in
                        let selected = vm.gameFilter == filter
                        let accent = PositronTheme.accentCyan(colorScheme)
                        Button {
                            vm.gameFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 11, weight: selected ? .bold : .semibold, design: .rounded))
                                .foregroundStyle(selected ? accent : PositronTheme.secondaryText(colorScheme))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4.5)
                                .background(
                                    Capsule()
                                        .fill(PositronTheme.tileFill(colorScheme, isSelected: selected, accent: accent))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(PositronTheme.tileBorder(colorScheme, isSelected: selected, accent: accent), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                // Custom Game Cards List (No AppKit NSTableView dark/light mismatch)
                if vm.installedGamesList.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(PositronTheme.mutedText(colorScheme))
                        Text(vm.installedApps.isEmpty ? "No Windows Games Detected" : "No Matching Games")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PositronTheme.primaryText(colorScheme))
                        Text("Install any Windows game in Steam or reset the filter above. Native macOS games run directly without Positron.")
                            .font(.caption2)
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(vm.installedGamesList) { game in
                                let isSelected = vm.selectedAppID == game.appID
                                let isApplied = vm.hasAppliedPreset(for: game.appID)
                                let hasPfx = vm.isPrefixInitialized(for: game.appID)
                                let accent = PositronTheme.accentCyan(colorScheme)

                                Button {
                                    vm.loadProfile(for: game.appID)
                                } label: {
                                    HStack(spacing: 10) {
                                        GameTileAvatar(title: game.title, appID: game.appID, size: 40)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(game.title)
                                                .font(.system(size: 12.5, weight: .bold))
                                                .foregroundStyle(PositronTheme.primaryText(colorScheme))
                                                .lineLimit(1)
                                            Text(game.subtitle)
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                                                .lineLimit(1)
                                            HStack(spacing: 5) {
                                                Text("#\(game.appID)")
                                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                                    .foregroundStyle(PositronTheme.mutedText(colorScheme))
                                                if isApplied {
                                                    BadgePill(text: "ACTIVE", color: .cyan)
                                                }
                                                if hasPfx {
                                                    BadgePill(text: "PREFIX", color: .green)
                                                }
                                                if vm.isStandalone(game.appID) {
                                                    BadgePill(text: "NON-STEAM", color: .orange)
                                                }
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(PositronTheme.tileFill(colorScheme, isSelected: isSelected, accent: accent))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(
                                                PositronTheme.tileBorder(colorScheme, isSelected: isSelected, accent: accent),
                                                lineWidth: isSelected ? 1.5 : 1.0
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Catalog Footer Card
                VStack(spacing: 7) {
                    Button {
                        vm.addStandaloneGame()
                    } label: {
                        Label("Add Non-Steam Game…", systemImage: "plus.app.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .glassActionButton()
                    .controlSize(.small)

                    Button {
                        showLibrarySheet = true
                    } label: {
                        Label("Browse \(GameQuirksDatabase.catalog.count) Game Presets", systemImage: "books.vertical.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .glassActionButton()
                    .controlSize(.small)

                    HStack(spacing: 8) {
                        Button {
                            vm.saveCurrentGameToPresetsCatalog()
                        } label: {
                            Label("Save to Catalog", systemImage: "square.and.arrow.down")
                                .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                        }
                        .controlSize(.mini)
                        .buttonStyle(.borderless)

                        Spacer()

                        Button {
                            vm.openPresetsCatalogJSON()
                        } label: {
                            Label("presets-catalog.json", systemImage: "curlybraces")
                                .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                        }
                        .controlSize(.mini)
                        .buttonStyle(.borderless)
                    }
                }
                .padding(10)
                .glassCard(cornerRadius: 12, tint: .cyan)
            }
            .frame(width: 296)
            .padding(14)
            .background(PositronTheme.columnFill(colorScheme))

            Rectangle()
                .fill(PositronTheme.chromeDivider(colorScheme))
                .frame(width: 1)

            // RIGHT COLUMN: HERO GAME BANNER + SUGGESTED PROFILE CARD + 2-COLUMN BENTO GRID
            ScrollView {
                let info = vm.selectedPresetInfo
                let pfx = vm.selectedGamePrefix
                let isApplied = vm.hasAppliedPreset(for: info.appID)
                let hasPfx = vm.isPrefixInitialized(for: info.appID)
                let isCurated = GameQuirksDatabase.presetInfo(forAppID: info.appID) != nil
                let heroImg = GameArtworkLoader.shared.heroImage(for: info.appID)

                VStack(alignment: .leading, spacing: 14) {
                    // 1A. CINEMATIC HERO BANNER (Always dark photographic scrim with crisp white text)
                    ZStack(alignment: .bottomLeading) {
                        if let heroImg {
                            Image(nsImage: heroImg)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 138)
                                .clipped()
                                .overlay(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.35),
                                            Color.black.opacity(0.82)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        } else {
                            LinearGradient(
                                colors: [
                                    Color(red: 0.05, green: 0.14, blue: 0.28),
                                    Color(red: 0.14, green: 0.07, blue: 0.26)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(height: 138)
                        }

                        HStack(alignment: .center, spacing: 15) {
                            GameTileAvatar(title: info.title, appID: info.appID, size: 64)

                            VStack(alignment: .leading, spacing: 6) {
                                Text(info.title)
                                    .font(.system(size: 21, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .shadow(color: .black.opacity(0.65), radius: 4, y: 1)

                                HStack(spacing: 7) {
                                    if isApplied {
                                        BadgePill(
                                            text: "ACTIVE IN STEAM",
                                            color: .cyan,
                                            icon: "checkmark.seal.fill",
                                            forceDarkSurface: true
                                        )
                                    } else {
                                        BadgePill(
                                            text: "DEFAULT",
                                            color: .orange,
                                            forceDarkSurface: true
                                        )
                                    }
                                    if hasPfx {
                                        BadgePill(
                                            text: "PREFIX READY",
                                            color: .green,
                                            icon: "folder.fill",
                                            forceDarkSurface: true
                                        )
                                    }
                                    Text("\(info.subtitle) • AppID \(info.appID)")
                                        .font(.system(size: 11.5, weight: .medium))
                                        .foregroundStyle(Color(white: 0.88))
                                        .lineLimit(1)
                                }

                                Text("Steam Tool: \(vm.editingProfile.resolvedCompatToolName(among: vm.runners))")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Color(red: 0.40, green: 0.90, blue: 1.0))
                            }

                            Spacer(minLength: 8)

                            VStack(alignment: .trailing, spacing: 6) {
                                let isNonSteam = vm.isStandalone(info.appID)
                                let needsSave = vm.hasUnsavedProfileEdits || !isApplied
                                Button {
                                    vm.playSelectedGame()
                                } label: {
                                    Label(
                                        isNonSteam
                                            ? "Launch Game"
                                            : (needsSave ? "Apply & Play in Steam" : "Play in Steam"),
                                        systemImage: "play.fill"
                                    )
                                    .fontWeight(.semibold)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .controlSize(.large)
                                .help(isNonSteam ? "Save the preset and start the game with Positron" : "Automatically applies your preset to Steam and launches the game")

                                Button {
                                    vm.saveCurrentProfile()
                                } label: {
                                    Label(
                                        isNonSteam
                                            ? (needsSave ? "Save Preset" : "Preset Saved ✓")
                                            : (needsSave ? (isApplied ? "Apply Changes to Steam" : "Apply Preset to Steam") : "Preset Applied in Steam ✓"),
                                        systemImage: "checkmark.circle.fill"
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(needsSave ? .cyan : .secondary)
                                .controlSize(.regular)

                                if isNonSteam {
                                    Button(role: .destructive) {
                                        vm.removeSelectedStandaloneGame()
                                    } label: {
                                        Label("Remove Game", systemImage: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else if isApplied {
                                    Button(role: .destructive) {
                                        vm.removeCurrentProfileFromSteam()
                                    } label: {
                                        Label("Remove Preset Override", systemImage: "xmark.circle")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.16), radius: 8, y: 3)

                    // 1B. ADAPTIVE SUGGESTED PROFILE CALLOUT CARD (High contrast in both Light & Dark Mode!)
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(PositronTheme.accentCyan(colorScheme))
                            .frame(width: 34, height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(PositronTheme.accentCyan(colorScheme).opacity(0.14))
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text("Suggested Best Profile: \(info.recommendedSummary)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(PositronTheme.accentCyan(colorScheme))
                                BadgePill(
                                    text: GameQuirksDatabase.isHandTuned(info.appID) ? "HAND-TUNED" : (isCurated ? "ENGINE PRESET" : "AUTO-ANALYZED PE"),
                                    color: isCurated ? .cyan : .purple
                                )
                            }
                            Text(info.notes)
                                .font(.system(size: 11))
                                .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        if !vm.isEditingMatchingRecommended || !isApplied {
                            Button {
                                vm.applySuggestedProfileToSteam()
                            } label: {
                                Label("Use Suggested & Apply", systemImage: "wand.and.stars")
                            }
                            .controlSize(.small)
                            .glassActionButton(prominent: false)
                        } else {
                            BadgePill(text: "SUGGESTED ACTIVE", color: .green, icon: "checkmark.circle.fill")
                        }
                    }
                    .padding(13)
                    .glassCard(cornerRadius: 13, tint: .cyan)

                    // 2. 2-COLUMN ADAPTIVE GLASS BENTO GRID
                    HStack(alignment: .top, spacing: 14) {
                        // LEFT BENTO COLUMN: CPU & GRAPHICS PIPELINE
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Label("CPU & Graphics Pipeline", systemImage: "cpu.fill")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(PositronTheme.primaryText(colorScheme))
                                Spacer()
                                Button("Reset to Suggested") {
                                    vm.resetToRecommendedProfile()
                                }
                                .font(.caption)
                                .foregroundStyle(PositronTheme.accentCyan(colorScheme))
                                .buttonStyle(.plain)
                            }

                            Text("CPU Translation Engine")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(PositronTheme.secondaryText(colorScheme))

                            HStack(spacing: 9) {
                                SelectableOptionCard(
                                    title: "Rosetta 2 (x86_64)",
                                    badge: "DX12 & 32-BIT",
                                    badgeColor: .blue,
                                    subtitle: "Best for DirectX 12 (D3DMetal), AVX, and 32-bit CEF launchers.",
                                    icon: "cpu",
                                    isSelected: vm.editingProfile.translator == .rosetta
                                ) {
                                    vm.editingProfile.translator = .rosetta
                                }

                                SelectableOptionCard(
                                    title: "FEX ARM64EC",
                                    badge: "LOW OVERHEAD",
                                    badgeColor: .purple,
                                    subtitle: "Native ARM64 Wine + FEX JIT. Fastest for 64-bit DX11 games.",
                                    icon: "bolt.horizontal.circle.fill",
                                    isSelected: vm.editingProfile.translator == .fex
                                ) {
                                    vm.editingProfile.translator = .fex
                                    if vm.editingProfile.graphics == .d3dMetal {
                                        vm.editingProfile.graphics = .dxmt
                                    }
                                }
                            }

                            Text("Graphics Renderer")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(PositronTheme.secondaryText(colorScheme))

                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                                SelectableOptionCard(
                                    title: "D3DMetal (GPTK)",
                                    badge: "DX12 / DX11",
                                    badgeColor: .green,
                                    subtitle: "Apple Game Porting Toolkit shader converter for DirectX 12.",
                                    icon: "cube.transparent.fill",
                                    isSelected: vm.editingProfile.graphics == .d3dMetal
                                ) {
                                    vm.editingProfile.graphics = .d3dMetal
                                    if vm.editingProfile.translator == .fex {
                                        vm.editingProfile.translator = .rosetta
                                    }
                                }

                                SelectableOptionCard(
                                    title: "DXMT (Metal)",
                                    badge: "DX11 FAST",
                                    badgeColor: .cyan,
                                    subtitle: "Native Metal DirectX 11 with 120 FPS Apple Silicon cap.",
                                    icon: "sparkles.rectangle.stack.fill",
                                    isSelected: vm.editingProfile.graphics == .dxmt
                                ) {
                                    vm.editingProfile.graphics = .dxmt
                                }

                                SelectableOptionCard(
                                    title: "WineD3D",
                                    badge: "32-BIT / CEF",
                                    badgeColor: .orange,
                                    subtitle: "Best for 32-bit CEF launchers (SWTOR) and legacy DX9.",
                                    icon: "window.ceiling",
                                    isSelected: vm.editingProfile.graphics == .wineD3D
                                ) {
                                    vm.editingProfile.graphics = .wineD3D
                                }

                                SelectableOptionCard(
                                    title: "DXVK",
                                    badge: "DX9 / DX10 / DX11",
                                    badgeColor: .indigo,
                                    subtitle: "Vulkan-to-MoltenVK renderer for older Direct3D titles.",
                                    icon: "square.3.layers.3d.down.right",
                                    isSelected: vm.editingProfile.graphics == .dxvk
                                ) {
                                    vm.editingProfile.graphics = .dxvk
                                }
                            }

                            HStack {
                                Text("Sync Mode")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                                Spacer()
                                Picker("", selection: $vm.editingProfile.sync) {
                                    ForEach(SyncPrimitive.allCases, id: \.self) { syncMode in
                                        Text(syncMode.rawValue.uppercased()).tag(syncMode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 220)
                            }

                            GameFixesPanel(vm: vm)

                            Divider().opacity(0.5)

                            VStack(spacing: 7) {
                                FeatureToggleCard(
                                    title: "Launch in Fullscreen",
                                    subtitle: "Start game in fullscreen at full display resolution",
                                    icon: "arrow.up.left.and.arrow.down.right",
                                    isOn: $vm.editingProfile.fullscreenMode
                                )
                                FeatureToggleCard(
                                    title: "Retina High-DPI Mode",
                                    subtitle: "Render at native macOS Retina pixel density",
                                    icon: "display",
                                    isOn: $vm.editingProfile.retinaMode
                                )
                                FeatureToggleCard(
                                    title: "Metal Performance HUD",
                                    subtitle: "Show real-time FPS & GPU frame-time graph",
                                    icon: "speedometer",
                                    isOn: $vm.editingProfile.metalHUD
                                )
                                FeatureToggleCard(
                                    title: "Controller Double-Input Fix",
                                    subtitle: "Disable raw hidraw so Steam Input owns gamepads",
                                    icon: "gamecontroller.fill",
                                    isOn: $vm.editingProfile.disableHidraw
                                )
                            }
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .glassCard(cornerRadius: 15, tint: .cyan)

                        // RIGHT BENTO COLUMN: WINE PREFIX & UTILITIES GRID
                        VStack(alignment: .leading, spacing: 11) {
                            HStack(alignment: .center) {
                                Label("Wine Prefix & Utilities", systemImage: "shippingbox.fill")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(PositronTheme.primaryText(colorScheme))
                                Spacer()
                                BadgePill(
                                    text: hasPfx ? "INITIALIZED" : "ON FIRST RUN",
                                    color: hasPfx ? .green : .orange,
                                    icon: hasPfx ? "checkmark.circle.fill" : "clock"
                                )
                                BadgePill(
                                    text: pfx.detectedPEArch ?? (pfx.isFEXPrefix ? "arm64" : "x86_64"),
                                    color: .blue
                                )
                            }

                            // Compact Prefix Path Bar
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.gearshape")
                                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                                    .font(.caption2)
                                Text(pfx.pfxURL.path(percentEncoded: false))
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(pfx.pfxURL.path(percentEncoded: false), forType: .string)
                                    vm.statusBanner = "Copied prefix path to clipboard."
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption2)
                                        .foregroundStyle(PositronTheme.accentCyan(colorScheme))
                                }
                                .buttonStyle(.borderless)
                                .help("Copy prefix path")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6.5)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(PositronTheme.tileFill(colorScheme, isSelected: false, accent: .cyan))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(PositronTheme.tileBorder(colorScheme, isSelected: false, accent: .cyan), lineWidth: 1)
                            )

                            Text("Windows Configuration Tools")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(PositronTheme.secondaryText(colorScheme))

                            // 2x2 Bento Grid of Wine Utilities
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                                UtilityActionTile(
                                    title: "Wine Settings",
                                    subtitle: "winecfg • Windows version, DPI & audio",
                                    icon: "slider.horizontal.3",
                                    accent: PositronTheme.accentCyan(colorScheme)
                                ) {
                                    vm.launchUtility(.winecfg, in: pfx)
                                }

                                UtilityActionTile(
                                    title: "Registry Editor",
                                    subtitle: "regedit • Inspect & modify keys",
                                    icon: "list.bullet.rectangle.portrait",
                                    accent: PositronTheme.accentPurple(colorScheme)
                                ) {
                                    vm.launchUtility(.regedit, in: pfx)
                                }

                                UtilityActionTile(
                                    title: "Control Panel",
                                    subtitle: "control • Gamepads & system applets",
                                    icon: "gearshape.2.fill",
                                    accent: PositronTheme.accentBlue(colorScheme)
                                ) {
                                    vm.launchUtility(.control, in: pfx)
                                }

                                UtilityActionTile(
                                    title: "Uninstallers",
                                    subtitle: "uninstaller • VC++ & redistributables",
                                    icon: "shippingbox.and.arrow.backward.fill",
                                    accent: PositronTheme.accentOrange(colorScheme)
                                ) {
                                    vm.launchUtility(.uninstaller, in: pfx)
                                }
                            }

                            Text("Files, Installers & Maintenance")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(PositronTheme.secondaryText(colorScheme))

                            // 2x2 Bento Grid for Installers, Drive C:, Save Games, & Log
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                                UtilityActionTile(
                                    title: "Run .exe / .msi",
                                    subtitle: "Execute installer or tool in prefix",
                                    icon: "play.square.fill",
                                    accent: PositronTheme.accentGreen(colorScheme)
                                ) {
                                    vm.chooseAndRunInstaller(in: pfx)
                                }

                                UtilityActionTile(
                                    title: "Open Drive C:",
                                    subtitle: "Browse Windows system & Program Files",
                                    icon: "folder.fill",
                                    accent: PositronTheme.accentCyan(colorScheme)
                                ) {
                                    try? FileManager.default.createDirectory(at: pfx.driveCURL, withIntermediateDirectories: true)
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: pfx.driveCURL.path(percentEncoded: false))
                                }

                                UtilityActionTile(
                                    title: "Open Save Games",
                                    subtitle: "Browse steamuser AppData & Documents",
                                    icon: "externaldrive.badge.person.crop",
                                    accent: PositronTheme.accentPurple(colorScheme)
                                ) {
                                    try? FileManager.default.createDirectory(at: pfx.steamuserURL, withIntermediateDirectories: true)
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: pfx.steamuserURL.path(percentEncoded: false))
                                }

                                UtilityActionTile(
                                    title: "Launch Log",
                                    subtitle: pfx.hasLaunchLog ? "Open notproton-run.log diagnostic file" : "Log created on next game launch",
                                    icon: "doc.text.magnifyingglass",
                                    accent: pfx.hasLaunchLog ? PositronTheme.accentGreen(colorScheme) : PositronTheme.mutedText(colorScheme)
                                ) {
                                    if pfx.hasLaunchLog {
                                        NSWorkspace.shared.open(pfx.launchLogURL)
                                    } else {
                                        vm.statusBanner = "No launch log yet—launch \(info.title) in Steam first."
                                    }
                                }
                            }

                            Divider().opacity(0.5)

                            HStack(spacing: 9) {
                                Button {
                                    vm.stopWineProcesses(in: pfx)
                                } label: {
                                    Label("Kill Wine Server", systemImage: "stop.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .glassActionButton()
                                .controlSize(.small)

                                if hasPfx {
                                    Button(role: .destructive) {
                                        vm.rebuildPrefix(in: pfx)
                                    } label: {
                                        Label("Rebuild Prefix (Keep Saves)", systemImage: "arrow.triangle.2.circlepath")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .glassActionButton()
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .glassCard(cornerRadius: 15, tint: .purple)
                    }

                    // 3. TECHNICAL ENVIRONMENT INSPECTOR
                    DisclosureGroup("Technical Launch Environment & DLL Overrides", isExpanded: $showTechDetails) {
                        let runnerURL = vm.runners.first?.rootURL
                            ?? URL(filePath: "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver")
                        let env = vm.editingProfile.buildLaunchEnvironment(
                            runnerRoot: runnerURL,
                            prefixRoot: pfx.compatDataURL
                        )
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(env.keys.sorted(), id: \.self) { k in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(k)
                                        .font(.caption2.monospaced().weight(.bold))
                                        .foregroundStyle(PositronTheme.accentCyan(colorScheme))
                                        .frame(width: 190, alignment: .leading)
                                    Text(env[k] ?? "")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                Divider().opacity(0.4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    .padding(14)
                    .glassCard(cornerRadius: 13, tint: .cyan)
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $showLibrarySheet) {
            PresetLibraryBrowserSheet(vm: vm, isPresented: $showLibrarySheet)
        }
    }
}


// MARK: - Preset Catalog Modal Sheet

struct PresetLibraryBrowserSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel
    @Binding var isPresented: Bool
    @State private var filterText = ""

    var entries: [PresetCatalogEntry] {
        let all = GameQuirksDatabase.loadCustomCatalog()
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.info.title.lowercased().contains(q) ||
            $0.info.subtitle.lowercased().contains(q) ||
            $0.info.recommendedSummary.lowercased().contains(q) ||
            String($0.info.appID).contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Positron Curated Preset Catalog (\(entries.count) Games)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PositronTheme.primaryText(colorScheme))
                    Text("When any of these games is installed in Steam, Positron automatically recommends its optimal macOS translation pipeline.")
                        .font(.caption)
                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                }
                Spacer()
                Button("Edit JSON Catalog...") {
                    vm.openPresetsCatalogJSON()
                }
                .glassActionButton()
                Button("Done") {
                    isPresented = false
                }
                .glassActionButton(prominent: true)
            }

            TextField("Search 50+ game presets by title, engine, DirectX, or AppID...", text: $filterText)
                .textFieldStyle(.roundedBorder)

            List(entries) { entry in
                let isInstalled = vm.installedApps[entry.info.appID] != nil
                HStack(alignment: .top, spacing: 12) {
                    GameTileAvatar(title: entry.info.title, appID: entry.info.appID, size: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(entry.info.title)
                                .font(.headline)
                            Text("AppID \(entry.info.appID)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            if isInstalled {
                                BadgePill(text: "INSTALLED ON MAC", color: .green)
                            }
                        }
                        Text(entry.info.subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("Recommended: \(entry.info.recommendedSummary)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PositronTheme.accentCyan(colorScheme))
                        Text(entry.info.notes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isInstalled {
                        Button("Configure Game") {
                            vm.loadProfile(for: entry.info.appID)
                            isPresented = false
                        }
                        .controlSize(.small)
                        .glassActionButton(prominent: true)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
    }
}


// MARK: - Switchable Game Fixes

struct GameFixesPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { vm.isFixEnabled(id) },
            set: { vm.setFix(id, enabled: $0) }
        )
    }

    private func dllDetail(_ mode: String) -> String {
        switch mode {
        case "d": return "Disabled: the game never loads this DLL"
        case "b": return "Always use Wine's builtin version"
        case "n": return "Always use the game's own version"
        default: return "Prefer the game's own DLL, fall back to Wine's"
        }
    }

    var body: some View {
        let fixes = RuntimeFix.applicable(to: vm.selectedAppID)
        let gameFixes = fixes.filter { $0.scope == .game }
        let globalFixes = fixes.filter { $0.scope == .global }
        let masterOn = vm.editingProfile.gameFixesEnabled
        let dlls = vm.editingProfile.dllOverrides.keys.sorted()
        let envKeys = vm.editingProfile.extraEnvironment.keys.sorted()

        VStack(alignment: .leading, spacing: 6) {
            Text("Game Fixes")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(PositronTheme.secondaryText(colorScheme))

            FeatureToggleCard(
                title: "Game-Specific Fixes",
                subtitle: "Master switch for this game's patches, DLL overrides and flags",
                icon: "wrench.and.screwdriver.fill",
                isOn: $vm.editingProfile.gameFixesEnabled
            )

            VStack(spacing: 5) {
                ForEach(gameFixes) { fix in
                    FixToggleRow(title: fix.title, detail: fix.detail, icon: "bandage.fill", isOn: binding(fix.id))
                }
                ForEach(dlls, id: \.self) { dll in
                    let mode = vm.editingProfile.dllOverrides[dll] ?? ""
                    FixToggleRow(
                        title: "DLL \(dll) = \(mode)",
                        detail: dllDetail(mode),
                        icon: "puzzlepiece.extension.fill",
                        isOn: binding(RuntimeFix.dllID(dll))
                    )
                }
                ForEach(envKeys, id: \.self) { key in
                    FixToggleRow(
                        title: "\(key)=\(vm.editingProfile.extraEnvironment[key] ?? "")",
                        detail: "Runtime flag for the graphics or Wine layer",
                        icon: "gearshape.fill",
                        isOn: binding(RuntimeFix.envID(key))
                    )
                }
            }
            .disabled(!masterOn)
            .opacity(masterOn ? 1 : 0.45)

            if !globalFixes.isEmpty {
                Text("Launch Safeguards (every game)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(PositronTheme.mutedText(colorScheme))
                    .padding(.top, 4)
                ForEach(globalFixes) { fix in
                    FixToggleRow(title: fix.title, detail: fix.detail, icon: "shield.lefthalf.filled", isOn: binding(fix.id))
                }
            }
        }
    }
}

struct FixToggleRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let detail: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        let accent = PositronTheme.accentCyan(colorScheme)
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isOn ? accent : PositronTheme.mutedText(colorScheme))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PositronTheme.primaryText(colorScheme))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(PositronTheme.tileFill(colorScheme, isSelected: false, accent: accent))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(PositronTheme.tileBorder(colorScheme, isSelected: false, accent: accent), lineWidth: 0.8)
        )
    }
}
