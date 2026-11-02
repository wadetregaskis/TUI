//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalSixelSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

// MARK: - Whether this terminal draws pictures by Sixel

extension TerminalClient {

    /// DA1's reply, from a host with no Kitty that the environment named, so that
    /// the startup exchange did not ask it who it is.
    @MainActor static var detectedPrimaryAttributes: String?

    /// How many colour registers the terminal said it has (`XTSMGRAPHICS`), or `nil`.
    @MainActor static var detectedSixelRegisters: Int?

    /// The cell in Sixel's pixels by `CSI 16 t`, for a host whose `TIOCGWINSZ` says
    /// nothing: over some ssh connections, and on Windows.
    @MainActor static var detectedSixelCell: TerminalCellPixels?

    /// Whether this terminal's pictures are drawn by Sixel: see
    /// ``sixelInUse(override:environment:detectedPictures:primaryAttributes:isTmux:)``.
    @MainActor static var sixelInUse: Bool {
        sixelInUse(
            override: graphicsSupport, environment: ProcessInfo.processInfo.environment,
            detectedPictures: detectedPictures,
            primaryAttributes: current.primaryDeviceAttributes ?? detectedPrimaryAttributes,
            isTmux: TerminalHost.isTmux)
    }

    /// Whether pictures go by Sixel, posed on its inputs: `TUI_GRAPHICS=sixel`, or
    /// no answer to either Kitty question, attribute 4 in DA1, and no multiplexer.
    /// Last of the paths: placeholders, classic placements, Sixel, glyphs.
    ///
    /// Asked, not looked up, so a host nobody here has run gets pictures by its own
    /// answer. tmux says 4 of itself whether or not the terminal watching it can draw
    /// one (measured, §2), and blank cells are worse than glyphs: a table of one,
    /// which `TUI_GRAPHICS=sixel` overrules.
    ///
    /// An override's `true` is a claim about placements, so it does not choose this.
    static func sixelInUse(
        override: Bool?, environment: [String: String], detectedPictures: Bool?, primaryAttributes: String?,
        isTmux: Bool
    ) -> Bool {
        if override == false { return false }
        switch environment["TUI_GRAPHICS"] {
        case "sixel": return true
        case "0", "1", "classic": return false
        default:
            guard override == nil, detectedPictures == false, !isTmux, let primaryAttributes else { return false }
            return deviceAttributesAdvertiseSixel(primaryAttributes)
        }
    }

    /// Whether a Primary Device Attributes reply lists attribute 4.
    static func deviceAttributesAdvertiseSixel(_ reply: String) -> Bool {
        guard reply.hasPrefix("\u{1B}[?"), reply.hasSuffix("c") else { return false }
        return reply.dropFirst(3).dropLast().split(separator: ";").contains("4")
    }

    /// A cell in Sixel's pixels, from what the terminal reports: `reported`, the
    /// reading of `TIOCGWINSZ`, which is device pixels on iTerm2 where `CSI 16 t` is
    /// points (measured 14 x 34 against 7 x 17, and iTerm2 draws a Sixel pixel as a
    /// device pixel). Windows Terminal is first, as it draws Sixel on a fixed 10 x 20
    /// whatever its font (read from its source, not run). `nil` leaves it as it is.
    @MainActor static func sixelCell(reported: TerminalCellPixels?) -> TerminalCellPixels? {
        sixelCell(
            reported: reported, asked: detectedSixelCell,
            isWindowsTerminal: ProcessInfo.processInfo.environment["WT_SESSION"] != nil)
    }

    /// ``sixelCell(reported:)``, posed on its inputs.
    static func sixelCell(
        reported: TerminalCellPixels?, asked: TerminalCellPixels?, isWindowsTerminal: Bool
    ) -> TerminalCellPixels? {
        if isWindowsTerminal { return TerminalCellPixels(width: 10, height: 20) }
        return reported ?? asked
    }
}
