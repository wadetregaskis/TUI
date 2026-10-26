//  🖥️ TUI — A Terminal UI framework for Swift
//  CollectionSurface.swift
//
//  The tones a list or table drawn on a surface of its own takes:
//  `.listStyle(.surface)` and `.tableStyle(.surface)`, a prototype.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore
import TUIFoundation
import TUIStyling
import TUIView

/// The two tones of a list or table drawn on a surface of its own
/// (``SurfaceListStyle``, ``SurfaceTableStyle``): its rows on ``body``, its
/// header — a table's column header, a list's title and section headers — on
/// ``header``, a step stronger.
///
/// Both are steps of the ladder a `TabView`'s body climbs
/// (``EnvironmentValues/liftedSurface``), so they inherit what that ladder
/// already guarantees on every palette and at every depth it measures: a
/// surface visibly off what it sits on, in the palette's own direction, and
/// never walked so far toward the text that the text stops being readable.
package struct CollectionSurface: Equatable {
    /// What the rows sit on: one plane's step off what the collection sits on.
    let body: Color
    /// What the header sits on: one step further.
    let header: Color

    /// The tones for a collection drawn in `environment`.
    ///
    /// The header's step is checked as it is painted, where the body's need
    /// not be: the ladder guards the text on ONE step off the page, and a
    /// second step toward the text can cost more than it allows (measured on
    /// the sixteen stated palettes: Silver Aerogel's at truecolour, Red's,
    /// Violet's and Novel's on the 256-colour cube — `CollectionSurfaceTests`).
    /// Where the text would read worse there than ``isReadable(_:in:)``
    /// allows, the header sits on what the collection sits on instead: a band
    /// the rows are lifted from, still a tone of its own.
    ///
    /// And it is checked against the rows as painted: the header has to be told
    /// from the rows AND from their stripe, which a coarse terminal can paint on
    /// the very entry the header's step lands on (measured: Green's, Homebrew's,
    /// Man Page's and Silver Aerogel's on the 256-colour cube, where the header
    /// read as one more striped row; on sixteen colours most palettes' step
    /// lands on the rows' own grey). So the step is the first of the header's
    /// step, a second step, and what the collection sits on that is readable
    /// and painted on an entry of its own; where none is, it is as before.
    init(_ environment: EnvironmentValues) {
        body = environment.liftedSurface
        header = Self.headerTone(over: body, in: environment)
    }

    /// The tone the header sits on, over rows on `body` — see ``init(_:)``.
    private static func headerTone(over body: Color, in environment: EnvironmentValues) -> Color {
        let palette = environment.palette
        let stronger = palette.lifted(from: body).resolve(with: palette)
        let fallback = isReadable(stronger, in: environment) ? stronger : environment.enclosingSurface
        let depth = ColorDepth.current
        guard depth > .noColor else { return fallback }
        let rows = body.downsampled(to: depth)
        let stripe = palette.stripeFill(over: body, at: depth)?.downsampled(to: depth)
        func standsApart(_ tone: Color) -> Bool {
            let shown = tone.downsampled(to: depth)
            return shown != rows && shown != stripe && isReadable(tone, in: environment)
        }
        let further = palette.lifted(from: stronger).resolve(with: palette)
        let candidates = [stronger, further, environment.enclosingSurface].filter(standsApart)
        guard depth < .truecolor else { return candidates.first ?? fallback }
        // On a coarse terminal, the candidate that stands apart nearest a quiet
        // step off the rows, not the first: the cube's rungs are far apart in
        // dark saturated hues, and two steps off the page landed Grass's and
        // Red Sands' headers on black (2.64:1 off Grass's rows), Ocean's on
        // `000087` (2.41:1) — a band too loud for a header, the owner's
        // ruling, where the page itself stood 1.76:1 and 1.11:1 off them.
        func offStep(_ tone: Color) -> Double {
            guard let shown = tone.downsampled(to: depth).rgbComponents, let row = rows.rgbComponents else {
                return .infinity
            }
            // Arithmetic, not ink: the entries' RGB, to measure a contrast with.
            // swiftlint:disable:next framework_colour_literal
            let shownEntry = Color.rgb(shown.red, shown.green, shown.blue)
            // swiftlint:disable:next framework_colour_literal
            let ratio = shownEntry.contrastRatio(against: Color.rgb(row.red, row.green, row.blue))
            return abs(log(ratio) - log(Self.headerStep))
        }
        return candidates.min { offStep($0) < offStep($1) } ?? fallback
    }

    /// The step, in contrast off the rows, a header aims at on a coarse
    /// terminal: visibly its own band, a little more than a stripe's step.
    static let headerStep = 1.25

    /// Whether the palette's text reads on `tone` as the terminal paints both
    /// at the current depth: at 4.5:1, or where the ground the collection sits
    /// on gives less, four fifths of what it gives — the floor a stripe keeps
    /// (``Palette/stripeFill(over:at:)``). Taken as readable where a colour
    /// cannot be measured: the terminal's own, before it has reported them.
    static func isReadable(_ tone: Color, in environment: EnvironmentValues) -> Bool {
        let palette = environment.palette
        let depth = ColorDepth.current
        func painted(_ colour: Color) -> Color? {
            let shown = colour.downsampled(to: depth)
            // Arithmetic, not ink: the entry's RGB, to measure a contrast with.
            // swiftlint:disable:next framework_colour_literal
            return shown.rgbComponents.map { Color.rgb($0.red, $0.green, $0.blue) }
        }
        guard let text = painted(palette.foreground.resolve(with: palette)), let shown = painted(tone),
            let ground = painted(environment.enclosingSurface)
        else { return true }
        return text.contrastRatio(against: shown) >= min(4.5, 0.8 * text.contrastRatio(against: ground))
    }

    /// `buffer` painted: the lines in `headerLines` on ``header`` and every
    /// other line on ``body``, each across the buffer's whole width, under
    /// whatever the content paints itself — a striped, selected or focused
    /// row keeps its own fill.
    ///
    /// The header lines are filled first, persistently, so the body's fill —
    /// re-applied after each of a line's resets, as `.background(_:)`'s is —
    /// comes before the header's on those lines and loses to it.
    @MainActor
    package func painted(_ buffer: FrameBuffer, headerLines: Range<Int>, context: RenderContext) -> FrameBuffer {
        guard !buffer.isEmpty else { return buffer }
        var buffer = buffer
        if !headerLines.isEmpty {
            let width = buffer.width
            let field = header.opaqueSpelling
            buffer = buffer.replacingLines(
                buffer.lines.enumerated().map { index, line in
                    guard headerLines.contains(index) else { return line }
                    return ANSIRenderer.applyPersistentBackground(line.padToVisibleWidth(width), color: field)
                        + ANSIRenderer.reset
                })
        }
        return BackgroundModifier(style: body).modify(buffer: buffer, context: context)
    }
}

