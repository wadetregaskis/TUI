//  🖥️ TUI — A Terminal UI framework for Swift
//  PaddingModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

/// Edge insets defining padding on each side.
public struct EdgeInsets: Sendable, Equatable {
    /// Padding above the content.
    public var top: Int

    /// Padding to the left of the content.
    public var leading: Int

    /// Padding below the content.
    public var bottom: Int

    /// Padding to the right of the content.
    public var trailing: Int

    /// Creates edge insets with individual values.
    public init(top: Int = 0, leading: Int = 0, bottom: Int = 0, trailing: Int = 0) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    /// Creates uniform edge insets.
    ///
    /// - Parameter value: The padding on all four sides.
    public init(all value: Int) {
        self.top = value
        self.leading = value
        self.bottom = value
        self.trailing = value
    }

    /// Creates horizontal and vertical edge insets.
    ///
    /// - Parameters:
    ///   - horizontal: The padding on leading and trailing sides.
    ///   - vertical: The padding on top and bottom sides.
    public init(horizontal: Int = 0, vertical: Int = 0) {
        self.top = vertical
        self.leading = horizontal
        self.bottom = vertical
        self.trailing = horizontal
    }
}

/// An edge of a view.
///
/// Mirrors SwiftUI's `Edge`: the type itself is a single edge, and the
/// nested ``Edge/Set-swift.struct`` is an efficient set of edges.
public enum Edge: Int8, Sendable, CaseIterable {
    /// The top edge.
    case top

    /// The leading (left) edge.
    case leading

    /// The bottom edge.
    case bottom

    /// The trailing (right) edge.
    case trailing

    /// An efficient set of edges.
    public struct Set: OptionSet, Sendable {
        /// The raw bitmask value for this edge set.
        public let rawValue: UInt8

        /// Creates an edge set from a raw bitmask value.
        ///
        /// - Parameter rawValue: The bitmask value.
        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// Creates a set containing the one edge given.
        ///
        /// SwiftUI's `Edge.Set(_:)`, and the reason to have it is that generic
        /// code holding an `Edge` has no other way to reach the set: the
        /// statics below are spelled the same but are a different type, so
        /// `Edge.Set(edge)` is what any `for edge in Edge.allCases` loop needs.
        ///
        /// - Parameter edge: The edge the set contains.
        public init(_ edge: Edge) {
            switch edge {
            case .top: self = .top
            case .leading: self = .leading
            case .bottom: self = .bottom
            case .trailing: self = .trailing
            }
        }

        /// The top edge.
        public static let top = Self(rawValue: 1 << 0)

        /// The leading (left) edge.
        public static let leading = Self(rawValue: 1 << 1)

        /// The bottom edge.
        public static let bottom = Self(rawValue: 1 << 2)

        /// The trailing (right) edge.
        public static let trailing = Self(rawValue: 1 << 3)

        /// All four edges.
        public static let all: Set = [.top, .leading, .bottom, .trailing]

        /// The leading and trailing edges.
        public static let horizontal: Set = [.leading, .trailing]

        /// The top and bottom edges.
        public static let vertical: Set = [.top, .bottom]
    }
}

/// A modifier that adds padding around a view.
///
/// - Important: This is framework infrastructure. Use `.padding()` on any
///   ``View`` instead of instantiating this type directly.
public struct PaddingModifier: BufferModifier {
    /// The padding insets.
    ///
    /// A `var` so an animation can substitute it — see the `Animatable`
    /// conformance below.
    ///
    /// Every inset is held to `0...Int.statedLengthLimit`, whether stated or
    /// animated (a spring overshoots below zero). A negative inset drew a
    /// negative count of blank rows — a trap — and SwiftUI's, which pulls the
    /// frame in over the content, has no cell grid to do it on; one past the
    /// limit overflowed the sum of the two insets.
    var insets: EdgeInsets {
        get { heldInsets }
        set { heldInsets = Self.held(newValue) }
    }

