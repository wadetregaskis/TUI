//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TransitionModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

extension View {
    /// How this view arrives when it is inserted, and how it leaves when it is
    /// removed.
    ///
    /// ```swift
    /// if showDetail {
    ///     Detail().transition(.move(edge: .top).combined(with: .opacity))
    /// }
    /// ```
    ///
    /// A transition runs only when the change that caused it was animated —
    /// inside ``withAnimation(_:_:)``, or under a ``View/animation(_:value:)``
    /// watching the condition. An unanimated appearance is still instant, which
    /// is what makes it safe to leave a transition on a view that appears for
    /// other reasons (a page being opened, a list being rebuilt).
    ///
    /// ## The views around it
    ///
    /// The transition decides only how the view itself arrives and leaves. The
    /// layout changes at once, as SwiftUI's does: inserted, the view takes its
    /// room on the frame it appears; removed, it gives the room back on the
    /// frame it goes. Under the animation, every view the change moved glides
    /// from its old place to its new one — measured in SwiftUI
    /// (`plan/fb16/samples.txt`), the row below an inserted one moved 187 →
    /// 202 → 218 → 247 over an 8 s linear animation, whatever the transition,
    /// `.identity` included. So a fading view is drawn where it lands from the
    /// first frame, and the row below slides away from over it; a view fading
    /// out is drawn where it was, and the row below slides up over it. A view
    /// leaving is drawn beneath the views around it, as SwiftUI draws it,
    /// unless a `.zIndex` lifts it.
    ///
    /// That is what an eager `VStack`, `HStack` and `ZStack` do, and a
    /// `Layout` with its subviews' places. Elsewhere a removal keeps its room
    /// while it plays and gives it back at once after — in a `Layout`, a lazy
    /// stack, a `Grid`, a `List` and a `nil` rendered on its own — and the
    /// children of a lazy stack, a `Grid` and a `List` move at once.
    ///
    /// ## How a view that no longer exists still leaves
    ///
    /// An **insertion** works wherever the view appears, because the view is
    /// there to be drawn.
    ///
    /// A **removal** has no view: the body no longer produces one, and a
    /// terminal rebuilds its whole frame from the tree. What plays it is
    /// whatever still stands where it stood — the `nil` the optional became —
    /// drawing the picture the view left behind on its last frame, where the
    /// view last was.
    ///
    /// This holds both where the optional is itself the thing being rendered (a
    /// page's body, a modifier's content) and for the far commoner `if` inside a
    /// stack. A stack asks its children to flatten themselves, and a `nil`
    /// flattens to no children at all; it makes the one exception for a `nil`
    /// something is still leaving from, and only for as long as that is true.
    ///
    /// The exception is claimed by address — the enclosing identity plus the
    /// wrapped view's type — so a `nil` in a tree that is animating nothing
    /// contributes no child and changes no spacing, exactly as before. The
    /// present view is given that same address, so the claim finds it wherever
    /// the `if` stands: beside siblings, as a stack's only content, or under a
    /// modifier that reaches each member of what it wraps (`.frame`,
    /// `.opacity`, `.disabled`, `.padding`, `.background`). In a stack the
    /// same holds through structure that holds one view with nothing drawn
    /// around it — `if a { if b { X } }`, `if a { Group { X } }`, `if a { if c
    /// { X } else { Y } }` — whose `nil` asks that structure where it put the
    /// view.
    ///
    /// The picture a removal plays is the transitioning view's, so a wrapper
    /// written outside the transition may stand between it and the `if` only
    /// if it draws nothing of its own: environment and style modifiers
    /// (`.foregroundStyle`, `.tint`, `.disabled`, `.environment`), lifecycle
    /// and event modifiers (`.onAppear`, `.task`, `.onChange`, `.onKeyEvent`,
    /// `.onHover`), focus modifiers (`.focusable`, `.focused`), and `AnyView`.
    /// `if show { Toast().transition(.opacity).onAppear { … } }` plays.
    ///
    /// ## A view with no transition
    ///
    /// A view an `if` puts in or takes out under an animated change fades when
    /// no transition is written on it: the default is ``AnyTransition/opacity``,
    /// as SwiftUI's is. The `if` keeps what its view last drew, so the removal
    /// plays in the slot it leaves, as above. An `if`/`else` whose branch flips,
    /// a `switch` and a `ForEach`'s rows still change at once.
    ///
    /// ## What does not play its transition
    ///
    /// The claim finds a departure only where the view carrying the transition
    /// rendered at exactly that address, so these removals do not play it.
    /// Where the `if` holds one view, the view fades instead, as one with no
    /// transition does; the first and the last of these go at once:
    ///
    /// - An `if` holding several views — two or more, a `ForEach`, a `Group`
    ///   of several — which have no one slot to keep; or one view behind a
    ///   modifier on the structure around it, `if a { Group { X }.padding() }`
    ///   or `.foregroundStyle(.red)` on that `Group`, whose member the `nil`
    ///   cannot find (and, padded, could not draw).
    /// - Where the optional is rendered directly — a view's whole `body`, or a
    ///   modifier's content such as `.overlay { if a { … } }` — a `Group` or an
    ///   `if`/`else` inside the `if`: `if a { Group { X } }`, `if a { if c { X }
    ///   else { Y } }`. Each draws its view a step below the optional's own
    ///   identity, where the `nil` does not look. In a stack both play, and a
    ///   nested `if` plays either way.
    /// - A transition with an identity step between it and the `if`: one on
    ///   the root of a `body` — a view of your own, or a modifier built as a
    ///   view with a body, such as `.tag` or `.zIndex` — rather than on the
    ///   view the `if` holds; one inside a presentation modifier (`.sheet`,
    ///   `.alert`, `.popover`, `.contextMenu`); or one with an `.id` outside
    ///   it — `X.transition(t).id(k)`, or `.id` written on the `if` itself.
    ///   `X.id(k).transition(t)` plays.
    /// - A transition with a modifier outside it in the `if` that moves,
    ///   resizes or draws: `X.transition(t).padding()`, and so `.frame`,
    ///   `.offset`, `.position`, `.background`, `.overlay`, `.border`,
    ///   `.opacity`, `.hidden()`, `.help`, a colour effect, a list row's insets
    ///   or colours — inside an `AnyView` or behind a wrapper that draws
    ///   nothing as much as bare. The picture the removal would play is the
    ///   transition's alone, so drawing it would drop the padding and move the
    ///   view; it fades instead. `X.padding().transition(t)` plays, padding and
    ///   all — write the transition after anything that draws.
    /// - A transition behind one of four wrappers that draw nothing but are
    ///   not yet looked through: `.onPreferenceChange`, `.appHeader`, and the
    ///   two status-bar item modifiers. `X.transition(t).onPreferenceChange(…)`
    ///   fades — it played until 2026-09-24, when a removal began checking the
    ///   type of the view that left its picture; write the transition after
    ///   them.
    /// - The branch an `if`/`else` leaves. The other branch takes the slot at
    ///   once, and nothing is left standing to play the removal.
    ///
    /// - Parameter transition: How to come and go.
    /// - Returns: A view that transitions.
    public func transition(_ transition: AnyTransition) -> some View {
        _TransitionView(content: self, transition: transition)
    }

