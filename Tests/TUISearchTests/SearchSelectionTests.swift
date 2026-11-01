//  🖥️ TUI — A Terminal UI framework for Swift
//  SearchSelectionTests.swift
//
//  `searchSelection(_:)` (decisions A25): the search field's caret and
//  selection exchanged with the app's binding, through the real input chain,
//  as a text field's `selection:` exchanges them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUISearch
@testable import TUITestSupport

/// What the page holds, by reference so the bindings a frame built reach it.
private final class Probe: @unchecked Sendable {
    var query = "hello"
    var selection: TextSelection?

    var text: Binding<String> { Binding(get: { self.query }, set: { self.query = $0 }) }
    var selected: Binding<TextSelection?> { Binding(get: { self.selection }, set: { self.selection = $0 }) }

    /// The selection as character offsets into the query.
    var offsets: Range<Int>? {
        guard case .selection(let range)? = selection?.indices else { return nil }
        return query.distance(from: query.startIndex, to: range.lowerBound)
            ..< query.distance(from: query.startIndex, to: range.upperBound)
    }

    func select(_ offsets: Range<Int>) {
        let lower = query.index(query.startIndex, offsetBy: offsets.lowerBound)
        let upper = query.index(query.startIndex, offsetBy: offsets.upperBound)
        selection = TextSelection(range: lower..<upper)
    }
}

/// A searchable page whose field's selection is bound with `searchSelection`.
private struct SelectedPage: View {
    let probe: Probe

    var body: some View {
        VStack { Button("Result") {} }
            .searchable(text: probe.text)
            .searchSelection(probe.selected)
    }
}

@MainActor
@Suite("Search selection", .rendersEnglishUI)
struct SearchSelectionTests {

    // `TextSelection` is macOS 15's; the bodies run where it exists, which is
    // every CI lane.

    @Test("The search field writes its caret and selection to the binding")
    func fieldWrites() {
        fieldWritesBody()
    }

    @Test("A selection the app writes moves the search field's, so typing replaces it")
    func appWrites() {
        appWritesBody()
    }

    private func fieldWritesBody() {
        let harness = InputChainHarness()
        let probe = Probe()
        harness.frame(SelectedPage(probe: probe))
        harness.frame(SelectedPage(probe: probe))
        harness.press(KeyEvent(key: .home))
        #expect(probe.offsets == 0..<0, "the caret is written as it moves: \(String(describing: probe.offsets))")
        harness.frame(SelectedPage(probe: probe))
        harness.press(KeyEvent(key: .right, shift: true))
        harness.frame(SelectedPage(probe: probe))
        harness.press(KeyEvent(key: .right, shift: true))
        #expect(probe.offsets == 0..<2, "and the selection as it grows: \(String(describing: probe.offsets))")
    }

    private func appWritesBody() {
        let harness = InputChainHarness()
        let probe = Probe()
        harness.frame(SelectedPage(probe: probe))
        harness.frame(SelectedPage(probe: probe))
        probe.select(1..<4)
        harness.frame(SelectedPage(probe: probe))
        harness.press(KeyEvent(character: "X"))
        #expect(probe.query == "hXo", "typing replaced the app's selection: \(probe.query)")
        #expect(probe.offsets == 2..<2, "\(String(describing: probe.offsets))")
    }
}
