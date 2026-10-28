//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer+ModalVeil.swift
//
//  The page behind a sheet or an alert: all of it still there, every glyph
//  and colour, faded toward the overlay colour, and inert.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

extension FrameBuffer {
    /// How much of the page a modal leaves showing: each cell's colours go
    /// this far from the overlay colour back toward their own (after
    /// ``modalVeilSaturation`` has taken colour out of them). A quarter: with
    /// the colour taken out, the page's borders, bars and text still read on a
    /// careful look, and nothing on it competes with the modal's own colours.
    /// (The owner, 2026-10-28, from a comparison of 50%, 35% and 25%, with and
    /// without colour taken out; half was still a little bright.)
    public static let modalVeilOpacity = 0.25

    /// How much of its colour each of the page's colours keeps behind a modal,
    /// before it is faded by ``modalVeilOpacity``: 40%, so it recedes without
    /// going darker, toward the grey it reads as (Rec. 709, as
    /// `.saturation(_:)` takes colour out).
    public static let modalVeilSaturation = 0.4

    /// What the veil does to a picture's pixels: ``modalVeilSaturation``'s
    /// colour taken out, then mixed toward `scrim` as ``modalVeilOpacity``
    /// veils a colour, in linear light (`Color.compositing(_:over:)`).
    package static func modalVeilTransform(toward scrim: (red: UInt8, green: UInt8, blue: UInt8)) -> ImageTransform {
        ImageTransform(greying: 1 - modalVeilSaturation).followed(
            by: ImageTransform(blurs: false, toward: scrim, fraction: 1 - modalVeilOpacity, linearLight: true))
    }

    /// The backdrop behind a modal: this page's colours muted to
    /// ``modalVeilSaturation`` and faded to ``modalVeilOpacity`` over `scrim`,
    /// every glyph kept, and nothing on it reachable.
    ///
    /// What a sheet or an alert covers stays what it was, visibly deactivated:
    /// pictures drawn in text cells, charts, coloured text and borders all
    /// keep their shapes, and their colours move toward `scrim`. (The owner,
    /// 2026-10-25: keep the page mostly the same, but plainly deactivated and
    /// inaccessible.) The flatten that did this before
    /// (``dimmedAsBackdrop(foreground:background:)``) redrew every row as text
    /// in two colours, and dropped block and line glyphs as ornaments, so a
    /// picture drawn in blocks, or a bar, came out as blank cells. It still
    /// draws `.dimmed()`, which asks for exactly that look.
    ///
    /// The fade is a rewrite of the colours each row names, as `.saturation`
    /// and the other colour effects rewrite them (`SGRColorRewrite`): each
    /// colour moves to `saturated(keeping: modalVeilSaturation)` and then
    /// `compositing(modalVeilOpacity, over: scrim)`, the blend the opacity
    /// resolution makes, and every glyph and attribute stays. A
    /// row starts in the veiled default colours, and every reset restates
    /// them, so text in the terminal's own colours fades too. A run (a
    /// spinner, a pulse) is rewritten frame by frame with its row, so the page
    /// keeps moving. A row holding a terminal-graphics picture is passed over:
    /// its foreground is the image's id, not a colour. Where the scrim is the
    /// terminal's own background, not yet reported, there is nothing to blend
    /// toward, and the page is drawn faint (SGR 2) instead.
    ///
    /// Not the opacity resolution itself, which this first was: a region over
    /// the whole page resolved cell by cell, contests and all, every frame a
    /// sheet was up, made a frame with a sheet open 40-60% dearer (Stress
    /// `session/notes` +39.9%, `session/inbox-sheet` +62.5%), for an answer
    /// that is one colour mapping. Every cell here is over nothing, so no
    /// contest can arise, and a page names few colours, so each is blended once.
    ///
    /// The page's own translucent views are resolved first, against `surface`,
    /// the colour they were drawn over, so a fade in the page is spent against
    /// the page rather than the scrim.
    ///
    /// Hit-test regions are dropped, as the flatten dropped them: the page is
    /// inert while the modal is up. Pending overlays ride through, since
    /// anything still to be drawn above the backdrop must not vanish.
    ///
    /// - Parameters:
    ///   - scrim: The colour the page fades toward: the palette's overlay
    ///     background.
    ///   - surface: The page's own background, which its translucent views
    ///     were drawn over, and what its default background means.
    ///   - palette: Resolves the colours.
    /// - Returns: The veiled page.
    public func veiledAsBackdrop(by scrim: Color, surface: Color, palette: any Palette) -> FrameBuffer {
        veiledAsBackdrop(by: scrim, surface: surface, palette: palette, images: nil)
    }

