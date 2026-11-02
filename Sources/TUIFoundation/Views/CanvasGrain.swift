//  🖥️ TUI — A Terminal UI framework for Swift
//  CanvasGrain.swift
//
//  How finely a `Canvas` draws in a cell: a TUI addition, since a pixel in
//  SwiftUI is whatever the display has, and a terminal offers several answers.
//
//  Created by Wade Tregaskis
//  License: MIT

/// How finely a ``Canvas`` draws — a TUI addition; see
/// ``View/canvasGrain(_:)``.
///
/// Every grain but ``automatic`` is a vocabulary of glyphs: a cell draws one of
/// them in two colours, so a finer grain gives sharper edges, not more colours.
public struct CanvasGrain: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case cells, halfBlocks, quadrants, sextants, octants, braille
    }

    /// `nil` for ``automatic``.
    let kind: Kind?

    /// The finest the terminal offers: the terminal's own pixels where it
    /// places pictures in its cell grid (``View/terminalGraphics(_:)`` and
    /// ``View/gradientGraphics(_:)`` can turn them off), otherwise
    /// ``quadrants``, which every terminal's font has.
    public static let automatic = Self(kind: nil)

    /// One colour a cell.
    public static let cells = Self(kind: .cells)

    /// Two pixels a cell, one above the other, each its own colour: `▀ ▄`. What
    /// a ``Shape`` is rasterized at.
    public static let halfBlocks = Self(kind: .halfBlocks)

    /// Two pixels by two: `▘ ▝ ▖ ▗ ▚ ▞ ▙ ▛ ▜ ▟`.
    public static let quadrants = Self(kind: .quadrants)

    /// Two pixels by three, from Symbols for Legacy Computing (Unicode 13).
    /// A terminal or font without them draws boxes instead, so this is asked
    /// for, never assumed.
    public static let sextants = Self(kind: .sextants)

    /// Two pixels by four, from Symbols for Legacy Computing Supplement
    /// (Unicode 16): the finest solid grain, and the least widely drawn.
    public static let octants = Self(kind: .octants)

    /// Two pixels by four, as Braille dots: as fine as ``octants`` and in
    /// nearly every font, with gaps between the dots, so it suits lines and
    /// plots better than filled areas.
    public static let braille = Self(kind: .braille)

    /// The glyphs this grain draws in, ``automatic``'s being ``quadrants``.
    var resolvedKind: Kind { kind ?? .quadrants }
}

private struct CanvasGrainKey: EnvironmentKey {
    static let defaultValue = CanvasGrain.automatic
}

extension EnvironmentValues {
    /// How finely the ``Canvas`` views beneath draw. See
    /// ``View/canvasGrain(_:)``.
    public var canvasGrain: CanvasGrain {
        get { self[CanvasGrainKey.self] }
        set { self[CanvasGrainKey.self] = newValue }
    }
}

extension View {
    /// Sets how finely the ``Canvas`` views within this view draw — a TUI
    /// addition, as SwiftUI's canvas draws in the display's pixels.
    ///
    /// The default is the finest the terminal offers. Name a grain for a look,
    /// or to reach further on a terminal you know draws it:
    ///
    /// ```swift
    /// Canvas { context, size in
    ///     context.stroke(plot, with: .color(.green), lineWidth: 0.5)
    /// }
    /// .canvasGrain(.braille)
    /// ```
    ///
    /// - Parameter grain: The grain to draw at.
    /// - Returns: A view whose canvases draw at `grain`.
    nonisolated public func canvasGrain(_ grain: CanvasGrain) -> some View {
        environment(\.canvasGrain, grain)
    }
}
