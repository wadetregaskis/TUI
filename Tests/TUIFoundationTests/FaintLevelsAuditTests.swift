//  🖥️ TUI — A Terminal UI framework for Swift
//  FaintLevelsAuditTests.swift
//
//  The faint content levels at 16 and 256 colours (decisions B22, decided
//  2026-10-05: a look at them, per-palette tiers skipped). Under a
//  `foregroundStyle`, `.secondary` to `.quinary` are that style at 0.5, 0.26,
//  0.1 and 0.05, composited at the cell; a depth with few colours snapped a
//  faint one onto the surface, or two onto one colour. Since A-EFFECTS-1
//  (option 3, 2026-10-27) none vanishes: at 16 colours they draw faint (SGR 2)
//  in the primary's colour, at 256 they step toward it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("The faint content levels at 16 and 256 colours")
struct FaintLevelsAuditTests {

    static let palettes: [any Palette] = PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles
    static let levels: [(name: String, style: HierarchicalShapeStyle)] = [
        ("primary", .primary), ("secondary", .secondary), ("tertiary", .tertiary),
        ("quaternary", .quaternary), ("quinary", .quinary),
    ]

    /// The ink a glyph at each level is drawn in, at `depth`, over `palette`'s
    /// page, under a `foregroundStyle` of the palette's foreground; and the
    /// page spelled as ink at that depth.
    static func inks(_ palette: any Palette, at depth: ColorDepth) -> (levels: [SGRState.Colour?], page: SGRState.Colour?) {
        let drawn = cells(palette, at: depth)
        return (drawn.levels.map(\.ink), drawn.page)
    }

    /// ``inks(_:at:)`` with whether each level is drawn faint (SGR 2).
    static func cells(
        _ palette: any Palette, at depth: ColorDepth
    ) -> (levels: [(ink: SGRState.Colour?, faint: Bool)], page: SGRState.Colour?) {
        ColorDepth.withCurrent(depth) {
            var context = makeRenderContext(width: 4, height: 1)
            context.environment.palette = palette
            let levels = Self.levels.map { level -> (ink: SGRState.Colour?, faint: Bool) in
                let view = Text("x").foregroundStyle(level.style).foregroundStyle(palette.foreground)
                let buffer = renderToBuffer(view, context: context)
                let line = buffer.resolvingOpacity(surface: palette.background, palette: palette).lines.first ?? ""
                let state = line.ansiSGRStateAt(visibleColumn: 0)
                return (state.foregroundColour, state.isFaint)
            }
            var page = SGRState()
            page.apply("\u{1B}[" + palette.background.resolve(with: palette).foregroundCodes().joined(separator: ";") + "m")
            return (levels, page.foregroundColour)
        }
    }

    @Test("Report: each faint level's ink at 16 and 256 colours, against the page")
    func report() {
        for depth in [ColorDepth.basic16, .palette256] {
            print("== \(depth) ==")
            for palette in Self.palettes {
                let (levels, page) = Self.inks(palette, at: depth)
                let cells = zip(Self.levels, levels).map { level, ink in
                    "\(level.name)=\(ink.map { "\($0)" } ?? "default")\(ink == page ? " (PAGE)" : "")"
                }
                print("  \(palette.name): page=\(page.map { "\($0)" } ?? "default") " + cells.joined(separator: " "))
            }
        }
    }

    /// No level is drawn in the page's own colour, at either depth, on any
    /// shipped palette. Measured 2026-10-19, before A-EFFECTS-1: at 16 colours
    /// every palette drew `.tertiary`, `.quaternary` and `.quinary` in the page's
    /// colour (48 cells); at 256, eleven cells (`.quinary` on Green, Red, Violet,
    /// Ocean and Solid Colors, `.quaternary` too on Grass, Homebrew and Novel).
    @Test("No faint level is drawn in the page's own colour")
    func noLevelVanishes() {
        for depth in [ColorDepth.basic16, .palette256] {
            for palette in Self.palettes {
                let (levels, page) = Self.inks(palette, at: depth)
                for (level, ink) in zip(Self.levels, levels) {
                    #expect(ink != page, "\(palette.name): \(level.name) at \(depth) is drawn in the page's colour")
                }
            }
        }
    }

    /// At 16 colours every level below the first is set apart from it, the only
    /// way 16 colours can: faint, in the primary's own colour. The primary is not.
    @Test("At 16 colours the faint levels draw faint, and the primary does not")
    func sixteenColoursDrawTheLevelsFaint() {
        for palette in Self.palettes {
            let (levels, _) = Self.cells(palette, at: .basic16)
            #expect(!levels[0].faint, "\(palette.name): primary drawn faint")
            for (level, cell) in zip(Self.levels, levels).dropFirst() {
                #expect(cell.faint, "\(palette.name): \(level.name) at 16 colours is not faint")
            }
        }
    }

    /// Truecolour draws what it is given: no level is faint.
    @Test("At 24-bit colour no level is drawn faint")
    func truecolourDrawsNoneFaint() {
        for palette in Self.palettes {
            let (levels, _) = Self.cells(palette, at: .truecolor)
            #expect(levels.allSatisfy { !$0.faint }, "\(palette.name)")
        }
    }
}
