//  🖥️ TUI — A Terminal UI framework for Swift
//  AlignmentGuideParityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
@testable import TUITestSupport

// MARK: - Fixtures

/// A column of `height` one-cell rows of `character`, for a guide on the
/// vertical axis.
private struct Column: View {
    let character: Character
    let height: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<height, id: \.self) { _ in Text(String(character)) }
        }
    }
}

/// One row of the GUIDE probe, measured in SwiftUI.
///
/// Two views in a stack with no spacing: the first ("G", `guided` cells along
/// the alignment axis) sets an explicit guide for the stack's alignment, and
/// the second ("S", `sibling` cells) sets none, so its guide is the
/// alignment's default. `swiftUI` is where SwiftUI put each view's leading (or
/// top) edge, and how wide (or tall) the stack came out.
///
/// SwiftUI 6.5.4, macOS 15.8.1, offscreen `NSHostingView`, 2026-10-11. The
/// views were `Color.clear.frame(width:height:)`, so one point stands for one
/// cell. The harness and its output are `Tools/SwiftUIProbes/Alignment guides/guide.swift` and
/// `guide.out`.
struct GuideProbeRow: Sendable, CustomTestStringConvertible {
    enum Alignment: String, Sendable {
        case leading, trailing, center, top, bottom

        var isHorizontal: Bool { self == .leading || self == .trailing || self == .center }
    }

    let alignment: Alignment
    let guided: Int
    let guide: Double
    let sibling: Int
    let swiftUI: (guidedAt: Int, siblingAt: Int, extent: Int)

    init(_ alignment: Alignment, _ guided: Int, guide: Double, _ sibling: Int, swiftUI: (Int, Int, Int)) {
        self.alignment = alignment
        self.guided = guided
        self.guide = guide
        self.sibling = sibling
        self.swiftUI = swiftUI
    }

    /// The row without its container, which the suite that reads it names:
    /// the probe's pairs are in a `VStack` (or `HStack`), and `ZStack`'s rows
    /// reuse the type.
    var testDescription: String {
        ".\(alignment): \(guided) cells with guide \(Int(guide)), then \(sibling)"
    }
}

/// SwiftUI's rule for an explicit alignment guide, measured: each view sits at
/// `max(guides) - its guide`, the stack is as wide as that needs, and a guide
/// is used exactly as given — never held to the view's own size, on either
/// side, on either axis, for any alignment.
@MainActor
@Suite("Alignment guides match SwiftUI's placement")
struct AlignmentGuideParityTests {
    typealias Row = GuideProbeRow

