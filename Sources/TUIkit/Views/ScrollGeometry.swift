//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollGeometry.swift
//
//  Where a scroll view is in its content, in the terms SwiftUI hands
//  `onScrollGeometryChange` and `onScrollPhaseChange`.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

// MARK: - ScrollGeometry

/// The geometry of a scroll view: how big its content is, where it is
/// scrolled to, and how much of it shows. Matches SwiftUI's type of the same
/// name, in cells.
///
/// The readings are SwiftUI's, measured on macOS 15:
///
/// - ``contentOffset`` is where the scroll view is in its content. Content
///   margins sit before the content's origin, so scrolled to the top with a
///   top margin of 2 it is `y: -2`; pushed past an edge
///   (``View/scrollOverscroll(top:bottom:)``) it goes further out, as
///   SwiftUI's does while rubber-banding.
/// - ``contentSize`` is the content's own size, margins not included.
/// - ``contentInsets`` are the content margins (and a `safeAreaPadding` along
///   the scrolling axes).
/// - ``containerSize`` is the area the content is seen through, less those
///   insets. Here that area is the viewport less what the scroll indicators
///   take — a bar's column or row, the "N more" lines when they are reserved —
///   since a terminal's bars are cells of the viewport, not overlays.
///
/// So `contentOffset.y + containerSize.height + contentInsets.bottom` reaches
/// `contentSize.height + contentInsets.bottom` exactly at the bottom.
public struct ScrollGeometry: Equatable, Sendable {
    /// Where the scroll view is in its content: the column and row of the
    /// content at the top-leading corner of ``bounds``.
    public var contentOffset: CellPoint

    /// The size of the content, without its margins.
    public var contentSize: CellSize

    /// The content's margins: the space kept around it inside the scrollable
    /// area.
    public var contentInsets: EdgeInsets

    /// The size of the area the content is seen through, less
    /// ``contentInsets``.
    public var containerSize: CellSize

    /// Creates a scroll geometry.
    public init(
        contentOffset: CellPoint, contentSize: CellSize, contentInsets: EdgeInsets,
        containerSize: CellSize
    ) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
    }

    /// The part of the content inside the insets: ``containerSize`` at
    /// ``contentOffset``. SwiftUI's, measured: the origin is the offset itself.
    public var bounds: CellRect {
        CellRect(
            x: contentOffset.x, y: contentOffset.y,
            width: containerSize.width, height: containerSize.height)
    }

    /// The part of the content on screen: the whole visible area, insets
    /// included, at ``contentOffset``.
    public var visibleRect: CellRect {
        CellRect(
            x: contentOffset.x, y: contentOffset.y,
            width: containerSize.width + contentInsets.leading + contentInsets.trailing,
            height: containerSize.height + contentInsets.top + contentInsets.bottom)
    }
}

extension ScrollGeometry: CustomDebugStringConvertible {
    public var debugDescription: String {
        "ScrollGeometry(contentOffset: (\(contentOffset.x), \(contentOffset.y)), "
            + "contentSize: \(contentSize.width)×\(contentSize.height), "
            + "contentInsets: (top: \(contentInsets.top), leading: \(contentInsets.leading), "
            + "bottom: \(contentInsets.bottom), trailing: \(contentInsets.trailing)), "
            + "containerSize: \(containerSize.width)×\(containerSize.height))"
    }
}

// MARK: - onScrollGeometryChange

extension View {
    /// Calls `action` when a value derived from the geometry of the first
    /// scroll view in this hierarchy changes. Matches SwiftUI's
    /// `onScrollGeometryChange(for:of:action:)`.
    ///
    /// ```swift
    /// ScrollView { … }
    ///     .onScrollGeometryChange(for: Bool.self) { geometry in
    ///         geometry.contentOffset.y < geometry.contentInsets.top
    ///     } action: { _, isBeyondTop in
    ///         showsTopShadow = isBeyondTop
    ///     }
    /// ```
    ///
    /// As in SwiftUI (measured): the action runs once when the scroll view first
    /// draws — with the same value as old and new — and then whenever the
    /// derived value changes. Only the first scroll view below this modifier
    /// reports to it: one inside that scroll view's content does not, and of
    /// two side by side, the one drawn first does.
    ///
    /// It runs as the scroll view draws, after the frame's scrolling has
    /// settled, so a state change it makes is seen on the next frame.
    ///
    /// - Parameters:
    ///   - type: The type of the derived value.
    ///   - transform: Derives the value from the scroll view's geometry.
    ///   - action: Receives the old and the new value.
    public func onScrollGeometryChange<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (ScrollGeometry) -> T,
        action: @escaping (T, T) -> Void
    ) -> some View {
        let observer = ScrollGeometryObserver(transform: transform, action: action)
        return transformEnvironment(\.scrollObservers) { $0.geometry.append(observer) }
    }
}

// MARK: - Observers

