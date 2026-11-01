//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Frame Dimension

/// Represents a frame dimension that can be a fixed value or infinity.
///
/// An integer literal is a fixed value, so SwiftUI's `.frame(maxWidth: 200)`
/// compiles as written — in cells (§2.1 of the compatibility guide).
public enum FrameDimension: Equatable, Sendable, ExpressibleByIntegerLiteral {
    /// A fixed size in characters/lines.
    case fixed(Int)

    /// Expand to fill all available space.
    case infinity

    /// The special infinity value for frame constraints.
    public static let max: FrameDimension = .infinity

    /// A fixed size of `value` cells.
    public init(integerLiteral value: Int) {
        self = .fixed(value)
    }
}

// MARK: - Flexible Frame View

/// A view that applies flexible frame constraints to its content.
///
/// This view handles min/max constraints and renders content with
/// the appropriate available space.
package struct FlexibleFrameView<Content: View>: View {
    // The six constraints are stored one word each — `FrameWord` — rather than
    // as `Int?` / `FrameDimension?`, and declared before the content. An
    // optional word is nine bytes at eight-byte alignment, so each left seven
    // bytes of padding behind it, 41 in `.frame(width:)` over a `Text`, and the
    // per-pass memos key a view by its bytes: padding is whatever the memory
    // held before, so two equal frames could miss each other. The words, then
    // the alignment (48 bytes, word-aligned too), then the content LAST, so
    // no field follows it whatever its size, leaves no gap
    // (`FrameLayoutPaddingTests`), and the wrapper over a `Text` is 200 →
    // 151 bytes. The optional-typed properties below
    // are the API, and `var` so an animation can substitute them — see the
    // `Animatable` conformance.
    private var minWidthWord: Int
    private var idealWidthWord: Int
    private var maxWidthWord: Int
    private var minHeightWord: Int
    private var idealHeightWord: Int
    private var maxHeightWord: Int

    /// The alignment of the content within the frame.
    let alignment: Alignment

    /// The content view to constrain.
    let content: Content

    init(
        content: Content, minWidth: Int? = nil, idealWidth: Int? = nil, maxWidth: FrameDimension? = nil,
        minHeight: Int? = nil, idealHeight: Int? = nil, maxHeight: FrameDimension? = nil,
        alignment: Alignment
    ) {
        self.minWidthWord = FrameWord.pack(minWidth)
        self.idealWidthWord = FrameWord.pack(idealWidth)
        self.maxWidthWord = FrameWord.pack(maxWidth)
        self.minHeightWord = FrameWord.pack(minHeight)
        self.idealHeightWord = FrameWord.pack(idealHeight)
        self.maxHeightWord = FrameWord.pack(maxHeight)
        self.alignment = alignment
        self.content = content
    }

    /// The minimum width in characters, or nil for no minimum.
    package var minWidth: Int? {
        get { FrameWord.unpack(minWidthWord) }
        set { minWidthWord = FrameWord.pack(newValue) }
    }

    /// The ideal width in characters, or nil to use intrinsic size.
    package var idealWidth: Int? {
        get { FrameWord.unpack(idealWidthWord) }
        set { idealWidthWord = FrameWord.pack(newValue) }
    }

    /// The maximum width constraint, or nil for no maximum.
    package var maxWidth: FrameDimension? {
        get { FrameWord.unpackDimension(maxWidthWord) }
        set { maxWidthWord = FrameWord.pack(newValue) }
    }

    /// The minimum height in lines, or nil for no minimum.
    package var minHeight: Int? {
        get { FrameWord.unpack(minHeightWord) }
        set { minHeightWord = FrameWord.pack(newValue) }
    }

    /// The ideal height in lines, or nil to use intrinsic size.
    package var idealHeight: Int? {
        get { FrameWord.unpack(idealHeightWord) }
        set { idealHeightWord = FrameWord.pack(newValue) }
    }

    /// The maximum height constraint, or nil for no maximum.
    package var maxHeight: FrameDimension? {
        get { FrameWord.unpackDimension(maxHeightWord) }
        set { maxHeightWord = FrameWord.pack(newValue) }
    }

    public var body: Never {
        fatalError("FlexibleFrameView renders via Renderable")
    }
}

/// A frame constraint in one word: `Int.min` is "none", `Int.min + 1` is
/// `.infinity`, and anything else is the size itself.
///
/// A size is stored held to ``Swift/Int/statedLengthLimit`` either way, which
/// keeps it clear of the two sentinels at `Int.min` and of overflow in the
/// sums that align content in the frame. Every use floors a constraint at
/// zero or takes the larger of it and a size, so a size that far below zero
/// means what zero does.
private enum FrameWord {
    static let none = Int.min
    static let infinity = Int.min + 1

