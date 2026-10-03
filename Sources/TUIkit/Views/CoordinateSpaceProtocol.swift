//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CoordinateSpaceProtocol.swift
//
//  SwiftUI's protocol form of a coordinate space, behind `.local` and
//  `.global` in `GeometryProxy.frame(in:)`. Named spaces and `.scrollView` are
//  not here: answering them needs to know where a view sits while it is still
//  being built, which is an open decision (decisions doc A2).
//
//  Created by Wade Tregaskis
//  License: MIT

/// A frame of reference within the layout system.
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
/// terminal's top-left cell.
public struct GlobalCoordinateSpace: CoordinateSpaceProtocol, Sendable {
    /// Creates the global coordinate space.
    public init() {}

    /// ``CoordinateSpace/global``.
    public var coordinateSpace: CoordinateSpace { .global }
}

extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
    /// The local coordinate space of the current view.
    public static var local: LocalCoordinateSpace { LocalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
    /// The global coordinate space at the root of the view hierarchy.
    public static var global: GlobalCoordinateSpace { GlobalCoordinateSpace() }
}

extension CoordinateSpace {
    /// Whether this is the global coordinate space.
    public var isGlobal: Bool { self == .global }

    /// Whether this is the local coordinate space.
    public var isLocal: Bool { self == .local }
}
