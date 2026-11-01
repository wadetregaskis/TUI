//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollTargetBehavior.swift
//
//  SwiftUI's scroll target behaviours: where a user's scroll comes to rest.
//  The protocol and the values it is handed; the two built-in behaviours are in
//  `ScrollTargetBehaviors.swift`, and how each scrollable applies them beside
//  its own scrolling code.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - ScrollTarget

/// Where a scroll view should try to scroll to. Matches SwiftUI's type of the
/// same name, in cells.
///
/// A ``ScrollTargetBehavior`` is handed one and moves it. The scroll view then
/// scrolls so that ``rect`` is aligned to its visible region at ``anchor``.
public struct ScrollTarget: Hashable, Sendable {
    /// The rect that a scrollable view should try to have contained, in the
    /// scroll content's coordinates: line 0 is the content's first line,
    /// inside its content margins, as in SwiftUI (measured) — so a target at
    /// 0 is the view at its top, with the top margin above it.
    public var rect: CellRect

    /// The anchor to which ``rect`` should be aligned within the visible region
    /// of the scrollable view — `.top` puts its top edge at the top of the
    /// view, `.center` its centre at the centre. `nil` aligns its top-leading
    /// corner with the view's.
    public var anchor: UnitPoint?

    /// A target. Internal, as SwiftUI's has no public initializer: a behaviour
    /// is handed one to move.
    init(rect: CellRect, anchor: UnitPoint? = nil) {
        self.rect = rect
        self.anchor = anchor
    }
}

// MARK: - Contexts and properties

/// Properties influencing the scroll view a scroll target behaviour applies
/// to. Matches SwiftUI's type of the same name, which has no public members.
public struct ScrollTargetBehaviorProperties: Equatable, Sendable {
    /// Creates a default set of properties.
    public init() {}
}

/// The context in which a scroll target behaviour can decide its properties.
/// Matches SwiftUI's type of the same name.
public struct ScrollTargetBehaviorPropertiesContext {
    /// The scrollable axes of the scroll view.
    public let axes: Axis.Set

    /// The environment of the scroll view.
    public let environment: EnvironmentValues
}

/// The context in which a scroll target behaviour updates its target. Matches
/// SwiftUI's type of the same name, in cells.
///
/// A terminal's scroll gestures end at every step — a wheel tick, a key, a
/// scrollbar arrow — so each step is a gesture of its own: ``originalTarget``
/// is where the view was before the step, the target handed to
/// ``ScrollTargetBehavior/updateTarget(_:context:)`` is where the step would
/// land, and ``velocity`` is the step itself. Releasing a dragged scrollbar
/// thumb is a gesture that ends where it is, with no velocity.
@dynamicMemberLookup
public struct ScrollTargetBehaviorContext {
    /// Where the view was when the gesture began.
    public let originalTarget: ScrollTarget

    /// The gesture's velocity: the step, in cells — its sign is its direction,
    /// and a page is the viewport's height. Zero for a gesture that ends where
    /// it is (a released scrollbar thumb). SwiftUI's is points per second; a
    /// terminal's steps have no duration to measure one from.
    public let velocity: CellVector

    /// The size of the scroll view's content, without its content margins.
    public let contentSize: CellSize

    /// The size of the area the content is seen through: the viewport, less
    /// what the scroll bars take, less the "N more" lines, which a view under
    /// a behaviour reserves at every offset rather than drawing them over its
    /// content — so every line of it can be read — and less the content
    /// margins, as SwiftUI documents and does (measured). It is the container
    /// a `containerRelativeFrame` in the content sizes against.
    public let containerSize: CellSize

    /// The axes in which the scrollable view is scrollable.
    public let axes: Axis.Set

    /// The scroll view's environment.
    let environment: EnvironmentValues