    static func pack(_ size: Int?) -> Int {
        guard let size else { return none }
        return size.heldToStatedLength
    }

    static func pack(_ dimension: FrameDimension?) -> Int {
        switch dimension {
        case nil: none
        case .infinity: infinity
        case .fixed(let size): size.heldToStatedLength
        }
    }

    static func unpack(_ word: Int) -> Int? {
        word == none ? nil : word
    }

    static func unpackDimension(_ word: Int) -> FrameDimension? {
        switch word {
        case none: nil
        case infinity: .infinity
        default: .fixed(word)
        }
    }
}

// MARK: - Equatable Conformance

extension FlexibleFrameView: @preconcurrency Equatable where Content: Equatable {
    package static func == (lhs: FlexibleFrameView<Content>, rhs: FlexibleFrameView<Content>) -> Bool {
        guard lhs.content == rhs.content, lhs.minWidth == rhs.minWidth, lhs.idealWidth == rhs.idealWidth,
            lhs.maxWidth == rhs.maxWidth, lhs.minHeight == rhs.minHeight, lhs.idealHeight == rhs.idealHeight,
            lhs.maxHeight == rhs.maxHeight
        else { return false }
        return lhs.alignment == rhs.alignment
    }
}

// MARK: - Renderable

extension FlexibleFrameView {
    /// The frame's width constraints, in order (``FlexibleFrameAxis``).
    var widthAxis: FlexibleFrameAxis {
        FlexibleFrameAxis(minimum: minWidth, ideal: idealWidth, maximum: maxWidth)
    }

    /// The frame's height constraints, in order (``FlexibleFrameAxis``).
    var heightAxis: FlexibleFrameAxis {
        FlexibleFrameAxis(minimum: minHeight, ideal: idealHeight, maximum: maxHeight)
    }

    /// The width the content is offered for a given available width: that
    /// width, held to a finite maximum. An ideal width is not read — a frame
    /// offered a width offers its content that width, as SwiftUI's does —
    /// unless the frame was offered no width (`offeredNothing`), when its
    /// content is offered the ideal.
    ///
    /// Shared by ``renderToBuffer(context:)`` and ``sizeThatFits(proposal:context:)``
    /// so the measure and render passes can never disagree about how the
    /// frame constrains its content.
    func contentTargetWidth(availableWidth: Int, offeredNothing: Bool = false) -> Int {
        widthAxis.contentBudget(availableWidth, unspecified: offeredNothing)
    }

    /// Whether this frame, laid out in `context`, was offered no width though
    /// the context carries one: it is laid out or drawn under `.fixedSize()`,
    /// which asked it its ideal width — SwiftUI's unspecified proposal — and
    /// hands it the width it answered, through nothing that offers it a width
    /// (``EnvironmentValues/offeredNoWidth``: a row passes the unspecified
    /// width on, a column of several does not). Only a frame with an ideal
    /// width tells the two apart: offered nothing it is exactly that ideal,
    /// where offered a width it is its content's
    /// (`Tools/SwiftUIProbes/Alignment guides/layout1.out`, case D2;
    /// `Flexible frames/ideal-placed.out`). Such a frame offers its content
    /// its ideal, a width, so the flag stops at it — `fixedSizeWidth` too, so
    /// a `List` inside it does not hug.
    func isOfferedNoWidth(in context: RenderContext) -> Bool {
        idealWidth != nil && context.environment.offeredNoWidth
    }

    /// `context` as this frame offers it to its content when it was offered no
    /// width (``isOfferedNoWidth(in:)``): offered its ideal, a width.
    func offeringItsIdeal(_ context: RenderContext) -> RenderContext {
        var offered = context
        offered.environment.fixedSizeWidth = false
        offered.environment.offeredNoWidth = false
        return offered
    }

    /// The frame's width around content `content` wide when it was offered
    /// `offer`, or nothing (``isOfferedNoWidth(in:)``).
    func finalWidth(content: Int, offer: Int, offeredNothing: Bool) -> Int {
        offeredNothing ? widthAxis.extentOfferedNothing(content: content) : widthAxis.extent(content: content, offer: offer)
    }

