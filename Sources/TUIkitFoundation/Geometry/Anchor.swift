//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Anchor.swift
//
//  `Anchor<Value>`: a geometry value tied to the view that made it, which a
//  reader elsewhere converts into its own coordinates.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Anchor

/// An opaque value derived from an anchor source and a particular view.
///
/// You can convert the anchor to a `Value` in the coordinate space of a target
/// view by using a ``GeometryProxy`` to specify the target view:
///
/// ```swift
/// Text("Badge")
///     .anchorPreference(key: BoundsKey.self, value: .bounds) { $0 }
///     .overlayPreferenceValue(BoundsKey.self) { anchor in
///         GeometryReader { proxy in
///             if let anchor {
///                 let rect = proxy[anchor]      // in the reader's cells
///                 …
///             }
///         }
///     }
/// ```
///
/// The values are cells: an `Anchor<CellRect>` is SwiftUI's
/// `Anchor<CGRect>`, an `Anchor<CellPoint>` its `Anchor<CGPoint>`.
///
/// ## How a terminal resolves one
///
/// The view that makes an anchor stamps a geometry marker where it begins
/// (`HitTestRegion.geometryMarker(_:)`). An `overlayPreferenceValue` or
/// `backgroundPreferenceValue` reading the anchor finds that marker in the base
/// it drew, before it builds the layer, so a reader in the layer resolves the
/// anchor against where the anchored view really is; the reader's own place in
/// the layer is found as a named space's reader is — exact for a reader that
/// fills the layer (the common case), and corrected once when it does not
/// (decisions A2). An anchor kept elsewhere — in `@State`, read by a reader in
/// another subtree — resolves through the global space, from where the anchored
/// view was when the last frame was drawn, as SwiftUI's does.
public struct Anchor<Value>: Equatable, Hashable, Sendable {
    /// The marker of the view the anchor was made by.
    let site: HitTestRegion.HandlerID

    /// What the anchor says about that view.
    let geometry: AnchorGeometry

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.site == rhs.site && lhs.geometry == rhs.geometry
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(site)
        hasher.combine(geometry)
    }

    /// A type-erased geometry value that produces an anchored value of a given
    /// type.
    ///
    /// SwiftUI passes values of this type to the ``View/anchorPreference(key:value:transform:)``
    /// modifier to retrieve geometry information from the view the modifier is
    /// attached to.
    public struct Source: Sendable {
        let geometry: AnchorGeometry

        /// The value this source names for a view whose top-left is at
        /// `origin` and that is `size` big.
        func value(origin: CellPoint, size: CellSize) -> Value {
            // The cast cannot fail: each `Source` is made by a static that
            // fixes `Value` to the type its geometry resolves to.
            geometry.resolve(origin: origin, size: size) as! Value  // swiftlint:disable:this force_cast
        }
    }

    /// The value in a coordinate space where the anchored view's top-left is
    /// at `origin` and it is `size` big.
    func value(origin: CellPoint, size: CellSize) -> Value {
        Source(geometry: geometry).value(origin: origin, size: size)
    }
}

/// What an anchor source says about the view it is attached to, in that view's
/// own cells — kept as data so two anchors compare.
indirect enum AnchorGeometry: Hashable, Sendable {
    /// The view's bounds: a `CellRect`.
    case bounds
    /// A rectangle in the view's own cells.
    case rect(CellRect)
    /// A point in the view's own cells.
    case point(CellPoint)
    /// A point at a fraction of the view's size.
    case unitPoint(UnitPoint)
    /// Each of several, as an array.
    case array([Self])
    /// One, or none.
    case optional(Self?)

    /// The value, for a view at `origin` that is `size` big.
    func resolve(origin: CellPoint, size: CellSize) -> Any {
        switch self {
        case .bounds:
            return CellRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
        case .rect(let rect):
            return CellRect(x: origin.x + rect.x, y: origin.y + rect.y, width: rect.width, height: rect.height)
        case .point(let point):
            return CellPoint(x: origin.x + point.x, y: origin.y + point.y)
        case .unitPoint(let unit):
            // Floored once, from the whole product: the midpoint of a 5-cell
            // view is column 2 (`AlignmentID` explains why it is never
            // floored in two steps).
            return CellPoint(
                x: origin.x + Int((unit.x * Double(size.width)).rounded(.down)),
                y: origin.y + Int((unit.y * Double(size.height)).rounded(.down)))
        case .array(let parts):
            return parts.map { $0.resolve(origin: origin, size: size) }
        case .optional(let part):
            return part.map { $0.resolve(origin: origin, size: size) } as Any
        }
    }
}

