//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollTargetBehaviors.swift
//
//  SwiftUI's two built-in scroll target behaviours: paging, and settling on the
//  views of a `scrollTargetLayout()`.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Paging

/// The scroll behaviour that aligns scroll targets to container-based
/// geometry: every gesture comes to rest a whole page from the top. Matches
/// SwiftUI's type of the same name.
///
/// A page is the visible area: the viewport, less what the scroll bars take,
/// less the "N more" lines, which a paging view keeps out of the content at
/// every offset — so every line is read at some page, as with Page Down — and
/// less the content margins, inside which every page lands. So a page sized
/// with `containerRelativeFrame` is the page a step moves. (SwiftUI's page is
/// the container plus half the top or leading margin, measured, which no
/// container-sized page matches: not copied, decisions B-SCROLL-1.)
/// Here a gesture is a step — a wheel tick, an arrow key, a scrollbar arrow —
/// so every step moves to the next page boundary in its direction, however
/// small it is, and a step further than a page (Page Down past an unaligned
/// position) goes to the boundary at or past it. The content's last page ends
/// at its end, as it does in SwiftUI, so the last boundary is the bottom.
///
/// Over a `scrollTargetLayout()`'s rows a page never cuts a row (owner,
/// 2026-10-26: "never a row cut off"): a step goes to the row the page it
/// leaves could not hold whole, which the scroll view draws blank below the
/// last whole row, so that row starts the next page — and back, to the
/// earliest row the page before can hold whole. A row taller than a page is
/// stepped through a page at a time.
///
/// In a ``List`` or ``Table`` each step moves a page from where the view is,
/// as Page Down does: their rows are not cells of one canvas a boundary could
/// be measured on.
public struct PagingScrollTargetBehavior: ScrollTargetBehavior, Equatable, Sendable {
    /// Creates a paging scroll behaviour.
    public init() {}

    /// The default properties: SwiftUI's have no public members.
    public func properties(context: PropertiesContext) -> Properties { Properties() }

    public func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        if context.axes.contains(.vertical) {
            let end = context.contentSize.height - context.containerSize.height
            target.rect.y =
                Self.rowPaged(
                    target.rect.y, from: context.originalTarget.rect.y, page: context.containerSize.height,
                    edgeLines: context.edgeLines, rows: context.targetLayoutRows, end: end)
                ?? Self.paged(
                    target.rect.y, from: context.originalTarget.rect.y, page: context.containerSize.height, end: end)
        }
        if context.axes.contains(.horizontal) {
            target.rect.x = Self.paged(
                target.rect.x, from: context.originalTarget.rect.x, page: context.containerSize.width,
                end: context.contentSize.width - context.containerSize.width)
        }
    }

    /// Where a gesture from `original` that would end at `proposed` rests:
    /// at least the next page boundary in its direction, and the boundary at
    /// or past `proposed`; the nearest boundary for one with no direction.
    ///
    /// `end` is where the last page begins — the content's end less a page —
    /// and is a boundary too. A step reaches it anyway, since the scroll stops
    /// there; a gesture with no direction has to be told, or a thumb released
    /// at the end, a resize or a step along the other axis took a view at its
    /// tail back to the multiple of the page before it.
    static func paged(_ proposed: Int, from original: Int, page: Int, end: Int) -> Int {
        guard page > 0 else { return proposed }
        func boundary(atOrBelow offset: Int) -> Int {
            Int((Double(offset) / Double(page)).rounded(.down)) * page
        }
        func boundary(atOrAbove offset: Int) -> Int {
            Int((Double(offset) / Double(page)).rounded(.up)) * page
        }
        if proposed > original {
            return max(boundary(atOrBelow: original) + page, boundary(atOrAbove: proposed))
        }
        if proposed < original {
            return min(boundary(atOrAbove: original) - page, boundary(atOrBelow: proposed))
        }
        let nearest = Int((Double(original) / Double(page)).rounded(.toNearestOrAwayFromZero)) * page
        return end > 0 && abs(end - original) < abs(nearest - original) ? end : nearest
    }
}

// MARK: - Paging over rows

