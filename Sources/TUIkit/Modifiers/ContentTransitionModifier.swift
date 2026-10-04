//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentTransitionModifier.swift
//
//  `contentTransition(_:)`: a change WITHIN a view, animated — the old drawing
//  dissolving into the new one.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// A kind of transition that applies to the content within a single view,
/// rather than to the insertion or removal of a view.
///
/// Set the behavior of content transitions within a view with the
/// `contentTransition(_:)` modifier, passing in one of the defined transitions,
/// such as ``opacity`` or ``interpolate`` as the parameter.
///
/// > Tip: Content transitions only take effect within transactions that apply
/// an ``Animation`` to the views inside the `contentTransition(_:)` modifier.
///
/// ## In cells
///
/// Every transition but ``identity`` dissolves the old drawing into the new
/// one, cell by cell, through the opacity compositor: a cell's colours blend,
/// and its glyph changes half way. That IS `interpolate` here — a cell whose
/// character is the same in both keeps it and moves only its colours, which is
/// what SwiftUI's interpolation does for "matching glyph pairs", and anything
/// else uses an opacity animation, which is SwiftUI's own fallback.
/// `numericText` dissolves the changed digits too: SwiftUI promises its
/// rolling digits only "in certain environments". The symbol-effect content
/// transitions are not offered (they need the Symbols framework's types).
public struct ContentTransition: Equatable, Sendable {
    enum Storage: Equatable, Sendable {
        /// What an environment holds when nothing has said otherwise: a
        /// change is drawn at once.
        case unspecified
        case identity
        case opacity
        case interpolate
        case numericText(countsDown: Bool)
        case numericValue(Double)
    }

    let storage: Storage

    /// The identity content transition, which indicates that content changes
    /// shouldn't animate.
    ///
    /// You can pass this value to a `contentTransition(_:)` modifier to
    /// selectively disable animations that would otherwise be applied by a
    /// ``withAnimation(_:_:)`` block.
    public static let identity = Self(storage: .identity)

    /// A content transition that indicates content fades from transparent to
    /// opaque on insertion, and from opaque to transparent on removal.
    public static let opacity = Self(storage: .opacity)

    /// A content transition that indicates the views attempt to interpolate
    /// their contents during transitions, where appropriate.
    ///
    /// A cell whose character is the same before and after keeps it and moves
    /// its colours; any other cell dissolves, as an opacity transition does.
    public static let interpolate = Self(storage: .interpolate)

    /// Creates a content transition intended to be used with `Text` views
    /// displaying numeric text. In certain environments changes to the text
    /// will enable a nonstandard transition tailored to numeric characters
    /// that count up or down; here the changed digits dissolve.
    ///
    /// - Parameter countsDown: true if the numbers represented by the text are
    ///   counting downwards.
    /// - Returns: a new content transition.
    public static func numericText(countsDown: Bool = false) -> Self {
        Self(storage: .numericText(countsDown: countsDown))
    }

    /// Creates a content transition intended to be used with `Text` views
    /// displaying numbers.
    ///
    /// ```swift
    /// Text("\(value)")
    ///     .contentTransition(.numericText(value: value))
    /// ```
    ///
    /// - Parameter value: the value represented by the `Text` view being
    ///   animated. The difference between the old and new values when the
    ///   text changes will be used to determine the animation direction.
    /// - Returns: a new content transition.
    public static func numericText(value: Double) -> Self {
        Self(storage: .numericValue(value))
    }

    /// Whether a change under this transition is drawn as a dissolve.
    var dissolves: Bool {
        switch storage {
        case .unspecified, .identity: false
        case .opacity, .interpolate, .numericText, .numericValue: true
        }
    }
}

private struct ContentTransitionKey: EnvironmentKey {
    static let defaultValue = ContentTransition(storage: .unspecified)
}

private struct ContentTransitionAddsDrawingGroupKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The current method of animating the contents of views.
    ///
    /// Unset, it is a value equal to none of the named transitions — as in
    /// SwiftUI, measured — and a change is drawn at once, as TUIkit has always
    /// drawn one.
    public var contentTransition: ContentTransition {
        get { self[ContentTransitionKey.self] }
        set { self[ContentTransitionKey.self] = newValue }
    }

    /// A Boolean value that controls whether views that render content
    /// transitions use GPU-accelerated rendering.
    ///
    /// A rendering strategy with no visible contract: SwiftUI wraps the
    /// transition in a drawing group, which changes how it is composited and
    /// not what it shows. A terminal composites cells either way, so the value
    /// is kept for whoever reads it and draws the same thing.
    public var contentTransitionAddsDrawingGroup: Bool {
        get { self[ContentTransitionAddsDrawingGroupKey.self] }
        set { self[ContentTransitionAddsDrawingGroupKey.self] = newValue }
    }
}

