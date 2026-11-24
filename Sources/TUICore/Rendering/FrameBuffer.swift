//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameBuffer.swift
//
//  Created by LAYERED.work
//  License: MIT

/// A 2D text buffer that views render into before flushing to the terminal.
///
/// `FrameBuffer` enables a two-pass rendering approach:
/// 1. Each view renders into its own buffer (measuring its size)
/// 2. Layout containers combine child buffers (horizontally, vertically, or layered)
/// 3. The final root buffer is flushed to the terminal
///
/// Each line in the buffer is a string that may contain ANSI escape codes.
///
/// - Important: This is framework infrastructure used as the rendering primitive in
///   ``BufferModifier/modify(buffer:context:)``. Most developers don't need to interact
///   with this type directly.
public struct FrameBuffer: Sendable, Equatable {
    /// The lines of rendered content (may contain ANSI escape codes).
    ///
    /// Assigning `lines` recomputes the cached ``width`` and
    /// ``linesAreUniformWidth`` and invalidates ``lineWidths`` (it cannot
    /// cheaply produce the per-line widths, so it drops them to `nil` rather
    /// than leave a stale array).
    public var lines: [String] {
        // Borrowed rather than returned: `lines` is read constantly (every
        // `height`, every combine, every consumer walking the rows) and a
        // plain `get` would hand back a +1 retained array each time. Measured
        // at ~1% on the `deep` Stress scenario, which is all reads.
        _read { yield storage }
        set {
            storage = newValue
            recomputeWidth()
        }
    }

    /// Backing store for ``lines``.
    ///
    /// The recompute belongs on the *public* door, not on the storage: it is
    /// a whole-buffer measure, so a mutator writing rows one at a time through
    /// an observer pays it once per row. ``composite(with:at:)`` does exactly
    /// that, and already knows the resulting geometry exactly — an Instruments
    /// trace of a custom `Layout` placing 160 children spent 29.4% of the run
    /// re-measuring the canvas per child only to have the answer overwritten.
    /// Mutators inside this file write `storage` and maintain ``width``,
    /// ``linesAreUniformWidth`` and ``lineWidths`` themselves; everyone else
    /// goes through ``lines`` and cannot tell the difference.
    private var storage: [String]

    /// The width of the buffer (the length of the longest line in visible characters).
    ///
    /// This is a stored property, recomputed automatically whenever
    /// ``lines`` is mutated. Accessing `width` is O(1) — the per-line
    /// `String.strippedLength` scan runs only once per mutation, not per
    /// access. It was an ANSI-stripping regex when this cache was introduced
    /// (`176cfc0d`, 2026-02-02); since `74fc7ea8` (2026-08-12) it is a
    /// byte-at-a-time CSI walk with an all-ASCII fast path, and no regex
    /// survives anywhere on the width path.
    public private(set) var width: Int

    /// Whether every line in ``lines`` has the same visible width (``width``).
    ///
    /// A performance hint with a deliberately conservative meaning: `true` means
    /// "definitely uniform", `false` means "unknown — measure per line". A parent
    /// that pads or borders these lines to a target width can, when this is
    /// `true`, skip re-measuring each line's visible width (it already knows each
    /// is exactly ``width``). That per-line `strippedLength` is the dominant cost
    /// in deeply-nested bordered layouts, where the same lines are otherwise
    /// re-measured at every enclosing level — O(depth²).
    ///
    /// Empty and single-line buffers are trivially uniform. Combining operations
    /// propagate it via cheap width comparisons, never by re-measuring, so it
    /// never reintroduces the cost it exists to remove. It is intentionally
    /// excluded from `==` (see the custom `Equatable` conformance): two buffers
    /// with identical lines are interchangeable, and `true` is only ever set when
    /// the lines genuinely are uniform.
    public private(set) var linesAreUniformWidth: Bool

    /// Whether ``overlays`` is known to hold no overflow
    /// (`OverlayLayer.isOverflow`): a hint with ``linesAreUniformWidth``'s
    /// conservative meaning — `true` is "definitely none", `false` "unknown,
    /// look". Any change to ``overlays`` makes it unknown, and the combining
    /// operations say what they know after each append
    /// (`appendOverlays(of:shiftedByX:y:)`), so a stack of a thousand children
    /// with a layer each asks about each child's layers once, not about every
    /// layer so far at every child. Declared beside the other `Bool`, in its
    /// padding, and excluded from `==` like the other hints.
    package var overlaysAreFreeOfOverflow = true

    /// Per-line visible widths, or `nil` when unknown ("measure on demand").
    ///
    /// A performance hint that complements ``linesAreUniformWidth`` for *ragged*
    /// content. When a producer already knows each line's visible width — most
    /// importantly ``Text``, which gets the widths for free while word-wrapping —
    /// it carries them here so a consumer that pads ragged lines to a target width
    /// (e.g. a `VStack` aligning a column of wrapped text) skips the per-line
    /// `String.strippedLength` re-measure. `nil` means "unknown":
    /// every consumer falls back to measuring per line, exactly as before this
    /// field existed.
    ///
    /// It is maintained with the same discipline as ``linesAreUniformWidth``:
    /// combining/mutating operations either produce the correct array cheaply
    /// (by concatenation, never by re-measuring) or set it to `nil` — a stale
    /// array is never left behind. Like ``linesAreUniformWidth`` it is excluded
    /// from `==` (a pure function of ``lines``, so it can never distinguish two
    /// buffers with identical lines).
    ///
    /// - Invariant: when non-`nil`, `lineWidths == lines.map(\.strippedLength)`
    ///   and `lineWidths!.count == lines.count`. Checked in debug builds wherever
    ///   the field is set (see `assertLineWidthsInvariant(_:checkedFrom:file:line:)`),
    ///   each row measured once as it enters the buffer rather than the whole
    ///   buffer re-walked per append — that method has the induction making the
    ///   two equivalent.
    public private(set) var lineWidths: [Int]?

    /// The height of the buffer (number of lines).
    public var height: Int {
        lines.count
    }

    /// Whether the buffer is empty.
    ///
    /// - Note: Reflects only the in-flow ``lines``. A buffer with no visible
    ///   lines may still carry `overlays`; combining operations check for
    ///   that case explicitly so overlay layers are never silently dropped.
    public var isEmpty: Bool {
        lines.isEmpty || lines.allSatisfy { $0.isEmpty }
    }

    /// Whether the buffer is *visually* empty: every line is blank or
    /// whitespace-only once ANSI codes are stripped.
    ///
    /// Stronger than ``isEmpty``, which only treats zero-length lines as
    /// empty. A line of spaces (or ANSI-styled blanks, e.g. a `Text("")` that
    /// padded itself) is blank here but not "empty". Containers use this to
    /// decide whether optional chrome — a header, a label, a footer — actually
    /// draws anything, so an empty title doesn't reserve a blank row.
    ///
    /// - Note: Considers only the in-flow ``lines``; a buffer carrying only
    ///   `overlays` is still reported blank.
    public var isBlank: Bool {
        lines.allSatisfy { $0.stripped.allSatisfy(\.isWhitespace) }
    }

    /// Free-floating layers composited above the content at render time.
    ///
    /// Most buffers carry none. A view emits a layer to draw outside its own
    /// bounds — for example a `Picker` drop-down — without disturbing sibling
    /// layout. Each layer's offset is relative to this buffer's top-left and
    /// is shifted by every combining operation, so it becomes absolute by the
    /// time the buffer reaches the root. See ``OverlayLayer``.
    package var overlays: [OverlayLayer] = [] {
        didSet { overlaysAreFreeOfOverflow = false }
    }

    /// Mouse hit-test rectangles that ride alongside this buffer's
    /// content as parents combine it.
    ///
    /// Every combining operation shifts these regions by the same
    /// amount it shifts the buffer's lines, so by the time the buffer
    /// reaches the root each region's offset is in absolute screen
    /// coordinates. The `MouseEventDispatcher` collects them at root
    /// composite time and uses them for hit-testing.
    public var hitTestRegions: [HitTestRegion] = []

    /// Short runs of cells that animate on their own — a breathing focus ring,
    /// a blinking cursor — carried and shifted exactly like ``hitTestRegions``,
    /// because a run *is* a claim about particular cells. See ``AnimatedCellRun``.
    public var animatedCells: [AnimatedCellRun] = []

    /// Rectangles of this buffer that are drawn at less than full opacity,
    /// carried and shifted exactly like ``hitTestRegions`` and ``animatedCells``
    /// — because opacity, like a run, is a claim about particular cells.
    ///
    /// Empty for almost every buffer, which is the identity and costs nothing.
    ///
    /// A view with `.opacity(_:)` emits one of these rather than fading its own
    /// colours, because **a colour cannot be faded toward a surface the view
    /// cannot see**. The fade is deferred to whatever finally draws the buffer
    /// onto something — a `ZStack`, an overlay, or the root — where the
    /// destination is known. See ``OpacityRegion`` and
    /// `Documentation/Colour and styling/Opacity as composition.md`.
    package var opacityRegions: [OpacityRegion] = []

