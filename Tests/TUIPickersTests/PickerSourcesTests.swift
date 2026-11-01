//  🖥️ TUI — A Terminal UI framework for Swift
//  PickerSourcesTests.swift
//
//  `Picker(sources:selection:)`: one picker for a collection of selections —
//  showing the value they share, none where they disagree, and setting them
//  all when an option is picked.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIPickers
import TUITesting
@testable import TUITestSupport

private struct Shape: Hashable, Identifiable {
    var id: Int
    var size: Int
}

/// The shapes the pickers under test stand for.
private final class Shapes: @unchecked Sendable {
    var shapes: [Shape]
    init(_ sizes: [Int]) { shapes = sizes.enumerated().map { Shape(id: $0.offset, size: $0.element) } }
    var binding: Binding<[Shape]> { Binding(get: { self.shapes }, set: { self.shapes = $0 }) }
}

@MainActor
@Suite("Picker(sources:)")
struct PickerSourcesTests {
    private func picker(_ store: Shapes) -> some View {
        Picker("Size", sources: store.binding, selection: \.size) {
            Text("Small").tag(1)
            Text("Large").tag(2)
        }
        .pickerStyle(.menu)
    }

    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 40, height: 4)).lines.first?.stripped ?? ""
    }

    @Test("Sources that agree show their value; sources that disagree show none")
    func display() {
        #expect(line(picker(Shapes([2, 2]))).contains("Large"))
        let mixed = line(picker(Shapes([1, 2])))
        #expect(!mixed.contains("Small") && !mixed.contains("Large"), "\(mixed)")
    }

    @Test("A radio group marks no option while the sources disagree")
    func radioMixed() {
        // Disabled, so no option holds the focus, which draws the same mark.
        func drawn(_ sizes: [Int]) -> String {
            renderToBuffer(
                Picker("Size", sources: Shapes(sizes).binding, selection: \.size) {
                    Text("Small").tag(1)
                    Text("Large").tag(2)
                }.pickerStyle(.radioGroup).disabled(true),
                context: makeRenderContext(width: 40, height: 4)
            ).lines.map(\.stripped).joined()
        }
        #expect(drawn([1, 1]).contains(TerminalSymbols.radioSelected))
        #expect(!drawn([1, 2]).contains(TerminalSymbols.radioSelected), "\(drawn([1, 2]))")
    }

    @Test("Picking an option sets every source to it")
    func picking() {
        let store = Shapes([1, 2, 1])
        // Open the menu, move to the second option, choose it.
        let app = TestApp(width: 40, height: 6) { picker(store) }
        for event in [KeyEvent(key: .enter), KeyEvent(key: .down), KeyEvent(key: .enter)] { app.press(event) }
        let sizes = Set(store.shapes.map(\.size))
        #expect(sizes.count == 1, "\(store.shapes)")
    }

    @Test("Over no sources the picker draws its label and an empty control")
    func empty() {
        #expect(line(picker(Shapes([]))).hasPrefix("Size —"))
    }
}