    /// How this view arrives when it is inserted, and how it leaves when it is
    /// removed, described by a ``Transition``.
    ///
    /// ```swift
    /// if showDetail {
    ///     Detail().transition(.push(from: .trailing))
    /// }
    /// ```
    ///
    /// The transition is erased to an ``AnyTransition`` and then plays exactly
    /// as `transition(_:)` with an `AnyTransition` describes, including what does
    /// not play it. A transition with a body of your own is drawn through that body —
    /// see ``Transition``.
    ///
    /// - Parameter transition: How to come and go.
    /// - Returns: A view that transitions.
    public func transition<T: Transition>(_ transition: T) -> some View {
        _TransitionView(content: self, transition: AnyTransition(transition))
    }
}

/// Applies a transition to its content while the content is arriving, and
/// leaves behind what is needed to play it out when the content goes.
/// See `View.transition(_:)`.
///
/// Where the environment reduces motion, a transition with motion plays as a
/// fade instead (``AnyTransition/reducingMotion(in:)``), decided as it renders.
struct _TransitionView<Content: View>: View {
    let content: Content
    let transition: AnyTransition

    var body: Never {
        fatalError("_TransitionView renders via Renderable")
    }
}

/// Which of a transitioning view's animation-store slots is which.
private enum StateIndex {
    static let phase = 0
}

