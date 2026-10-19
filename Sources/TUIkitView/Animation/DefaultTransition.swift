//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DefaultTransition.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// The default transition: a view an `if` puts in or takes out under an animated
// change fades, as SwiftUI's does with no `.transition` written. The branch an
// `if`/`else` takes and leaves, a `switch`'s case and a `ForEach`'s row fade
// too, through the container that places them (`ChildFade`) or, for a
// conditional drawn whole, through its own branch record (`BranchTransition`).
//
// ## Why one record per `if`, and not a re-declaration per frame
//
// An explicit `.transition` re-declares its view every frame it renders (see
// `DepartureStore`): nothing else can report that the view has gone. That makes
// every subtree holding one uncacheable, which is fine for the views an app
// chose to transition and not for every `if` in it — measured, a version that
// did that cost +9.5% on `dashboard` and +7.4% on `menus`, warm.
//
// Here the `if` reports for itself instead: it renders both ways, so it can say
// "I hold a view, and this is what it drew" and "I am empty" (`OptionalPresence`),
// the way an `if`/`else` notes which branch it took. The record is written only
// when the `if` renders, and a memo that serves the subtree leaves it standing —
// it is swept as the branch records are, so a served subtree keeps it — so
// nothing is replayed and no cache is turned off. The closure that draws the
// view leaving is made only when an animated change takes it out.
//
// An arrival is an `if` that was empty and now holds a view. One seen for the
// first time is not, so an `if` inside a view that is itself arriving does not
// fade a second time: SwiftUI transitions the view that was inserted, not each
// view inside it. Nor is one seen again after a pass unseen — inside a view
// that went and has come back — whose record is of a frame nobody has seen
// since; and a view it held then does not leave now
// (`StateStorage.wasOnScreenLastPass(writtenOn:at:)`).

/// A view that carries a transition of its own, so the default one stands
/// aside for it.
package protocol CarriesTransition {}

/// What an `if`'s slot held when it last rendered.
struct OptionalPresence {
    /// The picture its view drew, or `nil` when the slot was empty.
    var picture: FrameBuffer?
    /// Where the view drew it — the address a `nil` keeps a slot open at.
    var identity: ViewIdentity?
    /// The arrival in progress, if the view is still fading in.
    var arrival: Animation?
    var arrivalStartNanos: Int64 = 0
    /// The render pass that last wrote the record (`StateStorage.currentPass`),
    /// which keeps it through the sweep.
    var pass: UInt32 = 0
    /// Whether the `if` had rendered before: `false` on a record made just
    /// now, which is a first sight and never an arrival.
    var seen = false
}

/// An `if`'s present view as a stack draws it: unchanged, with its picture
/// recorded against the `if` and faded while it arrives.
///
/// A view of its own rather than a `ModifiedView`, so that what inspects a
/// stack's children — a `List` reading a `Section`, a split view reading a
/// column's frame — can look through it: see `ChildView.wrappedView`.
struct _DefaultTransitionView<Content: View>: View {
    let content: Content

    var body: Never {
        fatalError("_DefaultTransitionView renders via Renderable")
    }
}

/// Content an `if` draws through its default transition, and nothing else.
@MainActor
protocol DefaultTransitionWrapping {
    var transitionedView: any View { get }
}

extension _DefaultTransitionView: DefaultTransitionWrapping {
    var transitionedView: any View { content }
}

extension _DefaultTransitionView: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let buffer = TUIkitView.renderToBuffer(content, context: context)
        guard let scope = context.identity.parent else { return buffer }
        return DefaultTransition.present(buffer, scope: scope, context: context)
    }
}

