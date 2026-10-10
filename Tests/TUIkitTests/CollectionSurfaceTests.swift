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

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitLists
@testable import TUIkitStyling
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
}
