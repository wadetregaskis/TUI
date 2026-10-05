//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompositeMembersLazyTests.swift
//
//  A view of the app's own whose `body` is several views is taken apart into
//  them (decisions D1S, B-D1S-6), and a lazy stack must stay as lazy over such
//  views as over the views written bare. A loop of views whose body is a
//  `Section` — `ForEach(groups) { GroupView(group: $0) }` — is a loop of
//  sections, which a lazy stack keeps whole to window over them (B-D1S-1).
//  Counted as rows of a number only each row knows, every view's body was
//  evaluated, and unpinned every row of every section built, on every walk.
//
//  A view whose body is a loop — `LazyVStack { TodoRows() }` — is that loop's
//  rows, one body step below the stack. A focused row scrolled out of the band
//  must still be found by its focus ID and drawn, or it registers nothing and
//  the focus is lost.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// How many bodies of the app's own were evaluated.
@MainActor
private final class Built {
    var bodies = 0
    func note() { bodies += 1 }
}

/// A group of rows as a section of the app's own.
private struct GroupView: View {
    let group: Int
    let built: Built?

    var body: some View {
        built?.note()
        return Section {
            ForEach(0..<(group % 3 + 1), id: \.self) { Text("row \(group).\($0)") }
        } header: {
            Text("Header \(group)")
        }
    }
}

/// The same group written as a bare `Section`.
@MainActor
private func bareGroup(_ group: Int) -> some View {
    Section {
        ForEach(0..<(group % 3 + 1), id: \.self) { Text("row \(group).\($0)") }
    } header: {
        Text("Header \(group)")
    }
}

/// A view whose body is a loop of buttons.
private struct ButtonRows: View {
    let count: Int
    var body: some View {
        ForEach(0..<count, id: \.self) { i in Button("row \(i)") {} }
    }
}

@MainActor
@Suite("A lazy stack stays lazy over views of the app's own taken apart")
struct CompositeMembersLazyTests {
    private static let viewportHeight = 6

    /// One frame at `windowOffset`, as the live loop draws it, with a
    /// persistent focus manager.
    @discardableResult
    private func renderFrame(
        _ view: some View, tuiContext: TUIContext, focusManager: FocusManager, windowOffset: Int
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focusManager
        environment.applyRuntimeServices(from: tuiContext)
        environment.scrollContentWindow = ScrollContentWindow(
            offset: windowOffset, viewportHeight: Self.viewportHeight)
        let context = RenderContext(
            availableWidth: 40, availableHeight: 4_000, environment: environment, tuiContext: tuiContext)
        tuiContext.keyEventDispatcher.clearHandlers()
        tuiContext.preferences.beginRenderPass()
        tuiContext.stateStorage.beginRenderPass()
        tuiContext.renderCache.beginRenderPass()
        focusManager.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focusManager.endRenderPass()
        tuiContext.stateStorage.endRenderPass()
        tuiContext.renderCache.removeInactive()
        return Array(buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
            .dropFirst(windowOffset).prefix(Self.viewportHeight))
    }

    // MARK: - A loop of sections of the app's own

    @Test("A lazy stack over a thousand sections of the app's own evaluates only the bodies it draws", arguments: [false, true])
    func loopOfSectionViewsStaysLazy(pinned: Bool) {
        let built = Built()
        let view = LazyVStack(alignment: .leading, spacing: 0, pinnedViews: pinned ? .sectionHeaders : []) {
            ForEach(0..<1_000, id: \.self) { GroupView(group: $0, built: built) }
        }
        let drawn = renderFrame(view, tuiContext: TUIContext(), focusManager: FocusManager(), windowOffset: 0)
        #expect(drawn.first == "Header 0", "\(drawn)")
        #expect(built.bodies < 100, "pinned \(pinned): evaluated \(built.bodies) bodies to draw a screen")
    }