    /// Creates an empty buffer.
    public init() {
        self.storage = []
        self.width = 0
        self.linesAreUniformWidth = true  // vacuously uniform
        self.lineWidths = nil  // no lines → nothing to carry (uniform covers it)
    }

    /// Creates a buffer from an array of lines.
    ///
    /// - Parameter lines: The text lines.
    public init(lines: [String]) {
        self.storage = lines
        let measured = Self.measure(lines)
        self.width = measured.width
        self.linesAreUniformWidth = measured.uniform
        // The single-pass `measure` tracks only the min/max width, not the full
        // per-line array; producing one here would re-walk every line, so leave
        // the per-line widths unknown (measure on demand). A producer that has
        // them cheaply uses `init(lines:width:uniformWidth:lineWidths:)`.
        self.lineWidths = nil
    }

    /// Initializer that accepts pre-computed width.
    ///
    /// Use this when the width is already known to avoid redundant computation.
    ///
    /// - Parameters:
    ///   - lines: The buffer's content, one string per terminal row, ANSI included.
    ///   - width: The visible width in cells, which the caller is asserting
    ///     rather than the buffer measuring. It is what every consumer lays out
    ///     against, so a wrong value misplaces content as surely as wrong
    ///     lines would; `uniformWidth` and `lineWidths` are claims ABOUT it.
    ///   - uniformWidth: Pass `true` only when the caller knows every line in
    ///     `lines` is exactly `width` visible columns (e.g. it just padded them
    ///     to that width). Defaults to `false` — "unknown", the safe value that
    ///     makes any consumer fall back to measuring per line.
    ///   - lineWidths: The per-line visible widths, when the caller already knows
    ///     them (e.g. ``Text`` from word-wrapping). Defaults to `nil` —
    ///     "unknown", matching `uniformWidth`'s default. When supplied it MUST
    ///     equal `lines.map(\.strippedLength)` (asserted in debug builds); pass
    ///     `nil` rather than a guess.
    public init(
        lines: [String],
        width: Int,
        uniformWidth: Bool = false,
        lineWidths: [Int]? = nil
    ) {
        self.storage = lines
        self.width = width
        self.linesAreUniformWidth = uniformWidth
        self.lineWidths = lineWidths
        Self.assertLineWidthsInvariant(self)
    }

    /// Creates a buffer containing a single line.
    ///
    /// - Parameter text: The text content.
    public init(text: String) {
        self.storage = [text]
        self.width = text.strippedLength
        self.linesAreUniformWidth = true  // a single line is trivially uniform
        // Trivially uniform at `width`; `linesAreUniformWidth` already lets
        // consumers skip the per-line measure, so don't allocate a 1-element
        // array redundantly.
        self.lineWidths = nil
    }

    /// Creates a spacer buffer with the specified height.
    ///
    /// The buffer contains lines with a single space character to ensure
    /// it is not considered "empty" by layout algorithms. This is important
    /// for Spacer views which need to occupy vertical space even without
    /// visible content.
    ///
    /// - Parameter height: The number of lines; a negative one is none.
    public init(emptyWithHeight height: Int) {
        // Use a single space instead of empty string so the buffer
        // is not considered "empty" by appendVertically. Floored at zero, as
        // `init(footprintWidth:height:)` is: `Array(repeating:count:)` traps
        // on a negative count, and a lone `Spacer(minLength: -1)` asked for
        // one (hunt 11-20, CORE1-1).
        self.storage = Array(repeating: " ", count: max(0, height))
        self.width = 1
        self.linesAreUniformWidth = true  // all lines are a single space
        self.lineWidths = nil  // uniform at width 1; no array needed
    }

    /// Creates a buffer of empty spaces with the specified width and height.
    ///
    /// Used by horizontal stacks for Spacer views which need to occupy
    /// horizontal space across multiple rows.
    ///
    /// - Parameters:
    ///   - width: The width in characters; a negative one is none.
    ///   - height: The number of lines; a negative one is none.
    public init(emptyWithWidth width: Int, height: Int) {
        // Floored at zero, for the reason `init(emptyWithHeight:)` gives: a
        // negative `safeAreaInset` spacing past both views' extent came here.
        let width = max(0, width)
        self.storage = Array(repeating: String.spaces(width), count: max(0, height))
        self.width = width
        self.linesAreUniformWidth = true  // every line is `width` spaces
        self.lineWidths = nil  // uniform at `width`; no array needed
    }

    /// Creates a footprint: `height` rows that paint no cell at all, declaring
    /// itself `width` cells wide.
    ///
    /// NOT ``init(emptyWithWidth:height:)``, whose rows are spaces. Those
    /// PAINT: compositing is opaque per cell, so a blank-filled buffer erases
    /// whatever is beneath it — the opposite of what a view wants when it has
    /// floated its drawing somewhere else (`OverlayLayer`) and is leaving
    /// behind the space the measure pass promised.
    ///
    /// Both halves are load-bearing, and each was a shipped bug:
    ///
    /// - the rows have to EXIST. A buffer with no lines is not "a blank view"
    ///   to a stack, it is "no child": `appendVertically` drops it, spacing and
    ///   all, so every sibling after it moves up and the floated drawing lands
    ///   on whatever took its place.
    /// - the WIDTH has to be declared, even though no cell carries it, because
    ///   a container that aligns its children asks each buffer how wide it is —
    ///   a zero-width answer centres an 8-cell label 4 cells off centre.
    ///
    /// - Parameters:
    ///   - width: The width to declare, in cells.
    ///   - height: The number of rows to reserve.
    public init(footprintWidth width: Int, height: Int) {
        self.storage = Array(repeating: "", count: max(0, height))
        self.width = max(0, width)
        self.linesAreUniformWidth = false  // no line is `width` cells; none is drawn
        self.lineWidths = nil
    }

    // MARK: - Combining Arrays

    /// Creates a vertically stacked buffer from an array of buffers.
    ///
    /// TupleViews use this to combine their children vertically by default
    /// (the parent stack then decides the actual layout direction).
    ///
    /// - Parameter buffers: The buffers to stack vertically.
    public init(verticallyStacking buffers: [Self]) {
        self.init()
        for buffer in buffers {
            appendVertically(buffer)
        }
    }
}

// MARK: - Equatable

extension FrameBuffer {
    /// Equality compares rendered content only: ``lines``, ``overlays``, and
    /// ``hitTestRegions``.
    ///
    /// ``width`` is a pure function of ``lines`` so it adds nothing, and both
    /// ``linesAreUniformWidth`` and ``lineWidths`` are conservative performance
    /// hints excluded by design — two buffers with identical lines are
    /// interchangeable, and each hint is only ever populated when it genuinely
    /// describes those lines. Including them would spuriously distinguish
    /// otherwise-equal buffers and could defeat the render / measure memo that
    /// keys on buffer equality.
    public static func == (lhs: FrameBuffer, rhs: FrameBuffer) -> Bool {
        lhs.lines == rhs.lines
            && lhs.overlays == rhs.overlays
            && lhs.hitTestRegions == rhs.hitTestRegions
            && lhs.animatedCells == rhs.animatedCells
            // Opacity is CONTENT, not a hint: the render and measure memos key
            // on this equality, so leaving it out would serve an unfaded buffer
            // where a faded one was wanted — and the two are identical in every
            // other respect, which is exactly when a memo hits.
            && lhs.opacityRegions == rhs.opacityRegions
    }
}

// MARK: - Public API

