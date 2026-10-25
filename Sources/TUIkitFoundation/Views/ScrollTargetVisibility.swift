//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTargetVisibility.swift
//
//  `onScrollTargetVisibilityChange(idType:threshold:_:)`: the ids of the
//  views of a scroll view's content stack that it shows, reported when the
//  list changes.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

extension View {
    /// Adds an action to be called with information about what views would
    /// be considered visible.
    ///
    /// Use this modifier along with the modifier ``View/scrollTargetLayout(isEnabled:)``
    /// to be informed when the views in the targeted scroll view have crossed
    /// the provided threshold to be considered on or off screen.
    ///
    /// ```swift
    /// ScrollView {
    ///     LazyVStack {
    ///         ForEach(models) { model in
    ///             CardView(model: model)
    ///         }
    ///     }
    ///     .scrollTargetLayout()
    /// }
    /// .onScrollTargetVisibilityChange(idType: Model.ID.self, threshold: 0.2) { onScreenCards in
    ///     // Disable video playback for cards that are offscreen...
    /// }
    /// ```
    ///
    /// The views are the rows of the vertical stack, or the columns of the
    /// horizontal stack, that is the first scroll view's content below this
    /// modifier — at its origin, under its content margins or a `Section`'s
    /// header — each named as `.scrollPosition(id:)` names it: a `ForEach`
    /// row by its element's `id`, a view of the stack's own by its `.id(_:)`
    /// tag. One counts as shown when at least `threshold` of its length along
    /// the stack's axis is in the viewport, and at least a cell of it, at the
    /// offset the frame settled on; the action is called with the ids of
    /// those of type `ID`, in their order, once when the scroll view first
    /// draws and then whenever the list changes.
    ///
    /// The stack's rows are reported whether or not it is marked with
    /// `scrollTargetLayout()`, as `.scrollPosition` reads them back
    /// (deviation R6); SwiftUI asks for the mark. A row is measured along the
    /// stack's axis only, so a row of a two-axis view scrolled out sideways
    /// still counts as shown.
    ///
    /// - Parameters:
    ///   - idType: The type of the ids the views are named by.
    ///   - threshold: How much of a view, from 0 to 1, must be in the
    ///     viewport for it to count as shown.
    ///   - action: Called with the ids of the views shown.
    /// - Returns: A view that reports which of its scroll view's views it
    ///   shows.
    public func onScrollTargetVisibilityChange<ID: Hashable>(
        idType: ID.Type, threshold: Double = 0.5, _ action: @escaping ([ID]) -> Void
    ) -> some View {
        let observer = ScrollTargetVisibilityObserver(idType: idType, threshold: threshold, action: action)
        return transformEnvironment(\.scrollObservers) { $0.targetVisibility.append(observer) }
    }
}

/// One `onScrollTargetVisibilityChange`: its threshold, its action typed by
/// its ids, and the scroll view that has claimed it.
@MainActor
final class ScrollTargetVisibilityObserver {
    /// How much of a view must be shown for it to count.
    let threshold: Double

    /// Keeps the ids of the observer's type and compares them with the last
    /// list, keeping them; on a change — or on the first list — returns the
    /// action to take, and otherwise `nil`.
    private let report: ([AnyHashable], inout [AnyHashable]?) -> (() -> Void)?

    /// The scroll view this observer reports to — see
    /// ``ScrollGeometryObserver/claim(for:)``.
    private var claimant: ViewIdentity?

    init<ID: Hashable>(idType: ID.Type, threshold: Double, action: @escaping ([ID]) -> Void) {
        self.threshold = threshold
        report = { ids, last in
            let shown = ids.compactMap { $0 as? ID }
            let erased = shown.map { AnyHashable($0) }
            guard erased != last else { return nil }
            last = erased
            return { action(shown) }
        }
    }

    /// Whether the scroll view at `identity` reports to this observer: the
    /// first one to ask does, and only it.
    func claim(for identity: ViewIdentity) -> Bool {
        if let claimant { return claimant == identity }
        claimant = identity
        return true
    }

    /// Keeps `ids` in `last`, and returns what to do about a change — `nil`
    /// for none.
    func report(_ ids: [AnyHashable], last: inout [AnyHashable]?) -> (() -> Void)? {
        report(ids, &last)
    }
}