extension View {
    /// Modifies the view to use a given transition as its method of animating
    /// changes to the contents of its views.
    ///
    /// This modifier allows you to perform a transition that animates a change
    /// within a single view. A change made under an animation — inside
    /// ``withAnimation(_:_:)``, say — dissolves from the old drawing to the new
    /// one over the animation, rather than replacing it at once:
    ///
    /// ```swift
    /// Text("\(count)")
    ///     .contentTransition(.numericText(value: Double(count)))
    /// ```
    ///
    /// > Tip: The `contentTransition(_:)` modifier only has an effect within
    /// the context of an ``Animation``.
    ///
    /// The dissolve is drawn over everything the modifier wraps: an inner
    /// `contentTransition(.identity)` does not exempt part of it. The view keeps
    /// the size of its new content, so a drawing that shrinks loses its edges
    /// at once.
    ///
    /// - Parameter transition: The transition to apply when animating the
    ///   content change.
    public func contentTransition(_ transition: ContentTransition) -> some View {
        _ContentTransitionView(content: self, transition: transition)
    }
}

/// Dissolves its content's old drawing into its new one when the content
/// changes under an animation. See ``View/contentTransition(_:)``.
struct _ContentTransitionView<Content: View>: View {
    let content: Content
    let transition: ContentTransition

    var body: Never {
        fatalError("_ContentTransitionView renders via Renderable")
    }

    /// What the view drew, and the dissolve under way.
    struct Fade {
        /// The content's drawing on the last frame.
        var shown: FrameBuffer?
        /// The drawing being dissolved away, and how.
        var outgoing: FrameBuffer?
        var animation: Animation?
        var startNanos: Int64 = 0
    }

    /// Where the fades of every content transition at one identity are kept,
    /// by type — two nested at one place are different generic types. In the
    /// reserved range of `StateStorage.StateKey`, as the content renders at
    /// this view's own identity.
    private static var stateIndex: Int { -110 }

    private func withTransition(_ context: RenderContext) -> RenderContext {
        var inner = context
        inner.environment.contentTransition = transition
        return inner
    }
}

extension _ContentTransitionView: Renderable, Layoutable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let buffer = TUIkit.renderToBuffer(content, context: withTransition(context))
        guard transition.dissolves, !context.isMeasuring, let storage = context.stateStorage else {
            return buffer
        }
        storage.markActive(context.identity)
        let key = StateStorage.StateKey(identity: context.identity, propertyIndex: Self.stateIndex)
        var fades: [ObjectIdentifier: Any] = storage.trackedValue(for: key) ?? [:]
        var fade = fades[ObjectIdentifier(Self.self)] as? Fade ?? Fade()
        let frame = context.environment.animationFrame
        let now = frame.nowNanos
        defer {
            fade.shown = buffer
            // A finished dissolve lets its picture go.
            if let animation = fade.animation,
                animation.isFinished(at: Double(now - fade.startNanos) / 1_000_000_000)
            {
                (fade.outgoing, fade.animation) = (nil, nil)
            }
            fades[ObjectIdentifier(Self.self)] = fade
            storage.setTrackedValue(fades, for: key)
        }

        // The picture on screen right now, before this frame's change: a
        // dissolve still under way, or the last drawing.
        let onScreen = fade.shown.map { drawn(fade, over: $0, at: now, context: context) }
        if let onScreen, let shown = fade.shown, shown.lines != buffer.lines || shown.width != buffer.width,
            frame.canAnimate, let animation = context.environment.transaction.effectiveAnimation
        {
            fade.outgoing = onScreen
            fade.animation = animation
            fade.startNanos = now
            storage.animationCompletions.noteStarted(animation, at: now, key: nil)
        }
        return drawn(fade, over: buffer, at: now, context: context)
    }

    /// `buffer` with `fade`'s outgoing drawing dissolving away beneath it, or
    /// `buffer` alone when nothing is dissolving.
    private func drawn(_ fade: Fade, over buffer: FrameBuffer, at now: Int64, context: RenderContext) -> FrameBuffer {
        guard let outgoing = fade.outgoing, let animation = fade.animation else { return buffer }
        let elapsed = Double(now - fade.startNanos) / 1_000_000_000
        guard !animation.isFinished(at: elapsed) else { return buffer }
        // Frames until it is done, on the lattice every view animation shares.
        context.requestAnimation(
            token: "content-transition-\(context.identity.path)",
            frameTicks: AnimationRequest.viewAnimations.frameTicks)
        let presence = min(1, max(0, animation.fraction(at: elapsed)))
        // The new drawing over the old at `presence`: the compositor blends
        // each cell's colours and hands over its glyph half way, so the old
        // shows through at 1 − presence.
        var quiet = context.withChildIdentity(erasedType: Self.self, index: 0)
        quiet.environment.transaction.disablesAnimations = true
        let dissolved = TUIkit.renderToBuffer(
            ZStack(alignment: .topLeading) {
                BufferView(buffer: outgoing)
                BufferView(buffer: buffer).opacity(presence)
            },
            context: quiet)
        return dissolved.clamped(toWidth: buffer.width, height: buffer.height)
    }

    /// Measures as its content: a dissolve changes no layout.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: withTransition(context))
    }
}
