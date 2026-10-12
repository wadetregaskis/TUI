//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlignmentGuideContainerParityTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A column of `height` one-cell rows of `character`.
private struct Column: View {
    let character: Character
    let height: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<height, id: \.self) { _ in Text(String(character)) }
        }
    }
}

/// One single-child placement measured in SwiftUI: a 6-cell view whose guide
/// for the region's alignment is `guide`, in a 20-cell region.
struct GuidePlacementRow: Sendable, CustomTestStringConvertible {
    let alignment: GuideProbeRow.Alignment
    let guide: Double
    /// Where SwiftUI put the view's leading (or top) edge: the region's guide
    /// less the view's, outside the region where that falls outside it.
    let swiftUI: Int

    init(_ alignment: GuideProbeRow.Alignment, guide: Double, swiftUI: Int) {
        self.alignment = alignment
        self.guide = guide
        self.swiftUI = swiftUI
    }

    /// Where TUIkit draws it: the nearest place to SwiftUI's that keeps the
    /// whole view inside the region, as it places a view wider than its region.
    var tuikit: Int { min(max(0, swiftUI), 20 - 6) }

    var testDescription: String { ".\(alignment), guide \(Int(guide))" }
}

/// SwiftUI's guide rule — each view at `max(guides) - its guide`, the guide
/// used as given — in the other containers that place through the same run:
/// `ZStack`, the lazy stacks, and the single-child placements of `.frame`,
/// `.overlay` and `.background`.
///
/// Measured with SwiftUI 6.5.4 on macOS 15.8.1, offscreen `NSHostingView`,
/// 2026-10-11 (`Tools/SwiftUIProbes/Alignment guides/guide2.swift` to `guide6.swift`).
/// One point stands for one cell.
@MainActor
@Suite("Alignment guides in a ZStack, a lazy stack and a single-child placement")
struct AlignmentGuideContainerParityTests {
    typealias Row = GuideProbeRow
    typealias Placement = GuidePlacementRow

    /// A `ZStack` sizes to its run exactly as a stack does.
    nonisolated static let zStackRows: [Row] = [
        Row(.leading, 1, guide: 5, 6, swiftUI: (0, 5, 11)),
        Row(.leading, 1, guide: 25, 6, swiftUI: (0, 25, 31)),
        Row(.leading, 1, guide: -10, 6, swiftUI: (10, 0, 11)),
        Row(.trailing, 3, guide: 0, 6, swiftUI: (6, 0, 9)),
        Row(.trailing, 3, guide: 10, 6, swiftUI: (0, 4, 10)),
        Row(.top, 1, guide: 5, 6, swiftUI: (0, 5, 11)),
    ]

    /// `.frame(width: 20, alignment:)` around one 6-wide view: SwiftUI puts the
    /// view's guide on the frame's, even where that is outside the frame.
    nonisolated static let frameRows: [Placement] = [
        Placement(.leading, guide: 0, swiftUI: 0),
        Placement(.leading, guide: 5, swiftUI: -5),
        Placement(.leading, guide: 25, swiftUI: -25),
        Placement(.leading, guide: -5, swiftUI: 5),
        Placement(.trailing, guide: 0, swiftUI: 20),
        Placement(.trailing, guide: 5, swiftUI: 15),
        Placement(.trailing, guide: 25, swiftUI: -5),
        Placement(.trailing, guide: -5, swiftUI: 25),
        Placement(.center, guide: 0, swiftUI: 10),
        Placement(.center, guide: 5, swiftUI: 5),
        Placement(.center, guide: 25, swiftUI: -15),
        Placement(.center, guide: -5, swiftUI: 15),
    ]

    /// `.overlay(alignment:)` and `.background(alignment:)` on a 20-wide view.
    nonisolated static let layerRows: [Placement] = [
        Placement(.leading, guide: 5, swiftUI: -5),
        Placement(.leading, guide: -5, swiftUI: 5),
        Placement(.leading, guide: 25, swiftUI: -25),
        Placement(.trailing, guide: 0, swiftUI: 20),
        Placement(.trailing, guide: 5, swiftUI: 15),
        Placement(.trailing, guide: -5, swiftUI: 25),
    ]

    private func column(of character: Character, in buffer: FrameBuffer) -> Int? {
        for line in buffer.lines {
            if let index = Array(line.stripped).firstIndex(of: character) { return index }
        }
        return nil
    }

    private func row(of character: Character, in buffer: FrameBuffer) -> Int? {
        buffer.lines.firstIndex { $0.stripped.contains(character) }
    }

    private func horizontal(_ alignment: Row.Alignment) -> HorizontalAlignment {
        alignment == .leading ? .leading : alignment == .trailing ? .trailing : .center
    }

    private func guided(_ row: Placement) -> some View {
        Text("cccccc").alignmentGuide(horizontal(row.alignment)) { _ in row.guide }
    }

    // MARK: - ZStack

