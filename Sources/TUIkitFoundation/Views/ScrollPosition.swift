//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollPosition.swift
//
//  The bindable half of programmatic scrolling: where a ScrollView is, and
//  where you would like it to be. `ScrollViewProxy.scrollTo` is the
//  imperative form of the same machinery — this one is state you can hold.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - ScrollPosition

/// A scroll view's position, readable and writable as state. Matches
/// SwiftUI's type of the same name.
///
/// ```swift
/// @State private var position = ScrollPosition(idType: Row.ID.self)
///
/// ScrollView {
///     LazyVStack {
///         ForEach(rows) { RowView($0) }
///     }
/// }
/// .scrollPosition($position)
///
/// Button("Top") { position.scrollTo(edge: .top) }
/// Text("Showing: \(position.viewID(type: Row.ID.self).map(String.init(describing:)) ?? "—")")
/// ```
///
/// It works in both directions, and the two are asymmetric on purpose:
/// **writing** asks the scroll view to move (it takes effect on the next
/// frame), **reading** tells you what you asked for and where the scroll view
/// ended up — which is not necessarily where you asked, because the user can
/// scroll too.
///
/// What each reading answers, as in SwiftUI:
///
/// - ``edge``, ``x``, ``y`` and ``point`` are the request: what the position
///   was last asked to scroll to, kept until the user scrolls it themselves.
///   ``point`` is set only when both coordinates were asked for.
/// - ``viewID(type:)`` is the row: the one asked for, or else the row the
///   scroll view reports showing at its anchor (see there for which content
///   reports one).
/// - ``isPositionedByUser`` says the user scrolled it, and only that: a frame
///   drawn, or a programmatic scroll, never sets it.
///
/// > Note: SwiftUI's `point`/`x`/`y` forms take `CGPoint`/`CGFloat`; a terminal
///   scrolls in whole cells, so they take a ``CellPoint`` and `Int`s — rows
///   down, columns across.
public struct ScrollPosition: Equatable {

    /// What the position was last asked to scroll to. One of them at a time, as
    /// in SwiftUI: naming a row and naming an offset are different questions.
    enum Target: Equatable {
        case id(PositionID, anchor: UnitPoint?)
        case edge(Edge)
        /// Rows down (`y`) and columns across (`x`) from the content's origin;
        /// `nil` leaves that axis where it is.
        case offset(x: Int?, y: Int?)
    }

    /// An id as the position holds it: compared as an `AnyHashable`, and kept
    /// `Sendable` as well wherever its type is known to be.
    ///
    /// Two halves because the two sources differ. An id the app hands over
    /// arrives `Sendable` (SwiftUI's signatures ask for it), and ``viewID``
    /// gives it back as one. An id the scroll view reports comes from a
    /// `ForEach`, whose ids are only `Hashable`, and `Sendable` is a marker
    /// protocol no runtime cast can recover — so a reported id is `Sendable`
    /// only when the position was told its type (``init(idType:)``).
    struct PositionID: Equatable {
        let value: AnyHashable
        let sendable: (any Hashable & Sendable)?

        init(_ value: some Hashable & Sendable) {
            self.value = AnyHashable(value)
            self.sendable = value
        }

        init(reported value: AnyHashable, as idType: IDType?) {
            self.value = value
            self.sendable = idType.flatMap { Self.typed($0.type, value) }
        }

        private static func typed<T: Hashable & Sendable>(
            _ type: T.Type, _ value: AnyHashable
        ) -> (any Hashable & Sendable)? {
            value.base as? T
        }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    }

    /// The id type a position was created for (`init(idType:)` and friends).
    /// Compared by identity: metatypes are not `Equatable`.
    struct IDType: Equatable {
        let type: any (Hashable & Sendable).Type

        static func == (lhs: Self, rhs: Self) -> Bool {
            ObjectIdentifier(lhs.type) == ObjectIdentifier(rhs.type)
        }
    }

    /// The pending or last-applied request; `nil` once the user has scrolled.
    var target: Target?

    /// The row the scroll view last reported at its anchor, if it reports one.
    var reported: PositionID?

    /// The id type this position was created for, if one was named.
    let idType: IDType?

    /// Bumped by every `scrollTo`, so a scroll view can tell a fresh request
    /// from the same request still sitting there. Without it, asking twice for
    /// the same row after scrolling away by hand would be indistinguishable
    /// from not asking at all.
    var requestToken: Int = 0