    /// The height the content is offered for a given available height, or
    /// `nil` to use the content's intrinsic height. Shared by the render and
    /// measure passes (see ``contentTargetWidth(availableWidth:)``).
    ///
    /// - Parameter fills: Whether the frame was offered a height. True when
    ///   rendering — the frame is being given concrete space, which a
    ///   maximum fills up to. False when the caller asked for an IDEAL height
    ///   (no height in the proposal): the content is offered the frame's
    ///   ideal height, or its own where the frame has none, and "as tall as
    ///   I'm given" has no answer when nothing was given, so the honest
    ///   report is the content's own height, flagged flexible. SwiftUI
    ///   resolves an unspecified proposal the same way, and the alternative
    ///   is a lie with visible consequences — inside a `ScrollView`, a frame
    ///   reporting the measure budget as its natural height invents thousands
    ///   of lines of scrollable emptiness under a one-line label.
    func contentTargetHeight(availableHeight: Int, fills: Bool = true) -> Int? {
        let axis = heightAxis
        if fills {
            return axis.maximum == nil ? nil : axis.contentBudget(availableHeight, unspecified: false)
        }
        // A finite maximum still holds a content asked its own height, as it
        // always has; the frame comes out the same, cut to that maximum.
        guard axis.ideal != nil else {
            return axis.finiteMaximum == nil ? nil : axis.contentBudget(availableHeight, unspecified: false)
        }
        return axis.contentBudget(availableHeight, unspecified: true)
    }
}