    /// The probe's matrix, in its order. Leading: guided widths 1, 6 and 10
    /// over siblings 6 and 10. Trailing and center: guided 1 and 6 over 6.
    /// HStack top: guided heights 1 and 6 over 6; bottom: 1 over 6. Then the
    /// control rows, whose guides all lie inside their own views.
    nonisolated static let rows: [Row] = [
        Row(.leading, 1, guide: 0, 6, swiftUI: (0, 0, 6)),
        Row(.leading, 1, guide: 1, 6, swiftUI: (0, 1, 7)),
        Row(.leading, 1, guide: 2, 6, swiftUI: (0, 2, 8)),
        Row(.leading, 1, guide: 5, 6, swiftUI: (0, 5, 11)),
        Row(.leading, 1, guide: 10, 6, swiftUI: (0, 10, 16)),
        Row(.leading, 1, guide: 15, 6, swiftUI: (0, 15, 21)),
        Row(.leading, 1, guide: 25, 6, swiftUI: (0, 25, 31)),
        Row(.leading, 1, guide: -1, 6, swiftUI: (1, 0, 6)),
        Row(.leading, 1, guide: -3, 6, swiftUI: (3, 0, 6)),
        Row(.leading, 1, guide: -10, 6, swiftUI: (10, 0, 11)),
        Row(.leading, 1, guide: 0, 10, swiftUI: (0, 0, 10)),
        Row(.leading, 1, guide: 1, 10, swiftUI: (0, 1, 11)),
        Row(.leading, 1, guide: 2, 10, swiftUI: (0, 2, 12)),
        Row(.leading, 1, guide: 5, 10, swiftUI: (0, 5, 15)),
        Row(.leading, 1, guide: 10, 10, swiftUI: (0, 10, 20)),
        Row(.leading, 1, guide: 15, 10, swiftUI: (0, 15, 25)),
        Row(.leading, 1, guide: 25, 10, swiftUI: (0, 25, 35)),
        Row(.leading, 1, guide: -1, 10, swiftUI: (1, 0, 10)),
        Row(.leading, 1, guide: -3, 10, swiftUI: (3, 0, 10)),
        Row(.leading, 1, guide: -10, 10, swiftUI: (10, 0, 11)),
        Row(.leading, 6, guide: 0, 6, swiftUI: (0, 0, 6)),
        Row(.leading, 6, guide: 1, 6, swiftUI: (0, 1, 7)),
        Row(.leading, 6, guide: 2, 6, swiftUI: (0, 2, 8)),
        Row(.leading, 6, guide: 5, 6, swiftUI: (0, 5, 11)),
        Row(.leading, 6, guide: 10, 6, swiftUI: (0, 10, 16)),
        Row(.leading, 6, guide: 15, 6, swiftUI: (0, 15, 21)),
        Row(.leading, 6, guide: 25, 6, swiftUI: (0, 25, 31)),
        Row(.leading, 6, guide: -1, 6, swiftUI: (1, 0, 7)),
        Row(.leading, 6, guide: -3, 6, swiftUI: (3, 0, 9)),
        Row(.leading, 6, guide: -10, 6, swiftUI: (10, 0, 16)),
        Row(.leading, 6, guide: 0, 10, swiftUI: (0, 0, 10)),
        Row(.leading, 6, guide: 1, 10, swiftUI: (0, 1, 11)),
        Row(.leading, 6, guide: 2, 10, swiftUI: (0, 2, 12)),
        Row(.leading, 6, guide: 5, 10, swiftUI: (0, 5, 15)),
        Row(.leading, 6, guide: 10, 10, swiftUI: (0, 10, 20)),
        Row(.leading, 6, guide: 15, 10, swiftUI: (0, 15, 25)),
        Row(.leading, 6, guide: 25, 10, swiftUI: (0, 25, 35)),
        Row(.leading, 6, guide: -1, 10, swiftUI: (1, 0, 10)),
        Row(.leading, 6, guide: -3, 10, swiftUI: (3, 0, 10)),
        Row(.leading, 6, guide: -10, 10, swiftUI: (10, 0, 16)),
        Row(.leading, 10, guide: 0, 6, swiftUI: (0, 0, 10)),
        Row(.leading, 10, guide: 1, 6, swiftUI: (0, 1, 10)),
        Row(.leading, 10, guide: 2, 6, swiftUI: (0, 2, 10)),
        Row(.leading, 10, guide: 5, 6, swiftUI: (0, 5, 11)),
        Row(.leading, 10, guide: 10, 6, swiftUI: (0, 10, 16)),
        Row(.leading, 10, guide: 15, 6, swiftUI: (0, 15, 21)),
        Row(.leading, 10, guide: 25, 6, swiftUI: (0, 25, 31)),
        Row(.leading, 10, guide: -1, 6, swiftUI: (1, 0, 11)),
        Row(.leading, 10, guide: -3, 6, swiftUI: (3, 0, 13)),
        Row(.leading, 10, guide: -10, 6, swiftUI: (10, 0, 20)),
        Row(.leading, 10, guide: 0, 10, swiftUI: (0, 0, 10)),
        Row(.leading, 10, guide: 1, 10, swiftUI: (0, 1, 11)),
        Row(.leading, 10, guide: 2, 10, swiftUI: (0, 2, 12)),
        Row(.leading, 10, guide: 5, 10, swiftUI: (0, 5, 15)),
        Row(.leading, 10, guide: 10, 10, swiftUI: (0, 10, 20)),
        Row(.leading, 10, guide: 15, 10, swiftUI: (0, 15, 25)),
        Row(.leading, 10, guide: 25, 10, swiftUI: (0, 25, 35)),
        Row(.leading, 10, guide: -1, 10, swiftUI: (1, 0, 11)),
        Row(.leading, 10, guide: -3, 10, swiftUI: (3, 0, 13)),
        Row(.leading, 10, guide: -10, 10, swiftUI: (10, 0, 20)),
        Row(.trailing, 1, guide: 0, 6, swiftUI: (6, 0, 7)),
        Row(.trailing, 1, guide: 1, 6, swiftUI: (5, 0, 6)),
        Row(.trailing, 1, guide: 2, 6, swiftUI: (4, 0, 6)),
        Row(.trailing, 1, guide: 5, 6, swiftUI: (1, 0, 6)),
        Row(.trailing, 1, guide: 10, 6, swiftUI: (0, 4, 10)),
        Row(.trailing, 1, guide: 15, 6, swiftUI: (0, 9, 15)),
        Row(.trailing, 1, guide: 25, 6, swiftUI: (0, 19, 25)),
        Row(.trailing, 1, guide: -1, 6, swiftUI: (7, 0, 8)),
        Row(.trailing, 1, guide: -3, 6, swiftUI: (9, 0, 10)),
        Row(.trailing, 1, guide: -10, 6, swiftUI: (16, 0, 17)),
        Row(.trailing, 6, guide: 0, 6, swiftUI: (6, 0, 12)),
        Row(.trailing, 6, guide: 1, 6, swiftUI: (5, 0, 11)),
        Row(.trailing, 6, guide: 2, 6, swiftUI: (4, 0, 10)),
        Row(.trailing, 6, guide: 5, 6, swiftUI: (1, 0, 7)),
        Row(.trailing, 6, guide: 10, 6, swiftUI: (0, 4, 10)),
        Row(.trailing, 6, guide: 15, 6, swiftUI: (0, 9, 15)),
        Row(.trailing, 6, guide: 25, 6, swiftUI: (0, 19, 25)),
        Row(.trailing, 6, guide: -1, 6, swiftUI: (7, 0, 13)),
        Row(.trailing, 6, guide: -3, 6, swiftUI: (9, 0, 15)),
        Row(.trailing, 6, guide: -10, 6, swiftUI: (16, 0, 22)),
        Row(.center, 1, guide: 0, 6, swiftUI: (3, 0, 6)),
        Row(.center, 1, guide: 1, 6, swiftUI: (2, 0, 6)),
        Row(.center, 1, guide: 2, 6, swiftUI: (1, 0, 6)),
        Row(.center, 1, guide: 5, 6, swiftUI: (0, 2, 8)),
        Row(.center, 1, guide: 10, 6, swiftUI: (0, 7, 13)),
        Row(.center, 1, guide: 15, 6, swiftUI: (0, 12, 18)),
        Row(.center, 1, guide: 25, 6, swiftUI: (0, 22, 28)),
        Row(.center, 1, guide: -1, 6, swiftUI: (4, 0, 6)),
        Row(.center, 1, guide: -3, 6, swiftUI: (6, 0, 7)),
        Row(.center, 1, guide: -10, 6, swiftUI: (13, 0, 14)),
        Row(.center, 6, guide: 0, 6, swiftUI: (3, 0, 9)),
        Row(.center, 6, guide: 1, 6, swiftUI: (2, 0, 8)),
        Row(.center, 6, guide: 2, 6, swiftUI: (1, 0, 7)),
        Row(.center, 6, guide: 5, 6, swiftUI: (0, 2, 8)),
        Row(.center, 6, guide: 10, 6, swiftUI: (0, 7, 13)),
        Row(.center, 6, guide: 15, 6, swiftUI: (0, 12, 18)),
        Row(.center, 6, guide: 25, 6, swiftUI: (0, 22, 28)),
        Row(.center, 6, guide: -1, 6, swiftUI: (4, 0, 10)),
        Row(.center, 6, guide: -3, 6, swiftUI: (6, 0, 12)),
        Row(.center, 6, guide: -10, 6, swiftUI: (13, 0, 19)),
        Row(.top, 1, guide: 0, 6, swiftUI: (0, 0, 6)),
        Row(.top, 1, guide: 1, 6, swiftUI: (0, 1, 7)),
        Row(.top, 1, guide: 2, 6, swiftUI: (0, 2, 8)),
        Row(.top, 1, guide: 5, 6, swiftUI: (0, 5, 11)),
        Row(.top, 1, guide: 10, 6, swiftUI: (0, 10, 16)),
        Row(.top, 1, guide: 15, 6, swiftUI: (0, 15, 21)),
        Row(.top, 1, guide: 25, 6, swiftUI: (0, 25, 31)),
        Row(.top, 1, guide: -1, 6, swiftUI: (1, 0, 6)),
        Row(.top, 1, guide: -3, 6, swiftUI: (3, 0, 6)),
        Row(.top, 1, guide: -10, 6, swiftUI: (10, 0, 11)),
        Row(.top, 6, guide: 0, 6, swiftUI: (0, 0, 6)),
        Row(.top, 6, guide: 1, 6, swiftUI: (0, 1, 7)),
        Row(.top, 6, guide: 2, 6, swiftUI: (0, 2, 8)),
        Row(.top, 6, guide: 5, 6, swiftUI: (0, 5, 11)),
        Row(.top, 6, guide: 10, 6, swiftUI: (0, 10, 16)),
        Row(.top, 6, guide: 15, 6, swiftUI: (0, 15, 21)),
        Row(.top, 6, guide: 25, 6, swiftUI: (0, 25, 31)),
        Row(.top, 6, guide: -1, 6, swiftUI: (1, 0, 7)),
        Row(.top, 6, guide: -3, 6, swiftUI: (3, 0, 9)),
        Row(.top, 6, guide: -10, 6, swiftUI: (10, 0, 16)),
        Row(.bottom, 1, guide: 0, 6, swiftUI: (6, 0, 7)),
        Row(.bottom, 1, guide: 1, 6, swiftUI: (5, 0, 6)),
        Row(.bottom, 1, guide: 2, 6, swiftUI: (4, 0, 6)),
        Row(.bottom, 1, guide: 5, 6, swiftUI: (1, 0, 6)),
        Row(.bottom, 1, guide: 10, 6, swiftUI: (0, 4, 10)),
        Row(.bottom, 1, guide: 15, 6, swiftUI: (0, 9, 15)),
        Row(.bottom, 1, guide: 25, 6, swiftUI: (0, 19, 25)),
        Row(.bottom, 1, guide: -1, 6, swiftUI: (7, 0, 8)),
        Row(.bottom, 1, guide: -3, 6, swiftUI: (9, 0, 10)),
        Row(.bottom, 1, guide: -10, 6, swiftUI: (16, 0, 17)),
        Row(.trailing, 3, guide: 0, 6, swiftUI: (6, 0, 9)),
        Row(.trailing, 3, guide: 1, 6, swiftUI: (5, 0, 8)),
        Row(.center, 6, guide: -6, 6, swiftUI: (9, 0, 15)),
        Row(.center, 6, guide: 0, 6, swiftUI: (3, 0, 9)),
        Row(.bottom, 3, guide: 0, 6, swiftUI: (6, 0, 9)),
    ]