    /// The views of the content's `scrollTargetLayout()`, down the vertical
    /// axis and across the horizontal one — what the view-aligned behaviour
    /// settles on. Empty where nothing is marked, or nothing reported its
    /// views.
    let targetLayoutRows: TargetLayoutSpans
    let targetLayoutColumns: TargetLayoutSpans

    /// How many lines the "N more" pair draws over the content at each edge
    /// it shows at — one where it comes and goes under `.paging`, else none
    /// (``ScrollViewTargeting/overwrittenEdgeLines``, a half of it): where
    /// the line before a page's first, under "▲", and the line after its
    /// last, under "▼", are.
    var edgeLines = 0

    /// Reads a value from the scroll view's environment.
    public subscript<T>(dynamicMember keyPath: KeyPath<EnvironmentValues, T>) -> T {
        environment[keyPath: keyPath]
    }
}

/// The extents of a `scrollTargetLayout()`'s views along one axis — the rows
/// of a marked stack — as its last frame laid them out, in the scroll
/// content's coordinates.
struct TargetLayoutSpans: Equatable, Sendable {
    /// One view: where it starts along the axis, and how long it is — and
    /// its ordinal among its stack's children, which names it to
    /// `onScrollTargetVisibilityChange` (`ScrollContentReply.targetIDs`), or
    /// `-1` where nothing names it.
    struct Span: Equatable, Sendable {
        var origin: Int
        var length: Int
        var ordinal = -1
    }

    /// Rows of one height at a constant pitch from `origin` — a uniform lazy
    /// stack, whose every row's place is arithmetic, drawn or not.
    struct Uniform: Equatable, Sendable {
        var origin: Int
        var pitch: Int
        var length: Int
        var total: Int
    }

    /// The vertical spans: uniform, or as placed.
    var uniform: Uniform?
    var placed: [Span] = []

    /// No spans: nothing marked, or nothing reported.
    static let none = Self()

    var isEmpty: Bool { uniform == nil && placed.isEmpty }

    /// Whether any span is longer than one: a row a page can cut.
    var hasSpansLongerThanOne: Bool {
        if let uniform { return uniform.length > 1 }
        return placed.contains { $0.length > 1 }
    }

    /// The spans that overlap `range`, in order.
    func spans(overlapping range: ClosedRange<Int>) -> [Span] {
        if let uniform, uniform.pitch > 0, uniform.total >= 1 {
            let first = max(0, (range.lowerBound - uniform.origin) / uniform.pitch - 1)
            let last = min(uniform.total - 1, (range.upperBound - uniform.origin) / uniform.pitch + 1)
            guard first <= last else { return [] }
            return (first...last).map {
                Span(origin: uniform.origin + $0 * uniform.pitch, length: uniform.length, ordinal: $0)
            }
        }
        return placed.filter {
            $0.origin <= range.upperBound && $0.origin + max(1, $0.length) > range.lowerBound
        }
    }

    /// These spans as content drawn `lines` further down sees them.
    func shifted(by lines: Int) -> Self {
        guard lines != 0 else { return self }
        var shifted = self
        shifted.uniform?.origin += lines
        shifted.placed = placed.map { Span(origin: $0.origin + lines, length: $0.length, ordinal: $0.ordinal) }
        return shifted
    }
}

// MARK: - The protocol

