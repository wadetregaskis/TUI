//  🖥️ TUI — A Terminal UI framework for Swift
//  ForEachRowVaryingMembersTests.swift
//
//  A `ForEach` row of several views with an `if` without `else` among them —
//  `Text(name); if flagged { Text("!") }` — makes two views for some elements
//  and one for others, as SwiftUI counts them
//  (`Tools/SwiftUIProbes/Sections and subview counting/b15.swift`: a false
//  condition is no subview). Counted from its type as a fixed two, it handed
//  every walk that trusts the type an empty child for each element whose
//  condition was false: a `List` drew an invisible row the cursor stopped on,
//  a hand-written row beside the loop cost every looped row its selection
//  value, and `Group(subviews:)` counted the missing views. Decisions B15.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport
@testable import TUIView

/// What a transform or a layout was handed.
@MainActor
private final class Seen {
    var count = -1
    var tags: [String?] = []
}

/// Reports its subviews' count and implicit `String` tags.
private struct TagReading: Layout {
    let seen: Seen

    func sizeThatFits(proposal: ProposedSize, subviews: Subviews, cache: inout ()) -> ViewSize {
        seen.count = subviews.count
        seen.tags = subviews.map { $0.containerValues.tag(for: String.self) }
        return ViewSize(width: 1, height: 1)
    }

    func placeSubviews(in bounds: CellRect, proposal: ProposedSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(in: bounds, anchor: .topLeading, proposal: proposal) }
    }
}

@MainActor
@Suite("A ForEach row with an if among its views", .rendersEnglishUI)
struct ForEachRowVaryingMembersTests {

    /// Element `name`'s row: its name, and a detail line only for `b`.
    @ViewBuilder
    private static func row(_ name: String) -> some View {
        Text(name)
        if name == "b" { Text("detail") }
    }

    private static let names = ["a", "b", "c"]

    /// A live `List`, rendered through the real focus manager, so its rows'
    /// selection values are the handler's.
    @MainActor
    private final class Fixture {
        let tui = TUIContext()
        var env = EnvironmentValues()
        private(set) var buffer = FrameBuffer()

        init() {
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
        }

        var handler: ItemListHandler<String>? {
            env.focusManager?.currentFocused as? ItemListHandler<String>
        }

        /// Every row's selection value, `nil` for a row the selection cannot
        /// name.
        var rowIDs: [String?] {
            guard let handler else { return [] }
            return (0..<handler.itemCount).map { handler.id(at: $0) }
        }

        func render(_ view: some View) {
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            let context = RenderContext(
                availableWidth: 30, availableHeight: 12, environment: env, tuiContext: tui)
            buffer = renderToBuffer(view, context: context)
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
    }

    @Test("Group(subviews:) counts only the views a row makes, as SwiftUI does")
    func subviewsCount() {
        var count = -1
        let loop = ForEach(0..<3, id: \.self) { i in
            Text("a")
            if i != 1 { Text("b") }
        }
        _ = renderToBuffer(
            Group(subviews: loop) { subviews -> EmptyView in
                count = subviews.count
                return EmptyView()
            },
            context: makeRenderContext(width: 20, height: 6))
        #expect(count == 5)
    }

    @Test("A Layout tags each view a row makes with its element")
    func layoutTags() {
        let seen = Seen()
        _ = renderToBuffer(
            TagReading(seen: seen) { ForEach(Self.names, id: \.self) { Self.row($0) } },
            context: makeRenderContext(width: 20, height: 6))
        #expect(seen.count == 4)
        #expect(seen.tags == ["a", "b", "b", "c"])
    }

    @Test("A List draws a row only for each view there is, each selected by its element")
    func listOfTheLoop() {
        let fixture = Fixture()
        var selection: String?
        func list() -> some View {
            List(selection: Binding(get: { selection }, set: { selection = $0 })) {
                ForEach(Self.names, id: \.self) { Self.row($0) }
            }
            .frame(height: 8)
        }
        fixture.render(list())
        #expect(fixture.rowIDs == ["a", "b", "b", "c"], "\(fixture.rowIDs)")
        guard let handler = fixture.handler else {
            Issue.record("the list took focus")
            return
        }
        // Down from "detail" lands on "c": no invisible row between them.
        handler.focusedIndex = 2
        _ = handler.handleKeyEvent(KeyEvent(key: .down))
        #expect(handler.handleKeyEvent(KeyEvent(key: .space)) == true)
        #expect(selection == "c", "Space after one Down from the detail row: \(String(describing: selection))")
    }

    @Test("Beside a hand-written row, the loop's rows keep their elements' selection values")
    func listBesideAHandWrittenRow() {
        let fixture = Fixture()
        fixture.render(
            List(selection: .constant(String?.none)) {
                Text("All").tag("all")
                ForEach(Self.names, id: \.self) { Self.row($0) }
            }
            .frame(height: 8))
        #expect(fixture.rowIDs == ["all", "a", "b", "b", "c"], "\(fixture.rowIDs)")
    }

    @Test("In a Section, the loop's rows keep their elements' selection values")
    func sectionRows() {
        let section = Section { ForEach(Self.names, id: \.self) { Self.row($0) } }
        let extracted: SectionContentRows<String> = section.extractSectionContentRows(
            context: makeRenderContext(width: 30, height: 8))
        #expect(extracted.rows.map(\.id) == ["a", "b", "b", "c"])
    }

    @Test("A lazy stack draws each view a row makes, and nothing for the one it does not")
    func lazyStack() {
        let drawn = renderToBuffer(
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) { ForEach(Self.names, id: \.self) { Self.row($0) } }
            }
            .frame(height: 8),
            context: makeRenderContext(width: 20, height: 8)
        ).lines.map(\.stripped).map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(Array(drawn.prefix(7)) == ["a", "", "b", "", "detail", "", "c"], "\(drawn)")
    }

    @Test("An if around one view as a loop's whole row is still one child, empty while false")
    func wholeRowIf() {
        let children = resolveChildViews(
            from: ForEach(0..<3, id: \.self) { i in if i != 1 { Text("x") } },
            context: makeRenderContext(width: 10, height: 4))
        #expect(children.count == 3)
    }
}