    /// Whether the person using the app scrolled the view to where it is,
    /// rather than code. Matches SwiftUI's property of the same name.
    ///
    /// Set by the scroll view when the user scrolls — the wheel, the keys, the
    /// scrollbar — and never by a `scrollTo` or by a frame being drawn (both
    /// measured on SwiftUI). Writable as SwiftUI's is: setting it to `true`
    /// drops a requested edge or offset, which no longer describes where the
    /// view is, and every `scrollTo` sets it back to `false`.
    public var isPositionedByUser: Bool = false {
        didSet {
            guard isPositionedByUser else { return }
            switch target {
            case .edge, .offset: target = nil
            case .id, nil: break
            }
        }
    }

    /// Creates a position with no target — whatever the scroll view does by
    /// default — for content whose rows have ids of `idType`.
    ///
    /// Naming the type is what lets ``viewID`` hand back the ids the scroll
    /// view reports, which come from a `ForEach` that promises only `Hashable`;
    /// ``viewID(type:)`` needs no such help.
    public init(idType: (some Hashable & Sendable).Type = Never.self) {
        self.idType = Self.declared(idType)
    }

    /// Creates a position that starts by scrolling to `edge`.
    public init(idType: (some Hashable & Sendable).Type = Never.self, edge: Edge) {
        self.idType = Self.declared(idType)
        self.target = .edge(edge)
        self.requestToken = 1
    }

    /// Creates a position that starts at `point`: `point.y` rows down and
    /// `point.x` columns across.
    public init(idType: (some Hashable & Sendable).Type = Never.self, point: CellPoint) {
        self.init(idType: idType, x: point.x, y: point.y)
    }

    /// Creates a position that starts `x` columns across.
    public init(idType: (some Hashable & Sendable).Type = Never.self, x: Int) {
        self.idType = Self.declared(idType)
        self.target = .offset(x: x, y: nil)
        self.requestToken = 1
    }

    /// Creates a position that starts `x` columns across and `y` rows down.
    public init(idType: (some Hashable & Sendable).Type = Never.self, x: Int, y: Int) {
        self.idType = Self.declared(idType)
        self.target = .offset(x: x, y: y)
        self.requestToken = 1
    }

    /// Creates a position that starts `y` rows down.
    public init(idType: (some Hashable & Sendable).Type = Never.self, y: Int) {
        self.idType = Self.declared(idType)
        self.target = .offset(x: nil, y: y)
        self.requestToken = 1
    }

    /// Creates a position that starts at the row identified by `id`.
    public init(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
        self.idType = Self.declared(type(of: id))
        self.target = .id(PositionID(id), anchor: anchor)
        self.requestToken = 1
    }

    /// `nil` for SwiftUI's `Never` default, which names no ids at all.
    private static func declared(_ type: (some Hashable & Sendable).Type) -> IDType? {
        type == Never.self ? nil : IDType(type: type)
    }
}

// MARK: - Reading

extension ScrollPosition {
    /// The row: the one asked for, or else the row the scroll view reports
    /// showing at its anchor — `nil` when there is neither.
    private var row: PositionID? {
        if case .id(let id, _) = target { return id }
        return reported
    }

    /// The id of the row at the scroll view's anchor, if it is of type `T`.
    ///
    /// The row asked for (``scrollTo(id:anchor:)``) until the user scrolls;
    /// otherwise the row the scroll view reports. `nil` when nothing has been
    /// reported yet (the first frame), when the content has no ids to report,
    /// or when the id is not a `T`.
    ///
    /// The row is the child of the content's stack under the anchor — a
    /// vertical stack's, lazy or eager, or a horizontal stack's in a scroll
    /// view that scrolls only across (whose column is sampled at the anchor's
    /// `x`, or at the leading edge with no anchor stated) — named as a seek
    /// names it, per child: a `ForEach` row by its element's `id`, whatever
    /// else is in the stack (a heading, a second `ForEach` over the same ids),
    /// and a child of the stack's own by its `.id(_:)` tag, as the tag's own
    /// type. A child with neither — an untagged heading — reports nothing, and
    /// the reading stays at the row reported before it.
    ///
    /// SwiftUI reports a row only once the user scrolls past one; this reports
    /// the row the view shows after any scroll, and on the first frame. A
    /// reading SwiftUI would give is never different here — only present where
    /// SwiftUI's is still `nil`.
    ///
    /// SwiftUI asks `T` to be `Sendable` as well; a reading asks nothing of a
    /// type, so any `Hashable` one is accepted.
    public func viewID<T: Hashable>(type: T.Type) -> T? {
        row?.value.base as? T
    }

