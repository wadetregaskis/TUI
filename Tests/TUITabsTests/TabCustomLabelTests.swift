//  🖥️ TUI — A Terminal UI framework for Swift
//  TabCustomLabelTests.swift
//
//  A tab's label of the app's own (`Tab(content:label:)`) is drawn inside its
//  chip (owner, 2026-10-26, B75): whole, as tall as it draws — a row of chips
//  as tall as its tallest label — in the strip's ink where it states none, its
//  own colours kept, and breathing on the active chip as a text label does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUITabs
@testable import TUITestSupport

@MainActor
@Suite("A tab's own label is drawn in its chip")
struct TabCustomLabelTests {

    /// The colour a label of the app's own states for one of its words.
    private let hot = Color.rgb(200, 30, 40)

    /// A two-line label beside a text one, in `style`.
    private func twoLineTabs(_ style: some TabViewStyle, badge: Int = 0) -> some View {
        TabView(selection: .constant(0)) {
            Tab(value: 0) { Text("BODY") } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 1) {
                        Text("Hot").foregroundStyle(hot)
                        Text("Top")
                    }
                    Text("Bottom")
                }
            }
            .badge(badge)
            Tab("Plain", value: 1) { Text("OTHER") }
        }
        .tabViewStyle(style)
    }

    @Test("A two-line label draws both lines in its chip, and the content starts below them")
    func twoLines() {
        let drawn = renderToBuffer(twoLineTabs(.compact), context: makeRenderContext(width: 40, height: 8))
        let screen = drawn.lines.map(\.stripped)
        #expect(screen[0].contains("Hot Top"), "\(screen)")
        #expect(screen[1].contains("Bottom"), "\(screen)")
        // A text label sits on the middle line of the taller row.
        #expect(screen[1].contains("Plain") && !screen[0].contains("Plain"), "\(screen)")
        #expect(screen[2].contains("BODY"), "\(screen)")
    }

    @Test("A label's own colour is kept, and what it states none for takes the strip's ink")
    func ownColoursKept() throws {
        let drawn = renderToBuffer(twoLineTabs(.compact), context: makeRenderContext(width: 40, height: 8))
        let line = drawn.lines[0]
        let stripped = line.stripped
        let hotColumn = try #require(stripped.range(of: "Hot").map { stripped.distance(from: stripped.startIndex, to: $0.lowerBound) })
        let topColumn = try #require(stripped.range(of: "Top").map { stripped.distance(from: stripped.startIndex, to: $0.lowerBound) })
        #expect(truecolorInk(line, atColumn: hotColumn) == "200;30;40", "\(line.debugDescription)")
        #expect(truecolorInk(line, atColumn: topColumn) != "200;30;40", "\(line.debugDescription)")
    }

    @Test("A badge sits beside the label's middle line")
    func badgeOnMiddleLine() {
        let drawn = renderToBuffer(twoLineTabs(.compact, badge: 3), context: makeRenderContext(width: 40, height: 8))
        let screen = drawn.lines.map(\.stripped)
        // After the label's block, which is as wide as its widest line.
        #expect(screen[1].contains("Bottom  3"), "\(screen)")
        #expect(!screen[0].contains("3"), "\(screen)")
    }

    @Test("A folder tab's walls run down every line of a tall label")
    func borderedWalls() {
        let drawn = renderToBuffer(twoLineTabs(.bordered), context: makeRenderContext(width: 40, height: 10))
        let screen = drawn.lines.map(\.stripped)
        // Tops, two label lines, then the box's top border.
        #expect(screen[1].contains("Hot Top") && screen[2].contains("Bottom"), "\(screen)")
        for row in 1...2 {
            let walls = screen[row].filter { $0 == "│" }.count
            #expect(walls == 3, "row \(row) has \(walls) walls: \(screen)")
        }
        #expect(screen.contains { $0.contains("BODY") }, "\(screen)")
        #expect(drawn.height <= 10)
    }

    @Test("A strip of text labels is one line, as before")
    func textLabelsUnchanged() {
        let drawn = renderToBuffer(
            TabView(selection: .constant(0)) {
                Tab("One", value: 0) { Text("BODY") }
                Tab("Two", value: 1) { Text("OTHER") }
            },
            context: makeRenderContext(width: 40, height: 8))
        let screen = drawn.lines.map(\.stripped)
        #expect(screen[0].contains("One") && screen[0].contains("Two"), "\(screen)")
        #expect(screen[1].contains("BODY"), "\(screen)")
    }

    @Test("A click on a tall label's second line selects its tab")
    func clickOnSecondLine() throws {
        let view = TabView(selection: .constant(1)) {
            Tab(value: 0) { Text("BODY") } label: {
                VStack(spacing: 0) {
                    Text("Top")
                    Text("Bottom")
                }
            }
            Tab("Plain", value: 1) { Text("OTHER") }
        }
        let drawn = renderToBuffer(view, context: makeRenderContext(width: 40, height: 8))
        let stripped = drawn.lines[1].stripped
        let column = try #require(stripped.range(of: "Bottom").map { stripped.distance(from: stripped.startIndex, to: $0.lowerBound) })
        // The chip's click region: the one two lines tall that holds the word.
        let region = try #require(
            drawn.hitTestRegions.last { region in
                region.height == 2 && (region.offsetX..<(region.offsetX + region.width)).contains(column)
            })
        #expect(region.offsetY == 0, "\(region)")
    }

    @Test("A focused strip's active tall label breathes on each of its lines, its own colour still")
    func breathesEveryLine() throws {
        let context = makeRenderContext(width: 40, height: 8)
        // Rendered twice, so the frame asserted on is not the one the strip
        // registered its focus in.
        _ = renderToBuffer(twoLineTabs(.compact), context: context)
        let drawn = renderToBuffer(twoLineTabs(.compact), context: context)
        let runs = drawn.animatedCells.filter { $0.offsetY < 2 }
        #expect(Set(runs.map(\.offsetY)) == [0, 1], "\(runs.map { ($0.offsetX, $0.offsetY) })")
        let top = try #require(runs.first { $0.offsetY == 0 })
        // The label's words in every frame, and its own colour in every frame.
        #expect(top.frames.allSatisfy { $0.stripped.contains("Hot Top") })
        #expect(top.frames.allSatisfy { $0.contains("38;2;200;30;40") })
        // The strip's ink moves.
        #expect(Set(top.frames).count > 1, "the label holds still")
    }
}