/// The scroll observers stated above a view, for the first scroll view below
/// them to report to — and to take, so that its content's scroll views do not.
///
/// Compared by how many there are, not by what they are: a new observer is
/// made with every evaluation of the body that states it, so identity would
/// call every frame a change and turn the memos below it off. Nothing between
/// the statement and the scroll view draws differently for a different
/// observer, and the scroll view that reports to them declares the report as a
/// render side effect, so no memo above it keeps a picture that skipped one.
struct ScrollObservers: Equatable {
    var geometry: [ScrollGeometryObserver] = []

    var isEmpty: Bool { geometry.isEmpty }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.geometry.count == rhs.geometry.count
    }
}

/// One `onScrollGeometryChange`: its transform and action, type-erased, and
/// the scroll view that has claimed it.
@MainActor
final class ScrollGeometryObserver {
    /// Derives the value, compares it with the last one, and acts on a change
    /// — or on the first value, as old and new.
    private let report: (ScrollGeometry, inout Any?) -> Void

    /// The scroll view this observer reports to: the first to draw with it.
    /// See ``claim(for:)``.
    private var claimant: ViewIdentity?

    init<T: Equatable>(
        transform: @escaping (ScrollGeometry) -> T, action: @escaping (T, T) -> Void
    ) {
        report = { geometry, last in
            let value = transform(geometry)
            guard let previous = last as? T else {
                last = value
                action(value, value)
                return
            }
            guard previous != value else { return }
            last = value
            action(previous, value)
        }
    }

    /// Whether the scroll view at `identity` reports to this observer: the
    /// first one to ask does, and only it, for as long as this observer is the
    /// one stated — a new one is made with the body that states it.
    func claim(for identity: ViewIdentity) -> Bool {
        if let claimant { return claimant == identity }
        claimant = identity
        return true
    }

    func report(_ geometry: ScrollGeometry, last: inout Any?) {
        report(geometry, &last)
    }
}

private struct ScrollObserversKey: EnvironmentKey {
    static let defaultValue = ScrollObservers()
}

extension EnvironmentValues {
    /// The scroll observers stated above this view — see ``ScrollObservers``.
    var scrollObservers: ScrollObservers {
        get { self[ScrollObserversKey.self] }
        set { self[ScrollObserversKey.self] = newValue }
    }
}

// MARK: - The scroll view's side

extension _ScrollViewCore {
    /// What a render does once its frame is settled: records the tail it shows,
    /// for the next frame's glue to be judged by, and tells the scroll
    /// observers where the view now is. Render passes only.
    func finishFrame(
        _ handler: ScrollViewHandler, contentWidth: Int, viewportHeight: Int, context: RenderContext
    ) {
        guard !context.isMeasuring else { return }
        handler.tailAsLastDrawn = handler.maxOffset
        reportScrollGeometry(
            handler: handler, contentWidth: contentWidth, viewportHeight: viewportHeight,
            context: context)
    }

    /// This view's geometry as the frame left it, from the content width and
    /// viewport height the render settled on.
    func scrollGeometry(
        handler: ScrollViewHandler, contentWidth: Int, viewportHeight: Int, context: RenderContext
    ) -> ScrollGeometry {
        let insets = resolvedContentMargins(context.environment)
        let across = insets.leading + insets.trailing
        let along = insets.top + insets.bottom
        // A view that does not scroll horizontally lays its content out at the
        // width it shows it, and that is its width.
        let contentWidthTotal = axes.contains(.horizontal) ? handler.horizontal.extent : contentWidth
        let horizontalOffset = axes.contains(.horizontal) ? handler.horizontal.scrollOffset : 0
        return ScrollGeometry(
            contentOffset: CellPoint(
                x: horizontalOffset - insets.leading,
                y: handler.scrollOffset + handler.overscrollState.excursion - insets.top),
            contentSize: CellSize(
                width: max(0, contentWidthTotal - across),
                height: max(0, handler.contentHeight - along)),
            contentInsets: insets,
            containerSize: CellSize(
                width: max(0, contentWidth - across), height: max(0, viewportHeight - along)))
    }

    /// Reports this frame's geometry to the `onScrollGeometryChange` observers
    /// stated above this view that it has claimed. Render passes only.
    func reportScrollGeometry(
        handler: ScrollViewHandler, contentWidth: Int, viewportHeight: Int, context: RenderContext
    ) {
        let observers = context.environment.scrollObservers.geometry
        guard !observers.isEmpty, !context.isMeasuring else { return }
        // A comparison a stored picture cannot make: see `OnGeometryChangeModifier`.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let geometry = scrollGeometry(
            handler: handler, contentWidth: contentWidth, viewportHeight: viewportHeight,
            context: context)
        if handler.geometryObserverValues.count != observers.count {
            handler.geometryObserverValues = Array(repeating: nil, count: observers.count)
        }
        for (index, observer) in observers.enumerated() where observer.claim(for: context.identity) {
            observer.report(geometry, last: &handler.geometryObserverValues[index])
        }
    }
}
