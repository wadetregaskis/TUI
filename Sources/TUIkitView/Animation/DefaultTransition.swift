//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DefaultTransition.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// The default transition: a view an `if` puts in or takes out under an animated
// change fades, as SwiftUI's does with no `.transition` written.
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
// view inside it.

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
        // content drew: it plays the arrival and the removal, not this.
        guard !storage.departures.isPresent(at: context.identity) else { return buffer }
        let phase = storage.presentOptional(
            at: scope, identity: context.identity, picture: buffer,
            animation: frameAnimation(context), nowNanos: context.environment.frameNowNanos)
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

    /// `buffer` at `factor` of its strength, as `.opacity` draws it.
    static func faded(_ buffer: FrameBuffer, by factor: Double) -> FrameBuffer {
        guard factor < 1 else { return buffer }
        var faded = buffer
        faded.opacityRegions = buffer.opacityRegions.map { region in
            var scaled = region
            scaled.opacity *= factor
            scaled.cycle = region.cycle?.scaled(by: factor)
            return scaled
        }
        if !buffer.isEmpty {
            faded.opacityRegions.append(
                OpacityRegion(
                    offsetX: 0, offsetY: 0, width: buffer.width, height: buffer.lines.count, opacity: factor))
        }
        return faded
    }
}

extension StateStorage {
    /// Records that the `if` at `scope` holds a view that drew `picture` at
    /// `identity`, and returns how far it has arrived: `1` at rest, less while
    /// it fades in after an animated change put it there.
    func presentOptional(
        at scope: ViewIdentity, identity: ViewIdentity, picture: FrameBuffer, animation: Animation?,
        nowNanos: Int64
    ) -> Double {
        markActive(scope)
        let previous = optionalPresence[scope]
        var record = OptionalPresence(picture: picture, identity: identity)
        if let previous {
            if previous.picture == nil, let animation {
                record.arrival = animation
                record.arrivalStartNanos = nowNanos
            } else if let arrival = previous.arrival {
                record.arrival = arrival
                record.arrivalStartNanos = previous.arrivalStartNanos
            }
        }
        var phase = 1.0
        if let arrival = record.arrival {
            let elapsed = Double(nowNanos - record.arrivalStartNanos) / 1_000_000_000
            if arrival.isFinished(at: elapsed) {
                record.arrival = nil
            } else {
                phase = arrival.fraction(at: elapsed)
            }
        }
        optionalPresence[scope] = record
        return phase
    }

    /// Records that the `if` at `scope` is empty. If it held a view that drew
    /// and `frameAnimation` animates the change, that view's picture starts
    /// leaving from where it drew, for the slot the `nil` keeps to play.
    ///
    /// A measure may start the departure — it is what the render that follows
    /// would start, and the slot must be measured with it — but writes nothing
    /// else.
    func absentOptional(
        at scope: ViewIdentity, pictureType: Any.Type, frameAnimation: Animation?, nowNanos: Int64,
        isMeasuring: Bool
    ) {
        if !isMeasuring { markActive(scope) }
        let previous = optionalPresence[scope]
        if let previous, let picture = previous.picture {
            // A view with a transition of its own left its picture here too,
            // and plays its removal itself.
            if let frameAnimation, let identity = previous.identity, !departures.hasEntry(at: identity) {
                var arrived = 1.0
                if let arrival = previous.arrival {
                    arrived = min(1, max(0, arrival.fraction(at: Double(nowNanos - previous.arrivalStartNanos) / 1_000_000_000)))
                }
                departures.beginDeparture(
                    DepartureStore.Departure(
                        viewType: pictureType, width: picture.width, height: picture.lines.count,
                        explicitAnimation: nil,
                        render: { phase in DefaultTransition.faded(picture, by: phase * arrived) }),
                    at: identity, animation: frameAnimation, nowNanos: nowNanos)
            }
            optionalPresence[scope] = OptionalPresence()
        } else if previous == nil, !isMeasuring {
            optionalPresence[scope] = OptionalPresence()
        }
    }
}
