//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionActionsTests.swift
//
//  `.sectionActions(content:)`: a list section's actions on its header's
//  line, shown while the section is in use — the focused list's cursor, the
//  focus or the pointer in it (owner ruling B78-VISIBILITY) — and reached by
//  the keyboard; outside a list, nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitLists
@testable import TUIkitTestSupport

@MainActor
@Suite("Section actions")
struct SectionActionsTests {
    private final class Counter {
        var presses = 0
    }

    private func lines(_ view: some View, context: RenderContext? = nil) -> [String] {
        renderToBuffer(view, context: context ?? makeRenderContext(width: 40, height: 10)).lines.map(\.stripped)
    }

    /// The second frame of `view`, by when a list holds the focus the first
    /// frame gave it, its cursor in its first section.
    private func focusedLines(_ view: some View) -> [String] {
        let context = makeRenderContext(width: 40, height: 10)
        _ = lines(view, context: context)
        return lines(view, context: context)
    }

    /// A context with the services a pointer needs, and its `TUIContext`.
    private func harness() -> (TUIContext, RenderContext) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        return (tui, RenderContext(availableWidth: 40, availableHeight: 12, environment: environment, tuiContext: tui))
    }

    /// One frame, as the run loop draws it.
    private func frame(_ view: some View, tui: TUIContext, context: RenderContext) -> [String] {
        tui.mouseEventDispatcher.beginRenderPass()
        tui.keyEventDispatcher.clearHandlers()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        context.environment.focusManager?.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        tui.mouseEventDispatcher.setRegions(buffer.hitTestRegions)
        tui.stateStorage.endRenderPass()
        context.environment.focusManager?.endRenderPass()
        return buffer.lines.map(\.stripped)
    }

    /// Two sections with actions, under a button that takes the first focus.
    private func twoSections(focusFirst: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if focusFirst { Button("Elsewhere") {} }
            List {
                Section("Fruit") {
                    Text("Apple")
                    Text("Pear")
                }
                .sectionActions { Button("AddFruit") {} }
                Section("Veg") {
                    Text("Leek")
                }
                .sectionActions { Button("AddVeg") {} }
            }
        }
    }

    private func list(_ counter: Counter) -> some View {
        List {
            Section("Fruit") {
                Text("Apple")
                Text("Pear")
            }
            .sectionActions {
                Button("Add") { counter.presses += 1 }
            }
        }
    }

    @Test("In a list the actions are drawn on the header's line, and the rows stay rows")
    func drawnOnTheHeaderLine() {
        let drawn = focusedLines(list(Counter()))
        guard let header = drawn.firstIndex(where: { $0.contains("Fruit") }) else {
            Issue.record("\(drawn)")
            return
        }
        #expect(drawn[header].contains("Add"), "\(drawn)")
        #expect(drawn.firstIndex { $0.contains("Apple") } == header + 1, "\(drawn)")
        #expect(drawn.contains { $0.contains("Pear") }, "\(drawn)")
    }

    /// The cells after a line's last ink, before the list's right border —
    /// the trailing edge a badge and a flush-right action end at.
    private func trailingGap(_ line: String) -> Int {
        var cells = Array(line)
        if cells.last == "│" { cells.removeLast() }
        return cells.reversed().prefix { $0 == " " }.count
    }

    /// macOS puts the actions at the trailing end of the header; a list that
    /// hugs its rows draws its headers before it knows its width (decisions
    /// B78).
    @Test("In a list that fills its width the actions end where a row's badge ends; in one that hugs, after the title")
    func flushRightWhereTheListFills() {
        // In lines, where the badge's capsule and the action's face both end in
        // a glyph: a filled capsule ends in a cell of its field, which the gap
        // below cannot tell from the row's.
        let rows = List {
            Section("Fruit") {
                Text("Apple").badge(5)
            }
            .sectionActions {
                Button("Add") {}
            }
        }
        .controlStyle(.lines)
        let filled = focusedLines(rows)
        guard let header = filled.first(where: { $0.contains("Fruit") }),
            let apple = filled.first(where: { $0.contains("Apple") })
        else {
            Issue.record("\(filled)")
            return
        }
        #expect(trailingGap(header) == trailingGap(apple), "the action ends where the badge does: \(filled)")
        #expect(trailingGap(header) <= 2, "flush right: \(filled)")
        let hugged = focusedLines(HStack(spacing: 0) {
            rows.fixedSize(horizontal: true, vertical: false)
            Spacer()
        })
        guard let huggedHeader = hugged.first(where: { $0.contains("Fruit") }),
            let title = huggedHeader.range(of: "Fruit"), let add = huggedHeader.range(of: "Add")
        else {
            Issue.record("\(hugged)")
            return
        }
        #expect(
            huggedHeader.distance(from: title.upperBound, to: add.lowerBound) <= 3,
            "after the title in a list that hugs: \(hugged)")
    }

    @Test("An action is a focus stop that Return presses")
    func actionIsAFocusStop() {
        let counter = Counter()
        let context = makeRenderContext(width: 40, height: 10)
        let view = list(counter)
        _ = lines(view, context: context)
        _ = lines(view, context: context)
        guard let manager = context.environment.focusManager else {
            Issue.record("no focus manager")
            return
        }
        let ring = manager.registeredFocusIDsInActiveSection()
        guard let button = ring.first(where: { $0.hasPrefix("button") }) else {
            Issue.record("the action is no focus stop: \(ring)")
            return
        }
        manager.focus(id: button)
        _ = lines(view, context: context)
        #expect(manager.dispatchKeyEvent(KeyEvent(key: .enter)))
        #expect(counter.presses == 1)
    }

    @Test("A section without a header shows its actions alone on the header's line")
    func headerlessSection() {
        let drawn = focusedLines(
            List {
                Section {
                    Text("Apple")
                }
                .sectionActions {
                    Button("Add") {}
                }
            })
        guard let actions = drawn.firstIndex(where: { $0.contains("Add") }) else {
            Issue.record("\(drawn)")
            return
        }
        #expect(drawn.firstIndex { $0.contains("Apple") } == actions + 1, "\(drawn)")
    }

    @Test("A custom container reads them as the section's configuration actions")
    func configurationActions() {
        let content = Group {
            Section { Text("a") }
                .sectionActions { Text("act") }
            Section { Text("b") }
        }
        let drawn = lines(
            VStack(alignment: .leading) {
                ForEach(sections: content) { section in
                    HStack(spacing: 1) {
                        section.content
                        section.actions
                    }
                }
            })
        #expect(drawn.contains { $0.contains("a act") }, "\(drawn)")
        #expect(drawn.contains { $0.contains("b") && !$0.contains("act") }, "\(drawn)")
    }

    @Test("Not in use, the actions' cells stay blank: no focus stop, and the rows do not move")
    func hiddenWhileTheFocusIsElsewhere() {
        let context = makeRenderContext(width: 40, height: 12)
        let view = twoSections(focusFirst: true)
        _ = lines(view, context: context)
        let drawn = lines(view, context: context)
        #expect(!drawn.joined().contains("Add"), "\(drawn)")
        guard let header = drawn.firstIndex(where: { $0.contains("Fruit") }) else {
            Issue.record("\(drawn)")
            return
        }
        #expect(drawn.firstIndex { $0.contains("Apple") } == header + 1, "\(drawn)")
        let ring = context.environment.focusManager?.registeredFocusIDsInActiveSection() ?? []
        #expect(ring.filter { $0.hasPrefix("button") }.count == 1, "only Elsewhere: \(ring)")
        // A headerless section keeps its actions' line, blank.
        let headerless = List {
            Section { Text("Apple") }.sectionActions { Button("Add") {} }
        }
        let other = VStack { Button("Elsewhere") {}; headerless }
        let otherContext = makeRenderContext(width: 40, height: 10)
        _ = lines(other, context: otherContext)
        let blank = lines(other, context: otherContext)
        let shown = focusedLines(headerless)
        #expect(
            blank.firstIndex { $0.contains("Apple") }.map { $0 - 1 } == shown.firstIndex { $0.contains("Apple") },
            "the line stays: \(blank) \(shown)")
    }

    @Test("Only the section the cursor is in shows its actions; moving the cursor moves them")
    func followTheCursor() {
        let context = makeRenderContext(width: 40, height: 12)
        let view = twoSections(focusFirst: false)
        _ = lines(view, context: context)
        var drawn = lines(view, context: context)
        #expect(drawn.contains { $0.contains("Fruit") && $0.contains("AddFruit") }, "\(drawn)")
        #expect(!drawn.joined().contains("AddVeg"), "\(drawn)")
        for _ in 0..<3 { _ = context.environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .down)) }
        drawn = lines(view, context: context)
        #expect(drawn.contains { $0.contains("Veg") && $0.contains("AddVeg") }, "\(drawn)")
        #expect(!drawn.joined().contains("AddFruit"), "\(drawn)")
    }

    @Test("Tab from the list reaches the section's action, which stays while it holds the focus")
    func tabReachesTheActions() {
        let context = makeRenderContext(width: 40, height: 12)
        let view = twoSections(focusFirst: false)
        _ = lines(view, context: context)
        _ = lines(view, context: context)
        guard let manager = context.environment.focusManager else {
            Issue.record("no focus manager")
            return
        }
        _ = manager.dispatchKeyEvent(KeyEvent(key: .tab))
        let drawn = lines(view, context: context)
        #expect(manager.currentFocusedID?.hasPrefix("button") == true, "\(manager.currentFocusedID ?? "nil")")
        #expect(drawn.contains { $0.contains("Fruit") && $0.contains("AddFruit") }, "\(drawn)")
        #expect(!drawn.joined().contains("AddVeg"), "\(drawn)")
    }

    @Test("The pointer over a section shows its actions, and leaving takes them away")
    func pointerShowsThem() throws {
        let (tui, context) = harness()
        tui.mouseEventDispatcher.setActiveSupport(.full)
        let view = twoSections(focusFirst: true)
        _ = frame(view, tui: tui, context: context)
        var drawn = frame(view, tui: tui, context: context)
        #expect(!drawn.joined().contains("Add"), "\(drawn)")
        let leek = try #require(drawn.firstIndex { $0.contains("Leek") })
        let move = { (y: Int) in
            tui.mouseEventDispatcher.dispatch(MouseEvent(button: .none, phase: .moved, x: 5, y: y))
        }
        #expect(move(leek), "crossing into a section asks for a frame")
        drawn = frame(view, tui: tui, context: context)
        #expect(drawn.contains { $0.contains("Veg") && $0.contains("AddVeg") }, "\(drawn)")
        #expect(!drawn.joined().contains("AddFruit"), "\(drawn)")
        #expect(!move(leek), "a move within it does not")
        _ = move(drawn.count + 4)
        drawn = frame(view, tui: tui, context: context)
        #expect(!drawn.joined().contains("Add"), "\(drawn)")
    }

    @Test("Outside a list the section draws as it would without them")
    func outsideAList() {
        let plain = lines(VStack { Section("Fruit") { Text("Apple") } })
        let withActions = lines(
            VStack {
                Section("Fruit") { Text("Apple") }
                    .sectionActions { Button("Add") {} }
            })
        #expect(withActions == plain)
    }
}
