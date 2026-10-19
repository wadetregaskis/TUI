//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListScrollPositionTests.swift
//
//  `.scrollPosition` on a `List` and a `Table` (semantic audit 44): a bound
//  row is sought as `scrollTo` seeks it, an edge or a line is placed, and the
//  row at the binding's anchor is written back, as a `ScrollView` does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitLists
import TUIkitTables
@testable import TUIkitTestSupport
@testable import TUIkitView

@MainActor
@Suite(".scrollPosition on a List or a Table")
struct ListScrollPositionTests {
    private struct Numbered: Identifiable, Sendable {
        let id: Int
    }

    /// Renders one frame eight lines tall, driving the render-pass hooks the
    /// way the run loop does: the write-back is a render-time side effect.
    @discardableResult
    private func frame<V: View>(_ view: V, _ tui: TUIContext, _ focus: FocusManager) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = focus
        environment.verticalScrollIndicatorVisibility = .hidden
        environment.applyRuntimeServices(from: tui)
        let context = RenderContext(availableWidth: 30, availableHeight: 8, environment: environment, tuiContext: tui)
        tui.preferences.beginRenderPass()
        tui.stateStorage.beginRenderPass()
        tui.renderCache.beginRenderPass()
        focus.beginRenderPass()
        let buffer = renderToBuffer(view, context: context)
        focus.endRenderPass()
        tui.stateStorage.endRenderPass()
        tui.renderCache.removeInactive()
        return buffer.lines.map { $0.stripped.trimmingCharacters(in: .whitespaces) }
    }

    /// The labels of the rows drawn, in order.
    private func rows(_ lines: [String]) -> [String] {
        lines.compactMap { line in line.range(of: #"(row|item) \d+"#, options: .regularExpression).map { String(line[$0]) } }
    }

    private func handler(_ focus: FocusManager) -> (any ScrollableOffsetState)? {
        focus.activeSection?.focusables.compactMap { $0 as? any ScrollableOffsetState }.first
    }

    @Test("A List seeks the bound id and writes back the row at its top")
    func listIDBinding() {
        let (tui, focus) = (TUIContext(), FocusManager())
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let view = List { ForEach(0..<200, id: \.self) { Text("row \($0)") } }
            .scrollPosition(id: binding, anchor: .top)
        frame(view, tui, focus)
        #expect(visible == 0, "the first frame reports the row at the top")
        visible = 120
        let jumped = rows(frame(view, tui, focus))
        #expect(jumped.first == "row 120", "\(jumped)")
        #expect(visible == 120)
        handler(focus)?.userScrollFine(by: 3)
        let scrolled = rows(frame(view, tui, focus))
        #expect(scrolled.first == "row 123", "precondition: \(scrolled)")
        #expect(visible == 123, "the user's scroll is written back")
    }

    @Test("A List takes a ScrollPosition's edges and lines, and hears the user scroll")
    func listPosition() {
        let (tui, focus) = (TUIContext(), FocusManager())
        var position = ScrollPosition(idType: Int.self)
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = List { ForEach(0..<50, id: \.self) { Text("row \($0)") } }
            .scrollPosition(binding)
        frame(view, tui, focus)
        position.scrollTo(edge: .bottom)
        let bottom = rows(frame(view, tui, focus))
        #expect(bottom.last == "row 49", "\(bottom)")
        #expect(position.viewID(type: Int.self) == bottom.first.flatMap { Int($0.dropFirst(4)) })
        position.scrollTo(y: 10)
        let line = rows(frame(view, tui, focus))
        #expect(line.first == "row 10", "\(line)")
        position.scrollTo(id: 30, anchor: .top)
        let row = rows(frame(view, tui, focus))
        #expect(row.first == "row 30", "\(row)")
        #expect(!position.isPositionedByUser)
        handler(focus)?.userScrollFine(by: 1)
        frame(view, tui, focus)
        #expect(position.isPositionedByUser)
        #expect(position.viewID(type: Int.self) == 31)
    }

    @Test("A Table seeks the bound id and writes back the row at its top")
    func tableIDBinding() {
        let (tui, focus) = (TUIContext(), FocusManager())
        var visible: Int?
        let binding = Binding<Int?>(get: { visible }, set: { visible = $0 })
        let data = (0..<200).map { Numbered(id: $0) }
        let view = Table(data) { TableColumn("N") { (row: Numbered) in Text("item \(row.id)") } }
            .scrollPosition(id: binding, anchor: .top)
        frame(view, tui, focus)
        #expect(visible == 0)
        visible = 120
        let jumped = rows(frame(view, tui, focus))
        #expect(jumped.first == "item 120", "\(jumped)")
        handler(focus)?.userScrollFine(by: 2)
        let scrolled = rows(frame(view, tui, focus))
        #expect(scrolled.first == "item 122", "precondition: \(scrolled)")
        #expect(visible == 122)
    }
}
