//  🖥️ TUI — A Terminal UI framework for Swift
//  DefaultGlassEffectShape.swift
//
//  The shape a glass effect takes unless told otherwise: a capsule.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// The default shape applied by glass effects, a capsule — mirrors SwiftUI's
/// `DefaultGlassEffectShape`.
///
/// You do not use this type directly. Instead, TUI creates this shape on
/// your behalf as the default parameter of the ``View/glassEffect(_:in:)``
/// modifier. Drawn as a glass's rim it is a ``Capsule``'s: `╭─╮` / `╰─╯`, or
/// `( … )` one row tall.
nonisolated public struct DefaultGlassEffectShape: Shape {
    /// Creates the default glass effect shape.
    public init() {}

    /// A capsule in `rect`.
    public func path(in rect: CGRect) -> Path {
        Capsule().path(in: rect)
    }

    /// A glass's shape is filled.
    public static var role: ShapeRole { .fill }

    /// Fills whatever it is offered, from nothing, as every shape does unless
    /// it says otherwise — in TUI's layout terms (decisions B-W1-6).
    ///
    /// - Parameter proposal: The space offered, in cells.
    /// - Returns: Nothing fixed, flexible both ways.
    public func sizeThatFits(_ proposal: ProposedSize) -> ViewSize {
        ViewSize(width: 0, height: 0, isWidthFlexible: true, isHeightFlexible: true)
    }
}

extension DefaultGlassEffectShape {
    /// The default glass shape has nothing to animate.
    public typealias AnimatableData = EmptyAnimatableData
}

extension DefaultGlassEffectShape: BoxDrawnShape {
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii? {
        Capsule().boxCorners(in: rect)
    }
}
