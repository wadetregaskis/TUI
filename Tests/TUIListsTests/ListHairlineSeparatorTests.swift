//  🖥️ TUI — A Terminal UI framework for Swift
//  ListHairlineSeparatorTests.swift
//
//  A list's separators as hairlines (decisions A-D6L-2, the owner's option 4):
//  where the terminal draws them, `.automatic` shows SwiftUI's default
//  separators, each a mark along the top of the row below that takes no row;
//  elsewhere, the list is what it was.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
@testable import TUIListsTestSupport
@testable import TUITestSupport
@testable import TUIView

@MainActor
@Suite("List separators as hairlines")
struct ListHairlineSeparatorTests {

    private static let names = ["a", "b", "c", "d"]

    private func names(_ names: [String] = Self.names) -> some View {
        List { ForEach(names, id: \.self) { Text($0) } }
    }

    /// `view`'s lines, rendered `24` wide, where the host does or does not
    /// draw hairlines.
    private func render(_ view: some View, hairlines: Bool, style: some ListStyle = PlainListStyle()) -> [String] {
        KittyGraphics.withHairlineSupport(hairlines) {
            renderToBuffer(view.listStyle(style), context: makeRenderContext(width: 24, height: 12)).lines
        }
    }

    /// The text of each line, trimmed, the blank fill below the rows dropped.
    private func text(_ lines: [String]) -> [String] {
        Array(lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }.prefix { !$0.isEmpty })
    }

    /// The runs on each line, as column ranges.
    private func runs(_ lines: [String]) -> [[Range<Int>]] {
        lines.map { HairlineMarker.extracting($0).runs.map { $0.column..<($0.column + $0.width) } }
    }

    /// The indices of the lines carrying a mark.
    ///
    /// The list has the focus in every one of these renders, so its first row
    /// is the cursor's, painted in the focus fill, and no line touches it
    /// (``focusedRow()``): the first boundary drawn is the second row's.
    private func markedLines(_ lines: [String]) -> [Int] {
        runs(lines).indices.filter { !runs(lines)[$0].isEmpty }
    }

    @Test("Where hairlines are drawn, .automatic shows a separator between every two rows")
    func automaticShowsThem() {
        let lines = render(names(), hairlines: true)
        #expect(markedLines(lines) == [2, 3])
        // Across the row's content: past the one-cell gutter, short of the
        // trailing one — the cells the rule line would run across.
        #expect(runs(lines)[2] == [1..<23])
    }

    /// A line across a highlight reads as a seam in it.
    @Test("No line touches the focused row: none above it, none below")
    func focusedRow() {
        let lines = render(names(), hairlines: true)
        #expect(lines[0].contains("\u{1B}[48;"), "the first row is not the focused one: \(lines[0].debugDescription)")
        #expect(runs(lines)[0].isEmpty && runs(lines)[1].isEmpty)
    }

    /// The point of the look: a separator that costs nothing.
    @Test("The rows do not move: the list is the one it is without separators")
    func rowsDoNotMove() {
        let with = render(names(), hairlines: true)
        let without = render(names(), hairlines: false)
        #expect(text(with) == ["a", "b", "c", "d"])
        #expect(with.map(\.stripped) == without.map(\.stripped))
        #expect(with.map { HairlineMarker.extracting($0).line.stripped } == without.map(\.stripped))
    }

    @Test("Elsewhere, .automatic stays hidden and nothing is marked")
    func elsewhereNone() {
        let lines = render(names(), hairlines: false)
        #expect(markedLines(lines).isEmpty)
        #expect(!lines.contains { HairlineMarker.mayCarryMark($0) })
        #expect(text(lines) == ["a", "b", "c", "d"])
    }

    @Test("Elsewhere, a separator asked for is today's rule line of its own")
    func elsewhereRules() {
        let lines = render(names(["a", "b"]).listRowSeparator(.visible), hairlines: false)
        #expect(text(lines).count == 3)
        #expect(text(lines)[1].allSatisfy { $0 == "─" })
        #expect(markedLines(lines).isEmpty)
    }

    @Test("Where hairlines are drawn, a separator asked for is a hairline too, and takes no row")
    func visibleIsAHairline() {
        let lines = render(names(["a", "b", "c"]).listRowSeparator(.visible), hairlines: true)
        #expect(text(lines) == ["a", "b", "c"])
        #expect(markedLines(lines) == [2])
    }

    @Test("As SwiftUI's: none under .sidebar or .insetGrouped", arguments: [0, 1])
    func stylesWithout(style: Int) {
        let lines =
            style == 0
            ? render(names(), hairlines: true, style: SidebarListStyle())
            : render(names(), hairlines: true, style: InsetGroupedListStyle())
        #expect(markedLines(lines).isEmpty)
    }

    @Test("Under .automatic, .inset, .bordered and .surface, they show", arguments: [0, 1, 2, 3])
    func stylesWith(style: Int) {
        let lines =
            switch style {
            case 0: render(names(), hairlines: true, style: DefaultListStyle())
            case 1: render(names(), hairlines: true, style: InsetListStyle())
            case 2: render(names(), hairlines: true, style: BorderedListStyle())
            default: render(names(), hairlines: true, style: SurfaceListStyle())
            }
        #expect(markedLines(lines).count == 2, "\(lines.map(\.stripped))")
    }

    @Test(".listSeparatorStyle(.line) keeps a rule line of its own, and .automatic hidden, on any host")
    func lineLook() {
        let hidden = render(names().listSeparatorStyle(.line), hairlines: true)
        #expect(markedLines(hidden).isEmpty)
        #expect(text(hidden) == ["a", "b", "c", "d"])
        let ruled = render(names(["a", "b"]).listRowSeparator(.visible).listSeparatorStyle(.line), hairlines: true)
        #expect(text(ruled).count == 3)
        #expect(markedLines(ruled).isEmpty)
    }

    @Test(".listSeparatorStyle(.hairline) takes no row where nothing draws it, and marks nothing")
    func hairlineLookElsewhere() {
        let lines = render(names(["a", "b"]).listRowSeparator(.visible).listSeparatorStyle(.hairline), hairlines: false)
        #expect(text(lines) == ["a", "b"])
        #expect(markedLines(lines).isEmpty)
    }

    @Test("A row's .hidden takes away the line under it")
    func rowHidden() {
        let list = List {
            ForEach(Self.names, id: \.self) { name in
                Text(name).listRowSeparator(name == "c" ? .hidden : .automatic)
            }
        }
        #expect(markedLines(render(list, hairlines: true)) == [2])
    }

    @Test("A tint is the line's colour")
    func tint() {
        let lines = render(names(["a", "b", "c"]).listRowSeparatorTint(.rgb(200, 10, 20)), hairlines: true)
        let run = HairlineMarker.extracting(lines[2]).runs.first
        #expect(run.map { [$0.red, $0.green, $0.blue] } == [200, 10, 20])
    }

    @Test("The leading guide insets the line, as it insets the rule")
    func leadingGuide() {
        let list = List {
            ForEach(["a", "b", "c"], id: \.self) { name in
                Text(name).alignmentGuide(.listRowSeparatorLeading) { _ in 3 }
            }
        }
        #expect(runs(render(list, hairlines: true))[2] == [4..<23])
    }

    @Test("No line touches a selected row")
    func selectedRow() {
        let list = List(selection: .constant(Optional("b"))) {
            ForEach(Self.names, id: \.self) { Text($0) }
        }
        #expect(markedLines(render(list, hairlines: true)) == [3])
    }

    /// The header is the cursor's first stop here, so the section's first
    /// separator to show is under its first row; hidden, the header's own
    /// leaves the rest.
    @Test("A section's separators are hairlines, and its .hidden edge is the style's to keep")
    func sections() {
        let list = List {
            Section("Head") { ForEach(["a", "b", "c"], id: \.self) { Text($0) } }
        }
        let lines = render(list, hairlines: true)
        #expect(text(lines) == ["Head", "a", "b", "c"])
        #expect(markedLines(lines) == [2, 3])
        let two = List {
            Section("A") { Text("a1"); Text("a2") }
            Section("B") { Text("b1") }
        }
        let shown = render(two, hairlines: true)
        let hidden = render(two.listSectionSeparator(.hidden, edges: .bottom), hairlines: true)
        // a2 | B is the first section's bottom edge.
        #expect(markedLines(shown).contains(3))
        #expect(!markedLines(hidden).contains(3))
    }

    /// The mark is not a colour the blend knows, so a line under a fade — a
    /// modal's dimmed backdrop above all — would stay at full strength over the
    /// dimmed rows. Until its colour is blended, it goes.
    @Test("A fade takes the line away")
    func fadeTakesTheLine() {
        KittyGraphics.withHairlineSupport(true) {
            let context = makeRenderContext(width: 24, height: 8)
            let faded = renderToBuffer(names().listStyle(.plain).opacity(0.5), context: context)
                .resolvingOpacity(surface: .black, palette: context.environment.palette)
            #expect(markedLines(faded.lines).isEmpty)
        }
    }

    @Test("A scroll view's clip keeps the lines on the rows it shows")
    func scrollClip() {
        // Three rows shown of four, the first the focused one: the line on the
        // third is the only one on screen, and the fourth's is clipped away.
        let lines = render(ScrollView { names().frame(height: 6) }.frame(height: 3), hairlines: true)
        #expect(lines.count == 3)
        #expect(markedLines(lines) == [2])
    }

    @Test("The marks survive the list's containers")
    func throughContainers() {
        let lines = render(names(["a", "b", "c"]).padding(1).border(), hairlines: true)
        #expect(markedLines(lines).count == 1)
    }
}

