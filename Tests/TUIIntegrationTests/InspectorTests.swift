//  🖥️ TUI — A Terminal UI framework for Swift
//  InspectorTests.swift
//
//  `inspector(isPresented:content:)` and `inspectorColumnWidth`: a trailing
//  column at the width the content names, a divider the reader can move, and
//  a view whose state survives the inspector coming and going.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUINavigation
@testable import TUITestSupport

/// Whether the inspector shows, by reference so a frame's binding reaches it.
private final class Shown {
    var value = true
    var binding: Binding<Bool> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

/// A view with state of its own, to see it survive the inspector.
private struct Editor: View {
    @State private var count = 0

    var body: some View {
        Button("count \(count)") { count += 1 }
    }
}

@MainActor
@Suite("Inspector", .rendersEnglishUI)
struct InspectorTests {
    private func column(of text: String, in buffer: FrameBuffer) -> Int? {
        for line in buffer.lines.map(\.stripped) {
            if let range = line.range(of: text) {
                return line.distance(from: line.startIndex, to: range.lowerBound)
            }
        }
        return nil
    }

    @Test("A presented inspector is a trailing column at its default width, behind a divider")
    func defaultColumn() throws {
        let harness = InputChainHarness(width: 60, height: 6)
        let page = { Editor().inspector(isPresented: .constant(true)) { Text("traits") } }
        harness.frame(page())
        let buffer = harness.frame(page())
        let start = try #require(column(of: "traits", in: buffer))
        #expect(start == 60 - _InspectorModifier<Editor, Text>.defaultWidth)
        #expect(buffer.lines.map(\.stripped).first?.contains("│") == true, "a divider between the two")
    }

    @Test("inspectorColumnWidth sets where the column starts, found through another trait")
    func namedWidth() throws {
        let harness = InputChainHarness(width: 60, height: 6)
        let page = {
            Editor().inspector(isPresented: .constant(true)) {
                Text("traits")
                    .inspectorColumnWidth(12)
                    .interactiveDismissDisabled()
            }
        }
        harness.frame(page())
        #expect(try #require(column(of: "traits", in: harness.frame(page()))) == 48)

        let flexible = {
            Editor().inspector(isPresented: .constant(true)) {
                Text("traits").inspectorColumnWidth(min: 8, ideal: 20, max: 40)
            }
        }
        harness.frame(flexible())
        #expect(try #require(column(of: "traits", in: harness.frame(flexible()))) == 40, "ideal decides")
    }

    @Test("The divider stops at the column's minimum and maximum")
    func boundsHold() throws {
        let harness = InputChainHarness(width: 60, height: 6)
        let page = {
            Editor().inspector(isPresented: .constant(true)) {
                Text("traits").inspectorColumnWidth(min: 18, ideal: 20, max: 24)
            }
        }
        // The editor's button is the first stop, the divider the second.
        harness.play([KeyEvent(key: .tab), KeyEvent(key: .left, shift: true)]) { page() }
        #expect(try #require(column(of: "traits", in: harness.frame(page()))) == 36, "no wider than 24")
        harness.play([KeyEvent(key: .right, shift: true), KeyEvent(key: .right, shift: true)]) { page() }
        #expect(try #require(column(of: "traits", in: harness.frame(page()))) == 42, "no narrower than 18")
    }

    @Test("Hidden, there is no column; and the view keeps its state across showing and hiding")
    func hidingKeepsState() {
        let harness = InputChainHarness(width: 60, height: 6)
        let shown = Shown()
        let page = { Editor().inspector(isPresented: shown.binding) { Text("traits") } }
        harness.frame(page())
        harness.frame(page())
        harness.press(KeyEvent(key: .enter))
        harness.frame(page())
        shown.value = false
        let hidden = harness.frame(page())
        #expect(column(of: "traits", in: hidden) == nil)
        #expect(!(hidden.lines.map(\.stripped).first?.contains("│") ?? true))
        shown.value = true
        harness.frame(page())
        #expect(column(of: "count 1", in: harness.frame(page())) != nil, "the editor's count survived")
    }
}
