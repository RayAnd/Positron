// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

// MARK: - Adaptive Light & Dark Mode Liquid Glass Theme

enum PositronTheme {
    static func isDark(_ scheme: ColorScheme) -> Bool {
        scheme == .dark
    }

    static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.95, green: 0.97, blue: 1.0)
            : Color(red: 0.08, green: 0.11, blue: 0.18)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.68, green: 0.74, blue: 0.84)
            : Color(red: 0.33, green: 0.39, blue: 0.49)
    }

    static func mutedText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.52, green: 0.58, blue: 0.68)
            : Color(red: 0.45, green: 0.51, blue: 0.61)
    }

    static func accentCyan(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.22, green: 0.86, blue: 1.0)
            : Color(red: 0.00, green: 0.44, blue: 0.78)
    }

    static func accentGreen(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.25, green: 0.90, blue: 0.52)
            : Color(red: 0.06, green: 0.54, blue: 0.28)
    }

    static func accentPurple(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.74, green: 0.52, blue: 1.0)
            : Color(red: 0.44, green: 0.20, blue: 0.80)
    }

    static func accentOrange(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 1.0, green: 0.64, blue: 0.22)
            : Color(red: 0.80, green: 0.38, blue: 0.00)
    }

    static func accentBlue(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.38, green: 0.68, blue: 1.0)
            : Color(red: 0.08, green: 0.38, blue: 0.82)
    }

    static func sidebarFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.055, green: 0.075, blue: 0.125)
            : Color(red: 0.895, green: 0.925, blue: 0.965)
    }

    static func navBarFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.075, green: 0.10, blue: 0.16).opacity(0.95)
            : Color(red: 0.945, green: 0.965, blue: 0.99).opacity(0.95)
    }

    static func columnFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.07, green: 0.095, blue: 0.15).opacity(0.78)
            : Color(red: 0.925, green: 0.948, blue: 0.98).opacity(0.82)
    }

    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.12, green: 0.155, blue: 0.23).opacity(0.90)
            : Color.white.opacity(0.92)
    }

    static func cardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.09)
    }

    static func chromeDivider(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.09)
            : Color.black.opacity(0.08)
    }

    static func tileFill(_ scheme: ColorScheme, isSelected: Bool, accent: Color) -> Color {
        if isSelected {
            return scheme == .dark
                ? accent.opacity(0.20)
                : accent.opacity(0.12)
        }
        return scheme == .dark
            ? Color(red: 0.16, green: 0.205, blue: 0.295).opacity(0.85)
            : Color.white.opacity(0.97)
    }

    static func tileBorder(_ scheme: ColorScheme, isSelected: Bool, accent: Color) -> Color {
        if isSelected {
            return scheme == .dark
                ? accent.opacity(0.85)
                : accent.opacity(0.75)
        }
        return scheme == .dark
            ? Color.white.opacity(0.11)
            : Color.black.opacity(0.10)
    }
}

// MARK: - Native macOS Window Chrome Configurator (Seamless Full-Bleed Titlebar)

struct WindowChromeConfigurator: NSViewRepresentable {
    var colorScheme: ColorScheme

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    @MainActor
    private func configureWindow(for view: NSView) {
        guard let window = view.window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        if window.toolbar != nil {
            window.toolbar = nil
        }
        window.isMovableByWindowBackground = false
        window.isOpaque = true
        window.backgroundColor = colorScheme == .dark
            ? NSColor(srgbRed: 0.07, green: 0.09, blue: 0.15, alpha: 1.0)
            : NSColor(srgbRed: 0.94, green: 0.96, blue: 0.99, alpha: 1.0)
    }
}

struct AdaptiveGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 14
    var tint: Color = .cyan
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                ZStack {
                    shape.fill(PositronTheme.cardFill(colorScheme))
                    shape.fill(
                        LinearGradient(
                            colors: [
                                colorScheme == .dark
                                    ? Color.white.opacity(0.05)
                                    : Color.white.opacity(0.75),
                                tint.opacity(colorScheme == .dark ? 0.05 : 0.03),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            )
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: isSelected
                            ? [tint.opacity(0.85), tint.opacity(0.45)]
                            : [
                                colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.95),
                                PositronTheme.cardBorder(colorScheme)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isSelected ? 1.5 : 1.0
                )
            )
            .shadow(
                color: colorScheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.05),
                radius: 8,
                y: 2
            )
    }
}

extension View {
    func glassCard(
        cornerRadius: CGFloat = 14,
        tint: Color = .cyan,
        isSelected: Bool = false
    ) -> some View {
        modifier(AdaptiveGlassCardModifier(cornerRadius: cornerRadius, tint: tint, isSelected: isSelected))
    }

    @ViewBuilder
    func glassActionButton(prominent: Bool = false) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

struct LiquidGlassAmbientBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.105, blue: 0.165),
                        Color(red: 0.095, green: 0.125, blue: 0.19)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.968, blue: 0.992),
                        Color(red: 0.925, green: 0.948, blue: 0.984)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.cyan.opacity(colorScheme == .dark ? 0.09 : 0.07),
                            Color.blue.opacity(colorScheme == .dark ? 0.04 : 0.025),
                            .clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 420
                    )
                )
                .frame(width: 760, height: 760)
                .offset(x: -220, y: -220)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.purple.opacity(colorScheme == .dark ? 0.08 : 0.05),
                            Color.indigo.opacity(colorScheme == .dark ? 0.035 : 0.02),
                            .clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 420
                    )
                )
                .frame(width: 720, height: 720)
                .offset(x: 280, y: 220)
        }
        .ignoresSafeArea()
    }
}
