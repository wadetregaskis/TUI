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
/// scrollbar — so a user's scroll is ``interacting`` from its first step
/// until the steps have stopped for a quarter of a second (and for as long as
/// a scrollbar is held, or a page key's glide under
/// `scrollKeyboardAnimation(_:)` runs), and ``idle`` otherwise. A programmatic
/// scroll made inside `withAnimation` — a `scrollTo`, a ``ScrollPosition``
/// write — glides to its target, a `ScrollView` a line or a column at a time
/// and a `List` or a `Table` a row at a time, and is ``animating`` from the
/// frame it starts on to the one it lands on, as SwiftUI's is (measured,
/// B27). A `List` and a `Table` report their phases as a `ScrollView` does;
/// their cursor keys move the cursor, not a scroll, and report none. The other
/// two phases are SwiftUI's for input a terminal does not send: ``tracking`` a
/// finger that has not moved yet, ``decelerating`` after a fling. macOS never
/// decelerates under a mouse wheel either; a switch over them is still
/// exhaustive and still correct.
///
/// As in SwiftUI (measured), a programmatic scroll without animation — a
/// `scrollTo`, a ``ScrollPosition`` write — changes no phase, and nor does
/// one under reduce motion, which jumps.
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

    /// The view is animating to a target set by code: a `ScrollView`'s, a
    /// `List`'s or a `Table`'s `scrollTo` or ``ScrollPosition`` request made
    /// inside `withAnimation`, while it glides there. A user's scroll stops
    /// the glide, and the phase goes straight to ``interacting``.
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

    /// How fast the view was scrolling when its phase changed, in cells per
    /// second. Optional, as SwiftUI's is.
    ///
    /// Always `(0, 0)` here, and never `nil`: at the first report and at
    /// every change a terminal produces. That is what SwiftUI reports where
    /// it was measured — `(0, 0)` at its appear call and at both changes of an
    /// animated `scrollTo` (macOS 15.8; decisions B27). A terminal reports no
    /// speed, only discrete steps: the change to ``ScrollPhase/interacting``
    /// comes one step in, before there is a rate, and the change to
    /// ``ScrollPhase/idle`` a quarter of a second after the last step, when the
    /// view is still.
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

// MARK: - The scrollable's side

/// A scrollable whose phase `onScrollPhaseChange` is told: a `ScrollView`'s
/// handler, and a `List`'s or a `Table`'s, which are scroll views in SwiftUI.
/// What it holds is the phase and its timing; the reporting is shared
/// (`RenderContext.reportScrollPhase(of:geometry:)`).
@MainActor
package protocol ScrollPhaseReporting: AnyObject {
    /// What the view's scrolling is doing.
    var phase: ScrollPhase { get set }
    /// When the user last scrolled, on ``phaseNow``'s clock.
    var lastUserScrollNanos: UInt64 { get set }
    /// The phase each observer was last told, by its place among the
    /// observers the view reports to; `nil` before the first.
    var reportedPhases: [ScrollPhase?] { get set }
    /// The clock the phase is timed on.
    var phaseNow: () -> UInt64 { get }
    /// Whether the user's scroll is still under way though no step has come:
    /// a scrollbar held, a drag's auto-scroll. Its quiet waits until it is not.
    var holdsUserScroll: Bool { get }
}

extension RenderContext {
    /// Settles `scrollable`'s phase for the frame and reports it to the
    /// `onScrollPhaseChange` observers it claims (``reportScrollPhase(of:observers:geometry:)``),
    /// the ones stated above it.
    @MainActor
    package func reportScrollPhase(of scrollable: some ScrollPhaseReporting, geometry: () -> ScrollGeometry) {
        reportScrollPhase(of: scrollable, observers: environment.scrollObservers.phase, geometry: geometry)
    }

    /// Settles `scrollable`'s phase for the frame and reports it to those of
    /// `observers` it has claimed. Render passes only, and only with an
    /// observer: without one the phase is never read, and a view left
    /// `.interacting` costs nothing.
    @MainActor
    func reportScrollPhase(
        of scrollable: some ScrollPhaseReporting, observers: [ScrollPhaseObserver], geometry: () -> ScrollGeometry
    ) {
        guard !observers.isEmpty, !isMeasuring else { return }
        environment.volatileReadTracker?.recordRenderSideEffect()
        settlePhase(of: scrollable)
        if scrollable.reportedPhases.count != observers.count {
            scrollable.reportedPhases = Array(repeating: nil, count: observers.count)
        }
        let phase = scrollable.phase
        var changeContext: ScrollPhaseChangeContext?
        for (index, observer) in observers.enumerated() where observer.claim(for: identity) {
            let old = scrollable.reportedPhases[index]
            guard old != phase else { continue }
            scrollable.reportedPhases[index] = phase
            let made = changeContext ?? ScrollPhaseChangeContext(geometry: geometry(), velocity: .zero)
            changeContext = made
            // Held where this drawing may be drawn again, and the phase put
            // back if it is (`EffectStage`).
            let action = observer.action
            performEffect(
                { action(old ?? phase, phase, made) },
                undo: { [weak scrollable] in
                    guard let scrollable, scrollable.reportedPhases.indices.contains(index) else { return }
                    scrollable.reportedPhases[index] = old
                })
        }
    }

    /// Returns an interacting view to `.idle` once the user's scrolling has
    /// been quiet for ``ScrollPhase/quietNanos`` and nothing holds it, and
    /// otherwise asks for the frame that will find it so.
    @MainActor
    private func settlePhase(of scrollable: some ScrollPhaseReporting) {
        guard scrollable.phase == .interacting else { return }
        let held = scrollable.holdsUserScroll
        let quietFor = scrollable.phaseNow() &- scrollable.lastUserScrollNanos
        if !held, quietFor >= ScrollPhase.quietNanos {
            scrollable.phase = .idle
            return
        }
        let remaining = held ? ScrollPhase.quietNanos : ScrollPhase.quietNanos - quietFor
        requestWake(token: "scroll-phase-\(identity.path)", afterSeconds: Double(remaining) / 1e9)
    }
}

extension ScrollViewHandler: ScrollPhaseReporting {
    /// A scrollbar held on either axis, or a drag's auto-scroll
    /// (``ScrollPhaseReporting``). A key's glide (`scrollKeyboardAnimation(_:)`)
    /// holds it too: its quiet is counted from its landing, so a held Page
    /// Down is one span.
    package var holdsUserScroll: Bool {
        scrollbarDragGrab != nil || scrollbarRepeat != nil
            || horizontal.scrollbarDragGrab != nil || horizontal.scrollbarRepeat != nil
            || isAutoScrolling || glide?.isKeyboard == true
    }
}

// MARK: - The scroll view's side

extension _ScrollViewCore {
    /// Settles this view's phase for the frame and reports it to the
    /// `onScrollPhaseChange` observers it has claimed — none, for a framework
    /// scroller. Render passes only, and only with an observer.
    func reportScrollPhase(geometry: () -> ScrollGeometry, handler: ScrollViewHandler, context: RenderContext) {
        context.reportScrollPhase(
            of: handler, observers: pageScrollObservers(context.environment).phase, geometry: geometry)
    }
}
