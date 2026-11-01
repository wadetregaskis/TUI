//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalGraphicsSupport.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation

// MARK: - Whether this terminal draws pictures

extension TerminalClient {

    /// What the startup handshake was told, or `nil` if it never ran — no
    /// terminal, an answer already forced, or a host measured to print APC.
    ///
    /// The counterpart of `TerminalHost.startupIdentity` for graphics, and
    /// deliberately not a host table. See `TerminalGraphicsQuery`.
    ///
    /// Public because "never asked" and "asked, and told no" are different
    /// facts about a terminal and a diagnostic has to be able to tell them
    /// apart — ``graphicsSupported`` collapses both to `false`, which is right
    /// for rendering and useless for reporting. Read-only: the way to change
    /// the answer is ``graphicsSupport``.
    @MainActor public private(set) static var detectedGraphics: Bool?

    /// What the handshake said to its second question — whether a deflated
    /// transmission (`o=z`) is understood — or `nil` if it never ran.
    ///
    /// Asked in the same exchange as ``detectedGraphics`` and kept apart
    /// from it, because a host can draw placements and still not take them
    /// compressed; the two are separate facts about a terminal, reported
    /// separately.
    @MainActor public private(set) static var detectedGraphicsCompression: Bool?

    /// Force the answer for the terminal in front of you, whatever was
    /// detected.
    ///
    /// `true` is for a terminal that supports placements but could not be
    /// asked — the handshake is skipped inside a host known to print APC, and
    /// under a multiplexer that swallows it. `false` turns pictures off for a
    /// terminal that has them, which an app may genuinely want: the glyph
    /// renderer is a look, not only a fallback, and an app built around
    /// `.braille` or a custom ramp does not want a photograph appearing on
    /// Ghostty and nowhere else.
    ///
    /// `nil` (the default) means "use the handshake", unless `TUI_GRAPHICS`
    /// is set — `1` for on, `0` for off — which is how a user answers for
    /// their own terminal without the application knowing anything about it,
    /// and how the round trip is skipped entirely.
    @MainActor public static var graphicsSupport: Bool? {
        didSet {
            guard graphicsSupport != oldValue else { return }
            applyGraphicsSupport()
        }
    }

    /// Force whether transmissions are deflated, whatever was detected.
    ///
    /// The same three-way ladder as ``graphicsSupport`` — this, then
    /// `TUI_GRAPHICS_COMPRESSION` (`1` or `0`), then the handshake — and
    /// it can only ever turn compression ON where pictures are on at all and
    /// a zlib was found: `true` on a host with no `libz` still sends raw
    /// pixels, because there is nothing to deflate with. Off is the answer to
    /// give a terminal that acknowledged the probe and then drew nothing.
    @MainActor public static var graphicsCompressionSupport: Bool? {
        didSet {
            guard graphicsCompressionSupport != oldValue else { return }
            applyGraphicsSupport()
        }
    }

    /// Publishes ``graphicsSupported`` to
    /// ``KittyGraphics/isSupported``, which is what the render path
    /// actually reads.
    ///
    /// The twin of ``applyHyperlinkSupport()``, for the same reason: the
    /// question is answered here, on the main actor, where the terminal can be
    /// asked; the answer is read from a render path that cannot ask anything.
    @MainActor
    public static func applyGraphicsSupport() {
        KittyGraphics.isSupported = graphicsSupported
        KittyGraphics.isCompressionSupported = graphicsCompressionSupported
        KittyGraphics.isHairlineSupported = hairlinesSupported
        KittyGraphics.isPictureUnderTextSupported = picturesUnderTextSupported
    }

    /// Whether the terminal painting this app's output will place an image in
    /// its cell grid — the override, then the environment, then the handshake.
    ///
    /// Unlike ``hyperlinksSupported`` this does **not** read through
    /// ``effective``, so ``simulated`` does not change it. Simulating Apple
    /// Terminal is a statement about which compensations to emit; it is not a
    /// claim that the terminal actually in front of the user has stopped being
    /// able to draw. The override is how a diagnostic turns pictures off.
    @MainActor public static var graphicsSupported: Bool {
        graphicsSupported(
            override: graphicsSupport, environment: ProcessInfo.processInfo.environment,
            detected: detectedGraphics)
    }

    /// The ladder behind ``graphicsSupported``, posed on its inputs — the
    /// shape `ColorDepth.detect(environment:)` has — so it can be asked without
    /// setting anything a whole process reads. It takes no program, which is
    /// the asymmetry with `hyperlinksSupported(override:environment:program:)`
    /// described above.
    static func graphicsSupported(
        override: Bool?, environment: [String: String], detected: Bool?
    ) -> Bool {
        if let override { return override }
        switch environment["TUI_GRAPHICS"] {
        case "1": return true
        case "0": return false
        default: return detected ?? false
        }
    }

    /// Whether transmissions to this terminal are deflated: pictures at all,
    /// then the override, the environment, the handshake — and a zlib to do
    /// it with, since `SystemZlib` is what deflates them.
    @MainActor public static var graphicsCompressionSupported: Bool {
        guard graphicsSupported, SystemZlib.isAvailable else { return false }
        if let graphicsCompressionSupport { return graphicsCompressionSupport }
        switch ProcessInfo.processInfo.environment["TUI_GRAPHICS_COMPRESSION"] {
        case "1": return true
        case "0": return false
        default: return detectedGraphicsCompression ?? false
        }
    }

