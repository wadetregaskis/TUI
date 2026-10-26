//  🖥️ TUI — A Terminal UI framework for Swift
//  CoordinateSpaceModifier.swift
//
//  `coordinateSpace(_:)`: a view whose local space other views can ask about
//  by name.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension View {
    /// Assigns a name to the view's coordinate space, so other code can
    /// operate on dimensions like points and sizes relative to the named space.
    ///
    /// Use `coordinateSpace(_:)` to allow another function to find and operate
    /// on a view and operate on dimensions relative to that view:
    ///
    /// ```swift
    /// VStack {
    ///     Text("Row")
    ///     GeometryReader { proxy in
    ///         Text("I am \(proxy.frame(in: .named("stack")).minY) rows down")
    ///     }
    /// }
    /// .coordinateSpace(.named("stack"))
    /// ```
    ///
    /// The name is found from inside: a view asking about it is answered by the
    /// nearest view around it that declares it, and a view no declaration
    /// encloses is answered in the global space, as SwiftUI answers it. A
    /// presentation's content (a sheet, a popover) is drawn over the page
    /// rather than inside the view that presents it, so a name declared on the
    /// page does not reach into it — SwiftUI's names do not cross a
    /// presentation either.
    ///
    /// - Parameter name: A name used to identify this coordinate space.
    /// - Returns: A view whose coordinate space has that name.
    public func coordinateSpace(_ name: NamedCoordinateSpace) -> some View {
        CoordinateSpaceModifier(content: self, space: name.coordinateSpace)
    }
}

// MARK: - Modifier

/// Draws its content unchanged, and answers for it every view inside asking
/// about its space — see ``View/coordinateSpace(_:)``.
struct CoordinateSpaceModifier<Content: View>: View {
    let content: Content
    let space: CoordinateSpace

    var body: Never {
        fatalError("CoordinateSpaceModifier renders via Renderable")
    }
}

extension CoordinateSpaceModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring, let geometry = context.geometryCoordinator else {
            return TUIView.renderToBuffer(content, context: context)
        }
        // Noted before the content renders, so a correction can put the walk
        // back to here and draw the content again as if for the first time.
        let checkpoint = RenderWalkCheckpoint(context: context)
        defer { checkpoint.keep() }
        // A declaration exists to be read, so it carries an origin for its
        // content (starting one here when nothing above has) while there may
        // be a reader to predict for — not for a subtree whose only askers
        // are gestures and reporters, which never read a prediction — and
        // opens itself as the owner a reader's prediction is measured against.
        let contentContext =
            geometry.declarationsCarryOrigin ? context.carryingGeometryOrigin() : context
        let owner = geometry.enterOwner(
            of: [space], from: context, in: contentContext,
            size: CellSize(width: context.availableWidth, height: context.availableHeight))
        var drawn = TUIView.renderToBuffer(content, context: contentContext)
        geometry.leaveOwner(owner)
        var placed = contentPlacement(of: drawn, context: context)
        guard geometry.resolve([space], in: drawn, size: placed.size, shift: placed.shift) else { return drawn }
        // A reader inside drew from an answer that turned out wrong — its
        // first frame with nothing to predict from, or one on which something
        // the prediction does not follow moved it. Draw it again with the
        // answer just found; a reader cannot move itself, so one more drawing
        // settles it.
        geometry.noteCorrection(.named)
        checkpoint.rollBack(context: context)
        geometry.reenterOwner(owner)
        drawn = TUIView.renderToBuffer(content, context: contentContext)
        geometry.leaveOwner(owner)
        placed = contentPlacement(of: drawn, context: context)
        if geometry.resolve([space], in: drawn, size: placed.size, shift: placed.shift) { geometry.noteResidual() }
        return drawn
    }

    /// Where what the content drew sits in the space it names, and how big
    /// that space is.
    ///
    /// The content's own top-left and size — except for a lazy stack that is a
    /// scroll view's content and drew only the band around the viewport: its
    /// buffer starts where the band does, which is where the stack says
    /// (`ScrollContentReply.sliceOriginY`), and the space is as tall as the
    /// stack says the whole content is. Past the few hundred rows a lazy stack
    /// measures exactly, that height and the rows' places in it are an
    /// estimate, as the scrollbar's are (decisions A2, the owner's answer 8);
    /// `.scrollView` stays exact, being the viewport the band is drawn in.
    private func contentPlacement(of drawn: FrameBuffer, context: RenderContext) -> (
        shift: CellPoint, size: CellSize
    ) {
        guard let window = context.environment.scrollContentWindow, window.isAtOrigin(context.identity),
            let reply = window.reply, let sliceOrigin = reply.sliceOriginY
        else { return (CellPoint(x: 0, y: 0), drawn.cellSize) }
        return (
            CellPoint(x: 0, y: sliceOrigin),
            CellSize(width: drawn.width, height: reply.sliceTotalHeight ?? drawn.height)
        )
    }
}

extension CoordinateSpaceModifier: Layoutable {
    /// Measures as its content: naming a space changes no geometry.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// looks through this wrapper.
extension CoordinateSpaceModifier: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension CoordinateSpaceModifier: DrawsContentUnchanged {}

extension FrameBuffer {
    /// The buffer's size, as the cells a coordinate space spans.
    ///
    /// `@inlinable`: a scroll transition (TUIEffects) asks it of each row it
    /// draws, and the body names only public API.
    @inlinable
    package var cellSize: CellSize { CellSize(width: width, height: height) }
}