    private var heldInsets: EdgeInsets

    init(insets: EdgeInsets) {
        heldInsets = Self.held(insets)
    }

    private static func held(_ insets: EdgeInsets) -> EdgeInsets {
        func hold(_ inset: Int) -> Int { max(0, inset.heldToStatedLength) }
        return EdgeInsets(
            top: hold(insets.top), leading: hold(insets.leading), bottom: hold(insets.bottom),
            trailing: hold(insets.trailing))
    }

    public func adjustContext(_ context: RenderContext) -> RenderContext {
        var adjusted = context
        // Padding never takes the LAST cell from its content. Where there is
        // room for anything at all, the content keeps at least one cell of it
        // and the padding is what overflows — decoration losing to the thing it
        // decorates, which is the only order that degrades legibly.
        //
        // Clamped flat at zero, a `.padding(1).border()` in three rows offered
        // its text -1 lines, which became 0, which rendered nothing, which
        // collapsed the box to an empty 6×3 frame — the width gone too, because
        // a view with no content has no width to report. A height constraint
        // must not decide a width.
        adjusted.availableWidth = Self.remaining(
            context.availableWidth, less: insets.leading + insets.trailing)
        adjusted.availableHeight = Self.remaining(
            context.availableHeight, less: insets.top + insets.bottom)
        adjusted = relayingScrollWindow(from: context, to: adjusted)
        // Where the content sits in the padded view — past the leading and top
        // insets `modify` draws for content that is not empty — for a ramp
        // spanning the view and the carried geometry origin
        // (`RenderContext.placingChild(gradient:x:y:)`). Worked out only when
        // one of them will be read.
        guard context.placesChildren else { return adjusted }
        let leading = Self.drawnInsets(
            insets.leading, insets.trailing, in: context.availableWidth, contentIsEmpty: false
        ).before
        let top = Self.drawnInsets(
            insets.top, insets.bottom, in: context.availableHeight, contentIsEmpty: false
        ).before
        return adjusted.placingChild(gradient: adjusted.gradientFrame, x: leading, y: top)
    }

    /// `available` less `taken`, but never below one cell while `available` has
    /// one to give.
    ///
    /// The same rule a bordered container applies to its interior, and the same
    /// implementation: padding and a border are both decoration subtracting
    /// from an extent, and the day the two spellings drift is the day a
    /// `.padding().border()` measures one size and draws another.
    private static func remaining(_ available: Int, less taken: Int) -> Int {
        RenderContext.extent(available, insideChrome: taken)
    }

    /// How much padding an axis actually draws, split into the inset before the
    /// content and the one after it.
    ///
    /// Not the same question as ``remaining(_:less:)``, which decides what the
    /// CONTENT gets. This decides what the padding gets, and the two have to
    /// add up: `adjustContext` hands the content `remaining`, so anything else
    /// drawn on this axis makes the buffer wider than the view was measured to
    /// be. Deriving both from one subtraction is what keeps the measure and the
    /// render agreeing.
    ///
    /// The `before` cap is the part that is not just bookkeeping. A leading or
    /// top inset is an OFFSET — it pushes the content away from the very edge
    /// the viewport is measured from — so an inset the size of the viewport
    /// moves every cell of content past its far side. One row of terminal and a
    /// `.padding()` drew a blank row and put the text on row 1, and the screen
    /// went empty: not clipped, erased. So the leading inset stops one cell
    /// short of the space, and what it gives up the trailing inset cannot
    /// claim — the content is what wins the cell back.
    ///
    /// Unless the content drew nothing on the axis. Then there is no content to
    /// push past the edge and none to keep a cell for, so both insets are drawn
    /// as far as the space goes — which is what the measure said: an empty
    /// content's size plus the insets, where a stack hands the view exactly
    /// that. Kept back anyway, `VStack { Text("A"); EmptyView().padding(2);
    /// Text("B") }` measured six rows and drew five.
    private static func drawnInsets(
        _ before: Int, _ after: Int, in available: Int, contentIsEmpty: Bool
    ) -> (before: Int, after: Int) {
        if contentIsEmpty {
            let drawnBefore = min(before, max(0, available))
            return (drawnBefore, min(after, max(0, available - drawnBefore)))
        }
        let total = max(0, available - remaining(available, less: before + after))
        let drawnBefore = min(before, max(0, available - 1), total)
        return (drawnBefore, total - drawnBefore)
    }

