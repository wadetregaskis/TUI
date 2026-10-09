//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CustomTransition.swift
//
//  How a `Transition` with a body of the app's own is drawn: erased into an
//  `AnyTransition`, and scrubbed between its phases.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - The erased body

/// A ``Transition``'s body, erased so ``AnyTransition`` can hold it.
///
/// Two closures over the concrete transition, so the body is still built and
/// drawn as its own type — no `AnyView` between the body and the modifiers in
/// it — and a class, so two transitions compare by whether they are the same
/// one (``AnyTransition`` is `Equatable`; a transition of the app's own need
/// not be).
///
/// Not main-actor isolated itself: ``AnyTransition`` is a value made anywhere
/// (its built-ins are `static let`s), and combining one with a body of the
/// app's own must not need the main actor. Drawing does, and the closures are
/// isolated to it.
final class _AnyTransitionBox: Equatable, @unchecked Sendable {
    private let draw: @MainActor (TransitionPhase, PlaceholderSource, RenderContext) -> FrameBuffer
    private let size:
        @MainActor (TransitionPhase, PlaceholderSource, ProposedSize, RenderContext) -> ViewSize

    /// Whether the transition has motion — its ``TransitionProperties``, or
    /// for a composed pair either half's — which decides whether it is
    /// replaced by a fade where motion is reduced.
    let hasMotion: Bool

    /// `transition`'s body.
    @MainActor
    init<T: Transition>(_ transition: T) {
        draw = { renderTransitionBody(transition, phase: $0, content: $1, context: $2) }
        size = { measureTransitionBody(transition, phase: $0, content: $1, proposal: $2, context: $3) }
        hasMotion = T.properties.hasMotion
    }

    /// How two erased transitions are put together, where one of them has a
    /// body of the app's own — so the pair has to be drawn as bodies too.
    enum Composition {
        /// ``Transition/combined(with:)``: the first, then the second around it.
        case combined
        /// ``AsymmetricTransition``: the first arriving, the second leaving.
        case asymmetric
    }

    /// `first` and `second`, composed. Holds the two values rather than the
    /// composed ``Transition``, which is main-actor isolated and could not be
    /// built where an `AnyTransition` is.
    init(_ composition: Composition, _ first: AnyTransition, _ second: AnyTransition) {
        // Either half, combined or asymmetric — as SwiftUI's pairs report it.
        hasMotion = first.hasMotion || second.hasMotion
        switch composition {
        case .combined:
            draw = { phase, content, context in
                renderTransitionBody(
                    _CombinedTransition(first: _ErasedTransition(first), second: _ErasedTransition(second)),
                    phase: phase, content: content, context: context)
            }
            size = { phase, content, proposal, context in
                measureTransitionBody(
                    _CombinedTransition(first: _ErasedTransition(first), second: _ErasedTransition(second)),
                    phase: phase, content: content, proposal: proposal, context: context)
            }
        case .asymmetric:
            draw = { phase, content, context in
                renderTransitionBody(
                    AsymmetricTransition(
                        insertion: _ErasedTransition(first), removal: _ErasedTransition(second)),
                    phase: phase, content: content, context: context)
            }
            size = { phase, content, proposal, context in
                measureTransitionBody(
                    AsymmetricTransition(
                        insertion: _ErasedTransition(first), removal: _ErasedTransition(second)),
                    phase: phase, content: content, proposal: proposal, context: context)
            }
        }
    }

    /// The body at `phase`, built around `content` and drawn in `context`.
    @MainActor
    func render(
        phase: TransitionPhase, content: PlaceholderSource, context: RenderContext
    ) -> FrameBuffer {
        draw(phase, content, context)
    }

    /// The body at `phase`, built around `content` and measured.
    @MainActor
    func measure(
        phase: TransitionPhase, content: PlaceholderSource, proposal: ProposedSize,
        context: RenderContext
    ) -> ViewSize {
        size(phase, content, proposal, context)
    }

    /// The same transition, by identity: a body is not a value to compare.
    static func == (lhs: _AnyTransitionBox, rhs: _AnyTransitionBox) -> Bool {
        lhs === rhs
    }
}

/// `transition`'s body at `phase` around `content`, drawn one identity step in,
/// as a view's body is — the same step on every pass, so the body's animatable
/// values are filed at the same places whichever phase it is drawn at.
@MainActor
private func renderTransitionBody<T: Transition>(
    _ transition: T, phase: TransitionPhase, content: PlaceholderSource, context: RenderContext
) -> FrameBuffer {
    let body = transition.body(content: PlaceholderContentView(source: content), phase: phase)
    return TUIkitView.renderToBuffer(body, context: context.withChildIdentity(type: T.Body.self))
}

/// The measuring twin of `renderTransitionBody(_:phase:content:context:)`.
@MainActor
private func measureTransitionBody<T: Transition>(
    _ transition: T, phase: TransitionPhase, content: PlaceholderSource, proposal: ProposedSize,
    context: RenderContext
) -> ViewSize {
    let body = transition.body(content: PlaceholderContentView(source: content), phase: phase)
    return measureChild(
        body, proposal: proposal, context: context.withChildIdentity(type: T.Body.self))
}

/// An ``AnyTransition`` as a ``Transition`` — how one made of effects is
/// combined with, or made asymmetric against, one with a body of its own.
struct _ErasedTransition: Transition {
    let base: AnyTransition

    init(_ base: AnyTransition) {
        self.base = base
    }

