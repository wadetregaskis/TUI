//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CollectionSurfaceTests.swift
//
//  `.tableStyle(.surface)` and `.listStyle(.surface)`, the prototype of a
//  collection told from the text around it by a surface of its own rather
//  than a border (decisions A29/A46; A-D6L-1): no border, every line on the
//  surface, the header on a step stronger — and both tones readable on every
//  stated palette at every depth.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitStyling
import TUIkitTables
@testable import TUIkitTestSupport

@MainActor
@Suite("Surface-style lists and tables")
struct CollectionSurfaceTests {

    private struct Row: Identifiable, Sendable, Equatable {
        let id: Int
        let name: String
    }

    private static let rows = (0..<4).map { Row(id: $0, name: "row\($0)") }

    /// The background colour in force where `needle` starts in `line` — its
    /// first visible cell when `needle` is `nil` — read off the SGR before it:
    /// the LAST field stated, since a fill laid under another opens with its own
    /// code and the one stated after it is what shows.
    private func field(in line: String, at needle: String? = nil) -> String? {
        let stop = needle.flatMap { line.range(of: $0)?.lowerBound }
        var field: String?
        var index = line.startIndex
        while index < line.endIndex {
            if let stop, index >= stop { break }
            guard line[index...].hasPrefix("\u{1B}[") else {
                if stop == nil { break }
                index = line.index(after: index)
                continue
            }
            let code = line[line.index(index, offsetBy: 2)...].prefix { $0 != "m" }
            if code.hasPrefix("48;") { field = String(code.dropFirst(3)) }
            if code == "0" || code == "49" { field = nil }
            index = line.index(index, offsetBy: 2 + code.count + 1, limitedBy: line.endIndex) ?? line.endIndex
        }
        return field
    }

    private func firstField(_ line: String) -> String? { field(in: line) }

    private func table(_ style: some TableStyle) -> FrameBuffer {
        renderToBuffer(
            Table(Self.rows) { TableColumn("Name", value: \Row.name) }.tableStyle(style),
            context: makeRenderContext(width: 30, height: 8))
    }

    @Test("A surface table draws no border, its header on a tone of its own and every row on the surface")
    func surfaceTable() {
        let buffer = table(.surface)
        let text = buffer.lines.map(\.stripped).joined()
        #expect(!text.contains("╭") && !text.contains("│"), "a surface table draws a border")
        let header = buffer.lines.first { $0.stripped.contains("Name") } ?? ""
        // Row 2 is unstriped: the second row is the first a table stripes.
        let plainRow = buffer.lines.first { $0.stripped.contains("row2") } ?? ""
        let headerField = field(in: header, at: "Name")
        let rowField = field(in: plainRow, at: "row2")
        #expect(headerField != nil, "the header paints no field")
        #expect(rowField != nil, "an unstriped row paints no field: it is not on the surface")
        #expect(headerField != rowField, "the header and the rows share one tone")
    }

    @Test("A scrolling surface table's lines are all as wide as the table")
    func scrollingLinesLineUp() {
        let many = (0..<12).map { Row(id: $0, name: "row\($0)") }
        let buffer = renderToBuffer(
            Table(many) { TableColumn("Name", value: \Row.name) }
                .tableStyle(.surface).frame(height: 6).scrollIndicators(.visible),
            context: makeRenderContext(width: 30, height: 10))
        let widths = Set(buffer.lines.map(\.strippedLength))
        #expect(widths.count == 1, "\(buffer.lines.map(\.stripped))")
    }