    /// The id of the row at the scroll view's anchor, type-erased — see
    /// ``viewID(type:)``.
    ///
    /// A row the scroll view reports appears here only when the position knows
    /// its id type — create it with ``init(idType:)`` (as SwiftUI asks you to
    /// anyway). An id is not `Sendable` just because its value happens to be,
    /// and nothing at run time can make it so.
    public var viewID: (any Hashable & Sendable)? {
        row?.sendable
    }

    /// The edge this position was last asked to scroll to, if it was asked for
    /// one and the user has not scrolled since.
    public var edge: Edge? {
        guard case .edge(let edge) = target else { return nil }
        return edge
    }

    /// The column offset this position was last asked to scroll to, if it was
    /// asked for one and the user has not scrolled since.
    public var x: Int? {
        guard case .offset(let x, _) = target else { return nil }
        return x
    }

    /// The row offset this position was last asked to scroll to, if it was
    /// asked for one and the user has not scrolled since.
    public var y: Int? {
        guard case .offset(_, let y) = target else { return nil }
        return y
    }

    /// The point this position was last asked to scroll to — only when BOTH
    /// coordinates were asked for, as SwiftUI's is: after
    /// ``scrollTo(y:)`` alone it is `nil` (measured), and ``y`` is the answer.
    public var point: CellPoint? {
        guard case .offset(let x?, let y?) = target else { return nil }
        return CellPoint(x: x, y: y)
    }
}

// MARK: - Writing

extension ScrollPosition {
    /// Asks the scroll view to bring the row identified by `id` into view.
    ///
    /// - Parameters:
    ///   - id: The row's identity, as `ForEach` derives it — or a `.id(_:)`
    ///     tag on one of the content stack's own children, which seeks the
    ///     same way. (Not a `.id(_:)` written INSIDE a `ForEach` row, whose
    ///     identity is its element's `id`; see `ChildView.matchesSeekKey`.)
    ///   - anchor: Where the row lands — `nil` (the default) moves as little
    ///     as possible, and not at all if the row is already visible.
    public mutating func scrollTo(id: some Hashable & Sendable, anchor: UnitPoint? = nil) {
        request(.id(PositionID(id), anchor: anchor))
    }

    /// Asks the scroll view to scroll to one end of its content: `.top` and
    /// `.bottom` on the vertical axis, `.leading` and `.trailing` on the
    /// horizontal one.
    public mutating func scrollTo(edge: Edge) {
        request(.edge(edge))
    }

    /// Asks the scroll view to scroll to `point`: `point.y` rows down and
    /// `point.x` columns across. Clamped to the content, as SwiftUI's is.
    public mutating func scrollTo(point: CellPoint) {
        request(.offset(x: point.x, y: point.y))
    }

    /// Asks the scroll view to scroll `x` columns across, leaving the rows
    /// where they are. Clamped to the content.
    public mutating func scrollTo(x: Int) {
        request(.offset(x: x, y: nil))
    }

    /// Asks the scroll view to scroll `x` columns across and `y` rows down.
    /// Clamped to the content.
    public mutating func scrollTo(x: Int, y: Int) {
        request(.offset(x: x, y: y))
    }

    /// Asks the scroll view to scroll `y` rows down from the top of the
    /// content, leaving the columns where they are. Clamped to the content.
    public mutating func scrollTo(y: Int) {
        request(.offset(x: nil, y: y))
    }

    private mutating func request(_ target: Target) {
        self.target = target
        requestToken += 1
        isPositionedByUser = false
    }

    /// Records the row the scroll view reports showing at its anchor.
    ///
    /// Reported by the scroll view, never by the app. It changes what
    /// ``viewID(type:)`` answers once no row is being asked for, and nothing
    /// else: a report follows every scroll, the app's as well as the user's.
    mutating func reportVisible(id: AnyHashable) {
        reported = PositionID(reported: id, as: idType)
    }

    /// Records that the user scrolled the view: the request no longer
    /// describes where it is, and the row it shows is the answer.
    mutating func reportPositionedByUser() {
        target = nil
        isPositionedByUser = true
    }
}

// MARK: - Modifiers

extension View {
    /// Binds a scroll view's position to state you hold. Matches SwiftUI's
    /// `scrollPosition(_:anchor:)`.
    ///
    /// - Parameters:
    ///   - position: The position to read and write.
    ///   - anchor: Which point of the viewport the reported row is sampled at
    ///     — `nil` (the default) means the top.
    public func scrollPosition(
        _ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil
    ) -> some View {
        environment(\.scrollPositionBinding, ScrollPositionBinding(position, anchor: anchor))
    }

