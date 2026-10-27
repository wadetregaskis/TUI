//  🖥️ TUI — A Terminal UI framework for Swift
//  MaterialFrost.swift
//
//  How far a material's frost reaches: by default its thickness's, as
//  SwiftUI's materials blur more the thicker they are, and an app's to set
//  for a subtree (TUI-specific; owner request 2026-10-24).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

/// How much the materials and the glass in a subtree frost what is behind
/// them — TUI-specific: SwiftUI has no counterpart.
///
/// A material frosts what is behind it as a cell grid can blur: the glyphs
/// behind are dropped, and each cell takes the average colour of a box of
/// cells around it before the material's tint is laid over it. SwiftUI's only
/// control of a material's blur is its thickness — ``Material/ultraThin``
/// through ``Material/ultraThick``, thicker blurring more — and that is what
/// ``automatic`` follows here. This sets the box for a whole subtree, over
/// whatever thickness each material in it has:
///
/// ```swift
/// ZStack {
///     LogView()
///     Text("Paused").padding().background(.thinMaterial)
/// }
/// .materialFrost(.none)   // the glyphs dropped, nothing averaged
/// ```
///
/// A material that is opaque — inactive, or where the user asked for reduced
/// transparency — frosts nothing whatever this says.
public struct MaterialFrost: Sendable, Hashable {
    private enum Kind: Hashable {
        case automatic
        case none
        case radius(columns: UInt8, rows: UInt8)
    }

    private let kind: Kind

    private init(_ kind: Kind) { self.kind = kind }

    /// Each material's thickness decides: ``Material/ultraThin`` averages the
    /// smallest box and ``Material/ultraThick`` the largest, and glass the box
    /// of a material one step thinner than the one whose surface it takes.
    public static let automatic = Self(.automatic)

    /// No blur: the glyphs behind are dropped and each cell keeps its own
    /// colour, tinted. The cheapest frost — nothing is averaged.
    public static let none = Self(.none)

    /// A box `columns` cells either side of each cell and `rows` above and
    /// below it, averaged, whatever the material's thickness.
    ///
    /// A cell is about twice as tall as it is wide, so a box about as tall as
    /// it is wide reaches about twice as many columns as rows. `radius(columns:
    /// 0, rows: 0)` averages a cell with itself alone: its glyph, dropped, still
    /// counts as the share of the cell its ink covered.
    ///
    /// - Parameters:
    ///   - columns: How many columns either side a cell's average reaches, from 0
    ///     to 255.
    ///   - rows: How many rows above and below, from 0 to 255.
    /// - Returns: The frost.
    public static func radius(columns: Int, rows: Int) -> Self {
        Self(.radius(columns: UInt8(clamping: columns), rows: UInt8(clamping: rows)))
    }

    /// The frost a material whose thickness frosts as `thickness` does draws
    /// with under this setting, at `pixelsPerCell` where a picture is behind.
    func resolved(
        thickness: OpacityRegion.Frost, pixelsPerCell: (across: Int, down: Int) = (2, 4)
    ) -> OpacityRegion.Frost {
        let box: OpacityRegion.Frost =
            switch kind {
            case .automatic: thickness
            case .none: .droppingGlyphs
            case .radius(let columns, let rows): .averaging(columns: columns, rows: rows)
            }
        guard case .averaging(let columns, let rows, _, _) = box else { return box }
        return .averaging(
            columns: columns, rows: rows, pixelsAcross: UInt8(clamping: pixelsPerCell.across),
            pixelsDown: UInt8(clamping: pixelsPerCell.down))
    }
}

/// How finely the materials and the glass in a subtree frost a picture the
/// terminal draws behind them — TUI-specific: SwiftUI blurs at the screen's
/// own pixels.
///
/// A cell grid can blur only cells, so where a picture (a Kitty image) is
/// behind a frost, what is behind is frosted as one picture of its own, sent
/// to the terminal and scaled by it to the glass's cells (`Terminal graphics
/// protocols.md` §14.6). This says how many pixels a cell that picture has:
/// the terminal's own, ``native``, or fewer, ``downsampled(by:)`` merging
/// each square of `factor` × `factor` of them into one. More pixels draw a
/// smoother frost, with more of the pictures' detail at its edges; each costs
/// bytes to send — every time what is behind the glass changes — and work to
/// blur. Ghostty's cell on a Retina screen is 16 × 34 of its pixels.
///
/// ```swift
/// PhotoGrid()
///     .overlay { SharePanel().background(.thinMaterial) }
///     .materialFrostResolution(.downsampled(by: 4))   // 4 × 8 a Ghostty cell
/// ```
///
/// Where nothing the terminal draws as a picture is behind, the frost is the
/// cells' average colours, and this changes nothing.
public struct MaterialFrostResolution: Sendable, Hashable {
    private enum Kind: Hashable {
        case automatic
        case downsampled(Int)
    }