extension FrameBuffer {
    /// Stacks another buffer below this one with optional spacing.
    ///
    /// A buffer with **no lines** contributes no height *and* no spacing slot
    /// — the buffers join with the spacing they would have had if `other` were
    /// not in the list at all. This matches SwiftUI's `VStack` behaviour:
    /// `if false { ChildView() }` evaluates to `Optional<ChildView>.none`, and
    /// an `Optional.none` child does not consume a spacing slot from its parent
    /// stack. The same holds for `EmptyView()` and any other zero-height child.
    /// If callers want to reserve a row whether or not the conditional fires,
    /// they must opt in with a sized placeholder such as
    /// `Color.clear`-with-frame or `Spacer.init()`-with-frame — using
    /// `EmptyView()` in an `else` branch will NOT reserve the row, because
    /// `EmptyView()` is also empty.
    ///
    /// Its declared width still counts: the result is at least as wide as
    /// `other` says it is. That is a row of no rows — `HStack { Spacer() }`,
    /// which fills its column's width and has no height (SwiftUI's measured
    /// answer) — and a column holding it is as wide as it is.
    ///
    /// Height is what decides that, not paint: a buffer of N *empty* lines has
    /// a height of N and takes N rows, though it paints nothing in them. That
    /// is the shape a floated view leaves behind (`OffsetView`,
    /// `PositionView`) — the footprint its measure promised, with the drawing
    /// carried off in an overlay layer. Reading "paints nothing" as "is not
    /// here" collapsed those rows and pulled the following sibling up into
    /// them.
    ///
    /// A negative `spacing` pulls `other` up over this buffer's last rows, no
    /// further than its first, and `other` is drawn over them: the later child
    /// on top, as SwiftUI's `VStack` draws it (probed on macOS 15 with
    /// `ImageRenderer`: `VStack(spacing: -10) { red 20 tall; blue 20 tall }` is
    /// 30 tall, blue over the ten rows they share). The buffer is then
    /// `height + spacing + other.height` rows, as the stacks' measure charges
    /// it, so a row of this buffer that `other` ends above is cut — SwiftUI's
    /// stack is as short, and draws that row outside its frame.
    ///
    /// - Parameters:
    ///   - other: The buffer to append below.
    ///   - spacing: Number of empty lines between the two buffers, or, when
    ///     negative, the rows `other` is pulled up over (see above).
    ///     Ignored when `other` has no lines, by design (see above).
    public mutating func appendVertically(_ other: Self, spacing: Int = 0) {
        let priorHeight = lines.count

        guard !other.lines.isEmpty else {
            // `other` contributes no visible lines and no spacing
            // slot (see doc comment above). It may still carry
            // overlay layers and hit-test regions that must be
            // preserved — those are anchored to its (zero-height)
            // position, not to any inter-child spacing.
            appendOverlays(of: other, shiftedByX: 0, y: priorHeight)
            appendHitTestRegions(of: other, shiftedByX: 0, y: priorHeight)
            if !other.animatedCells.isEmpty {
                animatedCells.append(
                    contentsOf: other.shiftedAnimatedCells(byX: 0, y: priorHeight))
            }
            if !other.opacityRegions.isEmpty {
                opacityRegions.append(
                    contentsOf: other.shiftedOpacityRegions(byX: 0, y: priorHeight))
            }
            // …and the width it declares. A row of no rows (`HStack { Spacer() }`,
            // which SwiftUI makes no rows tall) is still as wide as it was
            // given, and the column it stands in is that wide, as
            // `appendHorizontally` keeps the rows of a buffer of no columns.
            // The lines keep their widths, so a wider declared width makes
            // the uniform hint false where there are any (none is "unknown").
            linesAreUniformWidth = linesAreUniformWidth && (storage.isEmpty || other.width <= width)
            width = max(width, other.width)
            return
        }

        // `other`'s content lands below the current lines (plus spacing), over
        // an earlier view's overflow there — or, pulled up by a negative gap,
        // over the current lines themselves.
        let spacingApplied = Self.appliedGap(spacing, after: priorHeight, before: other.lines.count)
        if spacingApplied < 0 {
            appendPulledUp(other, overlapping: -spacingApplied)
            return
        }
        let verticalShift = priorHeight + spacingApplied
        coverOverflow(under: other, at: (x: 0, y: verticalShift))

        // Pre-compute the new width (avoids redundant computation in didSet)
        let newWidth = max(width, other.width)
        let selfWasEmpty = storage.isEmpty

        // Propagate uniform-width cheaply (no re-measure). The stack is uniform
        // only when both sides are uniform AT THE SAME width and no empty spacer
        // line (visible width 0) was inserted between them. When self was empty,
        // the result is simply `other`. Anything else is "unknown" (false).
        //
        // Computed BEFORE the append below, which overwrites the geometry this
        // reads.
        let resultUniform: Bool
        if selfWasEmpty {
            // Unless this buffer of no lines declared a wider width (a
            // buffer of no lines appended to it), which `other`'s lines do
            // not reach.
            resultUniform = other.linesAreUniformWidth && other.width >= width
        } else {
            resultUniform =
                linesAreUniformWidth && other.linesAreUniformWidth
                && width == other.width && spacingApplied == 0
        }

        // Carry per-line widths cheaply (extension, no re-measure) — the exact
        // parallel of `storage`'s growth below. Possible only when both sides
        // already know their widths; otherwise the result is "unknown" (nil).
        // When self was empty the result is simply `other`'s widths; the
        // inserted spacing blank lines ("") each have visible width 0.
        // A uniform side carries no array ("uniform covers it"), but it KNOWS
        // every width — so it is spelled out here rather than dropped, or a
        // stack of uniform rows of two different widths would forget all of
        // them and every consumer downstream (a scroll window, a scrollbar,
        // the writer's pad) would scan the lines to learn them again.
        //
        // Read BEFORE the branch below overwrites it: a carried array is a claim
        // the debug invariant has already measured, while one derived from the
        // uniform hint is a brand-new claim about rows that are already here.
        // That is the whole difference between checking this buffer in linear
        // time and checking it in quadratic time — see
        // `assertLineWidthsInvariant(_:checkedFrom:file:line:)`.
        let lineWidthsWereCarried = lineWidths != nil
        if selfWasEmpty {
            lineWidths = other.lineWidths
        } else if resultUniform {
            lineWidths = nil
        } else if let theirs = other.lineWidths
            ?? (other.linesAreUniformWidth
                ? Array(repeating: other.width, count: other.lines.count) : nil),
            lineWidths != nil || linesAreUniformWidth
        {
            // TAKE the accumulated widths out of the field before growing them.
            // Binding them and copying — `var merged = mine`, where `mine` came
            // from `lineWidths` — left the field referencing that same buffer, so
            // it was never uniquely referenced and every append copied the WHOLE
            // accumulator: 4,000 fresh buffers for 4,000 appends, measured by
            // counting them. That is a second O(n²) in the child count and,
            // unlike the debug invariant re-measure, it shipped in RELEASE.
            //
            // So the `nil` is not tidying up; it is the fix. It drops the
            // field's reference, leaving `merged` the only owner, and the appends
            // below then grow the array in place.
            //
            // Deliberately an expression and an assignment rather than
            // `if let mine = lineWidths { lineWidths = nil; … }`: at `-Onone` a
            // `let` binding lives to the end of its scope, so the buffer would
            // still be shared at the appends and every debug build — the whole
            // test suite included — would go on copying.
            var merged = lineWidths ?? Array(repeating: width, count: storage.count)
            lineWidths = nil
            // No `reserveCapacity` here. It sizes to exactly what is asked for,
            // so reserving the exact final length on each of N appends
            // reallocates on each of them — the copy survives the fix above.
            // `append(contentsOf:)` grows geometrically instead, which is what
            // makes the accumulation amortised O(rows added): ~12 reallocations
            // for those same 4,000 appends.
            if spacingApplied > 0 {
                merged.append(contentsOf: repeatElement(0, count: spacingApplied))
            }
            merged.append(contentsOf: theirs)
            lineWidths = merged
        } else {
            lineWidths = nil
        }

        // Grow the accumulator IN PLACE rather than building a fresh array per
        // child. A stack appends its children one at a time into a single
        // buffer, so copying the accumulated rows on each append made the
        // combine O(n²) in the child count — and, because the rows are
        // `String`s, it retained/released every accumulated row each time.
        // Measured on a plain accumulation of single-line children: 500 → 8000
        // rows cost 0.53 → 103 ms, ~4× per doubling. Appending in place is
        // amortised O(rows added), which is what the loop as a whole needs to
        // be linear.
        //
        // `storage` (not `lines`) deliberately: the public setter recomputes the
        // whole-buffer width per write, and the geometry is already known
        // exactly here — the same reasoning `composite(with:at:)` documents.
        if spacingApplied > 0 {
            storage.append(contentsOf: repeatElement("", count: spacingApplied))
        }
        storage.append(contentsOf: other.lines)
        width = newWidth
        linesAreUniformWidth = resultUniform
        // Only the rows this call newly claims. `priorHeight` covers the
        // `selfWasEmpty` case too (it is 0 there), and the branches that set the
        // field to `nil` check nothing at all.
        Self.assertLineWidthsInvariant(
            self, checkedFrom: lineWidthsWereCarried ? priorHeight : 0)

        // Same story for the three carried side-channels: `a + b` allocates and
        // copies both sides every child, so accumulating N children's overlays
        // or hit regions was quadratic in their total count.
        appendOverlays(of: other, shiftedByX: 0, y: verticalShift)
        appendHitTestRegions(of: other, shiftedByX: 0, y: verticalShift)
        if !other.animatedCells.isEmpty {
            animatedCells.append(
                contentsOf: other.shiftedAnimatedCells(byX: 0, y: verticalShift))
        }
        if !other.opacityRegions.isEmpty {
            opacityRegions.append(
                contentsOf: other.shiftedOpacityRegions(byX: 0, y: verticalShift))
        }
    }

