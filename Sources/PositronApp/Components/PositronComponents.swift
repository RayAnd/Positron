// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PositronCore

// MARK: - Modernized Liquid Glass Brand Icon & Artwork Views

struct PositronBrandIcon: View {
    var size: CGFloat = 56

    var body: some View {
        let corner = size * 0.235
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.03, green: 0.06, blue: 0.17),
                            Color(red: 0.07, green: 0.04, blue: 0.21),
                            Color(red: 0.02, green: 0.13, blue: 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color.cyan.opacity(0.28), radius: size * 0.14, y: 2)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.cyan.opacity(0.55), Color.blue.opacity(0.18), .clear],
                            center: .center,
                            startRadius: 1,
                            endRadius: size * 0.45
                        )
                    )
                    .offset(x: -size * 0.15, y: -size * 0.16)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.50), Color.pink.opacity(0.16), .clear],
                            center: .center,
                            startRadius: 1,
                            endRadius: size * 0.45
                        )
                    )
                    .offset(x: size * 0.16, y: size * 0.15)

                ForEach([-32.0, 32.0, 90.0], id: \.self) { angle in
                    Ellipse()
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color.cyan.opacity(0.15),
                                    Color(red: 0.38, green: 0.94, blue: 1.0),
                                    .white,
                                    Color(red: 0.76, green: 0.44, blue: 1.0),
                                    Color.cyan.opacity(0.15)
                                ],
                                center: .center
                            ),
                            lineWidth: max(1.2, size * 0.024)
                        )
                        .frame(width: size * 0.74, height: size * 0.29)
                        .rotationEffect(.degrees(angle))
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.cyan.opacity(0.24),
                                Color.purple.opacity(0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size * 0.44, height: size * 0.44)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.9), .cyan.opacity(0.55), .purple.opacity(0.45)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: max(1.0, size * 0.02)
                            )
                    )

                Text("e⁺")
                    .font(.system(size: size * 0.29, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, Color(red: 0.72, green: 0.96, blue: 1.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color.cyan.opacity(0.75), radius: size * 0.08)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.32), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.90, height: size * 0.42)
                    .offset(y: -size * 0.26)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color.cyan.opacity(0.55),
                            Color.purple.opacity(0.40),
                            Color.cyan.opacity(0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.2, size * 0.025)
                )
                .frame(width: size, height: size)
        }
    }
}

struct GameTileAvatar: View {
    let title: String
    let appID: UInt32
    var size: CGFloat = 38

    private var initials: String {
        let words = title
            .replacingOccurrences(of: ":", with: " ")
            .split(separator: " ")
            .filter { !["the", "of", "and", "a", "for"].contains($0.lowercased()) }
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if let first = words.first {
            return String(first.prefix(2)).uppercased()
        }
        return "GM"
    }

    private var gradientColors: [Color] {
        let palette: [[Color]] = [
            [Color(red: 0.09, green: 0.36, blue: 0.68), Color(red: 0.04, green: 0.62, blue: 0.78)],
            [Color(red: 0.42, green: 0.16, blue: 0.68), Color(red: 0.18, green: 0.42, blue: 0.85)],
            [Color(red: 0.68, green: 0.22, blue: 0.16), Color(red: 0.85, green: 0.48, blue: 0.12)],
            [Color(red: 0.08, green: 0.52, blue: 0.42), Color(red: 0.14, green: 0.32, blue: 0.64)],
            [Color(red: 0.52, green: 0.12, blue: 0.42), Color(red: 0.24, green: 0.14, blue: 0.54)]
        ]
        let idx = Int(appID % UInt32(palette.count))
        return palette[idx]
    }

    var body: some View {
        let corner = size * 0.23
        if let nsImage = GameArtworkLoader.shared.iconImage(for: appID) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 3, y: 1)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )

                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

struct BadgePill: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    let color: Color
    var icon: String? = nil
    var forceDarkSurface: Bool = false

    private var resolvedForeground: Color {
        if forceDarkSurface || colorScheme == .dark {
            if color == .cyan { return Color(red: 0.32, green: 0.90, blue: 1.0) }
            if color == .green { return Color(red: 0.32, green: 0.95, blue: 0.58) }
            if color == .orange { return Color(red: 1.0, green: 0.72, blue: 0.28) }
            if color == .purple { return Color(red: 0.82, green: 0.62, blue: 1.0) }
            if color == .blue { return Color(red: 0.48, green: 0.76, blue: 1.0) }
            return color
        } else {
            if color == .cyan { return Color(red: 0.00, green: 0.42, blue: 0.72) }
            if color == .green { return Color(red: 0.05, green: 0.50, blue: 0.25) }
            if color == .orange { return Color(red: 0.76, green: 0.36, blue: 0.00) }
            if color == .purple { return Color(red: 0.42, green: 0.18, blue: 0.76) }
            if color == .blue { return Color(red: 0.08, green: 0.36, blue: 0.78) }
            if color == .indigo { return Color(red: 0.26, green: 0.22, blue: 0.74) }
            return color
        }
    }

    var body: some View {
        let fg = resolvedForeground
        HStack(spacing: 3.5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .bold))
            }
            Text(text)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 7.5)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(fg.opacity(forceDarkSurface ? 0.24 : (colorScheme == .dark ? 0.18 : 0.13)))
        )
        .overlay(
            Capsule()
                .stroke(fg.opacity(forceDarkSurface ? 0.55 : 0.38), lineWidth: 0.8)
        )
        .foregroundStyle(fg)
    }
}


// MARK: - Interactive High-Contrast Cards for Game Inspector

struct SelectableOptionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let badge: String
    let badgeColor: Color
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let accent = PositronTheme.accentCyan(colorScheme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(isSelected ? accent : PositronTheme.secondaryText(colorScheme))
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PositronTheme.primaryText(colorScheme))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? accent : PositronTheme.mutedText(colorScheme).opacity(0.6))
                        .font(.system(size: 13, weight: .bold))
                }
                BadgePill(text: badge, color: badgeColor)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
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

struct FeatureToggleCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        let accent = PositronTheme.accentCyan(colorScheme)
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? accent : PositronTheme.secondaryText(colorScheme))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(PositronTheme.primaryText(colorScheme))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8.5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(PositronTheme.tileFill(colorScheme, isSelected: isOn, accent: accent))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(PositronTheme.tileBorder(colorScheme, isSelected: isOn, accent: accent), lineWidth: 1)
        )
    }
}

struct UtilityActionTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(accent.opacity(0.15))
                        )
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(PositronTheme.mutedText(colorScheme))
                }
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(PositronTheme.primaryText(colorScheme))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(PositronTheme.secondaryText(colorScheme))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(PositronTheme.tileFill(colorScheme, isSelected: false, accent: accent))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(accent.opacity(colorScheme == .dark ? 0.32 : 0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