extension PagingScrollTargetBehavior {
    /// Where a gesture from `original` that would end at `proposed` rests
    /// over `rows`, a page at a time and never cutting a row, or `nil` where
    /// no row is taller than a line — no page can cut one, and the steps are
    /// whole pages, as with no rows — or the gesture has no direction.
    ///
    /// A page shown from offset `o` reads the lines from `o` — from `o` plus
    /// `edgeLines` below the first page, under "▲" — up to `o + page +
    /// edgeLines`, where "▼" is. The row that line falls inside is the one the
    /// page cuts, and the scroll view draws it blank
    /// (`ScrollView.blankingRowCutByPage`).
    static func rowPaged(
        _ proposed: Int, from original: Int, page: Int, edgeLines: Int, rows: TargetLayoutSpans, end: Int
    ) -> Int? {
        guard page > 0, rows.hasSpansLongerThanOne, proposed != original else { return nil }
        var offset = original
        if proposed > original {
            repeat { offset = pageAfter(offset, page: page, edgeLines: edgeLines, rows: rows) } while offset < proposed
                && offset < end
        } else {
            repeat { offset = pageBefore(offset, page: page, edgeLines: edgeLines, rows: rows) } while offset > proposed
                && offset > 0
        }
        return offset
    }

    /// The row a page shown from `offset` cuts: the one its last line read
    /// falls inside, where it starts below the page's first line read — or
    /// `nil` for none, where a row ends with the page or one taller than the
    /// page fills it.
    static func rowCut(at offset: Int, page: Int, edgeLines: Int, rows: TargetLayoutSpans) -> TargetLayoutSpans.Span? {
        let first = offset + (offset > 0 ? edgeLines : 0)
        let pastLast = offset + page + edgeLines
        return rows.spans(overlapping: (pastLast - 1)...pastLast).first { row in
            row.origin > first && row.origin < pastLast && row.origin + row.length > pastLast
        }
    }

    /// The offset of the page after the one shown from `offset`: the row it
    /// cut, read first under "▲"; a page on where it cut none.
    private static func pageAfter(_ offset: Int, page: Int, edgeLines: Int, rows: TargetLayoutSpans) -> Int {
        guard let cut = rowCut(at: offset, page: page, edgeLines: edgeLines, rows: rows) else { return offset + page }
        return max(offset + 1, cut.origin - edgeLines)
    }

    /// The offset of the page before the one shown from `offset`: the
    /// earliest row a page ending where this one's first line read begins can
    /// hold whole, read first under "▲" — the top, where that page would
    /// reach it; a page back where no row starts in it.
    private static func pageBefore(_ offset: Int, page: Int, edgeLines: Int, rows: TargetLayoutSpans) -> Int {
        let first = offset + (offset > 0 ? edgeLines : 0)
        // The first page reads a line more: from the top, no "▲" above it.
        if first <= page + edgeLines { return 0 }
        let earliest = first - page
        let starts = rows.spans(overlapping: earliest...first).map(\.origin).filter { $0 >= earliest && $0 < first }
        guard let start = starts.min() else { return max(0, offset - page) }
        return min(max(0, start - edgeLines), offset - 1)
    }
}

extension ScrollTargetBehavior where Self == PagingScrollTargetBehavior {
    /// The scroll behaviour that aligns scroll targets to container-based
    /// geometry. See ``PagingScrollTargetBehavior``.
    public static var paging: PagingScrollTargetBehavior { PagingScrollTargetBehavior() }
}

// MARK: - View-aligned