    /// Places another buffer to the right of this one with optional spacing.
    ///
    /// An `other` with no columns contributes no width *and* no spacing slot
    /// — the buffers join with the spacing they would have had if
    /// `other` were not in the list at all. This matches SwiftUI's
    /// `HStack` behaviour (and `appendVertically`'s mirror of the
    /// same rule): an `Optional<ChildView>.none`, an `EmptyView`,
    /// or any other zero-width child is treated as if it were not
    /// in the children list at all. To reserve a column whether or
    /// not a conditional fires, opt in with a sized placeholder
    /// such as `Color.clear`-with-frame or `Spacer.init()`-
    /// with-frame — `EmptyView()` in an `else` branch will NOT
    /// reserve the column, because `EmptyView()` is also empty.
    ///
    /// - Parameters:
    ///   - other: The buffer to append to the right.
    ///   - spacing: Number of space characters between the two buffers.
    ///     Ignored when `other` has no columns, and when this buffer is still
    ///     empty — a gap is charged only between two occupied column ranges.
    public mutating func appendHorizontally(_ other: Self, spacing: Int = 0) {
        let priorWidth = width

        // Not `!other.isEmpty` alone. `isEmpty` asks whether the LINE STRINGS
        // carry anything, and a buffer that declares columns while painting
        // none of them answers yes to that — which is exactly what `.offset`
        // and `.position` hand a stack (`OffsetView`: empty lines reserve the
        // rows, the declared width reserves the columns, and the drawing floats
        // as a layer so nothing is painted over what lies beneath). Sending one
        // of those down the contributes-nothing path dropped its columns, and
        // every later sibling closed up into the space it had been promised:
        // `HStack { Text("AB").offset(y: 1); Text("CD") }` drew "CD" at column
        // 0. `appendVertically`'s mirror asks `other.lines.isEmpty`, which is
        // why the row was held and only the columns were lost.
        guard !other.isEmpty || other.width > 0 else {
            // `other` contributes no visible columns and no spacing
            // slot (see doc comment above). It may still carry
            // overlay layers and hit-test regions that must be
            // preserved — those are anchored to its (zero-width)
            // position, not to any inter-child spacing.
            appendOverlays(of: other, shiftedByX: priorWidth, y: 0)
            appendHitTestRegions(of: other, shiftedByX: priorWidth, y: 0)
            if !other.animatedCells.isEmpty {
                animatedCells.append(
                    contentsOf: other.shiftedAnimatedCells(byX: priorWidth, y: 0))
            }
            if !other.opacityRegions.isEmpty {
                opacityRegions.append(
                    contentsOf: other.shiftedOpacityRegions(byX: priorWidth, y: 0))
            }
            return
        }

        let maxHeight = max(height, other.height)
        let myWidth = priorWidth

        // A gap belongs BETWEEN two occupied column ranges. With no columns yet
        // — an HStack whose leading child rendered empty — `other` is the first
        // thing in the row and must start at column 0, not be indented by a slot
        // it never earned. The mirror of `appendVertically`'s `priorHeight > 0`:
        // rows there, columns here.
        //
        // The predicate is `width`, not `isEmpty`, deliberately: `isEmpty` asks
        // whether the LINE STRINGS carry content, which is the right question
        // for `other` (a buffer of non-empty zero-width lines still contributes
        // HEIGHT below) and the wrong one here, where the question is whether
        // any columns are occupied. A styled-but-empty `Text` would otherwise
        // still earn a phantom indent.
        // …and BETWEEN two of them: `other` declaring no columns earns no gap
        // either, or a row's width would depend on whether any SGR bytes were
        // emitted. That is not hypothetical: a `Text("")` allocated 0 columns
        // renders one line of pure escape bytes (its foreground always resolves,
        // so `ANSIRenderer.render` wraps even an empty string), and `clamped`
        // returns it untouched because its width is ALREADY 0 — so `isEmpty` is
        // false and it reached here as a contributor. `HStack(spacing: 2) {
        // Text("A"); Text(""); Text("B") }` drew 6 cells in colour and 4 with
        // `--no-color`, and no reported width can be right in both.
        //
        // Only the GAP is withheld. `other` still merges its rows: the
        // `!other.isEmpty` half of the guard above exists for the footprint an
        // `.offset`/`.position` child leaves behind, and that one declares
        // columns (`other.width > 0`), so it is untouched here.
        //
        // A negative gap pulls `other` back over this buffer's last columns, no
        // further than its first, and each row here is cut where `other`
        // starts — the later child drawn over the earlier, as SwiftUI's is.
        // Joined like a positive gap, a row kept both halves whole while the
        // width took the overlap off, and the two disagreed.
        let spacingApplied = Self.appliedGap(spacing, after: priorWidth, before: other.width)
        let leftColumns = myWidth + min(0, spacingApplied)
        coverOverflow(under: other, at: (x: myWidth + spacingApplied, y: 0))

        // Pre-compute the new width
        let newWidth = myWidth + spacingApplied + other.width

        var result: [String] = []
        result.reserveCapacity(maxHeight)
        // Settled before the loop — see below it — so a uniform result, the
        // common one-line row, builds no `widths` it would not keep.
        let resultUniform =
            linesAreUniformWidth && other.linesAreUniformWidth && height <= other.height
        // Each combined row's width, kept as the result's `lineWidths` where
        // the result is ragged — see below the loop.
        var widths: [Int] = []
        if !resultUniform { widths.reserveCapacity(maxHeight) }

        for row in 0..<maxHeight {
            var left = row < lines.count ? lines[row] : ""
            let right = row < other.lines.count ? other.lines[row] : ""

            // Build each combined row in place: the left line padded to `myWidth`,
            // then `spacing` spaces, then the right line. This is byte-identical to
            // `left.padToVisibleWidth(myWidth) + spacer + right` but allocates the
            // row once (capacity reserved) and appends the padding/gap as borrowed
            // spaces — no per-row `String(repeating:)` spacer and no `+`-chain
            // intermediates. The left pad replicates `padToVisibleWidth`: append
            // `myWidth - leftWidth` trailing spaces only when the line is narrower.
            // Reuse a known visible width instead of re-measuring per row: a
            // uniform buffer's lines are each exactly `myWidth`, and a ragged
            // buffer that carries `lineWidths` already knows each row's width.
            // Only an unmeasured ragged buffer falls back to `strippedLength`
            // (the dominant cost this avoids). Rows past this buffer's height
            // are zero-wide.
            var leftWidth = knownWidth(ofRow: row, line: left)
            if spacingApplied < 0, leftWidth > leftColumns {
                left = left.ansiAwarePrefix(visibleCount: leftColumns)
                leftWidth = left.strippedLength
            }
            let leftPad = max(0, leftColumns - leftWidth)
            var combined = ""
            combined.reserveCapacity(
                left.utf8.count + leftPad + max(0, spacingApplied) + right.utf8.count)
            combined += left
            if leftPad > 0 { combined += asciiSpaces(leftPad) }
            if spacingApplied > 0 { combined += asciiSpaces(spacingApplied) }
            combined += right
            result.append(combined)
            if !resultUniform {
                widths.append(
                    max(leftWidth, leftColumns) + max(0, spacingApplied) + other.knownWidth(ofRow: row, line: right))
            }
        }

        // Supply the uniform-width hint the
        // bare `FrameBuffer(lines:width:)` used to discard (it defaults the flag
        // to false), so downstream consumers can skip their per-line padding walk
        // — the same hint discipline `appendVertically` follows. Each combined
        // row's left half is exactly `myWidth` when this buffer is uniform (its
        // lines are each `myWidth`, and the rows past its height pad up to
        // `myWidth`); its right half is uniformly `other.width` only when `other`
        // is uniform AND no row falls past `other.height` (a short-right row would
        // be zero-wide). So the result is uniform exactly when both sides are
        // uniform and `other` is at least as tall — anything less certain stays
        // the safe `false` ("unknown", byte-identical: the consumer re-measures).
        storage = result
        width = newWidth
        linesAreUniformWidth = resultUniform
        // Known row by row: the left padded to `myWidth` (or wider, where a
        // line overhangs), the gap, and the right as `other` knew it — measured
        // here once where it did not. Without them the NEXT append re-measured
        // every accumulated row (`left.strippedLength` above), so a row of k
        // ragged children measured its first child's lines k times: 5.6% of a
        // frame of Stress `framedcolumns`, in `_HStackCore.renderClip`.
        // A uniform result needs none: every row is `newWidth`.
        lineWidths = resultUniform ? nil : widths
        Self.assertLineWidthsInvariant(self)

        // `other`'s content lands to the right, past this buffer + spacing.
        // Appended in place rather than via `a + b`, which allocates and copies
        // both sides on every child — quadratic in the accumulated count for a
        // stack of many interactive children. Mirrors `appendVertically`.
        appendOverlays(of: other, shiftedByX: myWidth + spacingApplied, y: 0)
        appendHitTestRegions(of: other, shiftedByX: myWidth + spacingApplied, y: 0)
        if !other.animatedCells.isEmpty {
            animatedCells.append(
                contentsOf: other.shiftedAnimatedCells(byX: myWidth + spacingApplied, y: 0))
        }
        if !other.opacityRegions.isEmpty {
            opacityRegions.append(
                contentsOf: other.shiftedOpacityRegions(byX: myWidth + spacingApplied, y: 0))
        }
    }