extension FlexibleFrameView: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Calculate the target width and height based on constraints (the same
        // computation the measure pass uses, see contentTargetWidth/Height).
        let offeredNoWidth = isOfferedNoWidth(in: context)
        let targetWidth = contentTargetWidth(availableWidth: context.availableWidth, offeredNothing: offeredNoWidth)
        let targetHeight = contentTargetHeight(availableHeight: context.availableHeight)

        // Create context for content with constrained width
        var contentContext = context
        contentContext.availableWidth = targetWidth
        if let height = targetHeight {
            contentContext.availableHeight = height
        }
        // Offered no width, this frame offers its content its ideal: a width.
        if offeredNoWidth { contentContext = offeringItsIdeal(contentContext) }

        // Mark that an explicit width constraint was set
        if minWidth != nil || idealWidth != nil || maxWidth != nil {
            contentContext.hasExplicitWidth = true
        }
        // …and the height half, which was missing. `hasExplicitHeight` is the flag
        // by which "child views (like List) know to expand to fill the available
        // height" (see `RenderContext.withAvailableHeight(_:)`), and a
        // `.frame(height:)` is precisely a container giving a height — but only
        // the width half was ever set, so a `Table` inside one hugged its rows and
        // left the rest of the frame blank.
        if minHeight != nil || idealHeight != nil || maxHeight != nil {
            contentContext.hasExplicitHeight = true
        }

        // Content drawn at its own size, larger than the frame (`.fixedSize()`,
        // an image at its natural size): offered that size, so it comes back
        // whole rather than cut to the frame, and placed past the frame's edge
        // by its alignment (`alignBuffer`; decisions B-GUIDE3-1).
        let drawsPast = ownSizePastOffer(
            of: content, width: contentContext.availableWidth, height: contentContext.availableHeight,
            context: contentContext)
        if let drawsPast {
            contentContext.availableWidth = drawsPast.width
            contentContext.availableHeight = drawsPast.height
        }

        // Where the frame will align the content, for a ramp spanning the frame
        // and the carried geometry origin — worked out only when one of them
        // will be read.
        if contentContext.placesChildren, !context.isMeasuring {
            contentContext = placingContent(in: contentContext, frame: context)
        }

        // Render content
        let buffer = TUIView.renderToBuffer(content, context: contentContext)

        // The frame around the content: raised to a minimum, and grown to
        // what it was offered up to a maximum (``FlexibleFrameAxis``).
        let finalWidth = finalWidth(content: buffer.width, offer: context.availableWidth, offeredNothing: offeredNoWidth)
        let finalHeight = heightAxis.extent(content: buffer.height, offer: context.availableHeight)

        // If size matches buffer, return as-is — unless the content's own
        // guide places it, which it does even in a frame its own size:
        // SwiftUI's 4-wide view whose leading guide is 3 sits 3 cells left of
        // a 4-wide frame (decisions B-GUIDE-3). A static question first, so
        // content whose type carries no guide pays nothing; content that may
        // (a `Subview`, a guide wrapper) is asked for the guide, and comes
        // back as it is unless one applies (``alignBuffer``).
        let fitsAsIs = finalWidth == buffer.width && finalHeight == buffer.height
        if fitsAsIs && !Content._providesAlignmentGuide {
            return buffer
        }

        // Otherwise, align content within the frame
        return alignBuffer(
            buffer, toWidth: finalWidth, height: finalHeight, fitsAsIs: fitsAsIs, drawsPast: drawsPast != nil,
            contentContext: contentContext)
    }

    /// `contentContext` with the content placed where ``alignBuffer`` will put
    /// it: from the content's MEASURED size, which is the rendered one wherever
    /// measure and render agree (a disagreement moves a colour, or costs a
    /// reader's owner one correction — never a wrong drawing). The sizes are
    /// worked out as `renderToBuffer` works them out from the buffer.
    private func placingContent(in contentContext: RenderContext, frame context: RenderContext) -> RenderContext {
        let size = measureChild(
            content,
            proposal: ProposedSize(width: contentContext.availableWidth, height: contentContext.availableHeight),
            context: contentContext)
        let finalWidth = finalWidth(
            content: size.width, offer: context.availableWidth, offeredNothing: isOfferedNoWidth(in: context))
        let finalHeight = heightAxis.extent(content: size.height, offer: context.availableHeight)
        return contentContext.placingChild(
            gradient: contentContext.gradientFrame,
            x: alignment.horizontal.childOffset(childWidth: size.width, in: finalWidth),
            y: alignment.vertical.childOffset(childHeight: size.height, in: finalHeight))
    }

    /// Aligns buffer content within the target frame size.
    ///
    /// - Parameters:
    ///   - fitsAsIs: Whether the content is the frame's size already, so that
    ///     it comes back untouched when its own guide places it on neither
    ///     axis.
    ///   - drawsPast: Whether the content is drawn at its own size
    ///     (``DrawsAtItsOwnSize``) and larger than the frame: on an axis it is
    ///     larger along, it is placed by the alignment past the frame's edge,
    ///     as a guide places it, and drawn there.
    private func alignBuffer(
        _ buffer: FrameBuffer, toWidth targetWidth: Int, height targetHeight: Int, fitsAsIs: Bool,
        drawsPast: Bool = false, contentContext: RenderContext
    ) -> FrameBuffer {
        // The content's own explicit `.alignmentGuide`, when it set one. The
        // frame is a fixed region holding one child, so there is no run to
        // merge — the child's guide meets the frame's. The content is placed
        // as a BLOCK (one offset for every line) whatever places it
        // (`placeBuffer`). Content drawn at its own size and larger than the
        // frame is placed by the alignment past the frame's edge, as a guide
        // would place it.
        let contentSize = (width: buffer.width, height: buffer.height)
        let horizontalGuide =
            horizontalGuidePlacement(
                of: content, size: contentSize, alignment: alignment.horizontal, in: targetWidth,
                context: contentContext)
            ?? (drawsPast && buffer.width > targetWidth
                ? alignment.horizontal.offsetDrawingPast(childWidth: buffer.width, in: targetWidth) : nil)
        let verticalGuide =
            verticalGuidePlacement(
                of: content, size: contentSize, alignment: alignment.vertical, in: targetHeight,
                context: contentContext)
            ?? (drawsPast && buffer.height > targetHeight
                ? alignment.vertical.offsetDrawingPast(childHeight: buffer.height, in: targetHeight) : nil)
        let verticalOffset =
            verticalGuide ?? alignment.vertical.childOffset(childHeight: buffer.height, in: targetHeight)
        guard horizontalGuide != nil || verticalGuide != nil else {
            if fitsAsIs { return buffer }
            return placeBuffer(
                buffer, toWidth: targetWidth, height: targetHeight, guideOffset: nil,
                verticalOffset: verticalOffset)
        }

        // A guide can put the content partly or wholly outside the frame,
        // where SwiftUI draws it (measured, `Tools/SwiftUIProbes/Alignment
        // guides/guide2.out`): the part the frame holds is drawn in it, the
        // rest past it, at this view's place in the stacking order. A measure
        // pass draws nothing, so it keeps the content inside, at the nearest
        // place, which sizes the same.
        //
        // Only along a placed axis — a guided one, or one content drawn at
        // its own size overhangs (``DrawsAtItsOwnSize``). Other content larger
        // than the frame on an axis its alignment places is handled as it
        // always was — its rows past the frame dropped here, its columns left
        // for a clamp to cut, as a `Text` taller than its frame is cut where
        // SwiftUI's truncates — so the region on that axis is taken to hold
        // all of it (decisions-GUIDE3 B-GUIDE3-1).
        var position = (
            x: horizontalGuide ?? alignment.horizontal.childOffset(childWidth: buffer.width, in: targetWidth),
            y: verticalOffset)
        let region = (
            width: horizontalGuide == nil ? max(targetWidth, position.x + buffer.width) : targetWidth,
            height: verticalGuide == nil ? max(targetHeight, position.y + buffer.height) : targetHeight)
        if buffer.fits(at: position, inWidth: region.width, height: region.height) {
            return placeBuffer(
                buffer, toWidth: targetWidth, height: targetHeight, guideOffset: horizontalGuide,
                verticalOffset: verticalOffset)
        }
        guard !contentContext.isMeasuring else {
            position.x = min(max(0, position.x), max(0, targetWidth - buffer.width))
            position.y = min(max(0, position.y), max(0, targetHeight - buffer.height))
            return placeBuffer(
                buffer, toWidth: targetWidth, height: targetHeight,
                guideOffset: position.x, verticalOffset: position.y)
        }
        // Past the top or bottom edge only: across, the content is placed as
        // it is inside the frame before the rows are split, so the rows drawn
        // past the frame line up with those in it.
        var source = buffer
        if horizontalGuide == nil {
            source = placeBuffer(
                buffer, toWidth: targetWidth, height: buffer.height, guideOffset: nil, verticalOffset: 0)
            position.x = 0
        }
        let placement = source.splitPlacing(
            at: position, inWidth: horizontalGuide == nil ? max(targetWidth, source.width) : targetWidth,
            height: region.height)
        return placeBuffer(
            placement.insideCarryingOverflow, toWidth: targetWidth, height: targetHeight,
            guideOffset: placement.insideOrigin.x, verticalOffset: placement.insideOrigin.y)
    }

    /// `buffer` placed in a `targetWidth` × `targetHeight` frame `verticalOffset`
    /// rows down, and across as a block: `guideOffset` columns in when that is
    /// given, and otherwise where the frame's alignment puts a child of the
    /// buffer's width.
    ///
    /// A block, not each line by the alignment on its own width: SwiftUI
    /// places the content of a frame larger than it as one view, and a
    /// multi-line `Text` aligns its lines inside its own width by its
    /// `multilineTextAlignment` (measured, `Tools/SwiftUIProbes/Ragged text in
    /// a larger frame/ragged.out`: "aaaa" over "bb" in a 10-wide centred frame
    /// starts both lines 3 cells in). Placed line by line, every short line of
    /// a ragged buffer was centred on its own (" bb " under "aaaa"), and the
    /// buffer's layers, which move with the block, no longer lined up with it.
    private func placeBuffer(
        _ buffer: FrameBuffer, toWidth targetWidth: Int, height targetHeight: Int, guideOffset horizontalGuide: Int?,
        verticalOffset: Int
    ) -> FrameBuffer {
        let horizontalOffset =
            horizontalGuide
            ?? alignment.horizontal.childOffset(childWidth: buffer.width, in: targetWidth)
        var result: [String] = []

        // Track the aligned result's width as we build it — `alignHorizontally`
        // measures each line for its padding decision anyway, so threading that
        // width out lets the final `replacingLines` skip re-measuring every line.
        var resultWidth = 0
        for row in 0..<targetHeight {
            let contentRow = row - verticalOffset
            let line: String
            if contentRow >= 0 && contentRow < buffer.height {
                line = buffer.lines[contentRow]
            } else {
                line = ""
            }

            // Align horizontally within the frame
            let (aligned, alignedWidth) = alignHorizontally(
                line, toWidth: targetWidth, offset: horizontalOffset)
            result.append(aligned)
            resultWidth = max(resultWidth, alignedWidth)
        }

        // The content shifted within the frame; carry overlay layers by the
        // same amount, the block's offset. Pass the now-known width so
        // `replacingLines` doesn't re-measure every padded line. When nothing
        // overflowed the frame, every line is exactly `targetWidth` — flag
        // that so the buffer can skip per-line work too.
        return buffer.replacingLines(
            result, width: resultWidth, uniformWidth: resultWidth == targetWidth,
            overlayShiftX: horizontalOffset, overlayShiftY: verticalOffset)
    }

    /// Places a single line of the block `offset` columns into the given
    /// width, returning the aligned line and its visible width —
    /// `max(targetWidth, the line's own width)` — so the caller can total the
    /// result width without a second `strippedLength` pass.
    private func alignHorizontally(
        _ line: String, toWidth targetWidth: Int, offset: Int
    ) -> (line: String, width: Int) {
        let visibleWidth = line.strippedLength

        if visibleWidth >= targetWidth {
            return (line, visibleWidth)
        }

        let padding = targetWidth - visibleWidth

        // Build the aligned line in place: reserve `line` plus its padding, then
        // append the leading spaces (if any), the line, and the trailing spaces
        // (if any) as borrowed runs from the shared spaces buffer. Byte-identical
        // to the former `String(repeating:) + line + String(repeating:)` forms,
        // without the per-line spaces temporaries or `+`-chain intermediates. This
        // runs once per line of every `.frame(...)` (e.g. the `modifiers`
        // scenario, two framed-and-padded chains per row).
        // Every line at the block's one offset (`placeBuffer`), a short line's
        // shortfall trailing it.
        let leftPad = min(offset, padding)
        let rightPad = padding - leftPad
        var aligned = ""
        aligned.reserveCapacity(line.utf8.count + padding)
        if leftPad > 0 { aligned += asciiSpaces(leftPad) }
        aligned += line
        if rightPad > 0 { aligned += asciiSpaces(rightPad) }
        return (aligned, targetWidth)
    }
}