/// A type that defines where a scrollable view's scrolling comes to rest.
/// Matches SwiftUI's protocol of the same name.
///
/// A scroll view proposes where each scroll gesture would end, and the
/// behaviour can move that target. Apply one with
/// ``TUI/View/scrollTargetBehavior(_:)``:
///
/// ```swift
/// struct EveryFifthLine: ScrollTargetBehavior {
///     func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
///         target.rect.y = (target.rect.y + 2) / 5 * 5
///     }
/// }
///
/// ScrollView { … }.scrollTargetBehavior(EveryFifthLine())
/// ```
///
/// Here every step is a gesture: a wheel tick, an arrow or page key, a click
/// on a scrollbar arrow or the "N more" lines, and the release of a dragged
/// scrollbar thumb. Home and End go to the content's edges, and a programmatic
/// scroll (``ScrollViewProxy/scrollTo(_:anchor:)``, a `ScrollPosition`, the
/// reveal that follows the focus) is not a gesture, as in SwiftUI. Two
/// built-in behaviours: ``PagingScrollTargetBehavior`` and
/// ``ViewAlignedScrollTargetBehavior``.
///
/// Where it applies:
/// - ``ScrollView`` consults any behaviour, on both axes — after every step,
///   and when its viewport changes size, as SwiftUI's does, unless it rests at
///   an edge then.
/// - ``List`` and ``Table`` honour the two built-in ones: `.paging` makes every
///   step a page, and `.viewAligned` scrolls by whole rows. A behaviour of the
///   app's own is not consulted there — SwiftUI's `List` on macOS consults none
///   at all (measured; decisions-D2S B-D2S-2).
public protocol ScrollTargetBehavior {
    /// The properties of a scroll target behaviour.
    typealias Properties = ScrollTargetBehaviorProperties

    /// The context in which a scroll target behaviour decides its properties.
    typealias PropertiesContext = ScrollTargetBehaviorPropertiesContext

    /// The context in which a scroll target behaviour updates its target.
    typealias TargetContext = ScrollTargetBehaviorContext

    /// Updates the proposed target that a scrollable view should scroll to.
    ///
    /// Called when a scroll gesture ends, with where it would end. Change
    /// `target` to have the view come to rest somewhere else.
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext)

    /// The properties of this behaviour.
    func properties(context: PropertiesContext) -> Properties
}

extension ScrollTargetBehavior {
    /// The default properties.
    public func properties(context: PropertiesContext) -> Properties {
        Properties()
    }
}

// MARK: - AnyScrollTargetBehavior

/// A type-erased scroll target behaviour. Matches SwiftUI's type of the same
/// name.
public struct AnyScrollTargetBehavior: ScrollTargetBehavior {
    /// The behaviour this one wraps.
    public var base: any ScrollTargetBehavior

    /// Wraps `base`.
    public init(_ base: some ScrollTargetBehavior) {
        // Unwrapped, so a wrapper of a wrapper is one wrapper and a scrollable
        // can see which built-in behaviour it holds.
        self.base = (base as? Self)?.base ?? base
    }

    public func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        base.updateTarget(&target, context: context)
    }

    public func properties(context: PropertiesContext) -> Properties {
        base.properties(context: context)
    }
}

// MARK: - Environment

/// The behaviour in force when none was stated: the view rests where its steps
/// take it, a terminal line at a time.
///
/// A behaviour rather than an `Optional`'s `nil` so the environment value is
/// always one a memo can compare: a written value is comparable when its
/// dynamic type is `Equatable`, and `nil` has none.
struct _FreeScrollTargetBehavior: ScrollTargetBehavior, Equatable {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {}
}

/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct ScrollTargetBehaviorKey: EnvironmentKey {
    // Computed: a behaviour is not `Sendable` (SwiftUI's protocol is not), so a
    // stored default is refused.
    @usableFromInline static var defaultValue: any ScrollTargetBehavior { _FreeScrollTargetBehavior() }
}

extension EnvironmentValues {
    /// The scroll target behaviour of the scrollables in this subtree — see
    /// ``TUI/View/scrollTargetBehavior(_:)``.
    ///
    /// Internal, as SwiftUI exposes the modifier and not the value. The value
    /// written is the behaviour itself, so a memo below compares it by its own
    /// `==` when it has one (both built-in behaviours do) and declines to
    /// keep anything when it has not, which is the safe direction for a
    /// behaviour of an app's own.
    @inlinable
    package var scrollTargetBehavior: any ScrollTargetBehavior {
        get { self[ScrollTargetBehaviorKey.self] }
        set { self[ScrollTargetBehaviorKey.self] = newValue }
    }
}

