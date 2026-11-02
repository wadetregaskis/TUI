//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollVisibilityModifier.swift
//
//  `onScrollVisibilityChange(threshold:_:)`: a view told when it crosses the
//  threshold of being shown by the scroll view it is in.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

extension View {
    /// Adds an action to be called when the view crosses the threshold to be
    /// considered on or off screen.
    ///
    /// ```swift
    /// struct VideoPlayer: View {
    ///     @State var playing: Bool
    ///
    ///     var body: some View {
    ///         Group {
    ///             // ...
    ///         }
    ///         .onScrollVisibilityChange(threshold: 0.2) { isVisible in
    ///             playing = isVisible
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// As in SwiftUI (measured on macOS 15): the action is called once when the
    /// view first appears — with `true` or `false` — and then each time the
    /// fraction of the view the nearest scroll view shows crosses `threshold`.
    /// A fraction exactly at the threshold counts as shown, so a threshold of
    /// `0` reports every view shown. A view in no scroll view is reported
    /// shown, wherever it is. A `List` is a scroll view here as it is there.
    ///
    /// The fraction is measured against what the scroll view draws, once the
    /// frame has settled where it scrolls to, and the action runs when the
    /// frame is done — so a frame that draws the view twice reports once.
    ///
    /// Where TUI says more than SwiftUI: a row a lazy stack has stopped
    /// drawing because it scrolled out of the stack's window is reported
    /// hidden (if it was shown). It is still in the tree — its state is kept —
    /// and it is certainly not on screen; SwiftUI's lazy stacks destroy such a
    /// row instead, and report nothing until it is made again. A view removed
    /// from the tree is not reported, in either.
    ///
    /// - Parameters:
    ///   - threshold: How much of the view, from 0 to 1, the scroll view must
    ///     show for it to count as shown.
    ///   - action: Called with `true` when the view becomes shown, and `false`
    ///     when it stops being shown.
    /// - Returns: A view that reports its scroll visibility.
    nonisolated public func onScrollVisibilityChange(
        threshold: Double = 0.5, _ action: @escaping (Bool) -> Void
    ) -> some View {
        ScrollVisibilityModifier(content: self, threshold: threshold, action: action)
    }
}

// MARK: - Modifier

/// Draws its content unchanged, stamps a geometry marker at its origin, and
/// registers what to report — see ``View/onScrollVisibilityChange(threshold:_:)``.
nonisolated struct ScrollVisibilityModifier<Content: View>: View {
    let content: Content
    let threshold: Double
    let action: (Bool) -> Void

    @MainActor var body: Never {
        fatalError("ScrollVisibilityModifier renders via Renderable")
    }
}

@MainActor extension ScrollVisibilityModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        context.watchingScrollVisibility(threshold: threshold, action: action) {
            TUIView.renderToBuffer(content, context: context)
        }
    }
}

extension RenderContext {
    /// Whether ``watchingScrollVisibility(threshold:action:draw:)`` will report
    /// anything: not in a measure, and not where there is no frame's hit testing
    /// to carry its marker, as in a one-off snapshot.
    @MainActor
    package var canWatchScrollVisibility: Bool {
        !isMeasuring && environment.mouseEventDispatcher != nil
    }

    /// What `draw` draws, watched as ``View/onScrollVisibilityChange(threshold:_:)``
    /// watches a view: for a view that stops work of its own when it is not shown,
    /// as an animated `Image` does.
    @MainActor
    package func watchingScrollVisibility(
        threshold: Double, action: @escaping (Bool) -> Void, draw: () -> FrameBuffer
    ) -> FrameBuffer {
        // A measure asks a size, and is not a frame anything is shown in.
        guard canWatchScrollVisibility, let dispatcher = environment.mouseEventDispatcher else { return draw() }
        // Claimed BEFORE the content renders, for the reason
        // `OnGeometryChangeModifier` claims its slot first: the id is the
        // ordinal of this registration at this identity, and content drawn at
        // the same identity (an `if`, an `AnyView`) would move one claimed
        // afterwards from frame to frame.
        let id = dispatcher.geometryMarkerID(in: self)
        var buffer = draw()
        buffer.hitTestRegions.append(.geometryMarker(id))
        ScrollVisibilityRegistrar.register(
            id: id, identity: identity,
            size: CellSize(width: buffer.width, height: buffer.height),
            threshold: threshold, action: action, context: self)
        return buffer
    }
}

@MainActor extension ScrollVisibilityModifier: Layoutable {
    /// Measures as its content: watching is the whole of this modifier's
    /// effect, and it contributes no geometry.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// looks through this wrapper, as it does through `onGeometryChange`'s.
@MainActor extension ScrollVisibilityModifier: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
@MainActor extension ScrollVisibilityModifier: DrawsContentUnchanged {}

// MARK: - Registration

/// The registration a scroll visibility observer makes, live and replayed.
///
/// A memo that serves the buffer this observer drew into serves its marker
/// too, but not the registration — the coordinator's walk table is emptied
/// before every walk — so the registration is a REPLAYABLE effect, recorded
/// while a memo records and made again on every hit, as a mouse handler's is
/// (`MouseHandlerRegistrar`). A served row keeps reporting; and a served scroll
/// view replays what it measured of its observers as well
/// (`RenderContext.measureScrollVisibility(in:viewport:)`).
enum ScrollVisibilityRegistrar {
    /// The journal kind of an observer's registration.
    static let kind = EffectJournal.Kind("scrollVisibility")

    /// The journal kind of a scroll view's measures of the observers it drew
    /// (`RenderContext.measureScrollVisibility(in:viewport:)`), made again
    /// with the registrations when a memo serves the scroll view.
    static let measuredKind = EffectJournal.Kind("scrollVisibilityMeasured")

    /// Registers the observer into `context`'s coordinator, declares the
    /// registration replayable, and records it while a memo records.
    @MainActor
    static func register(
        id: HitTestRegion.HandlerID, identity: ViewIdentity, size: CellSize, threshold: Double,
        action: @escaping (Bool) -> Void, context: RenderContext
    ) {
        context.geometryCoordinator?.registerVisibilityObserver(
            id: id, identity: identity, size: size, threshold: threshold, action: action)
        context.environment.volatileReadTracker?.recordReplayableEffect()
        guard let journal = context.recordingEffectJournal else { return }
        journal.append(
            EffectJournal.Entry(kind: kind, channelToken: context.environment.keyChannelToken) { replay in
                replay.geometryCoordinator?.registerVisibilityObserver(
                    id: id, identity: identity, size: size, threshold: threshold, action: action)
            })
    }
}