    /// Binds the id of the row at a scroll view's anchor. Matches SwiftUI's
    /// `scrollPosition(id:anchor:)`.
    ///
    /// Writing the binding scrolls to that row; the scroll view writes back
    /// the row it is actually showing.
    ///
    /// - Parameters:
    ///   - id: The row identity to read and write.
    ///   - anchor: Which point of the viewport the row is sampled at.
    public func scrollPosition<ID: Hashable>(
        id: Binding<ID?>, anchor: UnitPoint? = nil
    ) -> some View {
        // Bridged onto the same channel rather than given its own: one scroll
        // view reading two mechanisms would need a precedence rule nobody
        // asked for.
        let bridged = Binding<ScrollPosition>(
            get: {
                var position = ScrollPosition()
                if let value = id.wrappedValue {
                    position.target = .id(
                        ScrollPosition.PositionID(reported: AnyHashable(value), as: nil),
                        anchor: anchor)
                    // A plain id binding has no token of its own: the VALUE
                    // changing is the request, which the scroll view detects by
                    // comparing against the row it last reported.
                    position.requestToken = 0
                }
                return position
            },
            set: { newValue in
                // The REPORTED row, not `viewID(type:)`: the position the
                // getter built names the bound value as its request, which
                // would win, and the binding would never hear the row move.
                let reported = newValue.reported?.value.base as? ID
                if id.wrappedValue != reported { id.wrappedValue = reported }
            })
        return environment(
            \.scrollPositionBinding,
            ScrollPositionBinding(bridged, anchor: anchor, tracksUserPositioning: false))
    }
}

// MARK: - Environment

/// The binding plus its anchor, carried to whichever ``ScrollView`` is inside.
///
/// The binding plus its anchor, and nothing else: this box is rebuilt with
/// every body evaluation, so it can carry no memory. The freshness that keeps
/// a standing target from re-applying every frame — which request token was
/// acted on, which id was last written back — lives on the persistent
/// ``ScrollViewHandler`` instead; kept here it reset every frame, and a
/// standing `scrollTo` undid the user's scroll on the very next render.
@MainActor
package final class ScrollPositionBinding {
    let binding: Binding<ScrollPosition>
    package let anchor: UnitPoint
    /// Where across the viewport a purely horizontal scroll view samples the
    /// column it reports: the anchor's `x`, or the leading edge where none was
    /// stated — the first column a reader sees, as the unstated anchor's
    /// `.top` names the first row.
    let columnUnitX: Double
    /// Whether the user's scrolls are reported as such (the request dropped,
    /// ``ScrollPosition/isPositionedByUser`` set). Not for the `id:` binding,
    /// whose positions are rebuilt from the bound id on every read: there is
    /// no request to drop, and dropping it would write `nil` to the id.
    let tracksUserPositioning: Bool

    init(_ binding: Binding<ScrollPosition>, anchor: UnitPoint?, tracksUserPositioning: Bool = true) {
        self.binding = binding
        self.anchor = anchor ?? .top
        self.columnUnitX = anchor?.x ?? 0
        self.tracksUserPositioning = tracksUserPositioning
    }
}

/// Equal when the ANCHOR is: the one thing the scroll view's content reads
/// of it while drawing.
///
/// The box is built afresh by every evaluation of the body that applies
/// `.scrollPosition`, so it has no identity to compare, and it was not
/// `Equatable` at all — which turned every memo off beneath it: a log viewer
/// that reported its top line spent 800 µs on a frame where nothing had
/// changed (`Stress --session log`). Compared by identity it would be worse,
/// a change on every frame and the scroll view's caches cleared with it.
///
/// What the binding HOLDS is read by the scroll view itself, on every render
/// it makes (`positionSeek`, `applyPositionOffset`, the report of the row it
/// shows) — none of which a memo below it serves — and a request an app makes
/// by writing the binding reaches the scroll view as a write to the app's own
/// state, which invalidates the view that holds it. The content reads only
/// where the reported row is sampled, the anchor.
extension ScrollPositionBinding: Equatable {
    nonisolated package static func == (lhs: ScrollPositionBinding, rhs: ScrollPositionBinding) -> Bool {
        lhs.anchor == rhs.anchor && lhs.columnUnitX == rhs.columnUnitX
    }
}

private struct ScrollPositionBindingKey: EnvironmentKey {
    static let defaultValue: ScrollPositionBinding? = nil
}

extension EnvironmentValues {
    /// The enclosing ``View/scrollPosition(_:anchor:)`` binding, if any.
    package var scrollPositionBinding: ScrollPositionBinding? {
        get { self[ScrollPositionBindingKey.self] }
        set { self[ScrollPositionBindingKey.self] = newValue }
    }
}

// MARK: - What a scrollable does with the binding