// MARK: - Layoutable

extension FlexibleFrameView: Layoutable {
    /// Measures the frame, skipping the render-to-measure fallback's double
    /// render for the common fill case.
    ///
    /// `FlexibleFrameView` is `Renderable`, so `measureChild` measured it
    /// through the render-to-measure fallback: render the whole subtree once for
    /// its natural size, then again 8 cells wider to probe width-flexibility
    /// (and the real render then made three passes in total).
    ///
    /// A `maxWidth: .infinity` frame always fills the width it is offered and is
    /// always width-flexible, so its size needs no flexibility probe — a single
    /// content measure (structural when the content is itself `Layoutable`, the
    /// common `VStack`/`HStack`/`Text` case) gives the height, and the width is
    /// the available width — or, asked for its ideal width, its content's. Every
    /// other constraint shape measures analytically
    /// too, by mirroring `renderToBuffer`'s sizing math around one content
    /// measure — see `measureAnalytically(proposal:context:)`.
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard hasInfiniteMaxWidth else {
            return measureAnalytically(proposal: proposal, context: context)
        }

        let availableWidth = proposal.width ?? context.availableWidth
        let availableHeight = proposal.height ?? context.availableHeight
        // The ideal-width ask — a nil width under the horizontal probe's mark,
        // ``RenderContext/asksIdealWidth`` — is the width half of what
        // `contentTargetHeight(availableHeight:fills:)` says of heights: "as
        // wide as I'm given" has no answer when nothing was given, so the frame
        // answers with its content, as SwiftUI's does under an unspecified
        // proposal. Anywhere else a nil width means the available width, as it
        // always has in TUI, and the frame fills it.
        let asksIdealWidth = (proposal.width == nil && context.asksIdealWidth) || isOfferedNoWidth(in: context)

