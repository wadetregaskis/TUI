//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ShadowScreen.swift
//
//  A view drawn as the screen root draws it, on a grey page a shadow can
//  darken, and read back cell by cell: what the shadow suites measure.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport
@testable import TUIkitView

/// A screen: a view rendered on a palette whose page is ``page`` and
/// composited as the screen root composites it, in 24-bit colour.
@MainActor
struct ShadowScreen {
    /// The page every screen is drawn on: a light grey, so that a shadow has
    /// something to darken.
    nonisolated static let page = 200

    let buffer: FrameBuffer

    /// `view` drawn in `width` × `height` cells.
    init(_ view: some View, width: Int = 12, height: Int = 8) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        var palette = ThemeProbePalette()
        palette.background = .rgb(UInt8(Self.page), UInt8(Self.page), UInt8(Self.page))
        environment.palette = palette
        environment.verticalScrollIndicatorVisibility = .hidden
        environment.horizontalScrollIndicatorVisibility = .hidden
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(
            availableWidth: width, availableHeight: height, environment: environment, tuiContext: tui
        ).isolatingRenderCache()
        buffer = ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(view, context: context)
                .compositingOverlays(maxWidth: width, maxHeight: height, palette: palette)
        }
    }

    /// `level` darkened by a shadow of black at `alpha`.
    nonisolated static func darkened(_ alpha: Double, from level: Int = page) -> Int {
        Int((Double(level) * (1 - alpha)).rounded())
    }

    /// The brightest channel of the field at `column`, `row`; `nil` where
    /// the cell states none (the page shows).
    func field(_ column: Int, _ row: Int) -> Int? {
        Self.level(painted(column, row)?.state.backgroundColour)
    }

    /// The brightest channel of the ink at `column`, `row`.
    func ink(_ column: Int, _ row: Int) -> Int? { Self.level(painted(column, row)?.ink) }

    /// The glyph at `column`, `row`.
    func glyph(_ column: Int, _ row: Int) -> Character? { painted(column, row)?.glyph }

    /// The fields of row `row`, from `columns`, the page reading as its own level.
    func fields(row: Int, _ columns: Range<Int>) -> [Int] {
        columns.map { field($0, row) ?? Self.page }
    }

    /// A cell as drawn: its glyph and the netted state it is drawn in.
    struct Cell: Equatable {
        let glyph: Character
        let state: SGRState
    }

    /// The cell at `column`, `row`.
    func cell(_ column: Int, _ row: Int) -> Cell? {
        painted(column, row).map { Cell(glyph: $0.glyph, state: $0.state) }
    }

    private func painted(_ column: Int, _ row: Int) -> PaintedCell? {
        guard buffer.lines.indices.contains(row) else { return nil }
        let cells = paintedCells(buffer.lines[row])
        return cells.indices.contains(column) ? cells[column] : nil
    }

    private static func level(_ colour: SGRState.Colour?) -> Int? {
        guard case .rgb(let red, let green, let blue) = colour else { return nil }
        return max(red, green, blue)
    }
}
