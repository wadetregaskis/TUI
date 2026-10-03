//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LongPressGestureModifier.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - State

/// Where ``LongPressGestureModifier`` keeps the press between frames. A
/// namespace of its own because a generic type cannot hold static stored
/// properties.
private enum LongPressStateIndex {
    // Negative: the modifier renders its content at its own identity, and 0...
    // belongs to a composite content view's own @State. See
    // `StateStorage.StateKey`'s reserved-range table.
    static let press = -90
}

/// A long press in progress, kept between frames.
///
/// A class, so a frame can note the deadline without the write asking for a
/// frame of its own; the mouse handler, which changes what the gesture is
/// doing, writes the box back to ask for one (see
/// ``LongPressGestureModifier``).
final class LongPressState: @unchecked Sendable {
    enum Phase: Equatable {
        /// No press, or one that failed or has been released.
        case idle
        /// The left button is down, and went down at this cell.
        case pressing(origin: CellPoint)
        /// The press lasted long enough and the action has run; the button
        /// is still down.
        case recognized
    }

    var phase = Phase.idle

    /// When the press succeeds, on the frame clock. Set by the first frame
    /// that sees the press, since that is the clock the deadline is checked
    /// against.
    var deadline: Int64?
}

// MARK: - Modifier

/// The modifier behind ``View/onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)``.
///
/// A press is a left-button down on the view, claimed so its drags and its
/// release come back here. The first frame after it sets the deadline and asks
/// the run loop for a frame at it; the frame that reaches it runs the action.
/// A release before then, or a drag further than ``maximumDistance`` from where
/// the press began, ends the press without it.
struct LongPressGestureModifier<Content: View>: View {
    let content: Content
    let minimumDuration: Double
    let maximumDistance: Int
    let action: () -> Void
    let onPressingChanged: ((Bool) -> Void)?

    var body: Never {
        fatalError("LongPressGestureModifier renders via Renderable")
    }
}

extension LongPressGestureModifier: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // A disabled view takes no press, as a disabled control takes no click;
        // and a measure pass registers nothing and starts no clock.
        guard !context.isMeasuring, context.environment.isEnabled, let storage = context.stateStorage else {
            return TUIkit.renderToBuffer(content, context: context)
        }
        storage.markActive(context.identity)
        let box: StateBox<LongPressState> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: LongPressStateIndex.press),
            default: LongPressState())
        advance(box.value, context: context)
        return TUIkit.renderToBuffer(
            OnMouseEventModifier(content: content, handler: mouseHandler(box)), context: context)
    }

    /// The press's clock: the first frame that sees a press sets its deadline,
    /// and the first at or past the deadline recognizes it. Until then each
    /// frame asks the run loop for one at the deadline — which also keeps a
    /// memo from storing a frame whose next one has to differ.
    private func advance(_ state: LongPressState, context: RenderContext) {
        guard case .pressing = state.phase else { return }
        let now = context.environment.frameNowNanos
        let deadline = state.deadline ?? (now &+ Int64((max(0, minimumDuration) * 1_000_000_000).rounded()))
        state.deadline = deadline
        guard now >= deadline else {
            context.requestWake(token: "longPress-\(context.identity.path)", atNanos: deadline)
            return
        }
        state.phase = .recognized
        action()
        // The press is over as a gesture once it succeeds, even with the
        // button still down.
        onPressingChanged?(false)
    }

    /// The mouse half: a left press starts the gesture, a drag too far ends
    /// it, a release ends it. Each writes the box back, which drops what was
    /// cached for this view and asks for a frame — the frame that starts the
    /// clock, or the one that stops it.
    private func mouseHandler(_ box: StateBox<LongPressState>) -> (MouseEvent) -> Bool {
        let maximumDistance = max(0, maximumDistance)
        let onPressingChanged = onPressingChanged
        return { event in
            guard event.button == .left else { return false }
            let state = box.value
            switch event.phase {
            case .pressed:
                state.phase = .pressing(origin: CellPoint(x: event.x, y: event.y))
                state.deadline = nil
                box.value = state
                onPressingChanged?(true)
                return true
            case .dragged:
                if case .pressing(let origin) = state.phase,
                    max(abs(event.x - origin.x), abs(event.y - origin.y)) > maximumDistance
                {
                    state.phase = .idle
                    box.value = state
                    onPressingChanged?(false)
                }
                return true
            case .released:
                if case .pressing = state.phase { onPressingChanged?(false) }
                state.phase = .idle
                state.deadline = nil
                box.value = state
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Layoutable

extension LongPressGestureModifier: Layoutable {
    /// Behaviour-only decorator — it renders `content` unchanged, so it
    /// measures as its content does.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

// MARK: - Seeing Through the Wrapper (the READ direction)

/// Names its content so a container asking for a z-index or an alignment guide
/// can look through this wrapper instead of stopping at it. Read-only: it does
/// NOT conform to ``ContentRewrapping``.
extension LongPressGestureModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

// MARK: - View Extension

extension View {
    /// Performs an action when the view is pressed and held — SwiftUI's
    /// `onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)`.
    ///
    /// ```swift
    /// Text(item.name)
    ///     .onLongPressGesture {
    ///         showDetails(item)
    ///     } onPressingChanged: { pressing in
    ///         isHighlighted = pressing
    ///     }
    /// ```
    ///
    /// The press is the left mouse button, held on the view. `onPressingChanged`
    /// hears `true` when it goes down and `false` when the press ends: when it
    /// succeeds (just after the action runs), when the button comes up first,
    /// or when the pointer strays too far.
    ///
    /// The press claims the button, so a tap gesture on the same view does not
    /// also hear it: a terminal reports one click, and there is no gesture
    /// arbitration to share it.
    ///
    /// - Parameters:
    ///   - minimumDuration: How long, in seconds, the button must be held.
    ///   - maximumDistance: How far, in cells along either axis, the pointer
    ///     may move from where the press began before the gesture fails —
    ///     cells where SwiftUI counts points (§2.1 of
    ///     `Documentation/SwiftUI-compatibility.md`). One cell by default, the
    ///     nearest a terminal comes to SwiftUI's ten points.
    ///   - action: The action to perform once the press has lasted long enough.
    ///   - onPressingChanged: Told when the press starts and ends.
    /// - Returns: A view that recognizes a long press.
    public func onLongPressGesture(
        minimumDuration: Double = 0.5, maximumDistance: Int = 1, perform action: @escaping () -> Void,
        onPressingChanged: ((Bool) -> Void)? = nil
    ) -> some View {
        LongPressGestureModifier(
            content: self, minimumDuration: minimumDuration, maximumDistance: maximumDistance,
            action: action, onPressingChanged: onPressingChanged)
    }
}
