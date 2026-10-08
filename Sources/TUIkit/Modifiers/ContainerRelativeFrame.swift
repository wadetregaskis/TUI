//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContainerRelativeFrame.swift
//
//  `containerRelativeFrame`: a frame sized relative to the nearest container —
//  the window's content area, a scroll view's viewport, a list's — rather than
//  to whatever the view was proposed. Containers publish their size into the
//  environment; the modifier reads it and becomes a fixed frame on the axes it
//  names.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

private struct ContainerRelativeSizeKey: EnvironmentKey {
    static let defaultValue: CellSize? = nil
}

extension EnvironmentValues {
    /// The size of the nearest container — the window's content area, a scroll
    /// view's or a list's viewport — or `nil` outside every one.
    ///
    /// A frame is not a container (measured in SwiftUI: inside a
    /// `.frame(width: 120)` in a 200-wide window a quarter is still 50), so
    /// only the containers SwiftUI names publish it. There is no safe area to
    /// subtract (decisions B6).
    ///
    /// `@usableFromInline`: the `@inlinable`
    /// ``RenderContext/publishingContainerSize(_:noting:)`` sets it and names
    /// its key path (module split step A3).
    @usableFromInline
    var containerRelativeSize: CellSize? {
        get { self[ContainerRelativeSizeKey.self] }
        set { self[ContainerRelativeSizeKey.self] = newValue }
    }
}

extension RenderContext {
    /// This context with ``EnvironmentValues/containerRelativeSize`` set to
    /// `size`, for a container to hand its content.
    ///
    /// Noted with the render cache as an applied environment value, the way
    /// `GeometryReader` notes its size: unlike a stack's axis, a container's
    /// size changes between frames (a resize, a divider dragged), and a
    /// memoized subtree below that read the old one has to be dropped.
    ///
    /// Noted only by a render that draws (`noting`), for `GeometryReader`'s
    /// reason: the cache answers a slot once per pass, so a measure offered
    /// some other size would be the one compared from frame to frame.
    ///
    /// `@inlinable` (module split step A3): every container that hands its
    /// content a size calls it, in modules that leave the substrate from B5.
    @inlinable
    func publishingContainerSize(_ size: CellSize, noting: Bool = true) -> Self {
        var copy = self
        copy.environment.containerRelativeSize = size
        copy.environmentApplicationDepth += 1
        if noting, !isMeasuring, let cache = renderCache,
            case .changed = cache.noteAppliedEnvironment(
                size, identity: identity, keyPath: \EnvironmentValues.containerRelativeSize,
                depth: copy.environmentApplicationDepth)
        {
            cache.clearAffected(by: identity)
        }
        return copy
    }
}

/// A fixed frame on `axes`, each as long as `length` makes of the nearest
/// container's extent along it.
struct _ContainerRelativeFrame<Content: View>: View {
    let content: Content
    let axes: Axis.Set
    let alignment: Alignment
    let length: (Int, Axis) -> Int

    @Environment(\.containerRelativeSize) private var container

    var body: some View {
        // Outside every container — a view rendered on its own, with no scene
        // around it — there is nothing to be relative to, and the view keeps
        // the size it was proposed.
        content.frame(
            width: container.flatMap { axes.contains(.horizontal) ? max(0, length($0.width, .horizontal)) : nil },
            height: container.flatMap { axes.contains(.vertical) ? max(0, length($0.height, .vertical)) : nil },
            alignment: alignment)
    }
}

extension View {
    /// Positions this view within an invisible frame the size of the nearest
    /// container on the given axes.
    ///
    /// The containers are the window's content area, a ``ScrollView``'s
    /// viewport and a ``List``'s. Axes not named keep the view's own size.
    ///
    /// ```swift
    /// ScrollView(.horizontal) {
    ///     LazyHStack(spacing: 0) {
    ///         ForEach(pages) { page in
    ///             PageView(page).containerRelativeFrame(.horizontal)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - axes: The axes to size from the container.
    ///   - alignment: Where the view goes in the frame. Default `.center`.
    /// - Returns: A view framed relative to its container.
    public func containerRelativeFrame(_ axes: Axis.Set, alignment: Alignment = .center) -> some View {
        _ContainerRelativeFrame(content: self, axes: axes, alignment: alignment) { length, _ in length }
    }

    /// Positions this view within an invisible frame spanning `span` of
    /// `count` equal divisions of the nearest container on the given axes.
    ///
    /// SwiftUI's formula, in whole cells and dividing last so no cell is lost
    /// to rounding along the way:
    ///
    /// ```
    /// available = container − spacing × (count − 1)
    /// length    = available × span ÷ count + spacing × (span − 1)
    /// ```
    ///
    /// - Parameters:
    ///   - axes: The axes to size from the container.
    ///   - count: The number of divisions of the container's length.
    ///   - span: How many divisions the view spans. Default 1.
    ///   - spacing: The cells between divisions.
    ///   - alignment: Where the view goes in the frame. Default `.center`.
    /// - Returns: A view framed relative to its container.
    public func containerRelativeFrame(
        _ axes: Axis.Set, count: Int, span: Int = 1, spacing: Int, alignment: Alignment = .center
    ) -> some View {
        _ContainerRelativeFrame(content: self, axes: axes, alignment: alignment) { length, _ in
            guard count > 0 else { return 0 }
            let available = max(0, length - spacing * (count - 1))
            return available * span / count + spacing * max(0, span - 1)
        }
    }

    /// Positions this view within an invisible frame whose size `length` works
    /// out from the nearest container's on each of the given axes.
    ///
    /// - Parameters:
    ///   - axes: The axes to size from the container.
    ///   - alignment: Where the view goes in the frame. Default `.center`.
    ///   - length: Given the container's length along an axis, in cells, and
    ///     the axis, the view's length along it.
    /// - Returns: A view framed relative to its container.
    public func containerRelativeFrame(
        _ axes: Axis.Set, alignment: Alignment = .center, _ length: @escaping (Int, Axis) -> Int
    ) -> some View {
        _ContainerRelativeFrame(content: self, axes: axes, alignment: alignment, length: length)
    }
}

// MARK: - Environment without reflection

extension _ContainerRelativeFrame: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _container.resolveEnvironment(environment)
    }
}
