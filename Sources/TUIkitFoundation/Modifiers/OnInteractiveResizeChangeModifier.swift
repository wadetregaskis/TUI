//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OnInteractiveResizeChangeModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - onInteractiveResizeChange

extension View {
    /// Adds an action to perform when the enclosing window is being
    /// interactively resized. Matches SwiftUI's
    /// `onInteractiveResizeChange(_:)`.
    ///
    /// Use it to throttle expensive drawing while the terminal is being
    /// resized, which is exactly what a terminal app pays for on every resize:
    /// the whole screen is laid out again at each new size.
    ///
    /// ```swift
    /// ChartView(samples: samples)
    ///     .onInteractiveResizeChange { isResizing in
    ///         chart.detail = isResizing ? .coarse : .full
    ///     }
    /// ```
    ///
    /// ## A burst of resizes
    ///
    /// A terminal says nothing about a drag: it reports each new size, once,
    /// and dragging a window's edge sends a burst of them. So TUIkit infers the
    /// drag from the burst. The action runs with `true` at the first frame
    /// drawn at a new size after a quiet period, and with `false` once no
    /// further size has arrived for ``EnvironmentValues/interactiveResizeTimeout``
    /// (200 ms unless set). Anything that changes the terminal's grid makes a
    /// burst, so a font-size change, a tmux pane resize or a window snapped to
    /// a new size counts as one too, usually a short one; a report that leaves
    /// the grid as it was does not.
    ///
    /// The calls alternate, `true` then `false`, for as long as the view is on
    /// screen: a view that first draws during a burst hears it begin then, and
    /// nothing runs when it first appears outside one. A view that leaves
    /// during a burst hears no `false`, as its other actions stop when it
    /// goes; undo what `true` did in `.onDisappear` if it must be undone.
    ///
    /// - Parameter action: A closure to run when the state of the window's
    ///   interactive resize changes.
    public func onInteractiveResizeChange(_ action: @escaping (Bool) -> Void) -> some View {
        OnInteractiveResizeChangeModifier(content: self, action: action)
    }

    /// Sets how long the terminal's size must have stayed the same before
    /// ``View/onInteractiveResizeChange(_:)`` reports the resize over.
    ///
    /// The default is 200 ms: long enough to span the gaps between the sizes
    /// a drag sends, short enough that the drawing an action held back comes
    /// back soon after the drag stops. Set it on the scene's root view for the
    /// whole app; a view inside can set its own. A zero timeout ends every
    /// burst before a frame can see it, so the action never runs.
    ///
    /// A TUIkit addition: SwiftUI is told when a drag begins and ends, and has
    /// no timeout to set.
    public func interactiveResizeTimeout(_ timeout: Duration) -> some View {
        environment(\.interactiveResizeTimeout, timeout)
    }
}

// MARK: - Environment

private struct InteractiveResizeTimeoutKey: EnvironmentKey {
    static let defaultValue: Duration = .milliseconds(200)
}

extension EnvironmentValues {
    /// How long the terminal's size must have stayed the same before
    /// ``View/onInteractiveResizeChange(_:)`` reports the resize over: 200 ms
    /// unless set. See ``View/interactiveResizeTimeout(_:)``.
    public var interactiveResizeTimeout: Duration {
        get { self[InteractiveResizeTimeoutKey.self] }
        set { self[InteractiveResizeTimeoutKey.self] = newValue }
    }
}

// MARK: - The modifier

/// The view behind ``View/onInteractiveResizeChange(_:)``: on each render
/// pass, compares whether the terminal is in a burst of resizes with what it
/// last told the action, tells it of a change, and asks for the frame at which
/// the burst it is in will have ended.
struct OnInteractiveResizeChangeModifier<Content: View>: View {
    let content: Content
    let action: (Bool) -> Void

    var body: Never {
        fatalError("OnInteractiveResizeChangeModifier renders via Renderable")
    }
}

extension OnInteractiveResizeChangeModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A render side effect, so never on a measure.
        //
        // NOT declared to a value-memoizing ancestor, unlike `.onChange`'s
        // comparison, and safely: the answer moves only with the terminal's
        // size, and a size change clears the whole render cache (the render
        // loop's `EnvironmentSnapshot` holds the size), so no buffer stored
        // before a burst is served after one. During the burst the wake below
        // declares itself, so nothing is stored then either; the frame that
        // ends it may be, and the next resize clears it. Declaring it here
        // would turn off every memo above an app's root that listens.
        guard !context.isMeasuring, let storage = context.stateStorage else {
            return TUIkitView.renderToBuffer(content, context: context)
        }

        let timeout = Int64(clamping: context.environment.interactiveResizeTimeout.clampedNanoseconds)
        let now = context.environment.frameNowNanos
        var isResizing = false
        if let resizedAt = context.environment.renderCache?.terminalResizedAtNanos {
            let endsAt = resizedAt &+ timeout
            isResizing = now < endsAt
            if isResizing {
                context.requestWake(token: "interactive-resize-\(context.identity.path)", atNanos: endsAt)
            }
        }

        // The last answer the action was given, positionally per walk as
        // `.onChange` claims its slot. A view appearing starts from `false`,
        // so the calls alternate even when it first draws mid-burst; one
        // leaving has its slot pruned with it, and hears no `false`.
        let index = storage.nextOnChangeIndex(for: context.identity)
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: index)
        let reported: Bool = storage.trackedValue(for: key) ?? false
        if reported != isResizing {
            action(isResizing)
        }
        storage.setTrackedValue(isResizing, for: key)
        storage.markActive(context.identity)

        return TUIkitView.renderToBuffer(content, context: context)
    }
}

extension OnInteractiveResizeChangeModifier: Layoutable {
    /// Behaviour only: it measures as its content does.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it.
extension OnInteractiveResizeChangeModifier: SingleContentWrapper {
    var wrappedContent: Content { content }

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension OnInteractiveResizeChangeModifier: DrawsContentUnchanged {}
/// Measures its content in the context it is given, so an alignment guide
/// inside it is asked through it — see `HandsContentItsContext`.
extension OnInteractiveResizeChangeModifier: HandsContentItsContext {}