extension _TransitionView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let transition = transition.reducingMotion(in: context.environment)
        if let custom = transition.custom { return renderBody(of: custom, context: context) }
        let buffer = TUIkitView.renderToBuffer(content, context: context)
        guard !context.isMeasuring, let storage = context.stateStorage else { return buffer }

        let animation =
            transition.explicitAnimation
            ?? (context.environment.canAnimate
                ? context.environment.transaction.effectiveAnimation : nil)

        // The departure re-declaration and the parting picture are per-frame
        // work no memo may skip: a cached buffer would starve the store of the
        // re-declaration (pruning the entry, so the removal snaps) and would
        // freeze the picture the removal plays.
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(Self.self),
            slot: StateIndex.phase)
        let phase = storage.animations.arrivalPhase(
            for: key, animation: animation,
            nowNanos: context.environment.frameNowNanos, isMeasuring: false)

        // Leave the parting picture behind on EVERY frame, so whatever holds
        // this slot can play it out if the next frame does not contain us.
        // Re-declared each frame because nothing else can report an absence —
        // see `DepartureStore` — and unconditionally, because how the view
        // will leave cannot be known while it is present: that is decided by
        // the transaction of the change that removes it, which the slot host
        // hands to the store at removal time.
        //
        // The arrival phase is folded in. A view removed mid-insertion is
        // only PART present, and a departure recorded from the raw content
        // buffer started the removal from full presence — the first departing
        // frame popped a 30%-arrived view to 100%. Scaling the removal's
        // phase by how far the arrival had got keeps the picture continuous
        // for the (symmetric) common case, and monotonic for every case.
        let removal = transition.removal
        let arrival = min(1, max(0, phase))
        storage.departures.present(
            DepartureStore.Departure(
                viewType: Self.self, width: buffer.width, height: buffer.lines.count,
                explicitAnimation: transition.explicitAnimation,
                render: { departurePhase in
                    removal.apply(to: buffer, phase: departurePhase * arrival, context: context)
                        .slotBuffer()
                }),
            at: context.identity)

        // `!= 1`, not `< 1`: a spring goes PAST its target and comes back, and
        // above 1 is a picture (the view a cell beyond where it lands) rather
        // than a rounding artefact — see ``AnyTransition/Effect/apply(to:phase:context:)``.
        // Exactly 1 is the settled value the store returns for a finished or
        // unanimated arrival, so the fast path still catches every idle frame.
        guard phase != 1 else { return buffer }
        return transition.insertion.apply(to: buffer, phase: phase, context: context).slotBuffer()
    }
}

extension _TransitionView: Layoutable {
    /// A transition never changes the size of its slot — see ``AnyTransition``
    /// on why the effects are applied to the buffer rather than to layout — so
    /// this measures exactly as its content, or as a custom body at rest.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let custom = transition.reducingMotion(in: context.environment).custom else {
            return measureChild(content, proposal: proposal, context: context)
        }
        return custom.measure(
            phase: .identity,
            content: .transitionContent(
                content, at: context.identity, keepingIn: TransitionContentPicture()),
            proposal: proposal, context: context)
    }
}

// MARK: - A body of the app's own

extension _TransitionView {
    /// A ``Transition`` with a body of the app's own: the body at rest, or —
    /// arriving — scrubbed from `.willAppear`, leaving behind the body
    /// scrubbed towards `.didDisappear` around the content's last picture.
    ///
    /// The same arrival phase, explicit animation and departure contract as
    /// the effects path above; only what is drawn at a given presence
    /// differs. See ``Transition`` and `TransitionScrub`.
    private func renderBody(of custom: _AnyTransitionBox, context: RenderContext) -> FrameBuffer {
        let picture = TransitionContentPicture()
        let live = PlaceholderSource.transitionContent(
            content, at: context.identity, keepingIn: picture)
        guard !context.isMeasuring, let storage = context.stateStorage else {
            return custom.render(phase: .identity, content: live, context: context)
        }

        let animation =
            transition.explicitAnimation
            ?? (context.environment.canAnimate
                ? context.environment.transaction.effectiveAnimation : nil)
        // Per-frame work no memo may skip, for the reasons the effects path
        // gives.
        context.environment.volatileReadTracker?.recordRenderSideEffect()

        let key = AnimationStore.Key(
            identity: context.identity, owner: ObjectIdentifier(Self.self),
            slot: StateIndex.phase)
        let phase = storage.animations.arrivalPhase(
            for: key, animation: animation,
            nowNanos: context.environment.frameNowNanos, isMeasuring: false)
        var buffer = custom.render(
            presence: phase, from: .willAppear, content: live,
            recordingAround: .transitionBlank(content, at: context.identity), context: context)
        if phase != 1 {
            // The slot is the body's size at rest, which is what the layout
            // measured; a body bigger part-way is drawn inside it.
            let rest = custom.measure(
                phase: .identity, content: live,
                proposal: ProposedSize(width: context.availableWidth, height: context.availableHeight),
                context: context)
            buffer = buffer.clamped(toWidth: rest.width, height: rest.height)
        }

        // The content's picture, as the body was handed it this frame: a
        // departing view has nothing else left to draw.
        let parting = picture.buffer ?? FrameBuffer()
        let arrival = min(1, max(0, phase))
        let (width, height) = (buffer.width, buffer.lines.count)
        storage.departures.present(
            DepartureStore.Departure(
                viewType: Self.self, width: width, height: height,
                explicitAnimation: transition.explicitAnimation,
                render: { departurePhase in
                    custom.render(
                        presence: departurePhase * arrival, from: .didDisappear,
                        content: .departedContent(parting),
                        recordingAround: .departedBlank(parting), context: context
                    ).clamped(toWidth: width, height: height)
                }),
            at: context.identity)
        return buffer
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``, so nothing about it is distributed to
/// the members of multi-view content.
extension _TransitionView: CarriesTransition {}

extension _TransitionView: SingleContentWrapper {
    var wrappedContent: Content { content }
}
