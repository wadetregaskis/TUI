//  🖥️ TUIkit — Terminal UI Kit for Swift
//  RowBackground.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// What a selectable row draws behind itself — a flat colour, or the whole
/// breath of one.
///
/// The cursor row of a focused list or table pulses its background. Resolving
/// that to a single `Color` as the row renders is a read of the live animation
/// clock, which makes the frame unreplayable: the run loop then has no way to
/// advance the pulse except by walking and re-rendering the entire view tree,
/// ten to twenty times a second, to recolour one row. Carrying the *cycle*
/// instead lets the row be drawn once and handed to the loop as
/// ``AnimatedCellRun``s. See ``SelectionEmphasisCycle``.
///
/// Shared by `_ListCore` and `Table` deliberately. They are twins — the same
/// rules about focus, selection and the unfocused-selection visibility, written
/// out twice — and the two have drifted apart before. One description of what a
/// row's background can be is one fewer thing to drift.
///
/// `@usableFromInline` (the module split's tier 2): TUIkitLists asks
/// ``tint(_:)``, ``claimableFill``, ``stepNow`` and ``pulseTiming`` of every row
/// it draws, and an `@inlinable` member of a type that is only `package` is not
/// serialized for another module to inline, whatever it says. `Sendable` stated
/// (here and on ``Paint``), as it was inferred while the type was not usable
/// from inline code: the compiler infers it only for types that are not, and a
/// list row stores one.
@usableFromInline
package enum RowBackground: Sendable {
    /// No background at all.
    case none

    /// One colour, every frame.
    case fixed(Color)

    /// A breathing colour: the whole cycle and the two ends it runs between.
    case pulsing(SelectionEmphasisCycle, dim: Color, bright: Color)

    /// Reverse video (SGR 7) over the palette's own ink and page, both stated beside
    /// the 7 — the highlight a terminal paints whatever colours it keeps, for a row
    /// whose fill cannot be measured (``HighlightFill``).
    case reversed(ink: Color, field: Color)

    /// A breath with one end in reverse video, the other a fill: a 16-colour row whose
    /// terminal has too few colours to tell every row's state apart (`RowFills`) — or,
    /// without colour, a reversal at both ends, bold at the bright one. The
    /// reversed end is the palette's pair exchanged, with every colour the row's
    /// content states dropped, so the whole row is the text's colour with its content
    /// in the page's (``ANSIRenderer/applyReversedPair(_:ink:field:)``).
    ///
    /// Only ever animating: a cycle that does not animate is still, and holds its
    /// bright end as ``fixed(_:)`` or ``reversed(ink:field:)``.
    case pulsingReversal(SelectionEmphasisCycle, dim: Paint, bright: Paint)

    /// How one frame of a breathing row paints its line. `@usableFromInline`, as
    /// the type of a case of one.
    @usableFromInline
    package enum Paint: Sendable {
        case fill(Color)
        /// The pair reversed; `bold` emboldens the whole row too.
        case reversed(ink: Color, field: Color, bold: Bool = false)

        /// `line`, a row's finished line, painted this way. A fill is left in force at
        /// the end, as ``String/withPersistentBackground(_:)`` leaves it.
        package func painting(_ line: String) -> String {
            switch self {
            case .fill(let colour): line.withPersistentBackground(colour)
            case .reversed(let ink, let field, let bold):
                ANSIRenderer.applyReversedPair(line, ink: ink.opaqueSpelling, field: field.opaqueSpelling, bold: bold)
            }
        }

        /// A row's lines this way, from a renderer that draws them over a colour:
        /// over the fill, or over none and then reversed.
        package func lines(_ render: (Color?) -> [String]) -> [String] {
            switch self {
            case .fill(let colour): render(colour)
            case .reversed: render(nil).map(painting)
            }
        }

        /// The colour the row is filled with, or `nil` for a reversal.
        var fill: Color? {
            guard case .fill(let colour) = self else { return nil }
            return colour
        }
    }

    /// `.fixed`, or `.none` for no colour — for the callers whose other branches
    /// produce an optional.
    init(_ color: Color?) {
        self = color.map(Self.fixed) ?? .none
    }

    /// The pulse a focused, selected row shows, between the shared min/max ends.
    ///
    /// The one definition of that colour pair: a list and a table showing
    /// visibly different pulses for the same state is exactly the kind of drift
    /// this type exists to prevent.
    ///
    /// Where the accent or the page has no RGB the pair cannot be mixed, and the row
    /// reverses the palette's pair instead of holding a colour nobody can check
    /// (``Palette/emphasisFill(over:)``).
    ///
    /// Where the view does not appear active (``EnvironmentValues/appearsActive`` —
    /// the terminal window has lost focus), the row is still the cursor, and says so,
    /// still: it takes the tint a selected row shows while its control does not hold
    /// the keys. The focus is parked, not gone. The rule is
    /// `Palette.highlightedRowFill(appearsActive:)`'s, shared with a menu's and a
    /// drop-down's highlighted row.
    @MainActor
    package static func focusedSelection(in context: RenderContext, palette: any Palette) -> Self {
        breathing(
            palette.highlightedRowFill(appearsActive: context.environment.appearsActive, reversing: true),
            in: context)
    }

    /// The highlight a row merely UNDER the cursor shows — the cursor row of a focused
    /// list or table, on a row the selection does not include: the focus wash,
    /// breathing (``Palette/focusWashPulse()``), or a reversal where that wash cannot
    /// be measured.
    ///
    /// It breathes for the reason the selected cursor row does: motion says the keys
    /// go here, now, and a list that has them says so wherever its cursor is. Where the
    /// view does not appear active it holds still at the bottom of that breath, the
    /// plain wash, the look it has always had — `Palette.focusWashEmphasis(appearsActive:)`
    /// is the rule, and says why a translucent wash is held spent over the page.
    ///
    /// Under ``View/rowSelectionIndicator(_:)`` `.hidden` too, where no ● says whether
    /// the cursor row is selected. Motion is what says where the keys go, so it cannot
    /// also be what says "selected": this row used to hold the plain wash still there,
    /// which made the one list on the page that had been told not to mark its
    /// selection the one whose cursor did not move. The focus indicator always visibly
    /// breathes, selected or not; which of the two a cursor row is, the breaths say
    /// themselves — a selected cursor row's peaks clearly brighter than an unselected
    /// one's (``Palette/accentFillPulse(over:)``).
    ///
    /// Here rather than at the two call sites for the reason ``focusedSelection(in:palette:)``
    /// is: the twins ask one question in one place.
    @MainActor
    package static func focused(in context: RenderContext, palette: any Palette) -> Self {
        breathing(
            palette.focusWashEmphasis(appearsActive: context.environment.appearsActive),
            in: context)
    }

    /// `highlight` as a cursor row draws it: a breath on the shared focus-emphasis
    /// cycle, and anything else still.
    @MainActor
    private static func breathing(_ highlight: HighlightFill, in context: RenderContext) -> Self {
        let cycle = context.environment.selectionEmphasis.cycle(true)
        if let ends = reversingEnds(of: highlight) {
            guard cycle.isAnimating else { return still(highlight) }
            return .pulsingReversal(cycle, dim: ends.dim, bright: ends.bright)
        }
        guard case .pulse(let dim, let bright) = highlight else { return still(highlight) }
        return .pulsing(cycle, dim: dim, bright: bright)
    }

    /// The two ends of a breath with reverse video in it, or `nil` for any other
    /// highlight: a 16-colour breath with one end reversed (`RowFills`), or, without
    /// colour, a reversal that breathes by its weight — bold at the bright end — where
    /// the terminal draws bold (``TerminalClient/drawsBold``; every one TUIkit has
    /// measured does). The one answer a list's or table's cursor row, a menu's bar and a
    /// drop-down's highlighted row all draw from.
    @MainActor
    package static func reversingEnds(of highlight: HighlightFill) -> (dim: Paint, bright: Paint)? {
        switch highlight {
        case .reversingPulse(let dim, let bright, let ink, let field):
            let reversal = Paint.reversed(ink: ink, field: field)
            return (dim.map(Paint.fill) ?? reversal, bright.map(Paint.fill) ?? reversal)
        case .reversed(let ink, let field) where ColorDepth.current == .noColor && TerminalClient.drawsBold:
            return (.reversed(ink: ink, field: field), .reversed(ink: ink, field: field, bold: true))
        case .fill, .pulse, .reversed:
            return nil
        }
    }

    /// The fill of a highlight that only ever TINTS — a selected row that is not the
    /// cursor, an alternating row — and nothing where that tint cannot be measured.
    ///
    /// Such a row repeats what the ● beside it and the cursor row already say. Reversed
    /// it would read as a second cursor, so where its tint has no RGB it is left
    /// unfilled, its ● alone saying it is selected. `_ListCore` and `Table` both ask
    /// this for a selected row the cursor is not on.
    @inlinable
    package static func tint(_ highlight: HighlightFill) -> Self {
        guard case .fill(let color) = highlight else { return .none }
        return .fixed(color)
    }

    /// `highlight` as a background that does not animate.
    ///
    /// A breath is not one: a site that can show one asks ``breathing(_:in:)``, and
    /// here the bright end stands in, which is the colour such a cycle holds anyway
    /// wherever it cannot be measured (§79).
    private static func still(_ highlight: HighlightFill) -> Self {
        switch highlight {
        case .fill(let color): return .fixed(color)
        case .pulse(_, let bright): return .fixed(bright)
        case .reversed(let ink, let field): return .reversed(ink: ink, field: field)
        case .reversingPulse(_, let bright, let ink, let field):
            return bright.map(Self.fixed) ?? .reversed(ink: ink, field: field)
        }
    }

    /// The colour to draw with in the frame being rendered now, or `nil` where the row
    /// fills with no colour of its own — no background at all, and a reversal, which
    /// paints with the pair already in force.
    @MainActor
    package var colorNow: Color? {
        switch self {
        case .none, .reversed: return nil
        case .fixed(let color): return color
        case .pulsing(let cycle, let dim, let bright):
            return cycle.colorNow(dim: dim, bright: bright)
        case .pulsingReversal: return paintNow?.fill
        }
    }

    /// Every frame of the breath, in cycle order — ``pulseColors`` as fills, or a
    /// reversing breath's frames — or `nil` when this background does not animate.
    @MainActor
    package var framePaints: [Paint]? {
        if case .pulsingReversal(let cycle, let dim, let bright) = self {
            return cycle.brightFrames().map { $0 ? bright : dim }
        }
        return pulseColors?.map(Paint.fill)
    }

    /// The frame of ``framePaints`` being rendered now.
    @MainActor
    private var paintNow: Paint? {
        guard let paints = framePaints, !paints.isEmpty else { return nil }
        return paints[stepNow % paints.count]
    }

    /// `line` — a row's finished line, padded to its width by `padding` spaces — drawn
    /// over this background as the frame being rendered now shows it.
    ///
    /// `padding` is what `painting(line + padding spaces)` draws, byte for byte, written
    /// inside the paint rather than into a padded copy of the line first: a still fill or
    /// reversal costs the one allocation of the painted line (see
    /// `ANSIRenderer.wrapping(_:restoring:opening:padding:closing:)`).
    ///
    /// A fill is left in force at the end of the line, as
    /// ``String/withPersistentBackground(_:)`` leaves it; a reversal closes itself with
    /// a reset. Both re-state themselves after every reset inside the line, because a
    /// row may reset inside itself before its plain padding: a list row closes every
    /// styled run with one, as a table row does under a reversal; elsewhere a table
    /// row states its ink once per run of plain cells and resets after a cell whose
    /// text carries escapes of its own, and at the end of its ink where it has no
    /// still fill — under one it closes its ink with SGR 39, which leaves the fill in
    /// force (`TableRowInk`). For the reversal the restating is the whole
    /// point: the 7 exchanges the colours IN FORCE, so without the palette's
    /// ink and field restated beside it the padding would fill with the terminal's own
    /// foreground (`ANSIRenderer.applyPersistentReverse(_:ink:field:)`).
    ///
    /// Opaque spellings, as every row paint uses: a translucent fill's alpha is claimed
    /// (``claimableFill``) and resolved against what is behind the row, and the emitter
    /// is never handed a colour that still states one.
    @MainActor
    package func painting(_ line: String, padding: Int = 0) -> String {
        if case .pulsingReversal = self, let paint = paintNow {
            return paint.painting(padding > 0 ? line + asciiSpaces(padding) : line)
        }
        guard case .reversed(let ink, let field) = self else {
            guard let fill = claimableFill?.opaqueSpelling ?? colorNow else {
                return padding > 0 ? line + asciiSpaces(padding) : line
            }
            return ANSIRenderer.applyPersistentBackground(line, color: fill, padding: padding)
        }
        return ANSIRenderer.applyPersistentReverse(
            line, ink: ink.opaqueSpelling, field: field.opaqueSpelling, padding: padding)
    }

    /// A row's still lines, from a renderer that draws them over a colour.
    ///
    /// ``painting(_:)`` for a caller whose lines are BUILT with their background rather
    /// than painted after the fact — a `List` row draws its badge and its gutter into
    /// them. A reversal renders them over no colour and reverses each; every other
    /// background hands the renderer the colour of the frame being rendered now.
    ///
    /// - Parameter render: Draws the row's lines over the colour it is given.
    @MainActor
    package func stillLines(_ render: (Color?) -> [String]) -> [String] {
        if case .pulsingReversal = self, let paint = paintNow { return paint.lines(render) }
        guard case .reversed = self else {
            return render(claimableFill?.opaqueSpelling ?? colorNow)
        }
        return render(nil).map { painting($0) }
    }

    /// Every colour of the pulse, in cycle order — or `nil` when this background
    /// does not animate (a still picture earns no runs: the ordinary render
    /// already drew it, and replaying it would emit bytes per tick to no
    /// visible effect). A pulse between two equal ends is still too, whatever its
    /// cycle: `accentFillPulse` returns one where the accent or the page has no RGB.
    @MainActor
    private var pulseColors: [Color]? {
        guard case .pulsing(let cycle, let dim, let bright) = self,
            cycle.isAnimating(dim: dim, bright: bright)
        else { return nil }
        return cycle.colors(dim: dim, bright: bright)
    }

    /// The frame duration and clock ``pulseColors`` step on, or `nil` exactly when
    /// that is `nil`: what a run built from those colours is built with.
    @inlinable
    package var pulseTiming: IndicatorCycleTiming? {
        switch self {
        case .pulsing(let cycle, let dim, let bright) where cycle.isAnimating(dim: dim, bright: bright):
            return cycle.timing
        case .pulsingReversal(let cycle, _, _):
            return cycle.timing
        default:
            return nil
        }
    }

    /// Which frame of ``pulseColors`` or ``framePaints`` the frame being rendered now
    /// shows.
    @MainActor
    @inlinable
    package var stepNow: Int {
        switch self {
        case .pulsing(let cycle, _, _), .pulsingReversal(let cycle, _, _):
            return cycle.frames.isEmpty ? 0 : cycle.step % cycle.frames.count
        default:
            return 0
        }
    }

    /// The fill a claim would be about, or `nil` where there is nothing to claim.
    ///
    /// A PULSING background earns none and needs none: `accentFillPulse` returns both
    /// ends through ``Color/opacity(_:over:)``, which consumes a translucent tint's
    /// alpha and stamps the result opaque (§21, §29). Every frame of the breath
    /// therefore states a concrete colour and no alpha is left over — which is also
    /// why the pulse can be a run at all, since a run's frames must all answer to one
    /// static region.
    @MainActor
    @inlinable
    package var claimableFill: Color? {
        guard case .fixed(let color) = self else { return nil }
        return color
    }
}