extension CollectionSurface {
    /// `context` drawn on the tones a collection in it takes, and the tones,
    /// when `applies` — a `.surface` list or table; `context` and `nil` when it
    /// does not.
    package static func drawing(_ context: RenderContext, when applies: Bool) -> (RenderContext, Self?) {
        guard applies else { return (context, nil) }
        let tones = Self(context.environment)
        return (context.onSurface(tones), tones)
    }
}

extension RenderContext {
    /// This context drawn on `tones`: its body the surface the content sits on
    /// — what a field inside steps off, and what a stripe or an indicator's
    /// translucent ink lands on (``EnvironmentValues/enclosingSurface``) — and
    /// its header tone where a list's section header rows can read it.
    func onSurface(_ tones: CollectionSurface) -> RenderContext {
        var context = self
        context.environment.surfaceBackground = tones.body
        context.environment.collectionHeaderSurface = tones.header
        return context
    }
}

private struct CollectionHeaderSurfaceKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The header tone of the surface-style collection this is drawn in
    /// (``CollectionSurface/header``), or `nil` outside one. Read by a list's
    /// section header rows.
    var collectionHeaderSurface: Color? {
        get { self[CollectionHeaderSurfaceKey.self] }
        set { self[CollectionHeaderSurfaceKey.self] = newValue }
    }
}
