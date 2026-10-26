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
    /// with under this setting.
    func resolved(thickness: OpacityRegion.Frost) -> OpacityRegion.Frost {
        switch kind {
        case .automatic: thickness
        case .none: .droppingGlyphs
        case .radius(let columns, let rows): .averaging(columns: columns, rows: rows)
        }
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
}
