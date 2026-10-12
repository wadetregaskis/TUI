//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OpacityFade.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitStyling
import TUIkitView

/// The colour arithmetic behind ``View/opacity(_:)``, kept out of
/// the generic view so there is one copy of it and tests can reach it.
enum OpacityFade {
    /// Fades every colour in `line` toward `surface`.
    ///
    /// A thin face on ``SGRColorRewrite``, which is the general form: every
    /// colour effect in the framework is the same walk over the same escape
    /// sequences with a different function of the colour.
    ///
    /// ``Color/opacity(_:over:)`` — the ENCODED-sRGB mix — and deliberately not
    /// ``Color/compositing(_:over:)``, which mixes in linear light. Both are
    /// correct arithmetic for different questions, and this one is a FADE
    /// watched by an eye rather than a translucent layer measured by a meter.
    /// See `Documentation/Colour and styling/Opacity as composition.md`.
    ///
    /// Over the terminal's page before it has reported it, a colour below ½
    /// becomes that page, which the foreground slot can only spell 39. A glyph
    /// left in it would show at full strength in the terminal's foreground, so
    /// it is dropped, as the composite drops it (§76, §83). A reversed cell is
    /// judged in the colours it displays, and its 7 is dropped with it (§91).
    ///
    /// A stated `ESC[49m` is a field of its own, the terminal's, and fades as
    /// ``View/opacity(_:)`` fades it (§95): against a surface with an RGB it is the
    /// heavier side from ½, and mixes once the terminal has reported its page. It
    /// used to be read as the surface — so a transition faded
    /// `Text("ab").background(Color.default)` onto the page at every phase, where
    /// the same label under `.opacity` stays on the terminal's own field above ½.
    static func fading(
        _ line: String, by factor: Double, over surface: Color, defaultForeground: Color
    ) -> String {
        let fade = { (colour: Color) in colour.opacity(factor, over: surface) }
        // Only that page can be an ink on itself here. An ink is a colour faded
        // toward the surface, so no ink is the page unless the surface is. Over any
        // other surface the rewrite is the whole of it, byte for byte.
        guard FrameBuffer.isTheUnreportedPageOnItself(ink: surface, field: surface) else {
            return SGRColorRewrite.rewriting(
                line, defaultForeground: defaultForeground, defaultBackground: .terminalBackground,
                transform: fade)
        }
        return fadingOverTheUnreportedPage(
            line, surface: surface, defaultForeground: defaultForeground, fade: fade)
    }

    /// `line` rewritten by `fade`, with every glyph whose ink is the unreported
    /// page, on that page, made blank.
    ///
    /// A glyph is judged in the colours the REWRITTEN line states, which the
    /// rewrite reports as it emits them. At the start of a line and after a
    /// reset nothing is stated: the terminal's own colours are in force, which
    /// the rewrite never fades, so the glyph stays.
    ///
    /// A blank takes as many cells as the glyph did. Underline, blink and strike
    /// ink a blank cell in the foreground colour (rule 6), so they are cleared
    /// across the blanks and put back after them. Reverse video inks one too, in
    /// the INK colour, so it is cleared with them (§91).
    ///
    /// A reversed cell is judged in the colours it DISPLAYS: its stated field is
    /// the ink the viewer sees, and its stated ink the fill. Where either is
    /// unstated the terminal's OTHER default is in force — an ink from the
    /// default background, a fill from the default foreground — and the rewrite
    /// never fades those, so such a cell stays.
    private static func fadingOverTheUnreportedPage(
        _ line: String, surface: Color, defaultForeground: Color, fade: (Color) -> Color
    ) -> String {
        var result = ""
        var ink: Color?
        var field: Color?
        // What the rewritten line has in force, and, while a dropped glyph's
        // underline, blink or strike is cleared, the state the terminal is in
        // instead, to be put back before anything else is drawn.
        var state = SGRState()
        var cleared: SGRState?
        line.forEachANSISegment { segment in
            switch segment {
            case .ansi(let sequence, let isSGR):
                if let off = cleared {
                    result += state.rendered(changingFrom: off)
                    cleared = nil
                }
                let rewritten = SGRColorRewrite.rewritingSGR(
                    sequence, defaultForeground: defaultForeground, defaultBackground: .terminalBackground,
                    transform: fade
                ) { slot, colour in
                    switch slot {
                    case .foreground: ink = colour
                    case .background: field = colour
                    case .reset: (ink, field) = (nil, nil)
                    }
                }
                result += rewritten
                if isSGR { state.apply(rewritten) }
            case .visible(let character):
                let displayedInk = state.reversesVideo ? (field ?? surface) : ink
                let displayedField =
                    state.reversesVideo ? (ink ?? defaultForeground) : (field ?? surface)
                guard
                    FrameBuffer.isTheUnreportedPageOnItself(
                        ink: displayedInk, field: displayedField)
                else {
                    if let off = cleared {
                        result += state.rendered(changingFrom: off)
                        cleared = nil
                    }
                    result.append(character)
                    return true
                }
                if cleared == nil, state.paintsInkOnBlankCell || state.reversesVideo {
                    var off = state
                    off.apply("\u{1B}[24;25;27;29m")
                    result += off.rendered(changingFrom: state)
                    cleared = off
                }
                result += String(repeating: " ", count: character.terminalWidth)
            }
            return true
        }
        if let off = cleared { result += state.rendered(changingFrom: off) }
        return result
    }
}