    /// Where `character` first appears across the buffer's rows.
    private func column(of character: Character, in buffer: FrameBuffer) -> Int? {
        for line in buffer.lines {
            if let index = Array(line.stripped).firstIndex(of: character) { return index }
        }
        return nil
    }

    /// The first row `character` appears on.
    private func row(of character: Character, in buffer: FrameBuffer) -> Int? {
        buffer.lines.firstIndex { $0.stripped.contains(character) }
    }

    /// The probe's pair as a `VStack`: a run of `g`s with the guide over a run
    /// of `s`s.
    private func column(_ row: Row, _ alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(String(repeating: "g", count: row.guided)).alignmentGuide(alignment) { _ in row.guide }
            Text(String(repeating: "s", count: row.sibling))
        }
    }

    /// The probe's pair as an `HStack`: a column of `g`s with the guide beside
    /// a column of `s`s.
    private func line(_ row: Row, _ alignment: VerticalAlignment) -> some View {
        HStack(alignment: alignment, spacing: 0) {
            Column(character: "g", height: row.guided).alignmentGuide(alignment) { _ in row.guide }
            Column(character: "s", height: row.sibling)
        }
    }

    /// The placement TUI draws, and the extent it measures, for `row`.
    private func placement(_ row: Row) -> (guidedAt: Int?, siblingAt: Int?, extent: Int, measured: Int) {
        switch row.alignment {
        case .leading, .trailing, .center:
            let alignment: HorizontalAlignment =
                row.alignment == .leading ? .leading : row.alignment == .trailing ? .trailing : .center
            let context = makeBareRenderContext(width: 80, height: 10)
            let buffer = renderToBuffer(column(row, alignment), context: context)
            let measured = measureChild(column(row, alignment), proposal: .unspecified, context: context)
            return (column(of: "g", in: buffer), column(of: "s", in: buffer), buffer.width, measured.width)
        case .top, .bottom:
            let alignment: VerticalAlignment = row.alignment == .top ? .top : .bottom
            let context = makeBareRenderContext(width: 20, height: 60)
            let buffer = renderToBuffer(line(row, alignment), context: context)
            let measured = measureChild(line(row, alignment), proposal: .unspecified, context: context)
            return (self.row(of: "g", in: buffer), self.row(of: "s", in: buffer), buffer.height, measured.height)
        }
    }

    @Test("Each view sits where SwiftUI puts it, in a stack as big as SwiftUI's", arguments: rows)
    func matchesSwiftUI(row: Row) {
        let drawn = placement(row)
        #expect(drawn.guidedAt == row.swiftUI.guidedAt, "guided view")
        #expect(drawn.siblingAt == row.swiftUI.siblingAt, "sibling")
        #expect(drawn.extent == row.swiftUI.extent, "drawn extent")
        #expect(drawn.measured == row.swiftUI.extent, "measured extent")
    }

    /// The shape the question was first seen in: a one-character `Text` whose
    /// leading guide is set, over a six-character one. SwiftUI (12-point
    /// monospaced text, 7.5 points a character) puts the second at the guide's
    /// value in points, however narrow the first: 0, 5 and 20. TUI's
    /// one-cell view used to hold its guide to `[-1, 2]`, so 5 indented by 2.
    @Test("A one-character view's guide indents its sibling by the guide's full value", arguments: [0.0, 5, 20])
    func observedShape(guide: Double) {
        let buffer = renderToBuffer(
            VStack(alignment: .leading, spacing: 0) {
                Text("x").alignmentGuide(.leading) { _ in guide }
                Text("yyyyyy")
            },
            context: makeBareRenderContext(width: 80, height: 10))
        #expect(column(of: "x", in: buffer) == 0)
        #expect(column(of: "y", in: buffer) == Int(guide))
        #expect(buffer.width == Int(guide) + 6)
    }
}
