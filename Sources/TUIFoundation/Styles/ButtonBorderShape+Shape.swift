//  🖥️ TUI — A Terminal UI framework for Swift
//  ButtonBorderShape+Shape.swift
//
//  A button border shape as a shape: the outline its glyph family stands for.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

extension ButtonBorderShape: Shape {
    /// The shape's outline in `rect`: a capsule for ``capsule`` and
    /// ``automatic`` — TUI's buttons' own look — a rectangle rounded a
    /// column and a half for ``roundedRectangle`` and TUI's
    /// ``brackets(_:_:)`` and ``underline``, square for a radius of zero, and a
    /// circle for ``circle``.
    ///
    /// The rounded rectangle's radius is the one a three-row solid button face
    /// is drawn at; ``roundedRectangle(radius:)`` keeps no radius of its own, a
    /// button face having only rounded and square to draw.
    public func path(in rect: CGRect) -> Path {
        switch kind {
        case .automatic, .capsule: Capsule().path(in: rect)
        case .roundedRectangle, .brackets, .underline: RoundedRectangle(cornerRadius: Self.cornerRadius).path(in: rect)
        case .square: Rectangle().path(in: rect)
        case .circle: Circle().path(in: rect)
        }
    }

    /// A button border shape has nothing to animate.
    public typealias AnimatableData = EmptyAnimatableData

    /// The radius a rounded rectangle is drawn at, in columns — the corner of
    /// a three-row solid button face (`ButtonFaceEdges.TallShape`).
    static let cornerRadius: CGFloat = 1.5
}

extension ButtonBorderShape: InsettableShape {
    /// The inset shape.
    public typealias InsetShape = _Inset

    /// Returns `self` inset by `amount`.
    ///
    /// - Parameter amount: How far to inset, in columns.
    /// - Returns: The inset shape.
    public func inset(by amount: CGFloat) -> _Inset {
        _Inset(shape: self, amount: amount)
    }

    /// A button border shape inset: its outline in the inset rectangle, a
    /// rounded corner shrunk by the same amount.
    public struct _Inset: InsettableShape {
        /// The shape inset.
        let shape: ButtonBorderShape
        /// By how much.
        var amount: CGFloat

        /// The shape's outline in `rect` inset by ``amount``.
        public func path(in rect: CGRect) -> Path {
            switch shape.kind {
            case .automatic, .capsule: Capsule().inset(by: amount).path(in: rect)
            case .roundedRectangle, .brackets, .underline:
                RoundedRectangle(cornerRadius: ButtonBorderShape.cornerRadius).inset(by: amount).path(in: rect)
            case .square: Rectangle().inset(by: amount).path(in: rect)
            case .circle: Circle().inset(by: amount).path(in: rect)
            }
        }

        /// The inset, animated.
        public var animatableData: CGFloat {
            get { amount }
            set { amount = newValue }
        }

        /// This inset further by `amount`.
        public func inset(by amount: CGFloat) -> Self {
            var inset = self
            inset.amount += amount
            return inset
        }
    }
}

extension Shape where Self == ButtonBorderShape {
    /// A shape that defers to the environment to determine the resolved button
    /// border shape — the one ``View/buttonBorderShape(_:)`` sets, a capsule
    /// where none is set.
    public static var buttonBorder: ButtonBorderShape { .automatic }
}

extension ButtonBorderShape: BoxDrawnShape {
    func boxCorners(in rect: CGRect) -> RectangleCornerRadii? {
        switch kind {
        case .automatic, .capsule:
            Capsule().boxCorners(in: rect)
        case .roundedRectangle, .brackets, .underline:
            RoundedRectangle(cornerRadius: Self.cornerRadius).boxCorners(in: rect)
        case .square:
            RectangleCornerRadii()
        case .circle:
            nil
        }
    }
}

extension ButtonBorderShape: EnvironmentResolvedShape {
    /// ``automatic`` defers to the environment's button border shape, as
    /// ``Shape/buttonBorder`` does; every other shape is itself.
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        resolved(in: context.environment)
    }

    /// The shape this stands for in `environment`: the one
    /// ``View/buttonBorderShape(_:)`` set for ``automatic``, a capsule where
    /// none is set; itself for every other shape.
    func resolved(in environment: EnvironmentValues) -> Self {
        guard kind == .automatic else { return self }
        let stated = environment.buttonBorderShape
        return stated.kind == .automatic ? Self.capsule : stated
    }
}

extension ButtonBorderShape._Inset: EnvironmentResolvedShape {
    /// ``ButtonBorderShape/automatic`` inset is the environment's button border
    /// shape, inset as far.
    func resolvedShape(in context: RenderContext, columns: Int, rows: Int) -> any Shape {
        Self(shape: shape.resolved(in: context.environment), amount: amount)
    }
}