// MARK: - Through the run loop

/// A list on a screen, drawn by the run loop to a terminal that draws
/// hairlines: the lines are placed, and the mark never reaches the terminal.
private struct HairlineListApp: App {
    var body: some Scene {
        WindowGroup {
            List { ForEach(["one", "two", "three"], id: \.self) { Text($0) } }.listStyle(.plain)
        }
    }
}

@MainActor
@Suite("List hairlines through the run loop")
struct ListHairlineRunLoopTests {

    /// Three rows, the first the focused one: one line, between two and three.
    @Test("The first frame places a line per separator, the next places nothing, and no mark is written")
    func placedOnce() {
        KittyGraphics.withHairlineSupport(true) {
            let harness = RenderLoopHarness()
            harness.terminal.size = (40, 10)
            harness.terminal.reportedCellPixels = TerminalCellPixels(width: 16, height: 34)
            let loop = harness.loop(HairlineListApp())
            _ = loop.render()
            let first = harness.terminal.allOutput
            #expect(!first.contains("7744"))
            #expect(first.components(separatedBy: "\u{1B}_Ga=p,").count - 1 == 1, "\(first.debugDescription)")
            #expect(first.contains("\u{1B}_Ga=t,"))
            // Its own row and column, 1-based: the third row, past the gutter.
            #expect(first.contains("\u{1B}[3;2H\u{1B}_Ga=p,"))
            harness.terminal.reset()
            harness.terminal.size = (40, 10)
            _ = loop.render()
            #expect(!harness.terminal.allOutput.contains("\u{1B}_G"))
        }
    }