        // Measure the content once, in the same context renderToBuffer renders
        // it in (full width, optional fixed height, explicit-width flag), to get
        // the height the frame reports. The width is the available width: the
        // content's `max(_, availableWidth)` bump fills it and the outer clamp
        // caps it there.
        // An `.infinity` maximum only fills a height that was actually proposed
        // (see `contentTargetHeight(availableHeight:fills:)`).
        let fillsHeight = proposal.height != nil
        let targetHeight = contentTargetHeight(availableHeight: availableHeight, fills: fillsHeight)
        // Under the ideal-width ask the content is asked ITS ideal width, or
        // offered the frame's own ideal when it has one.
        let contentProposalWidth = widthAxis.contentProposal(availableWidth, unspecified: asksIdealWidth)
        var contentContext = context
        contentContext.availableWidth = contentProposalWidth ?? availableWidth
        if let targetHeight {
            contentContext.availableHeight = targetHeight
        }
        contentContext.hasExplicitWidth = true
        // As the render path: offered no width, the content is offered the ideal.
        if isOfferedNoWidth(in: context) { contentContext = offeringItsIdeal(contentContext) }
        // As the render path: a height constraint is an explicit height.
        if minHeight != nil || idealHeight != nil || maxHeight != nil {
            contentContext.hasExplicitHeight = true
        }
        let contentSize = measureChild(
            content,
            proposal: ProposedSize(width: contentProposalWidth, height: targetHeight),
            context: contentContext)

        // Flexible under the ideal-width ask too — it still fills whatever it
        // is later given — except where the answer is CAPPED: the ladder stops
        // climbing at a flexible answer that reached its budget, and a frame
        // whose content, minimum or ideal is wider than the budget has a real
        // width past it. Content that itself fills whatever it is given has
        // none, and says so.
        var width = availableWidth
        var isWidthFlexible = true
        if asksIdealWidth {
            let wanted = widthAxis.extentOfferedNothing(content: contentSize.width)
            width = max(0, min(wanted, availableWidth))
            isWidthFlexible =
                wanted < availableWidth
                || (idealWidth == nil && (minWidth ?? 0) < availableWidth
                    && contentSize.isWidthFlexible)
        }

        let wantedHeight = heightAxis.extent(
            content: contentSize.height, offer: fillsHeight ? availableHeight : nil)
        let height = min(wantedHeight, availableHeight)