    public func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        let horizontal = Self.drawnInsets(
            insets.leading, insets.trailing, in: context.availableWidth,
            contentIsEmpty: buffer.width == 0)
        var vertical = Self.drawnInsets(
            insets.top, insets.bottom, in: context.availableHeight,
            contentIsEmpty: buffer.height == 0)
        // A lazy stack in the content that drew a band of its rows leaves out
        // the padding the band does not reach (`relayingScrollWindow`).
        if let placement = answerRelayedScrollWindow(contentBuffer: buffer, linesBelow: vertical.after, context: context) {
            if !placement.drawsAbove { vertical.before = 0 }
            if !placement.drawsBelow { vertical.after = 0 }
        }
        shiftAnsweredColumns(by: horizontal.before, context: context)

        var result: [String] = []
        result.reserveCapacity(vertical.before + buffer.lines.count + vertical.after)

        let leadingCount = horizontal.before
        let trailingCount = horizontal.after

        // Calculate line width
        let lineWidth = buffer.width + leadingCount + trailingCount
        // The full-width blank pad rows are all identical, so build one and reuse
        // its value for every top/bottom row (cheaper than re-slicing per row).
        let emptyLine = String(asciiSpaces(lineWidth))

        // Top padding (full lines)
        for _ in 0..<vertical.before {
            result.append(emptyLine)
        }

        // Content lines with horizontal padding. Each padded line is built in
        // place — reserve once, then append the leading spaces, the line, and the
        // trailing spaces as borrowed runs — byte-identical to
        // `leadingPad + line + trailingPad` without the `+`-chain intermediates.
        for line in buffer.lines {
            var padded = ""
            padded.reserveCapacity(line.utf8.count + leadingCount + trailingCount)
            if leadingCount > 0 { padded += asciiSpaces(leadingCount) }
            padded += line
            if trailingCount > 0 { padded += asciiSpaces(trailingCount) }
            result.append(padded)
        }

        // Bottom padding (full lines)
        for _ in 0..<vertical.after {
            result.append(emptyLine)
        }

        // Content shifted right by `leading` and down by `top`; carry any
        // overlay layers by the same amount so they stay anchored. The padded
        // width is exactly `lineWidth` (the widest input line is `buffer.width`,
        // and the empty pad lines are built to `lineWidth`), so pass it and skip
        // re-measuring every line — a hot recompute in deeply-nested layouts.
        //
        // The output is uniform-width exactly when the input is: each content
        // line becomes `leading + line + trailing`, so equal-width input lines
        // give equal-width output lines (all `lineWidth`, matching the pad rows).
        // Propagating this lets an enclosing border skip re-measuring in turn.
        return buffer.replacingLines(
            result, width: lineWidth, uniformWidth: buffer.linesAreUniformWidth,
            overlayShiftX: leadingCount, overlayShiftY: vertical.before)
    }
}

// MARK: - The scroll window, relayed

