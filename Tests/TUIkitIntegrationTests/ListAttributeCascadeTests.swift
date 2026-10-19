//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListAttributeCascadeTests.swift
//
//  A text attribute written on a `List` or a `Table` — `.bold()`, or a
//  `.style(.control(.list))` entry — reaches the text of every row, as
//  `.foregroundColor(.red)` on a `List` must reach every `Text` inside it
//  (CLAUDE.md, "Every control is a View with a real body"). The styling
//  design carried this as an open follow-up: the row memo was thought not to
//  re-key on the style cascade, so a cascade that changed between frames
//  might leave the rows drawn as they were.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

private struct CascadeRow: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
}

private let cascadeRows = [CascadeRow(id: 1, name: "Alpha"), CascadeRow(id: 2, name: "Bravo")]

/// Several frames through one `TUIContext`, so the render cache and the row
/// memos persist between them as they do in the app's run loop.
@MainActor
private final class Frames {
    let tui = TUIContext()
    var env = EnvironmentValues()

    init() {
        env.focusManager = FocusManager()
        env.applyRuntimeServices(from: tui)
    }

    /// One frame, bracketed as the run loop brackets it: the render cache's
    /// pass is what tells an environment write's note one frame from the next.
    func render(_ view: some View) -> [String] {
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        env.focusManager?.beginRenderPass()
        let context = RenderContext(availableWidth: 30, availableHeight: 8, environment: env, tuiContext: tui)
        let buffer = renderToBuffer(view, context: context)
        env.focusManager?.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines
    }
}

@MainActor
@Suite("List and Table container attribute cascade")
struct ListAttributeCascadeTests {

    private func isBold(_ word: String, _ lines: [String]) -> Bool? {
        sgrState(of: word, in: lines)?.isBold
    }

    @Test("A .bold() on a List reaches its hand-written rows")
    func listBoldReachesRows() {
        let lines = Frames().render(List { Text("Alpha"); Text("Bravo") }.bold())
        #expect(isBold("Alpha", lines) == true, "\(lines)")
        #expect(isBold("Bravo", lines) == true, "\(lines)")
    }

    @Test("A .bold() on a List reaches its looped rows")
    func listBoldReachesLoopedRows() {
        let lines = Frames().render(List(cascadeRows) { Text($0.name) }.bold())
        #expect(isBold("Alpha", lines) == true, "\(lines)")
        #expect(isBold("Bravo", lines) == true, "\(lines)")
    }

    @Test("A list style entry reaches its rows")
    func listStyleEntryReachesRows() {
        let lines = Frames().render(
            List(cascadeRows) { Text($0.name) }
                .style(.control(.list)) { $0.bold = true })
        #expect(isBold("Alpha", lines) == true, "\(lines)")
    }

    @Test("A table style entry reaches its cells")
    func tableStyleEntryReachesCells() {
        let lines = Frames().render(
            Table(cascadeRows) {
                TableColumn("Name", value: \CascadeRow.name)
            }
            .style(.control(.table)) { $0.bold = true })
        #expect(isBold("Bravo", lines) == true, "\(lines)")
    }

    @Test("A .bold() on a Table reaches its cells")
    func tableBoldReachesCells() {
        let lines = Frames().render(
            Table(cascadeRows) {
                TableColumn("Name", value: \CascadeRow.name)
            }
            .bold())
        #expect(isBold("Bravo", lines) == true, "\(lines)")
    }

    /// The memo case: the same rows over several frames, the cascade turned
    /// on, then off again. A row served from its memo across the change would
    /// keep the weight it was drawn with.
    @Test("A List's rows follow a change of the cascade between frames", arguments: [false, true])
    func listCascadeChangeBetweenFrames(sectioned: Bool) {
        let frames = Frames()
        func list(_ bold: Bool) -> some View {
            List {
                if sectioned {
                    Section("S") { ForEach(cascadeRows) { Text($0.name) } }
                } else {
                    ForEach(cascadeRows) { Text($0.name) }
                }
            }
            .bold(bold)
        }
        for (frame, bold) in [false, false, true, true, false].enumerated() {
            let lines = frames.render(list(bold))
            #expect(isBold("Bravo", lines) == bold, "frame \(frame): \(lines)")
        }
    }

    @Test("A Table's cells follow a change of the cascade between frames")
    func tableCascadeChangeBetweenFrames() {
        let frames = Frames()
        func table(_ bold: Bool) -> some View {
            Table(cascadeRows) {
                TableColumn("Name", value: \CascadeRow.name)
            }
            .bold(bold)
        }
        for (frame, bold) in [false, false, true, true, false].enumerated() {
            let lines = frames.render(table(bold))
            #expect(isBold("Bravo", lines) == bold, "frame \(frame): \(lines)")
        }
    }
}
