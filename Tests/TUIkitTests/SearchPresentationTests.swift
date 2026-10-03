//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SearchPresentationTests.swift
//
//  `searchFocused(_:)` / `searchFocused(_:equals:)` and
//  `searchable(text:isPresented:…)`, through the real input chain: the
//  search field's focus and presentation follow the bindings both ways.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit

/// What the page holds, by reference so the bindings a frame built reach it.
private final class Probe {
    var query = "hello"
    var presented = false
    var focus: FocusState<Bool>.Binding?
    var pressed = 0

    var text: Binding<String> { Binding(get: { self.query }, set: { self.query = $0 }) }
    var isPresented: Binding<Bool> { Binding(get: { self.presented }, set: { self.presented = $0 }) }
}

private enum Area: Hashable { case search, list }

/// A searchable page whose field's focus is bound with `searchFocused`.
private struct FocusedPage: View {
    @FocusState private var searchFocused: Bool
    let probe: Probe

    var body: some View {
        probe.focus = $searchFocused
        return VStack { Button("Result") { probe.pressed += 1 } }
            .searchable(text: probe.text)
            .searchFocused($searchFocused)
    }
}

/// The same with a focus state of several values.
private struct ValuedPage: View {
    @FocusState private var area: Area?
    let seen: (Area?) -> Void

    var body: some View {
        seen(area)
        return VStack { Button("Result") {}.focused($area, equals: .list) }
            .searchable(text: .constant(""))
            .searchFocused($area, equals: .search)
    }
}

/// A searchable page presented through `isPresented`.
private struct PresentedPage: View {
    let probe: Probe

    var body: some View {
        VStack { Button("Result") { probe.pressed += 1 } }
            .searchable(text: probe.text, isPresented: probe.isPresented)
    }
}

@MainActor
@Suite("Search focus and presentation", .rendersEnglishUI)
struct SearchPresentationTests {
    private let tab = KeyEvent(key: .tab)

    @Test("searchFocused reads the field's focus and moves it")
    func searchFocusedBool() {
        let harness = InputChainHarness()
        let probe = Probe()
        harness.frame(FocusedPage(probe: probe))
        harness.frame(FocusedPage(probe: probe))
        #expect(probe.focus?.wrappedValue == true, "the field, first on the page, holds the focus")

        harness.press(tab)
        harness.frame(FocusedPage(probe: probe))
        #expect(probe.focus?.wrappedValue == false, "Tab took the focus to the result")

        probe.focus?.wrappedValue = true
        harness.frame(FocusedPage(probe: probe))
        #expect(probe.focus?.wrappedValue == true, "setting it moved the focus back to the field")
        harness.press(KeyEvent(character: "!"))
        #expect(probe.query == "hello!", "and the field takes the typing")
    }

    @Test("searchFocused(_:equals:) gives the field its value in a shared focus state")
    func searchFocusedEquals() {
        let harness = InputChainHarness()
        var last: Area?
        let page = { ValuedPage { last = $0 } }
        harness.frame(page())
        harness.frame(page())
        #expect(last == .search)
        harness.press(tab)
        harness.frame(page())
        harness.frame(page())
        #expect(last == .list)
    }

    @Test("isPresented follows the field's focus, and presenting from the app focuses the field")
    func isPresentedBothWays() async {
        let harness = InputChainHarness()
        let probe = Probe()
        harness.frame(PresentedPage(probe: probe))
        harness.frame(PresentedPage(probe: probe))
        #expect(probe.presented, "the field took the opening focus, so search is presented")

        harness.press(tab)
        harness.frame(PresentedPage(probe: probe))
        #expect(!probe.presented, "the focus left the field")
        #expect(probe.query == "hello", "leaving the field is not cancelling the search")

        probe.presented = true
        harness.frame(PresentedPage(probe: probe))
        await Task.yield()
        harness.frame(PresentedPage(probe: probe))
        harness.press(KeyEvent(character: "!"))
        #expect(probe.query == "hello!", "presenting moved the focus to the field")
    }

    @Test("Ending the search from the app empties the query and moves the focus on")
    func endingFromTheApp() async {
        let harness = InputChainHarness()
        let probe = Probe()
        harness.frame(PresentedPage(probe: probe))
        harness.frame(PresentedPage(probe: probe))
        #expect(probe.presented)

        probe.presented = false
        harness.frame(PresentedPage(probe: probe))
        await Task.yield()
        harness.frame(PresentedPage(probe: probe))
        #expect(probe.query.isEmpty, "the search was dismissed")
        harness.press(KeyEvent(key: .enter))
        #expect(probe.pressed == 1, "and the focus moved on to the content")
    }

    /// The guarantee `searchPresentationToolbarBehavior(.avoidHidingContent)`
    /// asks for, asserted rather than the modifier's return: with search
    /// presented, what is above the field and the content below it are still
    /// drawn.
    @Test("Presenting search hides nothing around the field")
    func presentingHidesNothing() {
        let harness = InputChainHarness(width: 50, height: 12)
        let probe = Probe()
        let page = {
            VStack {
                Text("Notes")
                VStack { Text("first result") }
                    .searchable(text: probe.text, isPresented: probe.isPresented, placement: .toolbarPrincipal)
                    .searchToolbarBehavior(.automatic)
            }
            .searchPresentationToolbarBehavior(.avoidHidingContent)
        }
        harness.frame(page())
        let lines = harness.frame(page()).lines.map(\.stripped)
        #expect(probe.presented, "search is presented: the field holds the focus")
        #expect(lines.contains { $0.contains("Notes") }, "what is above the field is still drawn")
        #expect(lines.contains { $0.contains("first result") }, "and so is the content")
    }
}