extension View {
    /// Sets the scroll behaviour of the views scrollable in this view. Matches
    /// SwiftUI's modifier of the same name.
    ///
    /// ```swift
    /// ScrollView(.horizontal) {
    ///     LazyHStack { ForEach(pages) { PageView($0) } }
    /// }
    /// .scrollTargetBehavior(.paging)
    ///
    /// List(messages) { … }
    ///     .scrollTargetBehavior(.viewAligned)
    /// ```
    ///
    /// See ``ScrollTargetBehavior`` for where it applies, and
    /// ``TUI/View/scrollGranularity(_:)`` to take a subtree back to the
    /// default, line-by-line scrolling.
    ///
    /// A `ScrollView` under a behaviour other than the default draws its "N
    /// more" lines (`.scrollIndicatorStyle(.text)`) at every offset, keeping
    /// them out of the content as `.scrollIndicators(.visible)` does, so the
    /// window it lands pages and views in is the same at every stop.
    ///
    /// - Parameter behavior: The scroll behaviour to use.
    /// - Returns: A view whose scrollables use `behavior`.
    public func scrollTargetBehavior(_ behavior: some ScrollTargetBehavior) -> some View {
        // The base of a type-erased behaviour, so a memo compares the behaviour
        // itself and the scrollables see which built-in one it is.
        let unwrapped: any ScrollTargetBehavior = (behavior as? AnyScrollTargetBehavior)?.base ?? behavior
        return environment(\.scrollTargetBehavior, unwrapped)
    }
}

// MARK: - The target layout

private struct ScrollTargetLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the stack this reaches is a scroll target layout — see
    /// ``TUI/View/scrollTargetLayout(isEnabled:)``. Read by the stack that
    /// consumes a scroll view's window, when the window asks for its rows.
    ///
    /// A scroll view's content starts unmarked (`contentContext`): a mark
    /// stated around an outer scroll view's content is not one on a scroll
    /// view nested in it.
    var isScrollTargetLayout: Bool {
        get { self[ScrollTargetLayoutKey.self] }
        set { self[ScrollTargetLayoutKey.self] = newValue }
    }
}

extension View {
    /// Marks this layout's children as the views a scroll view settles on and
    /// reads its position from. Matches SwiftUI's
    /// `scrollTargetLayout(isEnabled:)`.
    ///
    /// Apply it to the stack that is a scroll view's content:
    ///
    /// ```swift
    /// ScrollView {
    ///     LazyVStack {
    ///         ForEach(items) { ItemView($0) }
    ///     }
    ///     .scrollTargetLayout()
    /// }
    /// .scrollTargetBehavior(.viewAligned)
    /// .scrollPosition(id: $topItem)
    /// ```
    ///
    /// Its reader is ``ViewAlignedScrollTargetBehavior``, which settles on the
    /// marked stack's rows and has nothing to settle on without the mark, as in
    /// SwiftUI. SwiftUI's `.scrollPosition(id:)` and ``ScrollPosition`` need
    /// the mark too; TUI reports the rows of the content's vertical stack,
    /// and the columns of a horizontal one in a scroll view that scrolls only
    /// across, lazy or eager, to those whether or not they are marked
    /// (``ScrollPosition/viewID(type:)`` says which content that is), so there
    /// the common pairing reads back as it does in SwiftUI with or without it
    /// (decisions B29).
    ///
    /// The views found are the rows of a vertical stack and the columns of a
    /// horizontal one — lazy or eager — that is the scroll view's content, or
    /// the content under a `Section`'s header or inside the content margins.
    /// A stack further in (below a header in a `VStack`, say) is not found.
    ///
    /// - Parameter isEnabled: Whether the mark applies.
    /// - Returns: A view whose stack is, or is not, a scroll target layout.
    public func scrollTargetLayout(isEnabled: Bool = true) -> some View {
        environment(\.isScrollTargetLayout, isEnabled)
    }
}