extension _DefaultTransitionView: Layoutable {
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

package enum DefaultTransition {
    /// Whether an `if` holding a view whose picture is of `type` takes the
    /// default: not where that view is a transition of the app's own.
    @MainActor
    static func applies(toPictureType type: Any.Type) -> Bool {
        !(type is CarriesTransition.Type)
    }

    /// The animation the current frame's change runs under, if it animates.
    @MainActor
    static func frameAnimation(_ context: RenderContext) -> Animation? {
        let environment = context.environment
        return environment.animationFrame.canAnimate ? environment.transaction.effectiveAnimation : nil
    }

    /// Records `buffer` as what the `if` at `scope` holds, and returns it as
    /// it is drawn this frame: faded while it arrives.
    @MainActor
    static func present(_ buffer: FrameBuffer, scope: ViewIdentity, context: RenderContext) -> FrameBuffer {
        guard !context.isMeasuring, let storage = context.stateStorage else { return buffer }
        // A transition of the view's own, declared at this address as the
        // content drew, plays the arrival. The picture is kept all the same:
        // where something is drawn round that transition — `X.transition(t)
        // .padding()` — its own removal would lose it, and the `if` fades the
        // whole picture out instead (`absentOptional`).
        let ownsArrival = storage.departures.isPresent(at: context.identity)
        let phase = storage.presentOptional(
            at: scope, identity: context.identity, picture: buffer,
            animation: ownsArrival ? nil : frameAnimation(context), nowNanos: context.environment.frameNowNanos)
        guard phase != 1 else { return buffer }
        // Moving: a function of time, which no memo may keep.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        return faded(buffer, by: min(1, max(0, phase)))
    }

    /// Tells the `if` at `scope` it is empty: what it held starts leaving, if
    /// it was drawn and this change animates.
    @MainActor
    static func absent(scope: ViewIdentity, pictureType: Any.Type, context: RenderContext) {
        guard let storage = context.stateStorage else { return }
        storage.absentOptional(
            at: scope, pictureType: pictureType, frameAnimation: frameAnimation(context),
            nowNanos: context.environment.frameNowNanos, isMeasuring: context.isMeasuring)
    }

    /// `buffer` at `factor` of its strength, as `.opacity` draws it: its
    /// lines, and the layers it draws past them — an `.offset` child, a matched
    /// view carried from another's frame — which are its own drawing,
    /// displaced, and fade with it as SwiftUI's do (measured,
    /// `Tools/SwiftUIProbes/Transitions/tr3.out` T14,
    /// `Tools/SwiftUIProbes/Matched geometry/mg3.out` A1, A2). A layer over the
    /// whole screen it only hosts — a sheet — is left alone
    /// (``OpacityFading/fadingOverlays(_:by:cycle:)``).
    package static func faded(_ buffer: FrameBuffer, by factor: Double) -> FrameBuffer {
        guard factor < 1 else { return buffer }
        var faded = buffer
        faded.opacityRegions = OpacityFading.fading(
            buffer.opacityRegions, by: factor, cycle: nil, wholeOf: buffer, appendingRectangle: !buffer.isEmpty)
        if !buffer.overlays.isEmpty { faded.overlays = OpacityFading.fadingOverlays(buffer.overlays, by: factor) }
        return faded
    }
}

extension StateStorage {
    /// Whether the `if` at `scope` is fading its view in — so the container
    /// that view is a child of leaves it to the `if` (`ChildFade`).
    func isArrivingOptional(at scope: ViewIdentity) -> Bool {
        optionalPresence[scope]?.arrival != nil
    }

    /// Records that the `if` at `scope` holds a view that drew `picture` at
    /// `identity`, and returns how far it has arrived: `1` at rest, less while
    /// it fades in after an animated change put it there.
    ///
    /// One access to the table a render — the record is read and written where
    /// it lies, through the dictionary's in-place accessor — and no mark in the
    /// active set: the record carries the pass that wrote it, which is what
    /// the sweep keeps it by. A lookup, a store and a mark per `if` per frame
    /// cost up to 3.4% of a cold `menus` frame (A/B, 2026-10-14).
    ///
    /// An `if` that has come back after a pass unseen is a new view's, and
    /// what it holds appears rather than arrives
    /// (``wasOnScreenLastPass(writtenOn:at:)``).
    func presentOptional(
        at scope: ViewIdentity, identity: ViewIdentity, picture: FrameBuffer, animation: Animation?,
        nowNanos: Int64
    ) -> Double {
        Self.present(
            &optionalPresence[scope, default: OptionalPresence()], identity: identity, picture: picture,
            animation: animation, nowNanos: nowNanos, pass: currentPass,
            wasOnScreen: { self.wasOnScreenLastPass(writtenOn: $0, at: scope) })
    }