    func body(content: Content, phase: TransitionPhase) -> some View {
        _ErasedTransitionBody(base: base, content: content, phase: phase)
    }

    var _erased: AnyTransition { base }
}

/// What ``_ErasedTransition``'s body draws: the erased body, or the effects as
/// the one animatable modifier the built-in transitions are made of.
struct _ErasedTransitionBody<Content: View>: View {
    let base: AnyTransition
    let content: Content
    let phase: TransitionPhase

    var body: Never {
        fatalError("_ErasedTransitionBody renders via Renderable")
    }

    private var effects: ModifiedView<Content, _TransitionEffectModifier> {
        content.modifier(
            _TransitionEffectModifier(insertion: base.insertion, removal: base.removal, phase: phase))
    }
}

extension _ErasedTransitionBody: Renderable, Layoutable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let custom = base.custom else {
            return TUIkitView.renderToBuffer(effects, context: context)
        }
        return custom.render(phase: phase, content: PlaceholderSource(view: content), context: context)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let custom = base.custom else {
            return measureChild(effects, proposal: proposal, context: context)
        }
        return custom.measure(
            phase: phase, content: PlaceholderSource(view: content), proposal: proposal,
            context: context)
    }
}

// MARK: - Drawing between two phases

extension _AnyTransitionBox {
    /// The body drawn `presence` of the way from `end` to `.identity`: 0 is
    /// the body at `end`, 1 at rest, and above 1 a spring carrying it past.
    ///
    /// Recorded at `end` around an empty box, then drawn at `.identity` around
    /// `content` with every animatable value interpolated — see
    /// ``TransitionScrub``. A scrub already installed (a transition drawn
    /// inside another's departing picture) is put back afterwards.
    @MainActor
    func render(
        presence: Double, from end: TransitionPhase, content: PlaceholderSource,
        recordingAround blank: PlaceholderSource, context: RenderContext
    ) -> FrameBuffer {
        guard presence != 1, let store = context.stateStorage?.animations else {
            return render(phase: .identity, content: content, context: context)
        }
        let scrub = TransitionScrub()
        let enclosing = store.scrub
        store.scrub = scrub
        defer { store.scrub = enclosing }
        _ = render(phase: end, content: blank, context: context)
        scrub.mode = .draw(presence: presence)
        return render(phase: .identity, content: content, context: context)
    }
}

// MARK: - What the placeholder draws

/// The picture a transitioning view's content drew on its latest frame, kept
/// for the departure that may play it.
@MainActor
final class TransitionContentPicture {
    var buffer: FrameBuffer?
}

extension PlaceholderSource {
    /// A transitioning view's live content: drawn at `identity` — the
    /// transition's own, wherever in the body the placeholder stands — under
    /// the environment the body gives it, with any scrub lifted so the
    /// content's own animations run as they would without the transition.
    /// What it draws is kept in `picture`.
    static func transitionContent<Content: View>(
        _ content: Content, at identity: ViewIdentity, keepingIn picture: TransitionContentPicture
    ) -> PlaceholderSource {
        PlaceholderSource(
            render: { context in
                let buffer = withScrubLifted(context) {
                    TUIkitView.renderToBuffer(content, context: pinned(context, to: identity))
                }
                picture.buffer = buffer
                return buffer
            },
            measure: { proposal, context in
                withScrubLifted(context) {
                    measureChild(content, proposal: proposal, context: pinned(context, to: identity))
                }
            })
    }

    /// An empty box the size the content measures at — what a body is
    /// recorded around, so the content draws once a frame and its side effects
    /// (focus, hit regions, lifecycle) happen once.
    static func transitionBlank<Content: View>(
        _ content: Content, at identity: ViewIdentity
    ) -> PlaceholderSource {
        PlaceholderSource(
            render: { context in
                let size = withScrubLifted(context) {
                    measureChild(
                        content,
                        proposal: ProposedSize(
                            width: context.availableWidth, height: context.availableHeight),
                        context: pinned(context, to: identity))
                }
                return FrameBuffer(footprintWidth: size.width, height: size.height)
            },
            measure: { proposal, context in
                withScrubLifted(context) {
                    measureChild(content, proposal: proposal, context: pinned(context, to: identity))
                }
            })
    }

    /// The picture a departed view's content left: what its body is drawn
    /// around while it leaves.
    static func departedContent(_ picture: FrameBuffer) -> PlaceholderSource {
        PlaceholderSource(
            render: { _ in picture },
            measure: { _, _ in .fixed(picture.width, picture.lines.count) })
    }

    /// An empty box the size of a departed view's picture.
    static func departedBlank(_ picture: FrameBuffer) -> PlaceholderSource {
        PlaceholderSource(
            render: { _ in FrameBuffer(footprintWidth: picture.width, height: picture.lines.count) },
            measure: { _, _ in .fixed(picture.width, picture.lines.count) })
    }
}

/// `context` with its identity replaced: the content's place in the tree is
/// the transition's, not the placeholder's.
@MainActor
private func pinned(_ context: RenderContext, to identity: ViewIdentity) -> RenderContext {
    var pinned = context
    pinned.identity = identity
    return pinned
}

/// `body`, run with no scrub installed on `context`'s animation store.
@MainActor
private func withScrubLifted<R>(_ context: RenderContext, _ body: () -> R) -> R {
    guard let store = context.stateStorage?.animations, let scrub = store.scrub else {
        return body()
    }
    store.scrub = nil
    defer { store.scrub = scrub }
    return body()
}
