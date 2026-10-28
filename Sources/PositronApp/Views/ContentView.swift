// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

// MARK: - Root macOS Window Shell (Seamless Full-Bleed Sidebar & Top Navigation Bar)

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel
    @State private var isSidebarVisible: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                PositronSidebarColumn(vm: vm, isSidebarVisible: $isSidebarVisible)
                    .frame(width: 244)
                    .transition(.move(edge: .leading))

                Rectangle()
                    .fill(PositronTheme.chromeDivider(colorScheme))
                    .frame(width: 1)
                    .ignoresSafeArea()
            }

            // Main Workspace Column with Integrated Top Navigation Bar
            ZStack {
                LiquidGlassAmbientBackdrop()

                VStack(spacing: 0) {
                    PositronTopNavigationBar(
                        vm: vm,
                        isSidebarVisible: $isSidebarVisible
                    )

                    if !vm.steamState.isPositronInjected || vm.isBridgeUpdateNeeded {
                        PositronActionBanner(vm: vm)
                    }

                    Group {
                        switch vm.selectedSection {
                        case .installedGames:
                            InstalledGamesView(vm: vm)
                        case .steamSetup:
                            SteamSetupView(vm: vm)
                        case .engines:
                            EnginesScreenView(vm: vm)
                        case .drives:
                            DrivesScreenView(vm: vm)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Bottom Status Bar
                    HStack(spacing: 10) {
                        Circle()
                            .fill(vm.steamState.isPositronInjected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(vm.statusBanner)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                            .lineLimit(1)
                        Spacer()
                        Text("\(vm.installedApps.count) Windows games • \(vm.libraries.count) Steam library drive(s)")
                            .font(.caption2)
                            .foregroundStyle(PositronTheme.mutedText(colorScheme))
                        Button {
                            vm.refreshAll()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .glassActionButton()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(PositronTheme.navBarFill(colorScheme))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(PositronTheme.chromeDivider(colorScheme))
                            .frame(height: 1)
                    }
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowChromeConfigurator(colorScheme: colorScheme))
        .frame(minWidth: 1140, minHeight: 740)
        .sheet(isPresented: $vm.showSupportSheet) {
            SupportPositronSheet(vm: vm, isPresented: $vm.showSupportSheet)
        }
    }
}

// MARK: - Full-Height Translucent macOS Sidebar

struct PositronSidebarColumn: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel
    @Binding var isSidebarVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Window Traffic-Light Header Row (38pt height aligns with macOS traffic lights)
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        isSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide Sidebar")
            }
            .frame(height: 36)
            .padding(.horizontal, 12)
            .padding(.top, 4)

            // Brand Header Card
            HStack(spacing: 11) {
                PositronBrandIcon(size: 40)
                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 6) {
                        Text("Positron")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(PositronTheme.primaryText(colorScheme))
                        BadgePill(text: "2.1", color: .cyan)
                    }
                    HStack(spacing: 5) {
                        Circle()
                            .fill(vm.steamState.isPositronInjected ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text(vm.steamState.isPositronInjected ? "Active in Steam" : "Steam Bridge Ready")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .glassCard(cornerRadius: 12, tint: .cyan)
            .padding(.horizontal, 11)

            Text("NAVIGATION")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(PositronTheme.mutedText(colorScheme))
                .padding(.horizontal, 16)
                .padding(.top, 2)

            // Custom High-Contrast Sidebar Navigation Rows
            VStack(spacing: 5) {
                ForEach(PositronSection.allCases) { section in
                    let isSelected = vm.selectedSection == section
                    let accent = PositronTheme.accentCyan(colorScheme)
                    Button {
                        vm.selectedSection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(isSelected ? accent : PositronTheme.secondaryText(colorScheme))
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1.5) {
                                Text(section.rawValue)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                                    .foregroundStyle(PositronTheme.primaryText(colorScheme))
                                Text(section.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                            }
                            Spacer()
                            if let badge = vm.badgeCount(for: section) {
                                BadgePill(text: badge, color: isSelected ? .cyan : .blue)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8.5)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    isSelected
                                        ? (colorScheme == .dark ? accent.opacity(0.18) : Color.white.opacity(0.92))
                                        : Color.clear
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    isSelected
                                        ? accent.opacity(colorScheme == .dark ? 0.50 : 0.45)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                        .shadow(
                            color: isSelected && colorScheme == .light ? Color.black.opacity(0.04) : .clear,
                            radius: 4,
                            y: 1
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)

            Spacer()

            // Sidebar Quick Footer
            VStack(spacing: 8) {
                Button {
                    vm.openOrSyncSteam()
                } label: {
                    Label(
                        !vm.steamState.isPositronInjected
                            ? "Enable in Steam"
                            : (vm.isBridgeUpdateNeeded ? "Update & Restart Steam" : "Open Steam"),
                        systemImage: !vm.steamState.isPositronInjected
                            ? "bolt.shield.fill"
                            : (vm.isBridgeUpdateNeeded ? "arrow.triangle.2.circlepath.circle.fill" : "play.fill")
                    )
                    .frame(maxWidth: .infinity)
                }
                .glassActionButton(prominent: true)
                .controlSize(.regular)

                HStack(spacing: 6) {
                    Button {
                        vm.refreshAll()
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .glassActionButton()
                    .controlSize(.small)
                    .help("Rescan Steam libraries and prefixes")

                    Button {
                        vm.enableInSteam()
                    } label: {
                        Label("Restart Steam", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .glassActionButton()
                    .controlSize(.small)
                    .help("Update Positron bridge in Steam.app and restart Steam automatically")
                }
            }
            .padding(10)
            .glassCard(cornerRadius: 12, tint: .cyan)
            .padding(.horizontal, 11)
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                PositronTheme.sidebarFill(colorScheme)
                LinearGradient(
                    colors: [
                        Color.cyan.opacity(colorScheme == .dark ? 0.04 : 0.03),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        )
    }
}

// MARK: - Integrated Top Window Navigation Bar

struct PositronTopNavigationBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel
    @Binding var isSidebarVisible: Bool

    var body: some View {
        let accent = PositronTheme.accentCyan(colorScheme)
        HStack(spacing: 12) {
            if !isSidebarVisible {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        isSidebarVisible = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .padding(.leading, 68) // Leave room for macOS traffic lights when sidebar is hidden
                .help("Show Sidebar")
            }

            // Section Breadcrumb Header
            HStack(spacing: 8) {
                Image(systemName: vm.selectedSection.icon)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(accent.opacity(0.14))
                    )

                Text(vm.selectedSection.rawValue)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PositronTheme.primaryText(colorScheme))

                if vm.selectedSection == .installedGames {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PositronTheme.mutedText(colorScheme))
                    Text(vm.selectedPresetInfo.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                        .lineLimit(1)
                    BadgePill(
                        text: "\(vm.editingProfile.translator.rawValue.uppercased()) • \(vm.editingProfile.graphics.rawValue.uppercased())",
                        color: .cyan
                    )
                } else {
                    Text("— \(vm.selectedSection.subtitle)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                }
            }

            Spacer()

            // Right-Hand Navigation Bar Controls: Engine Pill + Appearance Switcher + Steam Status
            if let primaryRunner = vm.runners.first {
                BadgePill(text: primaryRunner.displayName, color: .purple, icon: "cpu")
            }

            BadgePill(
                text: vm.steamState.isPositronInjected ? "STEAM BRIDGE ON" : "BRIDGE STANDBY",
                color: vm.steamState.isPositronInjected ? .green : .orange,
                icon: vm.steamState.isPositronInjected ? "checkmark.shield.fill" : "bolt.fill"
            )

            Button {
                vm.showSupportSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color.pink)
                    Text("Support")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(PositronTheme.primaryText(colorScheme))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.pink.opacity(colorScheme == .dark ? 0.18 : 0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.pink.opacity(0.45), lineWidth: 0.9)
                )
            }
            .buttonStyle(.plain)
            .help("Support Positron (Ko-fi & GitHub Sponsors)")

            // Appearance Mode Switcher Pill (Auto / Light / Dark)
            HStack(spacing: 2) {
                AppearanceModeButton(
                    label: "Auto",
                    icon: "circle.lefthalf.filled",
                    isSelected: vm.overrideColorScheme == nil,
                    colorScheme: colorScheme
                ) {
                    NSApp.appearance = nil
                    vm.overrideColorScheme = nil
                }
                AppearanceModeButton(
                    label: "Light",
                    icon: "sun.max.fill",
                    isSelected: vm.overrideColorScheme == .light,
                    colorScheme: colorScheme
                ) {
                    NSApp.appearance = NSAppearance(named: .aqua)
                    vm.overrideColorScheme = .light
                }
                AppearanceModeButton(
                    label: "Dark",
                    icon: "moon.stars.fill",
                    isSelected: vm.overrideColorScheme == .dark,
                    colorScheme: colorScheme
                ) {
                    NSApp.appearance = NSAppearance(named: .darkAqua)
                    vm.overrideColorScheme = .dark
                }
            }
            .padding(2.5)
            .background(
                Capsule()
                    .fill(PositronTheme.cardFill(colorScheme))
            )
            .overlay(
                Capsule()
                    .stroke(PositronTheme.cardBorder(colorScheme), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(PositronTheme.navBarFill(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PositronTheme.chromeDivider(colorScheme))
                .frame(height: 1)
        }
    }
}

private struct AppearanceModeButton: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        let accent = PositronTheme.accentCyan(colorScheme)
        Button(action: action) {
            HStack(spacing: 3.5) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
            }
            .foregroundStyle(isSelected ? accent : PositronTheme.secondaryText(colorScheme))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill(isSelected ? accent.opacity(colorScheme == .dark ? 0.20 : 0.13) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Guided One-Click Action Banner

struct PositronActionBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel

    var body: some View {
        let isUpdate = vm.steamState.isPositronInjected && vm.isBridgeUpdateNeeded
        let accent = isUpdate ? PositronTheme.accentCyan(colorScheme) : PositronTheme.accentOrange(colorScheme)
        HStack(spacing: 12) {
            Image(systemName: isUpdate ? "arrow.triangle.2.circlepath.circle.fill" : "bolt.shield.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(isUpdate ? "Positron Bridge Update Ready" : "Step 1: Enable Positron in Steam")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(PositronTheme.primaryText(colorScheme))
                Text(
                    isUpdate
                        ? "A newer Steam bridge and launch scripts are ready. Click once to update Steam.app and restart Steam automatically."
                        : "Click once to install the Positron compatibility bridge into Steam.app and restart Steam automatically."
                )
                .font(.system(size: 11))
                .foregroundStyle(PositronTheme.secondaryText(colorScheme))
            }

            Spacer()

            Button {
                vm.enableInSteam()
            } label: {
                Label(
                    isUpdate ? "Update & Restart Steam" : "Enable Positron in Steam",
                    systemImage: isUpdate ? "arrow.triangle.2.circlepath" : "bolt.fill"
                )
                .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(accent.opacity(colorScheme == .dark ? 0.14 : 0.10))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(accent.opacity(0.35))
                .frame(height: 1)
        }
    }
}

// MARK: - Voluntary Contributions Sheet (Ko-fi & GitHub Sponsors)

struct SupportPositronSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var vm: PositronViewModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.pink.opacity(0.16))
                        .frame(width: 52, height: 52)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.pink)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Support Positron")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(PositronTheme.primaryText(colorScheme))
                        BadgePill(text: "100% FREE & OPEN SOURCE", color: .cyan)
                    }
                    Text("Positron is completely free—no ads, no paywalls, and no subscriptions. If it helped you play your Windows library on your Mac, voluntary tips help fund testing and new game fixes.")
                        .font(.caption)
                        .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            VStack(spacing: 10) {
                // Option 1: Ko-fi
                HStack(spacing: 14) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PositronTheme.accentOrange(colorScheme))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(PositronTheme.accentOrange(colorScheme).opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Buy a Coffee on Ko-fi")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(PositronTheme.primaryText(colorScheme))
                            BadgePill(text: "APPLE PAY • NO LOGIN", color: .orange)
                        }
                        Text("Quick one-time contribution via Apple Pay, card, or PayPal with 0% platform fee.")
                            .font(.caption)
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                        Text(vm.funding.kofiURL)
                            .font(.caption2.monospaced())
                            .foregroundStyle(PositronTheme.mutedText(colorScheme))
                    }

                    Spacer()

                    Button {
                        vm.openKofiSupport()
                    } label: {
                        Label("Open Ko-fi", systemImage: "arrow.up.right")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(14)
                .glassCard(cornerRadius: 13, tint: .orange)

                // Option 2: GitHub Sponsors
                HStack(spacing: 14) {
                    Image(systemName: "heart.circle.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(PositronTheme.accentPurple(colorScheme))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(PositronTheme.accentPurple(colorScheme).opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Sponsor on GitHub")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(PositronTheme.primaryText(colorScheme))
                            BadgePill(text: "0% FEES", color: .purple)
                        }
                        Text("One-time or monthly sponsorship directly through your GitHub account.")
                            .font(.caption)
                            .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                        Text(vm.funding.githubSponsorsURL)
                            .font(.caption2.monospaced())
                            .foregroundStyle(PositronTheme.mutedText(colorScheme))
                    }

                    Spacer()

                    Button {
                        vm.openGitHubSponsors()
                    } label: {
                        Label("GitHub Sponsors", systemImage: "arrow.up.right")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
                .padding(14)
                .glassCard(cornerRadius: 13, tint: .purple)
            }

            HStack {
                Button {
                    vm.openGitHubRepo()
                } label: {
                    Label("Star Positron on GitHub", systemImage: "star.fill")
                }
                .glassActionButton()

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 580)
    }
}