    /// ``presentOptional(at:identity:picture:animation:nowNanos:)`` on the
    /// record in place; `wasOnScreen` answers for the pass the record was
    /// last written on, and is asked only of an `if` that held nothing.
    private static func present(
        _ record: inout OptionalPresence, identity: ViewIdentity, picture: FrameBuffer, animation: Animation?,
        nowNanos: Int64, pass: UInt32, wasOnScreen: (UInt32) -> Bool
    ) -> Double {
        // Seen before, empty, and put there by an animated change: arriving.
        if record.seen, record.picture == nil, let animation, wasOnScreen(record.pass) {
            record.arrival = animation
            record.arrivalStartNanos = nowNanos
        }
        record.picture = picture
        record.identity = identity
        record.pass = pass
        record.seen = true
        guard let arrival = record.arrival else { return 1 }
        let elapsed = Double(nowNanos - record.arrivalStartNanos) / 1_000_000_000
        guard !arrival.isFinished(at: elapsed) else {
            record.arrival = nil
            return 1
        }
        return arrival.fraction(at: elapsed)
    }

    /// Records that the `if` at `scope` is empty. If it held a view that drew
    /// and `frameAnimation` animates the change, that view's picture starts
    /// leaving from where it drew, for the slot the `nil` keeps to play.
    ///
    /// A measure may start the departure — it is what the render that follows
    /// would start, and the slot must be measured with it — but writes nothing
    /// else, so it looks the record up rather than making one. A render makes
    /// or changes the record in place, with one access, as
    /// ``presentOptional(at:identity:picture:animation:nowNanos:)`` does.
    func absentOptional(
        at scope: ViewIdentity, pictureType: Any.Type, frameAnimation: Animation?, nowNanos: Int64,
        isMeasuring: Bool
    ) {
        if isMeasuring, optionalPresence[scope]?.picture == nil { return }
        let pass = isMeasuring ? nil : currentPass
        Self.absent(
            &optionalPresence[scope, default: OptionalPresence()], pictureType: pictureType,
            frameAnimation: frameAnimation, nowNanos: nowNanos, pass: pass, departures: departures,
            wasOnScreen: { self.wasOnScreenLastPass(writtenOn: $0, at: scope) })
    }

    /// ``absentOptional(at:pictureType:frameAnimation:nowNanos:isMeasuring:)``
    /// on the record in place; `pass` is `nil` on a measure, which stamps
    /// nothing. A view the `if` held before it went unseen for a pass is
    /// not one anybody saw leave: its picture is dropped, not played.
    private static func absent(
        _ record: inout OptionalPresence, pictureType: Any.Type, frameAnimation: Animation?, nowNanos: Int64,
        pass: UInt32?, departures: DepartureStore, wasOnScreen: (UInt32) -> Bool
    ) {
        let lastWritten = record.pass
        if let pass {
            record.pass = pass
            record.seen = true
        }
        guard let picture = record.picture else { return }
        // A view with a transition of its own left its picture here too, and
        // plays its removal itself — where that picture is all the `if` drew.
        // Where something was drawn round the transition (`X.transition(t)
        // .padding()`), its picture would lose that, and the whole picture
        // fades instead, as a view with no transition does.
        if let frameAnimation, let identity = record.identity,
            !departures.hasEntry(at: identity, leftBy: pictureType), wasOnScreen(lastWritten)
        {
            var arrived = 1.0
            if let arrival = record.arrival {
                arrived = min(1, max(0, arrival.fraction(at: Double(nowNanos - record.arrivalStartNanos) / 1_000_000_000)))
            }
            departures.beginDeparture(
                DepartureStore.Departure(
                    viewType: pictureType, width: picture.width, height: picture.lines.count,
                    explicitAnimation: nil,
                    render: { phase in DefaultTransition.faded(picture, by: phase * arrived) }),
                at: identity, animation: frameAnimation, nowNanos: nowNanos)
        }
        record.picture = nil
        record.identity = nil
        record.arrival = nil
    }
}