    /// The gap ``appendVertically(_:spacing:)`` and
    /// ``appendHorizontally(_:spacing:)`` put before a buffer `extent` long,
    /// with `placedExtent` already placed along the same axis.
    ///
    /// None where either is empty: a gap belongs between two occupied ranges.
    /// Otherwise `spacing`, a negative one held to `-placedExtent`, so a later
    /// child is pulled back over the ones before it no further than the first
    /// of them. Every walk that predicts where an append puts a child — a
    /// stack's measure, its distribution, its glide — charges this gap, so
    /// the extent a stack reports is the extent it draws, and never negative.
    ///
    /// Holding the pull to the first child is a deliberate deviation (owner,
    /// 2026-11-22; L21 in `Deliberate deviations from SwiftUI.md`): SwiftUI lets
    /// a pull past everything before the child move it above the stack's frame,
    /// and draws it there. No practical use for that was found, and a stack
    /// here can't draw outside its frame; re-judge it if one turns up.
    package static func appliedGap(_ spacing: Int, after placedExtent: Int, before extent: Int) -> Int {
        placedExtent > 0 && extent > 0 ? max(spacing, -placedExtent) : 0
    }

    /// ``appendVertically(_:spacing:)`` pulled up by a negative gap: `other`
    /// drawn over this buffer's last `overlap` rows, its first `overlap` rows
    /// over them and the rest below.
    ///
    /// The covered rows are composited on their own, through
    /// ``composited(with:at:)`` — so what an overlay does to the cells it lands
    /// on (punched runs and opacity claims, the field kept under a cell that
    /// names none) is what this does — and spliced back, so the cost is the
    /// rows `other` brings, not the column so far. Only a negative `spacing`
    /// comes here; zero and positive ones stay on the append-only path.
    private mutating func appendPulledUp(_ other: Self, overlapping overlap: Int) {
        let top = lines.count - overlap
        // A row `other` ends above is cut: the stack is `top + other.height`
        // rows, which is what its measure charges (`appliedGap`).
        let bottom = top + other.lines.count
        if bottom < lines.count { self = clamped(toWidth: width, height: bottom) }

        let covered = FrameBuffer(lines: Array(storage[top...]))
        let joined = covered.composited(with: other, at: (x: 0, y: 0))
        // A footprint of rows that paint nothing (`.offset`'s) is not
        // composited, so it brings its rows here.
        let footprint = other.lines.count - joined.lines.count

        // Settled before `storage` is spliced: the rows above `top` keep the
        // widths they had, and only the spliced rows make a new claim.
        let wasUniform = linesAreUniformWidth
        let newWidth = Swift.max(width, joined.width)
        let resultUniform =
            (top == 0 || (wasUniform && width == newWidth)) && joined.linesAreUniformWidth
            && joined.width == newWidth && footprint == 0
        if resultUniform {
            lineWidths = nil
        } else if lineWidths != nil || wasUniform,
            let theirs = joined.linesAreUniformWidth
                ? Array(repeating: joined.width, count: joined.lines.count) : joined.lineWidths
        {
            // Taken out of the field before it is changed, so it is grown in
            // place — see `appendVertically`.
            var merged = lineWidths ?? Array(repeating: width, count: top)
            lineWidths = nil
            merged.removeSubrange(top...)
            merged.append(contentsOf: theirs)
            if footprint > 0 { merged.append(contentsOf: repeatElement(0, count: footprint)) }
            lineWidths = merged
        } else {
            lineWidths = nil
        }

        coverOverflow(under: other, at: (x: 0, y: top))
        animatedCells = animatedCellsPunched(by: other, at: (x: 0, y: top))
        opacityRegions = opacityRegionsPunched(by: other, at: (x: 0, y: top))

        storage.replaceSubrange(top..., with: joined.lines)
        if footprint > 0 { storage.append(contentsOf: repeatElement("", count: footprint)) }
        width = newWidth
        linesAreUniformWidth = resultUniform
        Self.assertLineWidthsInvariant(self, checkedFrom: top)

        appendOverlays(of: joined, shiftedByX: 0, y: top)
        appendHitTestRegions(of: joined, shiftedByX: 0, y: top)
        if !joined.animatedCells.isEmpty {
            animatedCells.append(contentsOf: joined.shiftedAnimatedCells(byX: 0, y: top))
        }
        if !joined.opacityRegions.isEmpty {
            opacityRegions.append(contentsOf: joined.shiftedOpacityRegions(byX: 0, y: top))
        }
    }

    /// The visible width of row `row`, whose string is `line`: none past the
    /// last row, the buffer's width where its lines are uniform, the width it
    /// carries in ``lineWidths``, and measured only where it knows none of
    /// these.
    ///
    /// `line` may be another spelling of the row's string — the same cells
    /// in other colours, as a list row's content is once spent on its fill —
    /// since only its width is asked of it.
    package func knownWidth(ofRow row: Int, line: String) -> Int {
        if row >= lines.count { return 0 }
        if linesAreUniformWidth { return width }
        if let lineWidths { return lineWidths[row] }
        return line.strippedLength
    }

    /// This buffer with `background` in force on every cell that names none of
    /// its own — the buffer-level twin of `String.paintedOver(background:)`.
    ///
    /// What makes a floating layer opaque. A cell that already states its own
    /// background is untouched, so a dialog that paints itself comes back
    /// byte-identical and only the blanks a surface never got round to
    /// colouring are filled.
    ///
    /// - Parameter background: A background escape
    ///   (`SGRState.renderedBackground`), or `""` to leave the buffer alone.
    package func paintedOver(background: String) -> Self {
        guard !background.isEmpty else { return self }
        // Through `replacingLines`, and with the geometry handed back rather
        // than recomputed: painting inserts ESCAPES and no visible cells, so
        // every width this buffer already knows is still true. Letting
        // `FrameBuffer(lines:)` re-measure would walk every line of every
        // floating layer, every frame, to arrive at the numbers above.
        var painted = replacingLines(
            storage.map { $0.paintedOver(background: background) },
            width: width, uniformWidth: linesAreUniformWidth, lineWidths: lineWidths)
        // The runs' cells were painted over it too, wherever their frames leave
        // them bare: the same painting, on their grounds.
        painted.paintRunGrounds { _, ground in ground.paintedOver(background: background) }
        return painted
    }

    /// Creates a new buffer with another buffer composited on top at the specified position.
    ///
    /// Compositing replaces the base cell under every cell of the overlay,
    /// blanks included — a buffer that should not erase what it covers must be
    /// trimmed before it gets here (see ``trimmingTrailingBlankCells()``).
    /// Only a zero-length overlay line is skipped.
    ///
    /// The **field** is the exception, and it is not an exception to the rule
    /// so much as a second statement about the same cell. A glyph and the
    /// colour behind it are two things, and an overlay cell that names no
    /// background of its own has said nothing about the field it lands on — so
    /// it keeps the one that is there, under that cell. That is what makes
    /// `ZStack { Color.red; Text("hi") }` draw the letters ON the red instead
    /// of punching a hole in it, and a label over two colours draws on each; it
    /// costs nothing where the base has no background, which is the ordinary
    /// case. An overlay that names its own background still wins: its escapes
    /// are the later statement.
    ///
    /// - Parameters:
    ///   - overlay: The buffer to composite on top.
    ///   - position: The (x, y) offset where the overlay should be placed.
    /// - Returns: A new buffer with the overlay composited.
    public func composited(with overlay: Self, at position: (x: Int, y: Int)) -> Self {
        composited(with: overlay, at: position, overlayIsPainted: false)
    }

