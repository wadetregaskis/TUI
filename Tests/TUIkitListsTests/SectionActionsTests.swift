//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionActionsTests.swift
//
//  `.sectionActions(content:)`: a list section's actions on its header's
//  line, always shown and reached by the keyboard; outside a list, nothing.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

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
        let drawn = lines(list(Counter()))
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
        let rows = List {
            Section("Fruit") {
                Text("Apple").badge(5)
            }
            .sectionActions {
                Button("Add") {}
            }
        }
        let filled = lines(rows)
        guard let header = filled.first(where: { $0.contains("Fruit") }),
            let apple = filled.first(where: { $0.contains("Apple") })
        else {
            Issue.record("\(filled)")
            return
        }
        #expect(trailingGap(header) == trailingGap(apple), "the action ends where the badge does: \(filled)")
        #expect(trailingGap(header) <= 2, "flush right: \(filled)")
        let hugged = lines(HStack(spacing: 0) {
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
        let drawn = lines(
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