    @Test("A ZStack places its layers where SwiftUI does, and is as big", arguments: zStackRows)
    func zStack(row: Row) {
        if row.alignment.isHorizontal {
            let alignment = horizontal(row.alignment)
            let stack = ZStack(alignment: Alignment(horizontal: alignment, vertical: .center)) {
                Text(String(repeating: "g", count: row.guided)).alignmentGuide(alignment) { _ in row.guide }
                Text(String(repeating: "s", count: row.sibling))
            }
            let context = makeBareRenderContext(width: 80, height: 10)
            let buffer = renderToBuffer(stack, context: context)
            #expect(column(of: "g", in: buffer) == row.swiftUI.guidedAt)
            #expect(column(of: "s", in: buffer) == row.swiftUI.siblingAt)
            #expect(buffer.width == row.swiftUI.extent)
            #expect(measureChild(stack, proposal: .unspecified, context: context).width == row.swiftUI.extent)
        } else {
            let stack = ZStack(alignment: .top) {
                Column(character: "g", height: row.guided).alignmentGuide(.top) { _ in row.guide }
                Column(character: "s", height: row.sibling)
            }
            let context = makeBareRenderContext(width: 20, height: 60)
            let buffer = renderToBuffer(stack, context: context)
            #expect(self.row(of: "g", in: buffer) == row.swiftUI.guidedAt)
            #expect(self.row(of: "s", in: buffer) == row.swiftUI.siblingAt)
            #expect(buffer.height == row.swiftUI.extent)
            #expect(measureChild(stack, proposal: .unspecified, context: context).height == row.swiftUI.extent)
        }
    }

    // MARK: - Lazy stacks

    @Test("A lazy column outside a scroll view sizes to its run as a column does")
    func placedLazyColumn() {
        let buffer = renderToBuffer(
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("g").alignmentGuide(.leading) { _ in 25 }
                Text("ssssss")
            },
            context: makeBareRenderContext(width: 80, height: 10))
        #expect(column(of: "g", in: buffer) == 0)
        #expect(column(of: "s", in: buffer) == 25)
    }

    @Test("A lazy column's window moves the run as a whole, its guides still on one line")
    func windowedLazyColumn() {
        // The window is the region (20 wide), bigger than the 9-cell run: the
        // run moves to the region's trailing edge, and the 3-wide view whose
        // trailing guide is 0 keeps its guide on the 6-wide view's trailing
        // edge. Moving to the region's guide (20) and pulling back only the
        // view that then hung out left the two 3 cells apart.
        var context = makeRenderContext(width: 20, height: 4)
        context.environment.scrollContentWindow = ScrollContentWindow(offset: 0, viewportHeight: 4)
        let buffer = renderToBuffer(
            LazyVStack(alignment: .trailing, spacing: 0) {
                Text("ggg").alignmentGuide(.trailing) { _ in 0 }
                Text("ssssss")
            },
            context: context)
        #expect(column(of: "g", in: buffer) == 17)
        #expect(column(of: "s", in: buffer) == 11)
    }

    // MARK: - One child in a region

    @Test("A frame places its child as near SwiftUI's place as the frame allows", arguments: frameRows)
    func frame(row: Placement) {
        let buffer = renderToBuffer(
            guided(row).frame(width: 20, alignment: Alignment(horizontal: horizontal(row.alignment), vertical: .center)),
            context: makeBareRenderContext(width: 80, height: 4))
        #expect(column(of: "c", in: buffer) == row.tuikit)
        #expect(buffer.width == 20)
    }

    @Test("A frame places a vertical guide the same way", arguments: [(5.0, -5), (-5, 5)])
    func verticalFrame(guide: Double, swiftUI: Int) {
        let buffer = renderToBuffer(
            Column(character: "c", height: 6).alignmentGuide(.top) { _ in guide }.frame(height: 20, alignment: .top),
            context: makeBareRenderContext(width: 10, height: 40))
        #expect(row(of: "c", in: buffer) == min(max(0, swiftUI), 14))
    }

    @Test("An overlay places its content as near SwiftUI's place as its base allows", arguments: layerRows)
    func overlay(row: Placement) {
        let alignment = Alignment(horizontal: horizontal(row.alignment), vertical: .center)
        let buffer = renderToBuffer(
            Text(String(repeating: "b", count: 20)).overlay(alignment: alignment) { guided(row) },
            context: makeBareRenderContext(width: 80, height: 4))
        #expect(column(of: "c", in: buffer) == row.tuikit)
    }

    @Test("A background places its content as near SwiftUI's place as its base allows", arguments: layerRows)
    func background(row: Placement) {
        let alignment = Alignment(horizontal: horizontal(row.alignment), vertical: .center)
        let buffer = renderToBuffer(
            Color.clear.frame(width: 20, height: 1).background(alignment: alignment) { guided(row) },
            context: makeBareRenderContext(width: 80, height: 4))
        #expect(column(of: "c", in: buffer) == row.tuikit)
    }
}