/// What a scrollable keeps, frame to frame, of the `.scrollPosition` bound
/// above it: which request it acted on and which row it last reported — on
/// its handler, since the binding's box is rebuilt with every body.
package struct ScrollPositionTracking {
    /// The token of the request last acted on (`ScrollPosition.requestToken`),
    /// `nil` before any.
    var lastAppliedToken: Int?
    /// The row last reported, or asked for by a plain `id:` binding.
    var lastReportedID: AnyHashable?

    package init() {}
}

/// An edge or an offset a bound position asks for: arithmetic, where a row
/// goes through the key seek (``ScrollPositionBinding/rowRequest(tracking:transactionAnchor:)``).
package enum ScrollPositionPlacement {
    case edge(Edge)
    case offset(x: Int?, y: Int?)
}

extension ScrollPositionBinding {
    /// The row this binding asks for on this frame, as a seek, or `nil`: none
    /// asked for, an edge or an offset asked for instead, or a request already
    /// acted on — the token, or for the plain `id:` binding the value
    /// differing from what was last reported, is what tells a fresh request
    /// from the same one still sitting in the binding. Without that,
    /// scrolling away by hand would be undone on the very next frame.
    ///
    /// A transaction's anchor (`Transaction.scrollTargetAnchor`) is preferred
    /// to the `id:` binding's modifier anchor, as SwiftUI documents; a
    /// `ScrollPosition` request's own anchor wins over it.
    package func rowRequest(
        tracking: inout ScrollPositionTracking, transactionAnchor: UnitPoint?
    ) -> ScrollToRequest? {
        let position = binding.wrappedValue
        guard case .id(let id, let anchor)? = position.target else { return nil }
        let value = id.value
        let isFresh =
            position.requestToken == 0
            ? tracking.lastReportedID != value
            : tracking.lastAppliedToken != position.requestToken
        guard isFresh else { return nil }
        tracking.lastAppliedToken = position.requestToken
        tracking.lastReportedID = value
        let seekAnchor = position.requestToken == 0 ? transactionAnchor ?? anchor : anchor ?? transactionAnchor
        // The same stringification `ForEach` derives its keys with, so the
        // comparison in the seek paths is exact.
        return ScrollToRequest(key: identityKey(value.base), anchor: seekAnchor)
    }

    /// The edge or offset this binding asks for on this frame, once, or `nil`.
    package func placementRequest(tracking: inout ScrollPositionTracking) -> ScrollPositionPlacement? {
        let position = binding.wrappedValue
        guard let target = position.target,
            tracking.lastAppliedToken != position.requestToken, position.requestToken > 0
        else { return nil }
        switch target {
        case .edge(let edge):
            tracking.lastAppliedToken = position.requestToken
            return .edge(edge)
        case .offset(let x, let y):
            tracking.lastAppliedToken = position.requestToken
            return .offset(x: x, y: y)
        case .id:
            return nil  // A row: see `rowRequest(tracking:transactionAnchor:)`.
        }
    }

    /// Writes `id` back as the row shown — only when it CHANGED. A render
    /// pass that wrote its binding every frame would invalidate its own
    /// subtree every frame and never settle, the discipline
    /// `onPreferenceChange` follows, for the same reason.
    ///
    /// The tracking is `owner`'s, at `tracking`. In a drawing that may yet be
    /// drawn again, the write waits for the drawing to be kept, and the row
    /// noted as reported is put back if it is not (`EffectStage`): the row the
    /// kept drawing shows is the one the binding is told.
    package func report<Owner: AnyObject>(
        _ id: AnyHashable, trackedBy owner: Owner, at tracking: ReferenceWritableKeyPath<Owner, ScrollPositionTracking>,
        context: RenderContext
    ) {
        let before = owner[keyPath: tracking].lastReportedID
        guard before != id else { return }
        owner[keyPath: tracking].lastReportedID = id
        let binding = binding
        context.performEffect(
            {
                var position = binding.wrappedValue
                position.reportVisible(id: id)
                binding.wrappedValue = position
            },
            undo: { [weak owner] in owner?[keyPath: tracking].lastReportedID = before })
    }

    /// Tells the position that the user scrolled it: its request is dropped
    /// and ``ScrollPosition/isPositionedByUser`` set, as SwiftUI does on the
    /// user's first scroll — only where that changes something, and not for
    /// the `id:` binding, which has no request to drop.
    package func reportPositionedByUser() {
        guard tracksUserPositioning else { return }
        var position = binding.wrappedValue
        guard position.target != nil || !position.isPositionedByUser else { return }
        position.reportPositionedByUser()
        binding.wrappedValue = position
    }
}
