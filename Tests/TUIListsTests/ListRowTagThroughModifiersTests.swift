//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRowTagThroughModifiersTests.swift
//
//  A `List` reads a row's `.tag(_:)` through the modifiers written after it,
//  as SwiftUI reads a container value — `Text("a").tag("a").padding()` is the
//  row "a" — on every path a row reaches the list by: hand-written, looped
//  (through `ForEach`'s value memo), spliced among hand-written rows, and in
//  a `Section`. It read only an outermost `.tag(_:)` before, so such a row
//  fell back on its ordinal or its element's id.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport

@MainActor
@Suite("A List reads a row's tag through the modifiers after it")
struct ListRowTagThroughModifiersTests {
    private static let names = ["Alpha", "Bravo"]

    /// Renders `list` twice (register, then focus), moves the cursor down
    /// `steps` rows and presses Return: what the selection became.
    private func select(after steps: Int, in list: (Binding<String?>) -> some View) -> String? {
        var selection: String?
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 30, availableHeight: 10, environment: environment, tuiContext: tui)
        func frame() {
            tui.stateStorage.beginRenderPass()
            environment.focusManager?.beginRenderPass()
            _ = renderToBuffer(list(binding).frame(height: 8), context: context)
            environment.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
        }
        frame()
        frame()
        for _ in 0..<steps {
            _ = environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .down))
            frame()
        }
        _ = environment.focusManager?.dispatchKeyEvent(KeyEvent(key: .enter))
        return selection
    }

    @Test("A hand-written row's tag is read through a padding and a bold")
    func handWritten() {
        let chosen = select(after: 1) { selection in
            List(selection: selection) {
                Text("Apple").tag("a").padding(.leading, 0)
                Text("Pear").tag("p").bold()
            }
        }
        #expect(chosen == "p")
    }

    @Test("A looped row's tag outranks its element's id through a padding")
    func looped() {
        let chosen = select(after: 1) { selection in
            List(selection: selection) {
                ForEach(Self.names, id: \.self) { Text($0).tag("tag-\($0)").padding(.leading, 0) }
            }
        }
        #expect(chosen == "tag-Bravo")
    }

    @Test("A looped row spliced among hand-written rows has its tag read through a padding")
    func spliced() {
        let chosen = select(after: 2) { selection in
            List(selection: selection) {
                Text("Top").tag("top")
                ForEach(Self.names, id: \.self) { Text($0).tag("tag-\($0)").padding(.leading, 0) }
            }
        }
        #expect(chosen == "tag-Bravo")
    }

    @Test("A row in a Section has its tag read through a padding")
    func inASection() {
        let chosen = select(after: 1) { selection in
            List(selection: selection) {
                Section("S") {
                    Text("Apple").tag("a").padding(.leading, 0)
                }
            }
        }
        #expect(chosen == "a", "the header is no row the cursor stops on")
    }

    @Test("The outermost of two tags wins, as the outermost write of a container value does")
    func outermostWins() {
        let chosen = select(after: 0) { selection in
            List(selection: selection) {
                Text("Apple").tag("inner").padding(.leading, 0).tag("outer")
            }
        }
        #expect(chosen == "outer")
    }
}
