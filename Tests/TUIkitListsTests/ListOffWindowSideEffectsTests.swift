//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListOffWindowSideEffectsTests.swift
//
//  A `List` draws only the rows its window walks, so a row scrolled out of
//  sight does nothing a drawn row does — appear, register a presentation,
//  take a place in the focus ring — until it is scrolled to. That holds for a
//  flat `ForEach`, for rows the list's child walk reads — a hand-written row
//  and a loop spliced beside it (`Shape.spliced`), drawn when the list reads
//  them since lane LISTS2 (decisions B73) — and for a `Section`'s rows
//  (`Shape.section`, `Shape.mixedSection`), since the section stopped drawing
//  its whole content a second time each frame (decisions B-LISTS-2).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation
import TUIkitLists
@testable import TUIkitTestSupport

@MainActor
@Suite("Rows a List does not draw have no side effects")
struct ListOffWindowSideEffectsTests {
    /// The rows whose `.onAppear` ran.
    @MainActor
    private final class Appeared {
        var rows = Set<Int>()

        func row(_ index: Int) -> some View {
            Text("r\(index)").onAppear { self.rows.insert(index) }
        }
    }

    /// Two frames of `view` through one context, as the run loop draws them.
    private func frames(_ view: some View) {
        let tui = TUIContext()
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 30, availableHeight: 10, environment: environment, tuiContext: tui)
        for _ in 0..<2 {
            tui.lifecycle.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            _ = renderToBuffer(view, context: context)
            tui.lifecycle.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
        }
    }

    enum Shape: String, CaseIterable {
        case flat, section, mixedSection, spliced
    }

    @ViewBuilder
    private func list(_ shape: Shape, _ appeared: Appeared) -> some View {
        switch shape {
        case .flat:
            List { ForEach(0..<40, id: \.self) { appeared.row($0) } }.frame(height: 8)
        case .section:
            List { Section("S") { ForEach(0..<40, id: \.self) { appeared.row($0) } } }.frame(height: 8)
        case .mixedSection:
            List {
                Section("S") {
                    Text("top")
                    ForEach(0..<40, id: \.self) { appeared.row($0) }
                }
            }
            .frame(height: 8)
        case .spliced:
            List {
                Text("top")
                ForEach(0..<40, id: \.self) { appeared.row($0) }
            }
            .frame(height: 8)
        }
    }

    @Test("A row far below the window does not appear; one in it does", arguments: Shape.allCases)
    func offWindowRowsDoNotAppear(_ shape: Shape) {
        let appeared = Appeared()
        frames(list(shape, appeared))
        #expect(appeared.rows.contains(1), "\(shape): a drawn row appears: \(appeared.rows.sorted())")
        #expect(!appeared.rows.contains(30), "\(shape): row 30 is far below the window: \(appeared.rows.sorted())")
    }
}