    /// ``composited(with:at:)`` for an overlay that has already stated every
    /// cell's field itself, `overlayIsPainted`, so the field it lands on is not
    /// asked for — in the lines or under its runs.
    ///
    /// A floating layer that is a surface (`OverlayLayer.isOpaque`) is painted onto
    /// the page's colour before it is composited, so every cell of it names a
    /// field, and that field is the layer's. Composited as anything else, the one
    /// cell it can still differ on is the surface's own `ESC[49m` on a palette whose
    /// page is the terminal's own: compositing reads a stated 49 as no field and
    /// fills it, so the surface took the field under it and showed it through.
    ///
    /// `terminalForeground` answers with the RGB the terminal reported for its own
    /// foreground, where the caller knows one, as a field: what an overlay cell over a
    /// cell reversed on the terminal's own ink is drawn on. Asked only under such a
    /// cell. Without an answer such a cell is drawn reversed itself
    /// (``String/paintedOver(fieldsReversing:)``), the one other spelling.
    ///
    /// `composingRows`, where given, puts a painted overlay's rows together itself:
    /// it is handed the base's line on every row of the result ("" past the base's
    /// end), the overlay's line on a row (`nil` where it has none), and the function
    /// that cuts a row's base line into the pieces either side of an overlay line so
    /// wide (``OverlayRowPieces``), and must leave each row as those pieces joined
    /// round the overlay's line. It may join pieces it kept from an earlier
    /// composite of the same base line, column, width and line width
    /// (`OpacityRowReuse`, `Opacity as composition.md` §117). Not asked for an
    /// overlay that is not painted, or one at a negative column.
    package func composited(
        with overlay: Self, at position: (x: Int, y: Int), overlayIsPainted: Bool,
        terminalForeground: () -> SGRState.Colour? = { nil },
        composingRows: ((inout [String], (Int) -> String?, (String, Int?) -> OverlayRowPieces) -> Void)? = nil
    ) -> Self {
        guard !overlay.isEmpty else {
            // Nothing visible to draw, but the overlay may still carry its
            // own nested layers / hit-test regions that need to be
            // lifted into the result.
            // All FOUR payloads, as the in-place twin's guard names them: a
            // faded subtree clamped to no rows is exactly a line-empty overlay
            // whose only payload is its opacity region, and this returned
            // `self` for it while `composite(with:at:)` lifted the region.
            guard !overlay.overlays.isEmpty || !overlay.hitTestRegions.isEmpty
                || !overlay.animatedCells.isEmpty || !overlay.opacityRegions.isEmpty
            else {
                return self
            }
            var result = self
            result.appendOverlays(of: overlay, shiftedByX: position.x, y: position.y)
            result.appendHitTestRegions(of: overlay, shiftedByX: position.x, y: position.y)
            // …and the runs, which the guard above already tests for and this
            // did not lift. The in-place twin `composite(with:at:)` does lift
            // them, so the two disagreed about a zero-size overlay carrying an
            // animation: through this path the run was dropped, and a dropped
            // run is not a lost animation but a FROZEN one, since the loop keeps
            // the clock alive only from the runs that reach the final buffer.
            result.animatedCells.append(
                contentsOf: overlay.shiftedAnimatedCells(byX: position.x, y: position.y))
            result.opacityRegions.append(
                contentsOf: overlay.shiftedOpacityRegions(byX: position.x, y: position.y))
            return result
        }

        let resultWidth = max(width, position.x + overlay.width)
        let resultHeight = max(height, position.y + overlay.height)

        // The fields each overlay row was painted over, for the overlay's runs to
        // record — kept only when it carries any, and when it was painted over them.
        // See `shiftedRuns(groundedOn:byX:y:)`.
        var fields =
            overlay.animatedCells.isEmpty || overlayIsPainted
            ? nil : [FieldsUnderOverlay](repeating: .none, count: overlay.lines.count)

        // The overlay's line on a row of the result, where it has one with anything
        // on it.
        func overlayLine(onRow row: Int) -> String? {
            let overlayRow = row - position.y
            guard overlayRow >= 0, overlayRow < overlay.lines.count, !overlay.lines[overlayRow].isEmpty
            else { return nil }
            return overlay.lines[overlayRow]
        }
        // A painted overlay's row, in its pieces (`OverlayRowPieces`): the base's
        // line padded, and cut round the overlay's line where it has one of
        // `overlayWidth` cells on the row.
        func pieces(_ base: String, overlayWidth: Int?) -> OverlayRowPieces {
            Self.paintedOverlayPieces(
                base: base.padToVisibleWidth(resultWidth), atColumn: position.x, overlayWidth: overlayWidth,
                terminalForeground: terminalForeground)
        }
        // A painted overlay is inserted as it is, between the pieces of the base
        // either side of it; at a negative column it is cut first, below.
        let insertsInPieces = overlayIsPainted && position.x >= 0

        // One row of the result from the base's line on it ("" past the base's
        // end, which pads to a blank row): the line padded to the result's width,
        // with the overlay's line on that row, if it has one, inserted.
        func composedRow(_ row: Int, _ base: String) -> String {
            if insertsInPieces {
                let line = overlayLine(onRow: row)
                return pieces(base, overlayWidth: line?.strippedLength).joined(around: line ?? "")
            }
            let baseLine = base.padToVisibleWidth(resultWidth)
            guard let overlayLine = overlayLine(onRow: row) else { return baseLine }
            let overlayRow = row - position.y
            let inserted = Self.insertOverlay(
                base: baseLine,
                overlay: overlayLine,
                atColumn: position.x,
                overlayIsPainted: overlayIsPainted,
                terminalForeground: terminalForeground
            )
            fields?[overlayRow] = inserted.fields
            return inserted.line
        }

        var result = (0..<resultHeight).map { $0 < lines.count ? lines[$0] : "" }
        if insertsInPieces, let composingRows {
            composingRows(&result, overlayLine(onRow:), pieces(_:overlayWidth:))
        } else {
            for row in result.indices {
                result[row] = composedRow(row, result[row])
            }
        }

        var composited = Self(lines: result)
        // Keep this buffer's own layers + hit-test regions (their
        // overflow cut where the overlay lands); lift the overlay's nested
        // ones, shifted to where the overlay was placed.
        composited.overlays = overflowCovered(under: overlay, at: position)
        composited.overlaysAreFreeOfOverflow = overlaysAreFreeOfOverflow
        composited.appendOverlays(of: overlay, shiftedByX: position.x, y: position.y)
        composited.hitTestRegions = hitTestRegions
        composited.appendHitTestRegions(of: overlay, shiftedByX: position.x, y: position.y)
        // The base's runs are dropped where the overlay covers them, for the
        // same reason its regions are punched below: a run replays its cells
        // over whatever is on screen, and a spinner under a freshly-opened
        // popup would repaint itself THROUGH the popup within one tick. The
        // modal and alert presenters cleared base runs by hand for exactly
        // this; every other overlap — popovers, menus, toasts, ZStack
        // siblings — went uncovered. A partly covered run is CUT to the cells
        // still showing, not dropped whole — `FrameBuffer+Punching.swift` has
        // the reasoning (688a9aa7; it used to be dropped, and a spinner half
        // under a popover froze). The in-place twin below defers here.
        composited.animatedCells =
            animatedCellsPunched(by: overlay, at: position)
            + overlay.shiftedRuns(groundedOn: fields, byX: position.x, y: position.y)
        // BOTH sides. The result is built from a bare `Self(lines:)`, so the
        // DESTINATION's own regions are as easy to drop here as the overlay's
        // — and dropping them un-fades a faded buffer the moment anything is
        // composited into it, which is what `_UserResizableCore` and `Grid` do
        // to their contents routinely.
        //
        // The destination's regions are PUNCHED first: they name cells of the
        // base, and the overlay just replaced some of those cells. A claim
        // left standing over the replaced footprint would fade the overlay's
        // content at the root — content that was never under the fade, as in
        // `.opacity(0.5).overlay { … }`, where the overlay applies to the
        // already-faded view.
        composited.opacityRegions =
            opacityRegionsPunched(by: overlay, at: position)
            + overlay.shiftedOpacityRegions(byX: position.x, y: position.y)
        return composited
    }

    /// Composites `overlay` on top at `position`, **in place**, touching only
    /// the rows the overlay actually covers.
    ///
    /// Identical in result to ``composited(with:at:)``, and there for the case
    /// that method is quadratic in: compositing many small children into one
    /// canvas. `composited` rebuilds — and re-pads — *every* line of the whole
    /// buffer per call, so folding n children through it costs n × canvas even
    /// when each child covers two rows. A custom `Layout` placing 160 subviews
    /// paid 160 full-canvas rebuilds, which is most of what made it slow.
    ///
    /// Only valid while the receiver's lines are uniform width, which is what
    /// lets the width bookkeeping stay incremental; otherwise it falls back to
    /// the copying path, so callers need not check.
    public mutating func composite(with overlay: Self, at position: (x: Int, y: Int)) {
        composite(with: overlay, at: position, terminalForeground: { nil })
    }