// MARK: - Sources

extension Anchor.Source where Value == CellRect {
    /// The anchored view's bounds.
    public static var bounds: Anchor<CellRect>.Source { Self(geometry: .bounds) }

    /// A rectangle in the anchored view's own cells.
    ///
    /// - Parameter rect: The rectangle, measured from the view's top-left.
    /// - Returns: A source producing that rectangle.
    public static func rect(_ rect: CellRect) -> Anchor<Value>.Source { Self(geometry: .rect(rect)) }
}

extension Anchor.Source where Value == CellPoint {
    /// A point in the anchored view's own cells.
    ///
    /// - Parameter point: The point, measured from the view's top-left.
    /// - Returns: A source producing that point.
    public static func point(_ point: CellPoint) -> Anchor<Value>.Source { Self(geometry: .point(point)) }

    /// A point at a fraction of the anchored view's size — `(0.5, 0.5)` is its
    /// centre, floored to a cell.
    ///
    /// - Parameter point: The fraction along each axis.
    /// - Returns: A source producing that point.
    public static func unitPoint(_ point: UnitPoint) -> Anchor<Value>.Source { Self(geometry: .unitPoint(point)) }

    /// The anchored view's top-leading corner.
    public static var topLeading: Anchor<CellPoint>.Source { unitPoint(.topLeading) }
    /// The middle of the anchored view's top edge.
    public static var top: Anchor<CellPoint>.Source { unitPoint(.top) }
    /// The anchored view's top-trailing corner.
    public static var topTrailing: Anchor<CellPoint>.Source { unitPoint(.topTrailing) }
    /// The middle of the anchored view's leading edge.
    public static var leading: Anchor<CellPoint>.Source { unitPoint(.leading) }
    /// The anchored view's centre.
    public static var center: Anchor<CellPoint>.Source { unitPoint(.center) }
    /// The middle of the anchored view's trailing edge.
    public static var trailing: Anchor<CellPoint>.Source { unitPoint(.trailing) }
    /// The anchored view's bottom-leading corner.
    public static var bottomLeading: Anchor<CellPoint>.Source { unitPoint(.bottomLeading) }
    /// The middle of the anchored view's bottom edge.
    public static var bottom: Anchor<CellPoint>.Source { unitPoint(.bottom) }
    /// The anchored view's bottom-trailing corner.
    public static var bottomTrailing: Anchor<CellPoint>.Source { unitPoint(.bottomTrailing) }
}

extension Anchor.Source {
    /// A source producing an array, one value per source given.
    ///
    /// - Parameter array: The sources.
    public init<T>(_ array: [Anchor<T>.Source]) where Value == [T] {
        self.init(geometry: .array(array.map(\.geometry)))
    }

    /// A source producing a value, or `nil` when none is given.
    ///
    /// - Parameter anchor: The source, or `nil`.
    public init<T>(_ anchor: Anchor<T>.Source?) where Value == T? {
        self.init(geometry: .optional(anchor?.geometry))
    }
}

// MARK: - Resolving

extension GeometryProxy {
    /// Resolves the value of an anchor to the container view: in the
    /// container's own cells, measured from its top-left.
    ///
    /// - Parameter anchor: An anchor made by ``View/anchorPreference(key:value:transform:)``.
    /// - Returns: The anchor's value in this container's coordinates.
    public subscript<T>(anchor: Anchor<T>) -> T {
        guard let ask, let coordinator = ask.coordinator else {
            return anchor.value(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 0, height: 0))
        }
        // In a preference layer whose base made the anchor: relative to where
        // this container is in that layer.
        var scope = ask.anchorScope
        while let layer = scope {
            if let site = layer.sites[anchor.site] {
                let here = ask.observation(in: layer.space)?.origin ?? CellPoint(x: 0, y: 0)
                return anchor.value(
                    origin: CellPoint(x: site.origin.x - here.x, y: site.origin.y - here.y), size: site.size)
            }
            scope = layer.parent
        }
        // Anywhere else — an anchor kept in `@State` — through the global
        // space, where the anchored view was when the last frame was drawn.
        let site = coordinator.globalAnchorSite(anchor.site)
        let here = ask.observation(in: .global)?.origin ?? CellPoint(x: 0, y: 0)
        let origin = site?.origin ?? here
        return anchor.value(
            origin: CellPoint(x: origin.x - here.x, y: origin.y - here.y),
            size: site?.size ?? CellSize(width: 0, height: 0))
    }
}