        // The height half of the flexibility report. It used to be
        // unobservable — an `.infinity` maxHeight reported `availableHeight`,
        // so a parent offering more got the same answer whether or not it knew
        // the frame could grow. Now that the report is the content's own
        // height, "can grow" is the only thing distinguishing this from a
        // rigid frame, and the measure/render parity harness reads it.
        return ViewSize(
            width: width, height: height,
            isWidthFlexible: isWidthFlexible,
            isHeightFlexible: heightAxis.isFlexible(
                reported: height, wanted: wantedHeight, contentFlexible: contentSize.isHeightFlexible))
    }

    /// Whether the frame fills its available width (`maxWidth: .infinity`).
    private var hasInfiniteMaxWidth: Bool {
        if case .infinity? = maxWidth { return true }
        return false
    }

    /// An analytic measure for the general constraint shapes (fixed, ideal and
    /// min-only frames): one content *measure* through `measureChild`, with the
    /// frame's own sizing math mirrored from ``renderToBuffer(context:)`` so
    /// the two can never disagree.
    ///
    /// This replaces a render-and-probe measure (render the whole subtree for
    /// its natural size, then again 8 cells wider to detect width growth) that
    /// predated Layoutable-everywhere. Now that every view reports an honest
    /// size *and flexibility* structurally, rendering to measure was only cost:
    /// each `.frame(width:)`/`.frame(height:)` measure was two full subtree
    /// renders, and because ancestors measure a child both in their own
    /// `sizeThatFits` and again in their render pass, nested frames compounded
    /// those renders multiplicatively — the issue #7 layout (two nested framed
    /// columns of interactive rows) fully rendered its Card subtree 15 times
    /// per idle pulse frame.
    ///
    /// Two clamps mirror the render path exactly:
    /// - the *content's* report is capped at the width/height the frame offers
    ///   it, because the universal `renderToBuffer` clamps the content's buffer
    ///   to its available space (a Slider whose track floor exceeds a narrow
    ///   `.frame(width:)` still renders inside it);
    /// - the *frame's* report is capped at its own availability, because the
    ///   same clamp applies to the frame's buffer in its parent (a
    ///   `.frame(width: 20)` squeezed into 12 cells renders 12 wide).
    private func measureAnalytically(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let availableWidth = proposal.width ?? context.availableWidth
        let availableHeight = proposal.height ?? context.availableHeight
        let (widthAxis, heightAxis) = (self.widthAxis, self.heightAxis)

        // Offered no width — the ideal-width ask, ``RenderContext/asksIdealWidth``
        // — the frame offers its content its ideal width, or nothing; and
        // offered no height, its ideal height (see
        // `contentTargetHeight(availableHeight:fills:)`). The same shared
        // helpers renderToBuffer uses.
        let asksIdealWidth = (proposal.width == nil && context.asksIdealWidth) || isOfferedNoWidth(in: context)
        let fillsHeight = proposal.height != nil
        let targetWidth = widthAxis.contentBudget(availableWidth, unspecified: asksIdealWidth)
        let targetHeight = contentTargetHeight(availableHeight: availableHeight, fills: fillsHeight)

        var contentContext = context
        contentContext.availableWidth = targetWidth
        contentContext.availableHeight = targetHeight ?? availableHeight
        if minWidth != nil || idealWidth != nil || maxWidth != nil {
            contentContext.hasExplicitWidth = true
        }
        // As the render path: offered no width, the content is offered the ideal.
        if isOfferedNoWidth(in: context) { contentContext = offeringItsIdeal(contentContext) }
        // As the render path: a height constraint is an explicit height.
        if minHeight != nil || idealHeight != nil || maxHeight != nil {
            contentContext.hasExplicitHeight = true
        }
        let contentSize = measureChild(
            content,
            proposal: ProposedSize(
                width: widthAxis.contentProposal(availableWidth, unspecified: asksIdealWidth),
                height: targetHeight),
            context: contentContext)

        // Mirror renderToBuffer's final-size math: the content is capped at
        // what the frame offers it — the universal `renderToBuffer` clamps the
        // content's buffer there — and the frame is sized around it
        // (``FlexibleFrameAxis/extent(content:offer:)``).
        let wantedWidth = finalWidth(
            content: min(contentSize.width, targetWidth), offer: availableWidth, offeredNothing: asksIdealWidth)
        let wantedHeight = heightAxis.extent(
            content: targetHeight.map { min(contentSize.height, $0) } ?? contentSize.height,
            offer: fillsHeight ? availableHeight : nil)

        // The universal render clamp caps the frame's own buffer at its
        // availability, so the report must not exceed it either.
        let width = min(wantedWidth, availableWidth)
        let height = min(wantedHeight, availableHeight)

        // An axis is flexible iff offering more space would grow the rendered
        // frame (``FlexibleFrameAxis/isFlexible(reported:wanted:contentFlexible:)``):
        // a `.frame(width: 20)` in 12 cells reports (12, flexible), one at 20 is
        // rigid, and a `maxWidth: 60` frame in 40 cells still grows.
        return ViewSize(
            width: width,
            height: height,
            isWidthFlexible: widthAxis.isFlexible(
                reported: width, wanted: wantedWidth, contentFlexible: contentSize.isWidthFlexible),
            isHeightFlexible: heightAxis.isFlexible(
                reported: height, wanted: wantedHeight, contentFlexible: contentSize.isHeightFlexible))
    }
}

