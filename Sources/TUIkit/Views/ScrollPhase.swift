//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollPhase.swift
//
//  Whether a scroll view is being scrolled, for `onScrollPhaseChange`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - ScrollPhase

/// What a scroll view's scrolling is doing. Matches SwiftUI's type of the same
/// name.
///
/// A terminal scrolls by discrete steps — a wheel tick, a key, a drag on the
/// scrollbar — and TUIkit never animates a scroll, so a scroll view here is
/// either ``idle`` or ``interacting``: interacting from the user's first step
/// until the steps have stopped for a quarter of a second (and for as long as
/// a scrollbar is held). The other phases are SwiftUI's for input a terminal
/// does not send: ``tracking`` a finger that has not moved yet,
/// ``decelerating`` after a fling, ``animating`` toward a target set with
/// `withAnimation`. macOS never decelerates under a mouse wheel either; a
/// switch over them is still exhaustive and still correct.
///
/// As in SwiftUI (measured), a programmatic scroll without animation — a
/// `scrollTo`, a ``ScrollPosition`` write — changes no phase.
@frozen
public enum ScrollPhase: Hashable, Sendable {
    /// No scrolling is happening.
    case idle

    /// The scroll view is following a gesture that has not started to scroll.
    /// Not produced in a terminal.
    case tracking

    /// The user is scrolling the view.
    case interacting

    /// The user has stopped and the view is slowing to a stop. Not produced in
    /// a terminal, whose scrolling has no momentum.
    case decelerating

    /// The view is animating to a target set by code. Not produced: TUIkit
    /// does not animate scrolling.
    case animating

    /// Whether the view is scrolling: any phase but ``idle``.
    public var isScrolling: Bool { self != .idle }

    /// How long the user's scrolling must have stopped before the view is
    /// idle again: fifteen frames at 60 Hz. A wheel's ticks and a held key's
    /// repeats arrive well inside it; a pause to read does not.
    static let quietNanos: UInt64 = 250_000_000
}

extension ScrollPhase: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .idle: "idle"
        case .tracking: "tracking"
        case .interacting: "interacting"
        case .decelerating: "decelerating"
        case .animating: "animating"
        }
    }
}

// MARK: - Context

/// What a scroll view was doing when its phase changed. Matches SwiftUI's type
/// of the same name; SwiftUI makes it, and so does TUIkit.
public struct ScrollPhaseChangeContext: Sendable {
    /// The scroll view's geometry when its phase changed.
    public let geometry: ScrollGeometry

    /// How fast the view was scrolling, or `nil` when that is not known.
    ///
    /// Always `nil`: a terminal's scrolling comes in discrete steps, and
    /// nothing measures a speed from them. SwiftUI's is `nil` in the same
    /// circumstance, and `(0, 0)` where it does measure.
    public let velocity: CellVector?
}

/// A two-dimensional vector in cells — the counterpart of `CGVector`, beside
/// ``CellPoint`` and ``CellSize``.
///
/// A rate (``ScrollPhaseChangeContext/velocity`` is cells per second) need not
/// be a whole number of cells, so the components are `Double`.
public struct CellVector: Hashable, Sendable {
    /// The horizontal component, in columns.
    public var dx: Double

    /// The vertical component, in rows.
    public var dy: Double

    /// Creates a vector.
    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    /// The zero vector.
    public static let zero = Self(dx: 0, dy: 0)
}

// MARK: - onScrollPhaseChange

extension View {
    /// Calls `action` when the phase of the first scroll view in this
    /// hierarchy changes. Matches SwiftUI's `onScrollPhaseChange(_:)`.
    ///
    /// ```swift
    /// ScrollView { … }
    ///     .onScrollPhaseChange { _, newPhase in
    ///         if newPhase == .idle { selection = itemAtTop() }
    ///     }
    /// ```
    ///
    /// As in SwiftUI (measured), the action runs once when the scroll view
    /// first draws, `.idle` to `.idle`, and then at each change. See
    /// ``ScrollPhase`` for the phases a terminal produces, and
    /// ``View/onScrollGeometryChange(for:of:action:)`` for which scroll view
    /// reports.
    ///
    /// - Parameter action: Receives the old and the new phase.
    public func onScrollPhaseChange(
        _ action: @escaping (ScrollPhase, ScrollPhase) -> Void
    ) -> some View {
        onScrollPhaseChange { old, new, _ in action(old, new) }
    }

    /// Calls `action` when the phase of the first scroll view in this
    /// hierarchy changes, with its geometry at the time. Matches SwiftUI's
    /// `onScrollPhaseChange(_:)`; see the two-argument form.
    ///
    /// - Parameter action: Receives the old and the new phase, and the
    ///   scroll view's geometry.
    public func onScrollPhaseChange(
        _ action: @escaping (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void
    ) -> some View {
        let observer = ScrollPhaseObserver(action: action)
        return transformEnvironment(\.scrollObservers) { $0.phase.append(observer) }
    }
}

/// One `onScrollPhaseChange`: its action, and the scroll view that has
/// claimed it (see ``ScrollGeometryObserver/claim(for:)``).
@MainActor
final class ScrollPhaseObserver {
    let action: (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void
    private var claimant: ViewIdentity?

    init(action: @escaping (ScrollPhase, ScrollPhase, ScrollPhaseChangeContext) -> Void) {
        self.action = action
    }

    func claim(for identity: ViewIdentity) -> Bool {
        if let claimant { return claimant == identity }
        claimant = identity
        return true
    }
}

// MARK: - The scroll view's side

extension _ScrollViewCore {
    /// Settles this view's phase for the frame and reports it to the
    /// `onScrollPhaseChange` observers it has claimed. Render passes only, and
    /// only with an observer: without one the phase is never read, and a view
    /// left `.interacting` costs nothing.
    func reportScrollPhase(geometry: () -> ScrollGeometry, handler: ScrollViewHandler, context: RenderContext) {
        let observers = context.environment.scrollObservers.phase
        guard !observers.isEmpty, !context.isMeasuring else { return }
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        settlePhase(handler: handler, context: context)
        if handler.reportedPhases.count != observers.count {
            handler.reportedPhases = Array(repeating: nil, count: observers.count)
        }
        let phase = handler.phase
        var changeContext: ScrollPhaseChangeContext?
        for (index, observer) in observers.enumerated() where observer.claim(for: context.identity) {
            let old = handler.reportedPhases[index]
            guard old != phase else { continue }
            handler.reportedPhases[index] = phase
            let made = changeContext ?? ScrollPhaseChangeContext(geometry: geometry(), velocity: nil)
            changeContext = made
            observer.action(old ?? phase, phase, made)
        }
    }

    /// Returns an interacting view to `.idle` once the user's scrolling has
    /// been quiet for ``ScrollPhase/quietNanos`` and nothing is held, and
    /// otherwise asks for the frame that will find it so.
    private func settlePhase(handler: ScrollViewHandler, context: RenderContext) {
        guard handler.phase == .interacting else { return }
        let held =
            handler.scrollbarDragGrab != nil || handler.scrollbarRepeat != nil
            || handler.horizontal.scrollbarDragGrab != nil || handler.horizontal.scrollbarRepeat != nil
            || handler.isAutoScrolling
        let quietFor = handler.phaseNow() &- handler.lastUserScrollNanos
        if !held, quietFor >= ScrollPhase.quietNanos {
            handler.phase = .idle
            return
        }
        let remaining = held ? ScrollPhase.quietNanos : ScrollPhase.quietNanos - quietFor
        context.requestWake(
            token: "scroll-phase-\(context.identity.path)", afterSeconds: Double(remaining) / 1e9)
    }
}