    /// Force whether `.hairline` list separators are drawn, whatever the
    /// measured table says: `true` to try them on a host nobody has measured
    /// (kitty, WezTerm) or one left out (iTerm2, whose pixel unit is unknown),
    /// `false` to keep a list's separators the rule lines of their own they
    /// are everywhere else.
    ///
    /// The same three-way ladder as ``graphicsSupport``: this, then
    /// `TUI_HAIRLINES` (`1` or `0`), then the table of measured hosts
    /// (``hairlinesSupported``).
    @MainActor public static var hairlineSupport: Bool? {
        didSet {
            guard hairlineSupport != oldValue else { return }
            applyGraphicsSupport()
        }
    }

    /// Whether the terminal reported its cell's size in pixels when the app
    /// started, which a hairline's crop is counted in. `nil` until asked.
    @MainActor public private(set) static var detectedCellPixels: Bool?

    /// Whether this terminal draws `.hairline` list separators — a Kitty
    /// classic placement along the boundary between two rows, taking no row —
    /// the override, then the environment, then the hosts measured to draw one.
    ///
    /// Read through ``TerminalClient/current`` rather than ``effective``, as
    /// ``graphicsSupported`` is: a simulated host changes the compensations,
    /// not what the terminal in front of the user can draw.
    @MainActor public static var hairlinesSupported: Bool {
        hairlinesSupported(
            override: hairlineSupport, environment: ProcessInfo.processInfo.environment,
            graphics: graphicsSupported, program: current.program, reportsCellPixels: detectedCellPixels ?? false)
    }

    /// The ladder behind ``hairlinesSupported``, posed on its inputs.
    ///
    /// The table is ONE host: Ghostty, measured on 1.3.1 to draw the line on
    /// the boundary, keep it through every rewrite TUI sends, delete it by
    /// id and hold it still at 60 Hz (`hairline_probe.py`, 2026-10-08). And
    /// only where the startup handshake said it places pictures, so a Ghostty
    /// that has them turned off is left alone, and where the terminal reported
    /// its cell's pixels, which the line's length is counted in. iTerm2 3.7.3
    /// drew the line too, in a pixel unit no query revealed, so a line there
    /// ends short of its row; kitty and WezTerm are unmeasured; Konsole hides
    /// the layer the line needs. Each is one `TUI_HAIRLINES=1` away from
    /// being tried. See `Documentation/Terminals/Terminal compatibility survey.md`.
    static func hairlinesSupported(
        override: Bool?, environment: [String: String], graphics: Bool, program: Program,
        reportsCellPixels: Bool
    ) -> Bool {
        if let override { return override }
        switch environment["TUI_HAIRLINES"] {
        case "1": return true
        case "0": return false
        default: return graphics && program == .ghostty && reportsCellPixels
        }
    }

    /// Force whether a glyph over a frosted picture stands on the picture,
    /// laid under the text by a Kitty classic placement
    /// (``KittyGraphics/isPictureUnderTextSupported``), whatever the measured
    /// table says: `true` to try it on a host nobody has measured (kitty),
    /// `false` for the average-colour cells everywhere.
    ///
    /// The same ladder as ``hairlineSupport``: this, then
    /// `TUI_PICTURES_UNDER_TEXT` (`1` or `0`), then the measured hosts
    /// (``picturesUnderTextSupported``).
    @MainActor public static var pictureUnderTextSupport: Bool? {
        didSet {
            guard pictureUnderTextSupport != oldValue else { return }
            applyGraphicsSupport()
        }
    }

    /// Whether this terminal draws a picture under a glyph — the override,
    /// then the environment, then the hosts measured to draw one.
    @MainActor public static var picturesUnderTextSupported: Bool {
        picturesUnderTextSupported(
            override: pictureUnderTextSupport, environment: ProcessInfo.processInfo.environment,
            graphics: graphicsSupported, program: current.program)
    }

    /// The ladder behind ``picturesUnderTextSupported``, posed on its inputs.
    ///
    /// The table is ONE host: Ghostty, measured on 1.3.1 to draw a classic
    /// placement at `z=-1` below the glyphs and above a cell's default field
    /// (`frost_over_image_card.py`'s panel D, 2026-10-26), and only where the
    /// startup handshake said it places pictures at all. iTerm2 3.7.6 refuses
    /// the placement and orders `z` otherwise; kitty is unmeasured. See the
    /// graphics notes §14.5.
    static func picturesUnderTextSupported(
        override: Bool?, environment: [String: String], graphics: Bool, program: Program
    ) -> Bool {
        if let override { return override }
        switch environment["TUI_PICTURES_UNDER_TEXT"] {
        case "1": return true
        case "0": return false
        default: return graphics && program == .ghostty
        }
    }

    /// Runs the startup handshake, if its answer is not already known, and
    /// publishes the result.
    ///
    /// Skips the round trip whenever something has already decided — an
    /// override, or `TUI_GRAPHICS` — because the exchange costs a terminal
    /// round trip at startup and there is no reason to pay it for an answer
    /// nobody will read.
    ///
    /// - Parameter terminal: the terminal to ask. It owns stdin and the raw
    ///   mode the reply depends on.
    @MainActor
    static func detectGraphics(using terminal: Terminal) {
        defer { applyGraphicsSupport() }
        detectedCellPixels = terminal.cellPixelSize() != nil
        guard graphicsSupport == nil else { return }
        let forced = ProcessInfo.processInfo.environment["TUI_GRAPHICS"]
        guard forced != "1", forced != "0" else { return }
        let answers = terminal.queryGraphicsSupport()
        detectedGraphics = answers.placement
        detectedGraphicsCompression = answers.compression
    }
}