// MARK: - Animating a fixed frame

extension FlexibleFrameView: Animatable {
    /// A **fixed** frame's width and height — what `.frame(width:height:)`
    /// pins — so growing or shrinking a box inside ``withAnimation(_:_:)``
    /// is a resize rather than a jump — except where
    /// ``EnvironmentValues/accessibilityReduceMotion`` is on, where it jumps:
    /// a resize moves what is in it and beside it.
    ///
    /// Only the fixed case. SwiftUI draws the same line by having two types
    /// (`_FrameLayout` is `Animatable`, `_FlexFrameLayout` is not); TUI has
    /// one, so the distinction is made here instead: a dimension is animated
    /// only where the view was built by pinning min, ideal and max to the same
    /// number. A genuinely flexible frame — `maxWidth: .infinity` — has no
    /// number to move between, and `-1` is the sentinel that says so. A
    /// dimension going from unconstrained to fixed therefore snaps, which is
    /// the honest answer: there is no width it was previously at.
    public var animatableData: AnimatablePair<Double, Double> {
        get {
            AnimatablePair(
                Self.pinned(minWidth, idealWidth, maxWidth),
                Self.pinned(minHeight, idealHeight, maxHeight))
        }
        set {
            // Through locals: the six are computed over one-word storage, and
            // three `inout` accesses to `self` at once overlap.
            var (minW, idealW, maxW) = (minWidth, idealWidth, maxWidth)
            var (minH, idealH, maxH) = (minHeight, idealHeight, maxHeight)
            Self.repin(&minW, &idealW, &maxW, to: newValue.first)
            Self.repin(&minH, &idealH, &maxH, to: newValue.second)
            (minWidth, idealWidth, maxWidth) = (minW, idealW, maxW)
            (minHeight, idealHeight, maxHeight) = (minH, idealH, maxH)
        }
    }

    /// The number a dimension is pinned to, or `-1` when it is not pinned.
    private static func pinned(_ min: Int?, _ ideal: Int?, _ max: FrameDimension?) -> Double {
        guard let ideal, min == ideal, max == .fixed(ideal) else { return -1 }
        return Double(ideal)
    }

    /// Moves a pinned dimension, leaving an unpinned one alone.
    private static func repin(
        _ min: inout Int?, _ ideal: inout Int?, _ max: inout FrameDimension?, to value: Double
    ) {
        guard value >= 0, pinned(min, ideal, max) >= 0 else { return }
        let cells = Int(clamping: value.rounded())
        min = cells
        ideal = cells
        max = .fixed(cells)
    }
}

/// Motion: a frame that grows or shrinks moves its content and what is beside
/// it, so under reduce motion it jumps to its end (owner decision A-D3M-1).
extension FlexibleFrameView: SpatialAnimatable {}

// MARK: - Seeing Through the Wrapper

/// - Note: Each member gets its OWN frame, which is the measured SwiftUI
///   result rather than the convenient reading:
///   `HStack { Group { Text("AA"); Text("BB") }.frame(width: 80) }` lays the
///   two texts out at exactly the frames writing `.frame(width: 80)` on each
///   member separately produces. A `.frame(maxWidth: .infinity)` on a `Group`
///   therefore gives every member the greed, and they share the slack.
extension FlexibleFrameView: ContentRewrapping {
    public var wrappedContent: Content { content }

    public func rewrapping<V: View>(_ view: V) -> any View {
        FlexibleFrameView<V>(
            content: view,
            minWidth: minWidth, idealWidth: idealWidth, maxWidth: maxWidth,
            minHeight: minHeight, idealHeight: idealHeight, maxHeight: maxHeight,
            alignment: alignment)
    }

    /// A frame lays its content out anew, at the size it chooses, so a
    /// priority written inside it is not the frame's, as SwiftUI loses one
    /// under `.frame(minWidth: 0)` (`Tools/SwiftUIProbes/Layout priority/priority.out`,
    /// after-frame): a layout modifier, as padding and a position are.
    public static var _providesLayoutValues: Bool { false }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension FlexibleFrameView: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension FlexibleFrameView: GridRowProviding where Content: GridRowProviding {}
