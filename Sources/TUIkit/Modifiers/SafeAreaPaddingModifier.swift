//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SafeAreaPaddingModifier.swift
//
//  `safeAreaPadding`: padding for ordinary content, and a content margin for a
//  scroll view along the axes it scrolls.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Adds `insets` to the safe area of this view. Matches SwiftUI's
    /// `safeAreaPadding(_:)`.
    ///
    /// TUIkit has no safe area (decisions B6), so this is what SwiftUI's draws
    /// with the safe area resolved: ordinary content is laid out inside the
    /// insets, which is padding. A ``ScrollView`` — this view itself, or behind
    /// modifiers that only set the environment — extends into the safe area
    /// along the axes it scrolls and keeps its content out of it, so there the
    /// insets on those edges are content margins, scrolling with the content
    /// and adding to any `contentMargins(_:_:for:)`;
    /// across its axes they are padding. That is SwiftUI's geometry (measured:
    /// `safeAreaPadding(15)` on a vertical scroll view insets its content top
    /// and bottom and narrows the view itself by 30).
    ///
    /// Nested calls add up, as SwiftUI's do (measured).
    ///
    /// - Parameter insets: The insets, in cells.
    public func safeAreaPadding(_ insets: EdgeInsets) -> some View {
        _SafeAreaPadding(content: self, insets: insets)
    }

    /// Adds `length` cells to every edge of the safe area of this view.
    /// Matches SwiftUI's `safeAreaPadding(_:)`; see
    /// the `EdgeInsets` form.
    ///
    /// - Parameter length: The inset on every edge, in cells.
    public func safeAreaPadding(_ length: Int) -> some View {
        safeAreaPadding(EdgeInsets(all: length))
    }

    /// Adds `length` cells to `edges` of the safe area of this view. Matches
    /// SwiftUI's `safeAreaPadding(_:_:)`; see
    /// the `EdgeInsets` form.
    ///
    /// - Parameters:
    ///   - edges: The edges to add to.
    ///   - length: The inset, in cells; `nil` is the default padding, one
    ///     cell — what SwiftUI's default (16 points, measured) is to
    ///     ``padding(_:_:)``.
    public func safeAreaPadding(_ edges: Edge.Set = .all, _ length: Int? = nil) -> some View {
        let length = length ?? 1
        return safeAreaPadding(
            EdgeInsets(
                top: edges.contains(.top) ? length : 0,
                leading: edges.contains(.leading) ? length : 0,
                bottom: edges.contains(.bottom) ? length : 0,
                trailing: edges.contains(.trailing) ? length : 0))
    }
}

/// Splits a safe-area inset between the scroll view under it, if there is one,
/// and padding.
struct _SafeAreaPadding<Content: View>: View {
    let content: Content
    let insets: EdgeInsets

    var body: some View {
        // The axes are a run-time value of the scroll view, so it is asked; a
        // view that is not one answers none, and the insets are all padding.
        let axes = (content as? any ScrollsUnderSafeArea)?.safeAreaScrollAxes ?? []
        let along = EdgeInsets(
            top: axes.contains(.vertical) ? insets.top : 0,
            leading: axes.contains(.horizontal) ? insets.leading : 0,
            bottom: axes.contains(.vertical) ? insets.bottom : 0,
            trailing: axes.contains(.horizontal) ? insets.trailing : 0)
        let across = EdgeInsets(
            top: insets.top - along.top, leading: insets.leading - along.leading,
            bottom: insets.bottom - along.bottom, trailing: insets.trailing - along.trailing)
        content
            .transformEnvironment(\.safeAreaContentMargins) { $0 = $0.adding(along) }
            .padding(across)
    }
}

// MARK: - What extends into the safe area

/// A view whose frame is a scroll view's, so a safe area applied to it is the
/// scroll view's along the axes it scrolls: ``ScrollView`` itself, and a
/// modifier that only sets the environment of one.
///
/// A geometry-changing modifier between them — a frame, padding — is not one:
/// the scroll view under it does not reach the edges the safe area is on, and
/// SwiftUI insets it as ordinary content.
@MainActor
protocol ScrollsUnderSafeArea {
    var safeAreaScrollAxes: Axis.Set { get }
}

extension ScrollView: ScrollsUnderSafeArea {
    var safeAreaScrollAxes: Axis.Set { axes }
}

extension EnvironmentModifier: ScrollsUnderSafeArea where Content: ScrollsUnderSafeArea {
    var safeAreaScrollAxes: Axis.Set { content.safeAreaScrollAxes }
}

extension TransformEnvironmentModifier: ScrollsUnderSafeArea where Content: ScrollsUnderSafeArea {
    var safeAreaScrollAxes: Axis.Set { content.safeAreaScrollAxes }
}

extension _SafeAreaPadding: ScrollsUnderSafeArea where Content: ScrollsUnderSafeArea {
    var safeAreaScrollAxes: Axis.Set { content.safeAreaScrollAxes }
}

// MARK: - Environment

private struct SafeAreaContentMarginsKey: EnvironmentKey {
    static let defaultValue = EdgeInsets()
}

extension EnvironmentValues {
    /// The safe-area insets `safeAreaPadding` hands the
    /// scroll view under it, to keep its content out of — added to its content
    /// margins and to its indicators', and not passed on to its content.
    var safeAreaContentMargins: EdgeInsets {
        get { self[SafeAreaContentMarginsKey.self] }
        set { self[SafeAreaContentMarginsKey.self] = newValue }
    }
}

extension EdgeInsets {
    /// These insets and `other`, edge by edge.
    func adding(_ other: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: top + other.top, leading: leading + other.leading,
            bottom: bottom + other.bottom, trailing: trailing + other.trailing)
    }
}
