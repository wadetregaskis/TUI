//  🖥️ TUI — A Terminal UI framework for Swift
//  View+SwiftUIUnavailable.swift
//
//  SwiftUI's geometry and pixel effects, which a grid of cells can't do, each
//  with a compile error that says so. TUIFoundation's file of this name says why
//  these exist and how they are written.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// No documentation: nothing here reaches a reader except its message.
// swiftlint:disable missing_docs

extension View {
    @available(*, unavailable, message: "A character cell can't be rotated.")
    @_alwaysEmitIntoClient
    nonisolated public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> Self { self }

    @available(*, unavailable, message: "A character cell can't be rotated.")
    @_alwaysEmitIntoClient
    nonisolated public func rotation3DEffect(
        _ angle: Angle,
        axis: (x: Double, y: Double, z: Double),
        anchor: UnitPoint = .center,
        anchorZ: Double = 0,
        perspective: Double = 1
    ) -> Self { self }

    @available(*, unavailable, message: "A character cell can't be scaled. To draw attention to a view, change its opacity or colour.")
    @_alwaysEmitIntoClient
    nonisolated public func scaleEffect<Scale>(_ scale: Scale, anchor: UnitPoint = .center) -> Self { self }

    @available(*, unavailable, message: "A character cell can't be scaled. To draw attention to a view, change its opacity or colour.")
    @_alwaysEmitIntoClient
    nonisolated public func scaleEffect(x: Double = 1, y: Double = 1, anchor: UnitPoint = .center) -> Self { self }

    @available(*, unavailable, message: "A terminal can't blur a cell. For a frosted look, use a material.")
    @_alwaysEmitIntoClient
    nonisolated public func blur<Radius>(radius: Radius, opaque: Bool = false) -> Self { self }
}

// swiftlint:enable missing_docs
