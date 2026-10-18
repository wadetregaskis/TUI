//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CoreGraphicsShims.swift
//
//  The three CoreGraphics types a shape's API is spelled in, declared where
//  CoreGraphics is absent.
//
//  Created by Wade Tregaskis
//  License: MIT

#if !canImport(CoreGraphics)
import Foundation

// MARK: - CGAffineTransform

/// An affine transformation matrix — CoreGraphics' `CGAffineTransform`, for the
/// platforms that have no CoreGraphics (Linux, Windows).
///
/// `Path.applying(_:)`, `Shape.transform(_:)` and every `transform:` parameter
/// of `Path`'s builders take one, as SwiftUI's do. swift-corelibs-foundation
/// declares `CGFloat`, `CGPoint`, `CGSize` and `CGRect` for exactly this reason
/// and stops there; this is the same move for the one more type shapes need,
/// with CoreGraphics' own members and arithmetic, so code written against
/// CoreGraphics compiles here unchanged. On Apple platforms this file is empty
/// and CoreGraphics' own type is the one in use.
///
/// The matrix is
///
/// ```
/// | a   b   0 |
/// | c   d   0 |
/// | tx  ty  1 |
/// ```
///
/// and a point `(x, y)` maps to `(a·x + c·y + tx, b·x + d·y + ty)`.
public struct CGAffineTransform: Equatable, Hashable, Sendable {
    /// The entry at row 1, column 1.
    public var a: CGFloat
    /// The entry at row 1, column 2.
    public var b: CGFloat
    /// The entry at row 2, column 1.
    public var c: CGFloat
    /// The entry at row 2, column 2.
    public var d: CGFloat
    /// The entry at row 3, column 1: the horizontal translation.
    public var tx: CGFloat
    /// The entry at row 3, column 2: the vertical translation.
    public var ty: CGFloat

    /// The identity transform.
    public init() {
        self.init(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
    }

    /// A transform with the given matrix entries.
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    /// A transform that translates by `(tx, ty)`.
    public init(translationX tx: CGFloat, y ty: CGFloat) {
        self.init(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty)
    }

    /// A transform that scales by `(sx, sy)`.
    public init(scaleX sx: CGFloat, y sy: CGFloat) {
        self.init(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    /// A transform that rotates by `angle` radians — clockwise on a screen
    /// whose y axis points down, as every TUIkit coordinate's does.
    public init(rotationAngle angle: CGFloat) {
        let (sine, cosine) = (sin(Double(angle)), cos(Double(angle)))
        self.init(a: cosine, b: sine, c: -sine, d: cosine, tx: 0, ty: 0)
    }

    /// The identity transform.
    public static let identity = Self()

    /// Whether this is the identity transform.
    public var isIdentity: Bool { self == .identity }

    /// This transform, then `t2`: the matrix product `self × t2`.
    public func concatenating(_ t2: Self) -> Self {
        Self(
            a: a * t2.a + b * t2.c, b: a * t2.b + b * t2.d,
            c: c * t2.a + d * t2.c, d: c * t2.b + d * t2.d,
            tx: tx * t2.a + ty * t2.c + t2.tx, ty: tx * t2.b + ty * t2.d + t2.ty)
    }

    /// A translation by `(x, y)`, then this transform.
    public func translatedBy(x: CGFloat, y: CGFloat) -> Self {
        Self(translationX: x, y: y).concatenating(self)
    }

    /// A scale by `(x, y)`, then this transform.
    public func scaledBy(x: CGFloat, y: CGFloat) -> Self {
        Self(scaleX: x, y: y).concatenating(self)
    }

    /// A rotation by `angle` radians, then this transform.
    public func rotated(by angle: CGFloat) -> Self {
        Self(rotationAngle: angle).concatenating(self)
    }

    /// The inverse of this transform, or the transform unchanged when it has
    /// none (a singular matrix), as CoreGraphics answers.
    public func inverted() -> Self {
        let determinant = a * d - b * c
        guard determinant != 0, determinant.isFinite else { return self }
        return Self(
            a: d / determinant, b: -b / determinant,
            c: -c / determinant, d: a / determinant,
            tx: (c * ty - d * tx) / determinant, ty: (b * tx - a * ty) / determinant)
    }
}

// MARK: - Line caps and joins

/// How the end of a stroked open subpath is drawn — CoreGraphics' `CGLineCap`,
/// for the platforms that have no CoreGraphics. ``StrokeStyle`` holds one.
public enum CGLineCap: Int32, Sendable {
    /// The line stops square at its end point.
    case butt = 0
    /// A half-circle of the line's width rounds the end.
    case round = 1
    /// The line continues half its width past its end point, square.
    case square = 2
}

/// How two segments of a stroked path meet — CoreGraphics' `CGLineJoin`, for
/// the platforms that have no CoreGraphics. ``StrokeStyle`` holds one.
public enum CGLineJoin: Int32, Sendable {
    /// The outer edges extend to a point, up to the miter limit.
    case miter = 0
    /// A circular arc rounds the corner.
    case round = 1
    /// The corner is cut off square.
    case bevel = 2
}

// MARK: - Applying a transform

extension CGPoint {
    /// This point mapped through `t`.
    public func applying(_ t: CGAffineTransform) -> CGPoint {
        CGPoint(x: t.a * x + t.c * y + t.tx, y: t.b * x + t.d * y + t.ty)
    }
}

extension CGSize {
    /// This size mapped through `t`'s linear part — the translation does not
    /// move a size.
    public func applying(_ t: CGAffineTransform) -> CGSize {
        CGSize(width: t.a * width + t.c * height, height: t.b * width + t.d * height)
    }
}

extension CGRect {
    /// The smallest rectangle holding this one's four corners mapped through
    /// `t`.
    public func applying(_ t: CGAffineTransform) -> CGRect {
        guard !isNull else { return self }
        let corners = [
            CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: minY),
            CGPoint(x: minX, y: maxY), CGPoint(x: maxX, y: maxY),
        ].map { $0.applying(t) }
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        let (left, top) = (xs.min() ?? 0, ys.min() ?? 0)
        return CGRect(x: left, y: top, width: (xs.max() ?? 0) - left, height: (ys.max() ?? 0) - top)
    }
}
#endif