extension PaddingModifier {
    /// The padding's lines above and below its content where it is the
    /// scroll content, or a single-child step of it: the window a lazy stack
    /// in the content bands itself against is relayed below the top padding
    /// (`ScrollWindowRelay`), as a `Section` relays it below its header and
    /// the content margins below theirs. Unrelayed, a stack under
    /// `.padding(.vertical)` took the window as if it were all the content:
    /// the scroll view took the stack's height for the content's, and End
    /// stopped short of the last row and the padding below it.
    ///
    /// The relay waits on the content's reply for ``modify(buffer:context:)``
    /// on the scroll view's own reply (``ScrollContentReply/pendingRelay``),
    /// the one thing the two passes share. Asked of the insets and the
    /// context first — vertical or leading padding, on a render, at the
    /// scroll content's origin — so every other padding reads nothing from
    /// the environment for it.
    ///
    /// A leading inset moves the content across instead: the column a
    /// purely horizontal view samples for its read-back is sought so much
    /// further left in the content (``RenderContext/withScrollWindowAcross(leading:)``),
    /// and the columns it answers are moved back right
    /// (``shiftAnsweredColumns(by:context:)``).
    fileprivate func relayingScrollWindow(from context: RenderContext, to adjusted: RenderContext) -> RenderContext {
        guard insets.top > 0 || insets.bottom > 0 || insets.leading > 0, !context.isMeasuring,
            context.mayConsumeScrollWindow
        else { return adjusted }
        var relayed = adjusted
        if insets.top > 0 || insets.bottom > 0 {
            let drawn = Self.drawnInsets(insets.top, insets.bottom, in: context.availableHeight, contentIsEmpty: false)
            if let relay = ScrollWindowRelay(context: context, linesAbove: drawn.before, linesBelow: { drawn.after }) {
                context.environment.scrollContentWindow?.reply?.pendingRelay = relay
                relayed = relay.contentContext(adjusted)
            }
        }
        guard insets.leading > 0, let window = relayed.environment.scrollContentWindow, window.columnReport != nil,
            window.isAtOrigin(context.identity)
        else { return relayed }
        let leading = Self.drawnInsets(insets.leading, insets.trailing, in: context.availableWidth, contentIsEmpty: false)
        return relayed.withScrollWindowAcross(leading: leading.before)
    }

    /// The columns the content answered into the scroll view's reply, moved
    /// right past the `leading` cells this padding draws before it, where the
    /// content is the scroll content or a single-child step of it: a column a
    /// carousel under `.padding()` sought was placed a cell short.
    fileprivate func shiftAnsweredColumns(by leading: Int, context: RenderContext) {
        guard leading > 0, !context.isMeasuring, context.mayConsumeScrollWindow,
            let window = context.environment.scrollContentWindow, window.isAtOrigin(context.identity)
        else { return }
        window.reply?.shiftColumns(by: leading)
    }

    /// The relay ``relayingScrollWindow(from:to:)`` set up, answered once the
    /// content has drawn: which of the padding's lines the band holds.
    fileprivate func answerRelayedScrollWindow(
        contentBuffer: FrameBuffer, linesBelow: Int, context: RenderContext
    ) -> ScrollWindowRelay.Placement? {
        guard insets.top > 0 || insets.bottom > 0, !context.isMeasuring, context.mayConsumeScrollWindow,
            let reply = context.environment.scrollContentWindow?.reply, let relay = reply.pendingRelay
        else { return nil }
        reply.pendingRelay = nil
        return relay.answer(contentBuffer: contentBuffer, linesBelow: linesBelow)
    }
}

// MARK: - Animating padding

extension PaddingModifier: Animatable {
    /// The insets are what moves, so a change to them inside
    /// ``withAnimation(_:_:)`` opens or closes the gap rather than jumping it
    /// — except where ``EnvironmentValues/accessibilityReduceMotion`` is on,
    /// where it jumps: padding moves the content.
    ///
    /// Padding is a *layout* change, so this is the expensive shape: the
    /// subtree is re-measured and re-laid-out on every frame of the animation.
    /// Bounded by the animation's duration, and not something to put on
    /// ``Animation/repeatForever(autoreverses:)``.
    public var animatableData: EdgeInsets.AnimatableData {
        get { insets.animatableData }
        set { insets.animatableData = newValue }
    }
}

/// Motion: an animated padding moves its content, so under reduce motion it
/// jumps to its end (owner decision A-D3M-1).
extension PaddingModifier: SpatialAnimatable {}