    /// ``composite(with:at:)`` with the RGB the terminal reported for its own
    /// foreground, where the caller knows one, and for an overlay that already
    /// states every field it needs (`overlayIsPainted`, drawn over nothing of
    /// the base's) — see ``composited(with:at:overlayIsPainted:terminalForeground:)``.
    package mutating func composite(
        with overlay: Self, at position: (x: Int, y: Int), overlayIsPainted: Bool = false,
        terminalForeground: () -> SGRState.Colour?
    ) {
        guard !overlay.isEmpty else {
            // No visible cells, but nested layers and hit regions still lift.
            guard !overlay.overlays.isEmpty || !overlay.hitTestRegions.isEmpty
                || !overlay.animatedCells.isEmpty || !overlay.opacityRegions.isEmpty
            else { return }
            appendOverlays(of: overlay, shiftedByX: position.x, y: position.y)
            appendHitTestRegions(of: overlay, shiftedByX: position.x, y: position.y)
            animatedCells.append(
                contentsOf: overlay.shiftedAnimatedCells(byX: position.x, y: position.y))
            opacityRegions.append(
                contentsOf: overlay.shiftedOpacityRegions(byX: position.x, y: position.y))
            return
        }
        guard linesAreUniformWidth else {
            self = composited(
                with: overlay, at: position, overlayIsPainted: overlayIsPainted,
                terminalForeground: terminalForeground)
            return
        }

        let resultWidth = Swift.max(width, position.x + overlay.width)
        let resultHeight = Swift.max(height, position.y + overlay.height)

        // Written through `storage`, not `lines`: the row writes below are the
        // whole point of this method, and each one through the public property
        // would re-measure the entire canvas to derive a width this method
        // already knows and overwrites at the end.
        //
        // Grow to the final size. Rows the overlay does not reach keep their
        // contents; they are re-padded only when the width actually grew, which
        // is what keeps every line the same width (and the bookkeeping below
        // honest) without touching them on the common in-bounds path.
        if storage.count < resultHeight {
            storage.append(
                contentsOf: Array(
                    repeating: String.spaces(resultWidth),
                    count: resultHeight - storage.count))
        }
        if resultWidth > width {
            for row in storage.indices {
                storage[row] = storage[row].padToVisibleWidth(resultWidth)
            }
        }

        // As in the copying twin: the fields each overlay row was painted over.
        var fields =
            overlay.animatedCells.isEmpty ? nil : [FieldsUnderOverlay](repeating: .none, count: overlay.lines.count)
        // A painted overlay as wide as the canvas from its first column covers
        // each of its rows whole: nothing of the base shows on them, so the base
        // need not be split around it — the split reads every cell of the row —
        // and the row is the overlay, between the resets an insertion puts round
        // it (``endsPlain(_:)``). A table's header pinned to a scroll view's top
        // is one, drawn over a row of its own on every frame that scrolls past
        // it (SCROLL-FIT P6b), and the split was most of what pinning it cost.
        let coversRows = overlayIsPainted && position.x == 0 && fields == nil && overlay.linesAreUniformWidth
            && overlay.width >= resultWidth
        for overlayRow in overlay.lines.indices {
            let row = position.y + overlayRow
            guard row >= 0, row < storage.count else { continue }
            let overlayLine = overlay.lines[overlayRow]
            guard !overlayLine.isEmpty else { continue }
            if coversRows, Self.endsPlain(storage[row]) {
                storage[row] = Self.ansiReset + overlayLine + Self.ansiReset
                continue
            }
            // The row is `resultWidth` already: every row was `width` (the
            // guard above), and was padded to `resultWidth` if that is wider.
            // Measuring it again to pad it by nothing walked the whole row, a
            // second time beside the split's own walk, for every overlay.
            assert(
                storage[row].strippedLength == resultWidth,
                "a buffer said its rows are one width, and row \(row) is not \(resultWidth) cells")
            let inserted = Self.insertOverlay(
                base: storage[row],
                overlay: overlayLine,
                atColumn: position.x,
                overlayIsPainted: overlayIsPainted,
                terminalForeground: terminalForeground)
            storage[row] = inserted.line
            fields?[overlayRow] = inserted.fields
        }

        width = resultWidth
        linesAreUniformWidth = true
        lineWidths = nil
        coverOverflow(under: overlay, at: position)
        appendOverlays(of: overlay, shiftedByX: position.x, y: position.y)
        appendHitTestRegions(of: overlay, shiftedByX: position.x, y: position.y)
        // Punched, then lifted — same reasoning as the copying twin above: the
        // overlay replaced base cells that pending regions were claiming and
        // runs were repainting.
        animatedCells = animatedCellsPunched(by: overlay, at: position)
        animatedCells.append(
            contentsOf: overlay.shiftedRuns(groundedOn: fields, byX: position.x, y: position.y))
        opacityRegions = opacityRegionsPunched(by: overlay, at: position)
        opacityRegions.append(
            contentsOf: overlay.shiftedOpacityRegions(byX: position.x, y: position.y))
    }
}

// MARK: - Private Helpers

extension FrameBuffer {

    /// ANSI SGR reset sequence. Inlined to avoid depending on ANSIRenderer.
    static let ansiReset = "\u{1B}[0m"

    /// Debug-only check of the ``lineWidths`` invariant: when non-`nil`, it must
    /// equal `buffer.lines.map(\.strippedLength)` (so a carried width is never
    /// allowed to drift from the line it describes).
    ///
    /// Compiled out of release builds entirely — the per-line `strippedLength`
    /// walk it performs is exactly the cost ``lineWidths`` exists to avoid, so it
    /// must never run in production. Call it wherever the field is assigned a
    /// non-`nil` value.
    ///
    /// `checkedFrom` is the first row the caller is making a NEW claim about.
    /// It defaults to 0 — "the whole buffer", the only safe answer for a caller
    /// that cannot say, and what every producer coming through
    /// ``init(lines:width:uniformWidth:lineWidths:)`` gets.
    /// ``appendVertically(_:spacing:)`` *can* say, and that is the difference
    /// between checking a stack in linear time and checking it in quadratic
    /// time: it grows ONE accumulator child by child, so re-measuring the whole
    /// buffer per append cost `N(N+1)/2` row measures to verify N rows — the
    /// same O(n²) in the child count that `88fede9c` took out of the append
    /// itself, put back by the check meant to guard it.
    ///
    /// Skipping the prefix is not a weaker check. Three facts about the append
    /// make it the same check, spread out:
    ///
    /// 1. a row is measured by the call that ADDS it — an appended row is never
    ///    below that call's `checkedFrom`;
    /// 2. the append only ever GROWS `storage`, so a row's text never changes
    ///    afterwards; and
    /// 3. the only thing that restates an existing row's WIDTH is the
    ///    uniform-hint derivation in the merge, which passes 0 and so
    ///    re-measures everything it restated.
    ///
    /// So every (row, width) pair in a non-`nil` ``lineWidths`` has been measured
    /// against its own line, exactly as when the whole buffer was walked every
    /// time. It rests on every OTHER mutator in this file dropping the field to
    /// `nil` rather than leaving it stale — the premise
    /// `FrameBufferLineWidthInvariantTests` exists to pin.
    fileprivate static func assertLineWidthsInvariant(
        _ buffer: FrameBuffer, checkedFrom first: Int = 0,
        file: StaticString = #fileID, line: UInt = #line
    ) {
        #if DEBUG
        guard let widths = buffer.lineWidths else { return }
        guard widths.count == buffer.lines.count else {
            assertionFailure(
                "FrameBuffer.lineWidths count \(widths.count) != lines count \(buffer.lines.count)",
                file: file, line: line)
            return
        }
        if let row = firstLineWidthMismatch(in: buffer.lines, against: widths, from: first) {
            assertionFailure(
                """
                FrameBuffer.lineWidths[\(row)] is \(widths[row]), but row \(row) \
                measures \(buffer.lines[row].strippedLength)
                """,
                file: file, line: line)
        }
        #endif
    }

