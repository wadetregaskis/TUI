//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CoordinateSpaceProtocol.swift
//
//  The coordinate spaces a frame can be asked in: the view's own (`.local`),
//  the screen's (`.global`), one a view named (`.named(_:)`, declared by
//  `coordinateSpace(_:)`), and the nearest scroll view's (`.scrollView`). How a
//  view learns where it sits in one of them while it is still being built is
//  `GeometryCoordinator`'s business (design study A2).
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Coordinate Space

/// A resolved coordinate space created by the coordinate space protocol.
///
/// You don't typically use `CoordinateSpace` directly. Instead, use the static
/// properties and functions of ``CoordinateSpaceProtocol`` such as `.global`,
/// `.local`, and `.named(_:)`.
///
/// Not `Sendable`, as SwiftUI's is not: a name is any `Hashable`, held as an
/// `AnyHashable`, and nothing says the value inside is safe to share.
public enum CoordinateSpace: Hashable {
    /// The global coordinate space: the terminal's top-left cell.
    ///
    /// The whole screen, the window's bars included — the space a pointer's
    /// `.global` location is reported in, so a view's global frame and a
    /// click's global location agree.
    case global

    /// The local coordinate space of the current view: its origin is `(0, 0)`.
    case local

    /// A named reference to a view's local coordinate space — one
    /// ``View/coordinateSpace(_:)`` declared, or the nearest scroll view's
    /// (``CoordinateSpaceProtocol/scrollView``).
    ///
    /// Where no view declares the name around the asking view, the space is
    /// the global one, as SwiftUI's is (measured on macOS 15).
    case named(AnyHashable)
}

extension CoordinateSpace {
    /// Whether this is the global coordinate space.
    public var isGlobal: Bool { self == .global }

    /// Whether this is the local coordinate space.
    public var isLocal: Bool { self == .local }
}

// MARK: - Coordinate Space Protocol

/// A frame of reference within the layout system.
///
/// All geometric properties of a view, including size, position, and
/// transform, are defined within the local coordinate space of the view's
/// parent. These values can be converted into other coordinate spaces by
/// passing types conforming to this protocol into functions such as
/// `GeometryProxy.frame(in:)`.
public protocol CoordinateSpaceProtocol {
    /// The resolved coordinate space.
    var coordinateSpace: CoordinateSpace { get }
}

/// The local coordinate space of the current view: its origin is `(0, 0)`.
public struct LocalCoordinateSpace: CoordinateSpaceProtocol, Sendable {
    /// Creates the local coordinate space.
    public init() {}

    /// ``CoordinateSpace/local``.
    public var coordinateSpace: CoordinateSpace { .local }
}

/// The global coordinate space, at the root of the view hierarchy: the
/// terminal's top-left cell (see ``CoordinateSpace/global``).
public struct GlobalCoordinateSpace: CoordinateSpaceProtocol, Sendable {
    /// Creates the global coordinate space.
    public init() {}

    /// ``CoordinateSpace/global``.
    public var coordinateSpace: CoordinateSpace { .global }
}

/// A named coordinate space.
///
/// Use the ``View/coordinateSpace(_:)`` modifier to assign a name to the local
/// coordinate space of a parent view. Child views can then refer to that
/// coordinate space using `.named(_:)`.
public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Equatable {
    /// The name the space resolves to: the one given, or the scroll view's.
    let name: AnyHashable

    /// The resolved coordinate space.
    public var coordinateSpace: CoordinateSpace { .named(name) }
}

/// The name `.scrollView` and `.scrollView(axis:)` resolve to: the nearest
/// scroll view, or the nearest one scrolling along `axis`.
///
/// Internal, as SwiftUI's is: no view can declare it, so only a scroll view
/// answers it — the scroll view's own viewport, which moves with the scroll
/// (measured on macOS 15: a reader forty rows down a view scrolled forty rows
/// reports `y == 0`).
struct ScrollViewSpaceName: Hashable, Sendable {
    /// The axis the scroll view must scroll along, or `nil` for any.
    let axis: Axis?
}

extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
    /// The local coordinate space of the current view.
    public static var local: LocalCoordinateSpace { LocalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
    /// The global coordinate space at the root of the view hierarchy.
    public static var global: GlobalCoordinateSpace { GlobalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// Creates a named coordinate space using the given value.
    ///
    /// Use the ``View/coordinateSpace(_:)`` modifier to assign a name to the
    /// local coordinate space of a parent view. Child views can then refer to
    /// that coordinate space using `.named(_:)`.
    ///
    /// - Parameter name: A unique value that identifies the coordinate space.
    /// - Returns: A named coordinate space identified by the given value.
    public static func named(_ name: some Hashable) -> NamedCoordinateSpace {
        NamedCoordinateSpace(name: AnyHashable(name))
    }

    /// The named coordinate space that is added by the system for the
    /// innermost containing scroll view.
    ///
    /// The scroll view's viewport: content moves through it as it scrolls. A
    /// view in no scroll view is answered in the global space, as SwiftUI's is.
    public static var scrollView: NamedCoordinateSpace {
        NamedCoordinateSpace(name: AnyHashable(ScrollViewSpaceName(axis: nil)))
    }

    /// The named coordinate space that is added by the system for the
    /// innermost containing scroll view that allows scrolling along the
    /// provided axis.
    ///
    /// - Parameter axis: The axis the scroll view must scroll along.
    /// - Returns: That scroll view's space.
    public static func scrollView(axis: Axis) -> Self {
        NamedCoordinateSpace(name: AnyHashable(ScrollViewSpaceName(axis: axis)))
    }
}