    /// ``veiledAsBackdrop(by:surface:palette:)`` knowing the pictures the app has
    /// put in the terminal: a picture on the page draws a copy of itself veiled as
    /// the page's colours are, toward `scrim` in linear light
    /// (`OpacityBlend+Pictures.swift`), where without them it keeps its own
    /// brightness. What the screen root runs.
    package func veiledAsBackdrop(
        by scrim: Color, surface: Color, palette: any Palette, images: TerminalImageStore?
    ) -> FrameBuffer {
        guard !isEmpty else { return self }
        let scrim = scrim.resolve(with: palette).opaqueSpelling
        let surface = surface.resolve(with: palette)
        let ink = palette.foreground.resolve(with: palette)
        var page = opacityRegions.isEmpty ? self : resolvingOpacity(surface: surface, palette: palette, images: images)
        var veil = Veil(scrim: scrim)
        // Where the scrim has no RGB (the terminal's own background, not yet
        // reported) nothing can be blended toward it: the page is drawn faint
        // (SGR 2) instead, which every terminal can do without knowing its
        // colours.
        let faint = scrim.rgbComponents == nil
        let inkCodes = faint ? ["2"] : veil[ink].foregroundCodes()
        let fieldCodes = faint ? [] : veil[surface].backgroundCodes()
        let lineDefaults = "\u{1B}[" + (inkCodes + fieldCodes).joined(separator: ";") + "m"
        let frameDefaults = "\u{1B}[" + inkCodes.joined(separator: ";") + "m"
        // A row and a run's records of what is under it start in the veiled
        // defaults, field included. A run's frame does not: it is spliced into
        // its row, and a field it does not name is the row's (its records), so
        // stating one would draw the frame on it instead.
        func veiled(_ line: String, startingWith defaults: String?, afterAReset restated: String) -> String {
            let drawsPictures = line.unicodeScalars.contains(.terminalImagePlaceholder)
            // A picture's cells name the image in their foreground: without the
            // store there is nothing to veil them with, so the row keeps its own.
            guard !drawsPictures || (images != nil && !faint) else { return line }
            var result = defaults ?? ""
            // Where the row draws a picture, the ink in force, to read each
            // picture cell's image by.
            var state = SGRState()
            result.reserveCapacity(line.utf8.count + restated.utf8.count * 2)
            line.forEachANSISegment { segment in
                switch segment {
                case .visible(let character):
                    if drawsPictures, let images, let picture = Self.veiledPicture(
                        character, ink: state.foregroundColour, toward: scrim, store: images)
                    {
                        // The copy's cell, its id stated, and the row's state put
                        // back for whatever follows it: the next picture cell's own
                        // id, or the `ESC[39m` a picture's row ends with.
                        result += picture + "\u{1B}[39m" + state.rendered
                    } else {
                        result.append(character)
                    }
                // A rendered line's escape segment, not a colour: the rule
                // matches `.ansi(` wherever it is written.
                // swiftlint:disable:next framework_colour_literal
                case .ansi(let sequence, _):
                    if drawsPictures { state.apply(sequence) }
                    guard !faint else {
                        result += sequence
                        var reset = false
                        SGRColorRewrite.readingColors(sequence) { slot, _ in if case .reset = slot { reset = true } }
                        if reset { result += restated }
                        return true
                    }
                    var reset = false
                    result += SGRColorRewrite.rewritingSGR(
                        sequence, defaultForeground: ink, defaultBackground: surface,
                        transform: { veil[$0] }, emitted: { slot, _ in if case .reset = slot { reset = true } })
                    if reset { result += restated }
                }
                return true
            }
            return result
        }
        let row = { (line: String) in veiled(line, startingWith: lineDefaults, afterAReset: lineDefaults) }
        page = page.replacingLines(
            page.lines.map(row), width: page.width, uniformWidth: page.linesAreUniformWidth,
            lineWidths: page.lineWidths)
        // As `restyleRuns` does, but with the frame's rewrite apart from the
        // records'.
        page.animatedCells = page.animatedCells.map { run in
            let style = run.groundStyle
            let frames = run.frames.map {
                veiled(style.map($0.restatingGroundStyle) ?? $0, startingWith: faint ? frameDefaults : nil,
                       afterAReset: frameDefaults)
            }
            return run.replacingFrames(frames, alpha: run.alpha).paintingGround(row)
        }
        page.hitTestRegions = []
        page.overlays = overlays
        return page
    }
}

extension FrameBuffer {
    /// The cell drawing a copy of the picture `character` names in `ink`, veiled
    /// toward `scrim` as the page's colours are veiled — spelled with its
    /// copy's id — or `nil` where `character` is no picture's.
    fileprivate static func veiledPicture(
        _ character: Character, ink: SGRState.Colour?, toward scrim: Color, store: TerminalImageStore
    ) -> String? {
        // A pattern reading the ink's channels, not a colour this draws with.
        // swiftlint:disable:next framework_colour_literal
        guard case .rgb(let red, let green, let blue)? = ink,
            let picture = KittyGraphics.placeholderCell(
                character, foreground: (UInt8(clamping: red), UInt8(clamping: green), UInt8(clamping: blue))),
            let toward = scrim.rgbComponents
        else { return nil }
        return store.derived(picture, by: modalVeilTransform(toward: toward))?.spelled
    }
}

/// Each colour a page names, veiled: blended once, then looked up. A page names
/// a few dozen colours over thousands of cells.
private struct Veil {
    let scrim: Color
    private var memo: [Color: Color] = [:]

    init(scrim: Color) { self.scrim = scrim }

    subscript(colour: Color) -> Color {
        mutating get {
            if let known = memo[colour] { return known }
            let veiled = colour.saturated(keeping: FrameBuffer.modalVeilSaturation)
                .compositing(FrameBuffer.modalVeilOpacity, over: scrim).opaqueSpelling
            memo[colour] = veiled
            return veiled
        }
    }
}