    /// The owner's ruling, 2026-10-16: a blank cell after a bordered table's bar
    /// mirrors the one before its rows, inside the frame; a surface table has
    /// no frame, and the column of surface past the bar read as the table
    /// running on past its edge.
    @Test("A surface table's scrollbar is its last column; a bordered table's keeps a cell before the border")
    func barAtTheEdge() throws {
        let many = (0..<12).map { Row(id: $0, name: "row\($0)") }
        func lastInk(_ style: some TableStyle) throws -> (column: Int, width: Int) {
            let buffer = renderToBuffer(
                Table(many) { TableColumn("Name", value: \Row.name) }
                    .tableStyle(style).frame(height: 6).scrollIndicators(.visible),
                context: makeRenderContext(width: 30, height: 10))
            let row = try #require(buffer.lines.map(\.stripped).first { $0.contains("row0") })
            let characters = Array(row)
            let last = try #require(characters.lastIndex { $0 != " " })
            return (last, characters.count)
        }
        let surface = try lastInk(.surface)
        #expect(surface.column == surface.width - 1, "the bar is the surface table's last column")
        let bordered = try lastInk(.bordered)
        // The border's `│` is the last ink; the bar stands one blank cell before it.
        #expect(bordered.column == bordered.width - 1)
        let borderedRow = try #require(
            renderToBuffer(
                Table(many) { TableColumn("Name", value: \Row.name) }
                    .tableStyle(.bordered).frame(height: 6).scrollIndicators(.visible),
                context: makeRenderContext(width: 30, height: 10)
            ).lines.map(\.stripped).first { $0.contains("row0") })
        #expect(Array(borderedRow)[bordered.width - 2] == " ", "the bordered table's blank cell before its border")
    }

    @Test("A bordered or inset table paints no surface")
    func otherStylesPaintNone() {
        for buffer in [table(.automatic), table(.inset)] {
            let plainRow = buffer.lines.first { $0.stripped.contains("row2") } ?? ""
            #expect(firstField(plainRow) == nil)
        }
    }

    @Test("A surface table stripes over its surface, not over the page")
    func stripeOverTheSurface() throws {
        var context = makeRenderContext(width: 30, height: 8)
        let palette = context.environment.palette
        let surface = context.environment.liftedSurface
        let expected = try #require(palette.stripeFill(over: surface))
        let overPage = try #require(palette.stripeFill(over: palette.background))
        #expect(expected != overPage, "the test palette cannot tell the two grounds apart")
        context.environment.palette = palette
        let buffer = renderToBuffer(
            Table(Self.rows) { TableColumn("Name", value: \Row.name) }.tableStyle(.surface), context: context)
        let striped = buffer.lines.first { $0.stripped.contains("row1") } ?? ""
        #expect(striped.contains(expected.backgroundEscape()), "row1 is \(striped.debugDescription)")
    }

    @Test("A surface list draws no border, its section headers on a tone of their own")
    func surfaceList() {
        let list = List {
            Section("Fruit") {
                ForEach(Self.rows) { Text($0.name) }
            }
        }
        .listStyle(.surface)
        let buffer = renderToBuffer(list, context: makeRenderContext(width: 30, height: 8))
        let text = buffer.lines.map(\.stripped).joined()
        #expect(!text.contains("╭") && !text.contains("│"), "a surface list draws a border")
        let header = buffer.lines.first { $0.stripped.contains("Fruit") } ?? ""
        let plainRow = buffer.lines.first { $0.stripped.contains("row1") } ?? ""
        let blank = buffer.lines.last ?? ""
        #expect(firstField(plainRow) != nil, "a row is not on the surface")
        #expect(firstField(blank) == firstField(plainRow), "the list's empty lines are not on the surface")
        let headerField = field(in: header, at: "Fruit")
        #expect(headerField != nil && headerField != field(in: plainRow, at: "row1"), "header \(header.debugDescription)")
    }

    // MARK: - Legibility across palettes and depths

    private static var statedPalettes: [any Palette] {
        PaletteRegistry.phosphorPresets + PaletteRegistry.appleTerminalProfiles
    }

    /// `colour` as painted at `depth` (see `StripeLegibilityTests.painted`).
    nonisolated private static func painted(_ colour: Color, at depth: ColorDepth) -> Color? {
        switch depth {
        case .palette256:
            return colour.downsampledToPalette256().rgbComponents.map { Color.rgb($0.red, $0.green, $0.blue) }
        case .basic16:
            guard case .ansi(let slot) = colour.downsampledToANSI16().value else { return nil }
            let packed = RowFills.reportedTable()[Int(slot.rawValue)]
            return .rgb(
                UInt8(truncatingIfNeeded: packed >> 16), UInt8(truncatingIfNeeded: packed >> 8),
                UInt8(truncatingIfNeeded: packed))
        default:
            return colour.rgbComponents.map { Color.rgb($0.red, $0.green, $0.blue) }
        }
    }

    @Test(
        "The text stays readable on the surface and on its header",
        arguments: [ColorDepth.truecolor, .palette256, .basic16])
    func readable(depth: ColorDepth) throws {
        for palette in Self.statedPalettes {
            var environment = EnvironmentValues()
            environment.palette = palette
            let tones = withColorDepth(depth) { CollectionSurface(environment) }
            let page = try #require(Self.painted(palette.background.resolve(with: palette), at: depth))
            let text = try #require(Self.painted(palette.foreground, at: depth))
            let floor = min(4.5, 0.8 * text.contrastRatio(against: page))
            for (name, tone) in [("surface", tones.body), ("header", tones.header)] {
                let shown = try #require(Self.painted(tone, at: depth))
                let ratio = text.contrastRatio(against: shown)
                #expect(ratio >= floor - 0.005, "\(palette.name) at \(depth): text \(ratio) on the \(name), \(floor) asked")
            }
        }
    }

    @Test(
        "The header's tone is told from the rows' and from their stripe, as painted",
        arguments: [ColorDepth.truecolor, .palette256, .basic16])
    func headerStandsApart(depth: ColorDepth) throws {
        var clashes: [String] = []
        for palette in Self.statedPalettes {
            var environment = EnvironmentValues()
            environment.palette = palette
            let (tones, stripe) = withColorDepth(depth) {
                let tones = CollectionSurface(environment)
                return (tones, palette.stripeFill(over: tones.body, at: depth))
            }
            let header = try #require(Self.painted(tones.header, at: depth))
            let body = try #require(Self.painted(tones.body, at: depth))
            // Sixteen colours have four greys, and on most palettes the rows,
            // the page and every readable step land on one of them: the header
            // keeps its tone there only where one stands apart. It must never
            // read as a striped row, at any depth.
            if header == body, depth > .basic16 { clashes.append("\(palette.name): header = rows") }
            if let stripe, let painted = Self.painted(stripe, at: depth), painted == header {
                clashes.append("\(palette.name): header = stripe")
            }
        }
        #expect(clashes.isEmpty, "at \(depth): \(clashes)")
    }

    /// The owner's ruling, 2026-10-16: some themes' surface headers were black,
    /// or near it, on Apple Terminal's cube — two steps off the page in a dark
    /// saturated hue, where the cube's rungs are far apart. Grass's was black
    /// on rows of `005f00`, 2.64:1, where its page stood 1.76:1 off them.
    @Test("On the cube a surface header is the quietest tone that stands apart, not the furthest step")
    func quietHeaderOnTheCube() throws {
        for name in ["Grass", "Red Sands"] {
            let palette = try #require(Self.statedPalettes.first { $0.name == name })
            var environment = EnvironmentValues()
            environment.palette = palette
            let tones = withColorDepth(.palette256) { CollectionSurface(environment) }
            let header = try #require(Self.painted(tones.header, at: .palette256))
            let body = try #require(Self.painted(tones.body, at: .palette256))
            let page = try #require(Self.painted(palette.background, at: .palette256))
            #expect(header.rgbComponents.map { $0.red | $0.green | $0.blue } != 0, "\(name): a black header")
            #expect(
                header.contrastRatio(against: body) <= page.contrastRatio(against: body) + 0.01,
                "\(name): the header is further off the rows than the page is")
        }
    }
}