    private let kind: Kind

    private init(_ kind: Kind) { self.kind = kind }

    /// 2 × 4 pixels a cell, whatever the terminal's: 32 bytes of colour a
    /// cell, about Ghostty's own pixels downsampled by 8. The default.
    public static let automatic = Self(.automatic)

    /// The terminal's own pixels: a cell's worth for every cell.
    public static let native = Self(.downsampled(1))

    /// The terminal's pixels with each square of `factor` × `factor` of them
    /// merged into one: `1` is ``native``, `2` a quarter of its pixels, `3` a
    /// ninth. A cell keeps at least one pixel each way.
    ///
    /// - Parameter factor: How many of the terminal's pixels, each way, make
    ///   one of the frost's; from 1.
    /// - Returns: The resolution.
    public static func downsampled(by factor: Int) -> Self {
        Self(.downsampled(max(1, factor)))
    }

    /// The pixels a cell the frost's picture has, where a cell is `cell` of
    /// the terminal's pixels.
    func pixelsPerCell(cell: TerminalCellPixels) -> (across: Int, down: Int) {
        switch kind {
        case .automatic:
            return (DerivedImages.pixelsAcross, DerivedImages.pixelsDown)
        case .downsampled(let factor):
            // Rounded to the nearest, and at most what a claim can carry.
            func reduced(_ pixels: Int) -> Int { min(255, max(1, (pixels + factor / 2) / factor)) }
            return (reduced(cell.width), reduced(cell.height))
        }
    }
}

private struct MaterialFrostResolutionKey: EnvironmentKey {
    static let defaultValue = MaterialFrostResolution.automatic
}

extension EnvironmentValues {
    /// How finely the materials and glass in this subtree frost a picture the
    /// terminal draws behind them — TUI-specific. ``MaterialFrostResolution/automatic``
    /// by default.
    public var materialFrostResolution: MaterialFrostResolution {
        get { self[MaterialFrostResolutionKey.self] }
        set { self[MaterialFrostResolutionKey.self] = newValue }
    }

    /// The frost a material or glass whose thickness frosts as `thickness`
    /// does draws with here: ``materialFrost``'s box, at
    /// ``materialFrostResolution`` of this terminal's cell (``imageCellPixels``).
    func resolvedFrost(thickness: OpacityRegion.Frost) -> OpacityRegion.Frost {
        materialFrost.resolved(
            thickness: thickness, pixelsPerCell: materialFrostResolution.pixelsPerCell(cell: imageCellPixels))
    }
}

private struct MaterialFrostKey: EnvironmentKey {
    static let defaultValue = MaterialFrost.automatic
}

extension EnvironmentValues {
    /// How much the materials and glass in this subtree frost what is behind
    /// them — TUI-specific. ``MaterialFrost/automatic`` by default: each
    /// material's thickness decides.
    public var materialFrost: MaterialFrost {
        get { self[MaterialFrostKey.self] }
        set { self[MaterialFrostKey.self] = newValue }
    }
}

extension View {
    /// Sets how much the materials and glass in this view frost what is behind
    /// them — TUI-specific: SwiftUI's only control is a material's thickness,
    /// which ``MaterialFrost/automatic`` (the default) follows.
    ///
    /// - Parameter frost: The frost: ``MaterialFrost/automatic``,
    ///   ``MaterialFrost/none``, or a box of ``MaterialFrost/radius(columns:rows:)``.
    /// - Returns: A view whose materials and glass frost as `frost` says.
    public func materialFrost(_ frost: MaterialFrost) -> some View {
        environment(\.materialFrost, frost)
    }

    /// Sets how finely the materials and glass in this view frost a picture
    /// the terminal draws behind them — TUI-specific.
    ///
    /// - Parameter resolution: The pixels a cell the frost of a picture has:
    ///   ``MaterialFrostResolution/automatic`` (the default, 2 × 4),
    ///   ``MaterialFrostResolution/native``, or the terminal's pixels
    ///   ``MaterialFrostResolution/downsampled(by:)``.
    /// - Returns: A view whose materials and glass frost pictures at `resolution`.
    public func materialFrostResolution(_ resolution: MaterialFrostResolution) -> some View {
        environment(\.materialFrostResolution, resolution)
    }
}