    @Test("Where the host draws none, a frame writes no graphics at all")
    func noneElsewhere() {
        KittyGraphics.withHairlineSupport(false) {
            let harness = RenderLoopHarness()
            harness.terminal.reportedCellPixels = TerminalCellPixels(width: 16, height: 34)
            let loop = harness.loop(HairlineListApp())
            _ = loop.render()
            #expect(!harness.terminal.allOutput.contains("\u{1B}_G"))
            #expect(loop.hairlines.isIdle)
        }
    }

    @Test("A resize places every line again; the farewell takes them away")
    func invalidationAndFarewell() {
        KittyGraphics.withHairlineSupport(true) {
            let harness = RenderLoopHarness()
            harness.terminal.size = (40, 10)
            harness.terminal.reportedCellPixels = TerminalCellPixels(width: 16, height: 34)
            let loop = harness.loop(HairlineListApp())
            _ = loop.render()
            harness.terminal.reset()
            harness.terminal.size = (40, 10)
            loop.invalidateDiffCache()
            _ = loop.render()
            let again = harness.terminal.allOutput
            #expect(again.contains("a=d,d=I"))
            #expect(again.components(separatedBy: "\u{1B}_Ga=p,").count - 1 == 1)
            #expect(loop.handBackHairlines().contains("a=d,d=I"))
            #expect(loop.hairlines.isIdle)
        }
    }
}
