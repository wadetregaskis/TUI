//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FaintLevelsAuditTests.swift
//
//  The faint content levels at 16 and 256 colours (decisions B22, decided
//  2026-10-05: a look at them, per-palette tiers skipped). Under a
//  `foregroundStyle`, `.secondary` to `.quinary` are that style at 0.5, 0.26,
//  0.1 and 0.05, composited at the cell; a depth with few colours may snap a
//  faint one onto the surface, or two onto one colour.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitStyling
@testable import TUIkitTestSupport

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
        ColorDepth.withCurrent(depth) {
            var context = makeRenderContext(width: 4, height: 1)
            context.environment.palette = palette
            let levels = Self.levels.map { level -> SGRState.Colour? in
                let view = Text("x").foregroundStyle(level.style).foregroundStyle(palette.foreground)
                let buffer = renderToBuffer(view, context: context)
                let line = buffer.resolvingOpacity(surface: palette.background, palette: palette).lines.first ?? ""
                return line.ansiSGRStateAt(visibleColumn: 0).foregroundColour
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

    /// The levels that vanish today: drawn in the page's own colour, so the text
    /// is not seen. Recorded as known issues for the owner's question A-EFFECTS-1
    /// (Open owner decisions); a level that stops vanishing fails here until the
    /// table is brought up to date.
    ///
    /// Measured 2026-10-19: at 16 colours every shipped palette draws
    /// `.tertiary`, `.quaternary` and `.quinary` in the page's colour, and
    /// `.secondary` in `.primary`'s; at 256, `.quinary` on Green, Red, Violet,
    /// Ocean and Solid Colors, and `.quaternary` too on Grass, Homebrew and
    /// Novel.
    @Test("No faint level is drawn in the page's own colour (known issues: A-EFFECTS-1)")
    func noLevelVanishes() {
        var vanished: [String: Int] = [:]
        for depth in [ColorDepth.basic16, .palette256] {
            for palette in Self.palettes {
                let (levels, page) = Self.inks(palette, at: depth)
                for (level, ink) in zip(Self.levels, levels) where ink == page {
                    vanished["\(depth)", default: 0] += 1
                    withKnownIssue("A-EFFECTS-1: \(palette.name) \(level.name) at \(depth) is the page") {
                        Issue.record("\(palette.name): \(level.name) at \(depth) is drawn in the page's colour")
                    }
                }
            }
        }
        // The table as measured: three levels on all sixteen palettes at 16 colours,
        // eleven cells at 256.
        #expect(vanished["\(ColorDepth.basic16)"] == 48)
        #expect(vanished["\(ColorDepth.palette256)"] == 11)
    }
}