    @Test("Such sections draw as the same sections written bare, pinned and not, wherever the stack is scrolled", arguments: [false, true])
    func loopOfSectionViewsDrawsAsBare(pinned: Bool) {
        let pins: PinnedScrollableViews = pinned ? .sectionHeaders : []
        let views = LazyVStack(alignment: .leading, spacing: 0, pinnedViews: pins) {
            ForEach(0..<300, id: \.self) { GroupView(group: $0, built: nil) }
        }
        let bare = LazyVStack(alignment: .leading, spacing: 0, pinnedViews: pins) {
            ForEach(0..<300, id: \.self) { bareGroup($0) }
        }
        let viewsContext = TUIContext()
        let bareContext = TUIContext()
        for offset in [0, 1, 3, 7, 50, 51, 400] {
            let drawn = renderFrame(views, tuiContext: viewsContext, focusManager: FocusManager(), windowOffset: offset)
            let expected = renderFrame(bare, tuiContext: bareContext, focusManager: FocusManager(), windowOffset: offset)
            #expect(drawn == expected, "pinned \(pinned), offset \(offset): \(drawn) vs \(expected)")
        }
    }

    @Test("To a List and to the section APIs, a loop of sections of the app's own is a loop of sections")
    func loopOfSectionViewsElsewhere() {
        let fixture = ListSectionEditingFixture()
        fixture.render(
            List(selection: .constant(Int?.none)) {
                ForEach(0..<2, id: \.self) { GroupView(group: $0, built: nil) }
            }
            .frame(height: 10))
        let handler = fixture.handler(Int.self)
        let ids = (0..<(handler?.itemCount ?? 0)).map { handler?.id(at: $0) }
        // Each group's header, then its rows, selected by their own ids.
        #expect(ids == [nil, 0, nil, 0, 1], "\(ids)")

        var counts: [Int] = []
        _ = renderToBuffer(
            Group(sections: ForEach(0..<3, id: \.self) { GroupView(group: $0, built: nil) }) { sections -> EmptyView in
                counts = sections.map { $0.content.count }
                return EmptyView()
            },
            context: makeRenderContext(width: 30, height: 8))
        #expect(counts == [1, 2, 3], "\(counts)")
    }

    // MARK: - A view whose body is a loop

    /// The bottom row's focus ID, captured while it is on screen.
    private func captureTailRowID(
        _ view: some View, rows: Int, tuiContext: TUIContext, focusManager: FocusManager
    ) -> String {
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: rows - Self.viewportHeight)
        let id = focusManager.registeredFocusIDsInActiveSection().last
        #expect(id?.contains("[\(rows - 1)]") == true, "the last row must have registered while visible: \(id ?? "nil")")
        return id ?? ""
    }

    // Such content is no lazy collection — the view's members come resolved,
    // in an array — so the stack takes its exact viewport walk, which finds
    // the focused row by its identity (`rowIndex(addressedBy:)`), not the
    // uniform window's parse of the focus ID for a `[key]` directly below the
    // stack (`rowKey(inFocusID:belowStackPath:)`), which the body step would
    // defeat. These pin that the row is found either way.
    @Test("A focused row of a view whose body is a loop is kept, drawn and focused, scrolled out of the band")
    func focusedRowKeptOffBand() {
        let rows = 500
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = LazyVStack(alignment: .leading, spacing: 0) { ButtonRows(count: rows) }

        let tailID = captureTailRowID(view, rows: rows, tuiContext: tuiContext, focusManager: focusManager)
        focusManager.focus(id: tailID)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: rows - Self.viewportHeight)
        #expect(focusManager.currentFocusedID == tailID)

        // Scrolled back to the top, the focused row is far out of the band.
        for _ in 0..<3 {
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        }
        #expect(focusManager.currentFocusedID == tailID, "focus left the row scrolled away from")
        #expect(
            focusManager.registeredFocusIDsInActiveSection().contains(tailID),
            "the focused row out of the band no longer registers")
    }

    @Test("Tab walks past the band's edge through a view whose body is a loop")
    func tabWalksPastTheBand() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let view = LazyVStack(alignment: .leading, spacing: 0) { ButtonRows(count: 500) }

        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        let ring = focusManager.registeredFocusIDsInActiveSection()
        guard let first = ring.first else {
            Issue.record("nothing registered")
            return
        }
        focusManager.focus(id: first)
        renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        for _ in 1...12 {
            focusManager.focusNext()
            renderFrame(view, tuiContext: tuiContext, focusManager: focusManager, windowOffset: 0)
        }
        #expect(
            focusManager.currentFocusedID?.contains("[12]") == true,
            "twelve steps from row 0: \(focusManager.currentFocusedID ?? "nil")")
    }
}