    /// The first row at or after `from` whose carried width disagrees with a
    /// fresh measure of the line, or `nil` when every one of them agrees.
    ///
    /// Split out of ``assertLineWidthsInvariant(_:checkedFrom:file:line:)`` for
    /// two reasons: a test can ask exactly what the assertion asks without
    /// trapping, and the failure can name the offending row rather than dump two
    /// arrays that are routinely thousands of entries long. Deliberately not
    /// itself `#if DEBUG` — a predicate nobody calls costs a release build
    /// nothing, and one that exists only in debug rots unnoticed.
    static func firstLineWidthMismatch(
        in lines: [String], against widths: [Int], from first: Int
    ) -> Int? {
        let end = Swift.min(lines.count, widths.count)
        let start = Swift.min(Swift.max(0, first), end)
        return (start..<end).first(where: { lines[$0].strippedLength != widths[$0] })
    }
    /// Recomputes the cached ``width`` and ``linesAreUniformWidth`` from the
    /// current ``lines``, and invalidates ``lineWidths``.
    ///
    /// Called automatically by the `didSet` observer on ``lines``. A direct
    /// mutation of `lines` (external assignment) changes the
    /// line content, so any previously-carried per-line widths no longer match;
    /// the single-pass `measure` does not produce the full per-line array, so
    /// they are dropped to `nil` (measure on demand) rather than left stale.
    fileprivate mutating func recomputeWidth() {
        let measured = Self.measure(lines)
        width = measured.width
        linesAreUniformWidth = measured.uniform
        lineWidths = nil
    }

    /// Measures a set of lines in a single pass: the widest line's visible width
    /// and whether every line shares that width.
    ///
    /// Uniformity falls out of tracking the min and max visible width together —
    /// they are equal iff all lines match — so it costs nothing beyond the
    /// per-line `strippedLength` the width already needs. Empty / single-line
    /// inputs are trivially uniform.
    ///
    /// - Parameter lines: The lines to measure.
    /// - Returns: The widest line's visible width and whether all lines match it.
    fileprivate static func measure(_ lines: [String]) -> (width: Int, uniform: Bool) {
        guard let first = lines.first else { return (0, true) }
        var minWidth = first.strippedLength
        var maxWidth = minWidth
        for line in lines.dropFirst() {
            let w = line.strippedLength
            if w < minWidth { minWidth = w }
            if w > maxWidth { maxWidth = w }
        }
        return (maxWidth, minWidth == maxWidth)
    }

    /// Inserts overlay text into base text at the specified column position.
    ///
    /// Splits the base line at visible-character boundaries (ignoring ANSI codes)
    /// and preserves the base's ANSI styling in the prefix and suffix regions.
    /// The overlay replaces the base in its column range, with its own styling intact.
    ///
    /// After the overlay, the base's active ANSI state is restored before the
    /// suffix so the dimmed background (or any other base styling) continues
    /// seamlessly to the right of the overlay.
    ///
    /// Everything it needs about `base` comes from one
    /// `String.ansiOverlaySplit(prefixColumns:suffixDropColumns:)`. It
    /// used to come from five separate ANSI-aware walks of the line, which is
    /// quadratic where it hurts most: a canvas row grows with every styled child
    /// already composited into it, so placing n children rescanned an
    /// ever-longer line 5n times.
    ///
    /// - Parameters:
    ///   - base: The base text line (may contain ANSI codes), already padded to
    ///     the width of the row being built.
    ///   - overlay: The overlay text to insert (may contain ANSI codes).
    ///   - column: The column position (0-based, in visible characters).
    ///   - overlayIsPainted: Whether the overlay already states every field it
    ///     needs, so nothing is painted under it — see
    ///     ``insertOverlay(split:overlay:atColumn:minimumTotalWidth:overlayIsPainted:)``.
    /// - Returns: The composited line with base styling preserved around the overlay,
    ///   and the fields the overlay's bare cells were painted over there, column by
    ///   column (`ANSIOverlaySplit.fieldsUnderOverlay`) — which the overlay's runs
    ///   record as their ground (``AnimatedCellRun/ground``).
    /// Whether `line` ends in no style and no hyperlink: a reset last, and no
    /// OSC escape (a link's) anywhere. An insertion that covers such a line
    /// whole restores nothing after the overlay — the style the split nets at
    /// its end is the default, and no link reopens — so it is the overlay
    /// between two resets, and the split need not be made to find that out.
    /// A byte scan, which reads no cell's width.
    private static func endsPlain(_ line: String) -> Bool {
        guard line.hasSuffix(ansiReset) else { return false }
        var afterEscape = false
        for byte in line.utf8 {
            if afterEscape, byte == 0x5D { return false }
            afterEscape = byte == 0x1B
        }
        return true
    }

    fileprivate static func insertOverlay(
        base: String,
        overlay: String,
        atColumn column: Int,
        overlayIsPainted: Bool = false,
        terminalForeground: () -> SGRState.Colour? = { nil }
    ) -> (line: String, fields: FieldsUnderOverlay) {
        // An overlay starting LEFT of the base is cut to the part that is on it and
        // inserted at column 0 — the answer both composite twins already give a negative
        // ROW, which they skip. It used to pass straight through: the split has no prefix
        // before a negative column and drops only `column + width` cells of the base, so
        // the WHOLE overlay went in at column 0 and the base's own cells slid right behind
        // it. The row came out `-column` cells wider than the canvas, and the in-place
        // twin then stamped the canvas's width and `linesAreUniformWidth = true` over it —
        // a lie every consumer that trusts the hint mis-pads on: a parent `HStack` starts
        // its next child inside the row, and a row past the terminal edge wraps onto the
        // next. The public route is a custom `Layout` placing a subview's centre at x: 0
        // with `place(at:anchor:)`, which does not clamp (its `place(in:)` sibling does).
        //
        // Here, and not at the two twins' call sites, because this is the function only
        // they call: the run splice and the opacity splice share the split-taking overload
        // below, and every column reaching them is already clamped non-negative.
        guard column >= 0 else {
            guard column + overlay.strippedLength > 0 else { return (base, .none) }
            return insertOverlay(
                base: base, overlay: overlay.ansiAwareCuttingLeadingColumns(-column), atColumn: 0,
                overlayIsPainted: overlayIsPainted, terminalForeground: terminalForeground)
        }
        let overlayVisibleWidth = overlay.strippedLength

        // Split the base into prefix (before overlay) and suffix (after overlay),
        // preserving all ANSI codes in both segments.
        let split = base.ansiOverlaySplit(
            prefixColumns: column, suffixDropColumns: column + overlayVisibleWidth,
            terminalForeground: terminalForeground)
        return (
            insertOverlay(split: split, overlay: overlay, atColumn: column, overlayIsPainted: overlayIsPainted),
            split.fieldsUnderOverlay
        )
    }

    /// ``insertOverlay(base:overlay:atColumn:overlayIsPainted:)`` for a caller that has already
    /// split the base at the overlay's columns — the split carries the
    /// overlay's end, so nothing is measured again.
    ///
    /// `overlayIsPainted` is for a caller that has already put every field the
    /// overlay needs in force, cell by cell — the animation tick, the opacity
    /// resolution's span, and a floating surface; anything else is painted over
    /// the field under each of its cells.
    static func insertOverlay(
        split: ANSIOverlaySplit,
        overlay: String,
        atColumn column: Int,
        minimumTotalWidth: Int = 0,
        overlayIsPainted: Bool = false
    ) -> String {
        let afterOverlayColumn = split.suffixDropColumns
        let seams = Self.seams(of: split, atColumn: column, minimumTotalWidth: minimumTotalWidth)

        // A cell has a glyph AND a field, and an overlay cell that states no
        // background of its own has said nothing about the field — so it keeps
        // the one it lands on. `ZStack { Color.red; Text("hi") }` is the case
        // that wants this: the letters are drawn ON the red rather than
        // punching a hole in it. An overlay that states its own background
        // still wins, because its escapes come after this one.
        //
        // The one it lands on is the one under EACH cell. Read once, under the
        // overlay's first column, it drew a label over two colours all on the
        // first (`FieldsUnderOverlay.swift`). One field under the whole span is
        // nearly every overlay, and is painted as it always was, from the escape
        // the split already rendered — and nothing is emitted where the base
        // states no background, which is the ordinary case.
        let overlay =
            if overlayIsPainted {
                overlay
            } else if split.fieldsUnderOverlay.showsTerminalForeground {
                overlay.paintedOver(
                    fieldsReversing: split.fieldsUnderOverlay.fields(
                        over: split.fieldsUnderOverlay.column..<afterOverlayColumn))
            } else if split.fieldsUnderOverlay.isUniform {
                overlay.paintedOver(background: split.backgroundUnderOverlay)
            } else {
                overlay.paintedOver(
                    split.fieldsUnderOverlay, atColumn: split.fieldsUnderOverlay.column,
                    width: afterOverlayColumn - split.fieldsUnderOverlay.column)
            }

        // Build: [prefix + reset] + [overlay] + [reset + base style restore + suffix]
        var result = seams.head
        result += overlay
        result += seams.tail
        return result
    }
}