/// What the content's stack reported for the visibility observers on a
/// frame's drawing: its rows or its columns, in the scroll content's
/// coordinates, and how to name each.
struct ScrollTargetVisibilityReport {
    var rows: TargetLayoutSpans?
    var columns: TargetLayoutSpans?
    var ids: @MainActor (Int) -> AnyHashable?
}

extension _ScrollViewCore {
    /// Whether a visibility observer stated above this view asks its content
    /// for its stack's views (``ScrollContentWindow/reportsTargetVisibility``).
    func asksTargetVisibility(_ context: RenderContext) -> Bool {
        !context.isMeasuring && !pageScrollObservers(context.environment).targetVisibility.isEmpty
    }

    /// Keeps what the content's stack reported for the visibility observers
    /// on this drawing, for ``reportScrollTargetVisibility(handler:contentWidth:context:)``
    /// to measure once the offset is final. Render passes only.
    func recordTargetVisibility(_ reply: ScrollContentReply, handler: ScrollViewHandler) {
        guard let ids = reply.targetIDs else {
            handler.targetVisibility = nil
            return
        }
        handler.targetVisibility = ScrollTargetVisibilityReport(
            rows: reply.targetVisibleRows, columns: reply.targetVisibleColumns, ids: ids)
    }

    /// Tells the visibility observers this view has claimed which of its
    /// content's views it shows, when that changed. Render passes only, once
    /// the frame's offset is final (`finishFrame`).
    func reportScrollTargetVisibility(handler: ScrollViewHandler, contentWidth: Int, context: RenderContext) {
        let observers = pageScrollObservers(context.environment).targetVisibility
        guard !observers.isEmpty, !context.isMeasuring else { return }
        // A comparison a stored picture cannot make: see `OnGeometryChangeModifier`.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        if handler.targetVisibilityValues.count != observers.count {
            handler.targetVisibilityValues = Array(repeating: nil, count: observers.count)
        }
        let report = handler.targetVisibility
        for (index, observer) in observers.enumerated() where observer.claim(for: context.identity) {
            let ids =
                report.map {
                    Self.shownIDs(
                        $0, threshold: observer.threshold,
                        rows: handler.scrollOffset..<(handler.scrollOffset + handler.viewportHeight),
                        columns: handler.horizontal.scrollOffset..<(handler.horizontal.scrollOffset + contentWidth))
                } ?? []
            let before = handler.targetVisibilityValues[index]
            guard let action = observer.report(ids, last: &handler.targetVisibilityValues[index]) else { continue }
            // Held where this drawing may be drawn again, and the list put
            // back if it is (`EffectStage`).
            context.performEffect(action) { [weak handler] in
                guard let handler, handler.targetVisibilityValues.indices.contains(index) else { return }
                handler.targetVisibilityValues[index] = before
            }
        }
    }

    /// The ids of the views `report` holds that show at least `threshold`
    /// of themselves along their axis, and at least a cell: lines `rows` of
    /// the content for a vertical stack's rows, columns `columns` for a
    /// horizontal one's. A view of no length is shown whole when its place is
    /// in the window.
    static func shownIDs(
        _ report: ScrollTargetVisibilityReport, threshold: Double, rows: Range<Int>, columns: Range<Int>
    ) -> [AnyHashable] {
        let (spans, window) = report.rows.map { ($0, rows) } ?? (report.columns ?? .none, columns)
        guard !window.isEmpty else { return [] }
        var ids: [AnyHashable] = []
        for span in spans.spans(overlapping: window.lowerBound...(window.upperBound - 1)) where span.ordinal >= 0 {
            let fraction: Double
            if span.length > 0 {
                let end = min(span.origin + span.length, window.upperBound)
                let shown = end - max(span.origin, window.lowerBound)
                guard shown > 0 else { continue }
                fraction = Double(shown) / Double(span.length)
            } else {
                guard window.contains(span.origin) else { continue }
                fraction = 1
            }
            guard fraction >= threshold, let id = report.ids(span.ordinal) else { continue }
            ids.append(id)
        }
        return ids
    }
}