/// The scroll behaviour that aligns scroll targets to view-based geometry:
/// every gesture comes to rest with one of the views of the content's
/// ``TUI/View/scrollTargetLayout(isEnabled:)`` aligned to the visible area.
/// Matches SwiftUI's type of the same name.
///
/// ```swift
/// ScrollView {
///     LazyVStack {
///         ForEach(messages) { MessageView($0) }
///     }
///     .scrollTargetLayout()
/// }
/// .scrollTargetBehavior(.viewAligned)
/// ```
///
/// A step moves to the furthest view in its direction that it reaches, and at
/// least to the next one, so a wheel tick over three-line rows moves a whole
/// row. A gesture with no direction — a released scrollbar thumb, a resize, a
/// step along the other axis — rests on the nearest view, or on the content's
/// end when that is nearer, since the scroll stops there. The `anchor` says
/// which point of the view meets which point of the visible area: the top edge
/// by default, the centre for `.center`.
///
/// Where it finds the views:
/// - In a ``ScrollView``, the rows of a vertical stack and the columns of a
///   horizontal one marked with `scrollTargetLayout()` — lazy or not — that is
///   the content, or the content under a `Section`'s header or inside its
///   content margins. As in SwiftUI, without the mark there is nothing to
///   align to, and the view scrolls freely.
/// - In a ``List`` or ``Table``, its rows, marked or not: the view scrolls a
///   whole row at a time, the top row whole, at the top whatever the anchor
///   (decisions-D2S B-D2S-3).
public struct ViewAlignedScrollTargetBehavior: ScrollTargetBehavior, Equatable, Sendable {
    /// How many views one gesture may scroll past. Matches SwiftUI's type of
    /// the same name.
    public struct LimitBehavior: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case automatic, always, alwaysByFew, alwaysByOne, never
        }

        let kind: Kind

        /// Limited along an axis whose size class is compact — as SwiftUI's
        /// is — and not otherwise. TUI never sets a size class, so this is
        /// `.never` unless the app makes one compact.
        public static var automatic: Self { Self(kind: .automatic) }

        /// Always limited: a gesture scrolls at most a screenful of views.
        public static var always: Self { Self(kind: .always) }

        /// Limited to a few views a gesture — three, the rows one wheel tick
        /// moves.
        public static var alwaysByFew: Self { Self(kind: .alwaysByFew) }

        /// Limited to one view a gesture.
        public static var alwaysByOne: Self { Self(kind: .alwaysByOne) }

        /// Never limited.
        public static var never: Self { Self(kind: .never) }
    }

    /// How many views a gesture may scroll past.
    let limitBehavior: LimitBehavior

    /// Which point of a view is aligned with the same point of the visible
    /// area; `nil` is the top-leading corner.
    let anchor: UnitPoint?

    /// Creates a view-aligned scroll behaviour.
    public init(limitBehavior: LimitBehavior = .automatic) {
        self.init(limitBehavior: limitBehavior, anchor: nil)
    }

    /// Creates a view-aligned scroll behaviour that aligns at `anchor`.
    public init(anchor: UnitPoint?) {
        self.init(limitBehavior: .automatic, anchor: anchor)
    }

    /// Creates a view-aligned scroll behaviour with both settings.
    public init(limitBehavior: LimitBehavior, anchor: UnitPoint?) {
        self.limitBehavior = limitBehavior
        self.anchor = anchor
    }

    /// The default properties: SwiftUI's have no public members.
    public func properties(context: PropertiesContext) -> Properties { Properties() }

    public func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let anchor = self.anchor ?? .topLeading
        var aligned = false
        if context.axes.contains(.vertical),
            let span = Self.settle(
                proposed: target.rect.y, original: context.originalTarget.rect.y,
                container: context.containerSize.height, unit: anchor.y,
                spans: context.targetLayoutRows,
                limit: limit(compact: context.environment.verticalSizeClass == .compact),
                end: context.contentSize.height - context.containerSize.height)
        {
            target.rect.y = span.origin
            target.rect.height = span.length
            aligned = true
        }
        if context.axes.contains(.horizontal),
            let span = Self.settle(
                proposed: target.rect.x, original: context.originalTarget.rect.x,
                container: context.containerSize.width, unit: anchor.x,
                spans: context.targetLayoutColumns,
                limit: limit(compact: context.environment.horizontalSizeClass == .compact),
                end: context.contentSize.width - context.containerSize.width)
        {
            target.rect.x = span.origin
            target.rect.width = span.length
            aligned = true
        }
        if aligned { target.anchor = anchor }
    }

    /// How far one gesture may go, in views or in screenfuls.
    package enum Limit: Equatable {
        case views(Int)
        case screenful
    }

    /// This behaviour's limit along an axis whose size class is, or is not,
    /// compact; `nil` for none.
    package func limit(compact: Bool) -> Limit? {
        switch limitBehavior.kind {
        case .automatic: compact ? .screenful : nil
        case .always: .screenful
        case .alwaysByFew: .views(ViewConstants.mouseWheelScrollLines)
        case .alwaysByOne: .views(1)
        case .never: nil
        }
    }

    /// The view a gesture from `original` that would end at `proposed` rests
    /// on, along one axis, or `nil` when there is none to rest on.
    ///
    /// Each view rests where its `unit` point meets the visible area's (its
    /// LANDING). A gesture moving forward rests on the furthest landing it
    /// reaches, and at least on the first one past `original`; backward, the
    /// same the other way; one with no direction, on the nearest.
    ///
    /// `end`, where the visible area meets the content's end, is a resting
    /// place for a gesture with no direction too, as it is for `.paging`: the
    /// scroll stops there, so a view whose landing is past it rests there
    /// anyway. Without it a two-axis view at its tail went to the nearest
    /// row's top on a Left key — off the tail it was following — and a thumb
    /// released at the end did the same. It comes back as a span the visible
    /// area's size at `end`, which lands there whatever the anchor.
    static func settle(
        proposed: Int, original: Int, container: Int, unit: Double,
        spans: TargetLayoutSpans, limit: Limit?, end: Int
    ) -> TargetLayoutSpans.Span? {
        guard !spans.isEmpty, container > 0 else { return nil }
        let reach = (min(original, proposed) - 2 * container)...(max(original, proposed) + 2 * container)
        // Typed, and sorted in place: inferred as one `map`-then-`sorted`
        // chain, this needed over 3,000 solver scopes to type-check.
        typealias Landing = (landing: Int, span: TargetLayoutSpans.Span)
        var landings: [Landing] = spans.spans(overlapping: reach).map { (span: TargetLayoutSpans.Span) -> Landing in
            let offset: Double = unit * Double(span.length - container)
            return (landing: span.origin + Int(offset.rounded(.down)), span: span)
        }
        landings.sort { (a: Landing, b: Landing) -> Bool in a.landing < b.landing }
        guard !landings.isEmpty else { return nil }
        if proposed == original {
            let nearest = landings.min { abs($0.landing - proposed) < abs($1.landing - proposed) }
            if end > 0, let nearest, abs(end - proposed) < abs(nearest.landing - proposed) {
                return TargetLayoutSpans.Span(origin: end, length: container)
            }
            return nearest?.span
        }
        let forward = proposed > original
        // In the gesture's direction, nearest first.
        let ahead =
            forward
            ? landings.filter { $0.landing > original }
            : landings.filter { $0.landing < original }.reversed()
        guard let first = ahead.first else { return nil }
        let reached = ahead.last { forward ? $0.landing <= proposed : $0.landing >= proposed } ?? first
        var pick = reached
        switch limit {
        case .views(let count):
            let allowed = ahead[min(count, ahead.count) - 1]
            if forward ? allowed.landing < pick.landing : allowed.landing > pick.landing { pick = allowed }
        case .screenful:
            let bound = forward ? original + container : original - container
            let within = ahead.last { forward ? $0.landing <= bound : $0.landing >= bound } ?? first
            if forward ? within.landing < pick.landing : within.landing > pick.landing { pick = within }
        case nil:
            break
        }
        return pick.span
    }
}

extension ScrollTargetBehavior where Self == ViewAlignedScrollTargetBehavior {
    /// The scroll behaviour that aligns scroll targets to view-based geometry.
    /// See ``ViewAlignedScrollTargetBehavior``.
    public static var viewAligned: ViewAlignedScrollTargetBehavior { ViewAlignedScrollTargetBehavior() }

    /// The view-aligned behaviour, aligning each view at `anchor`.
    public static func viewAligned(anchor: UnitPoint?) -> Self {
        ViewAlignedScrollTargetBehavior(anchor: anchor)
    }

    /// The view-aligned behaviour, limiting how many views a gesture scrolls.
    public static func viewAligned(limitBehavior: ViewAlignedScrollTargetBehavior.LimitBehavior) -> Self {
        ViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior)
    }

    /// The view-aligned behaviour with both settings.
    public static func viewAligned(
        limitBehavior: ViewAlignedScrollTargetBehavior.LimitBehavior, anchor: UnitPoint?
    ) -> Self {
        ViewAlignedScrollTargetBehavior(limitBehavior: limitBehavior, anchor: anchor)
    }
}
