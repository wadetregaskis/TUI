//  🖥️ TUI — A Terminal UI framework for Swift
//  SystemColor.swift
//
//  SwiftUI's named colours that follow the colour scheme, and their light and
//  dark values.
//
//  Created by Wade Tregaskis
//  License: MIT

extension Color {
    /// One of SwiftUI's named colours whose value follows the colour scheme:
    /// `Color.red`, `.blue` and the eleven others with a light and a dark value.
    ///
    /// A NAME, resolved where it is drawn: ``Color/resolve(with:)`` answers the
    /// value for the palette's ``Palette/colorScheme``, so `.red` is Apple's
    /// light red on a light page and its dark red on a dark one, and in a
    /// subtree pinned with `.environment(\.colorScheme, …)` the pinned scheme's.
    /// Everything that reads a colour's components without a palette — a blend,
    /// a contrast floor, ``Color/rgbComponents``, done in a view body — reads
    /// the LIGHT value, as SwiftUI's `resolve(in: EnvironmentValues())` does.
    ///
    /// `Color.black` and `Color.white` are not cases: they are the same in both
    /// schemes, so they are plain RGB. Neither is TUI's own `Color.magenta`.
    ///
    /// The values are measured, not guessed: `Color.resolve(in:)` under a light
    /// and a dark `EnvironmentValues` on macOS 15.8.1, which agree with
    /// `NSColor.systemRed` and friends under the aqua and darkAqua appearances
    /// (`Tools/SwiftUIProbes/Named colours by scheme/namedcolours.swift`, and
    /// its `.out`).
    public enum SystemColor: UInt8, Sendable, CaseIterable {
        case red
        case orange
        case yellow
        case green
        case mint
        case teal
        case cyan
        case blue
        case indigo
        case purple
        case pink
        case brown
        case gray

        /// The value under a light colour scheme, `0xRRGGBB`.
        var lightHex: UInt32 {
            switch self {
            case .red: 0xFF_3B_30
            case .orange: 0xFF_95_00
            case .yellow: 0xFF_CC_00
            case .green: 0x28_CD_41
            case .mint: 0x00_C7_BE
            case .teal: 0x59_AD_C4
            case .cyan: 0x55_BE_F0
            case .blue: 0x00_7A_FF
            case .indigo: 0x58_56_D6
            case .purple: 0xAF_52_DE
            case .pink: 0xFF_2D_55
            case .brown: 0xA2_84_5E
            case .gray: 0x8E_8E_93
            }
        }

        /// The value under a dark colour scheme, `0xRRGGBB`.
        var darkHex: UInt32 {
            switch self {
            case .red: 0xFF_45_3A
            case .orange: 0xFF_9F_0A
            case .yellow: 0xFF_D6_0A
            case .green: 0x32_D7_4B
            case .mint: 0x63_E6_E2
            case .teal: 0x6A_C4_DC
            case .cyan: 0x5A_C8_F5
            case .blue: 0x0A_84_FF
            case .indigo: 0x5E_5C_E6
            case .purple: 0xBF_5A_F2
            case .pink: 0xFF_37_5F
            case .brown: 0xAC_8E_68
            case .gray: 0x98_98_9D
            }
        }

        /// This colour's value under `scheme`, as an opaque RGB colour.
        public func color(in scheme: ColorScheme) -> Color {
            .hex(scheme == .dark ? darkHex : lightHex)
        }

        /// The value a view body measures: the light one.
        var lightComponents: (red: UInt8, green: UInt8, blue: UInt8) {
            let hex = lightHex
            return (UInt8(truncatingIfNeeded: hex >> 16), UInt8(truncatingIfNeeded: hex >> 8),
                UInt8(truncatingIfNeeded: hex))
        }
    }
}
