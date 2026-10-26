//  🖥️ TUI — A Terminal UI framework for Swift
//  DrawingGroupModifier.swift
//
//  `drawingGroup(opaque:colorMode:)` and `ColorRenderingMode`: a compositing
//  group whose blends can be in linear light (decisions A27, ruled
//  2026-10-26).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIView

/// The set of possible working colour spaces for colour-compositing
/// operations — mirrors SwiftUI's `ColorRenderingMode`.
///
/// Where TUI blends — an ``View/opacity(_:)``, a translucent colour, a
/// ``View/blendMode(_:)`` — it mixes encoded sRGB values, as macOS draws them,
/// unless a ``View/drawingGroup(opaque:colorMode:)`` asks for linear light.
public enum ColorRenderingMode: Equatable, Hashable, Sendable {
    /// The non-linear sRGB working colour space: blends mix the encoded values.
    case nonLinear

    /// The linear sRGB working colour space: blends decode the colours to
    /// linear light, mix them there and encode the result.
    case linear

    /// The extended linear sRGB working colour space. A terminal's colours are
    /// in the standard range, so this is ``linear``, clamped to it.
    case extendedLinear
}

extension View {
    /// Composites this view's contents into an offscreen image before final
    /// display — mirrors SwiftUI's `drawingGroup(opaque:colorMode:)`.
    ///
    /// A terminal has no offscreen image to flatten into: every view is
    /// composited into one picture before an effect above it applies, as for
    /// ``View/compositingGroup()``, so the group is that already. What the
    /// modifier changes is the colour space the blends inside it mix in:
    ///
    /// - ``ColorRenderingMode/nonLinear``, the default, mixes encoded sRGB, as
    ///   every blend does outside a drawing group.
    /// - ``ColorRenderingMode/linear`` and ``ColorRenderingMode/extendedLinear``
    ///   mix in linear light: where a translucent colour, a faded view or a blend
    ///   mode in this view lands on another part of it, the colours are decoded,
    ///   mixed and encoded again.
    ///
    /// What lands on something outside the group mixes as it would without one,
    /// as SwiftUI composites the group's image into the window; and the
    /// innermost group decides for what is inside it.
    ///
    /// - Parameters:
    ///   - opaque: Whether the image is opaque: a promise by the caller that
    ///     every cell paints, which a terminal has no use for.
    ///   - colorMode: The working colour space blends in this view mix in.
    /// - Returns: This view, its blends in `colorMode`.
    public func drawingGroup(opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear) -> some View {
        environment(\.blendsInLinearLight, colorMode != .nonLinear)
    }
}

private struct BlendsInLinearLightKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the composites in this subtree spend the alphas that land in
    /// them in linear light: inside a `drawingGroup(colorMode: .linear)` or
    /// `.extendedLinear` (``OpacityRegion/blendsInLinearLight``).
    package var blendsInLinearLight: Bool {
        get { self[BlendsInLinearLightKey.self] }
        set { self[BlendsInLinearLightKey.self] = newValue }
    }
}
