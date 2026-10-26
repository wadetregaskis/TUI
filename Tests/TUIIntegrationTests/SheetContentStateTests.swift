//  🖥️ TUI — A Terminal UI framework for Swift
//  SheetContentStateTests.swift
//
//  A sheet's content loses its `@State` when the sheet is dismissed, and an
//  `item:` sheet's when it is presented for another item — under a view that
//  keeps its subtree's state too: a `List` row, a lazy stack's row. Presented
//  again, the sheet starts from what its modifier says now.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUIFoundation
@testable import TUITestSupport

/// What the page presents, by reference so every frame's bindings reach it.
@MainActor
private final class DraftModel {
    var presented = true
    var item: DraftItem? = DraftItem(id: "A")
    /// What a draft presented next starts from.
    var initial = "first"
    var binding: Binding<Bool> { Binding(get: { self.presented }, set: { self.presented = $0 }) }
    var itemBinding: Binding<DraftItem?> { Binding(get: { self.item }, set: { self.item = $0 }) }
}

private struct DraftItem: Identifiable {
    let id: String
}

/// A sheet's content with `@State` of its own, made from what it is handed,
/// and a button that changes it.
private struct Draft: View {
    @State private var text: String

    init(_ initial: String) {
        _text = State(initialValue: initial)
    }

    var body: some View {
        VStack {
            Text("draft: \(text)")
            Button("Edit") { text = "edited" }
        }
    }
}

/// A presentation's content that counts, in its own `@State`, how many times
/// it has appeared: once for a content that starts afresh.
private struct Openings: View {
    var label = ""
    @State private var openings = 0

    var body: some View {
        Text("\(label) opened \(openings)".trimmingCharacters(in: .whitespaces))
            .onAppear { openings += 1 }
    }
}

@MainActor
@Suite("A dismissed sheet's or popover's content loses its state, under a view that keeps its subtree's")
struct SheetContentStateTests {
    private static let width = 60
    private static let height = 20

    private func harness() -> InputChainHarness {
        InputChainHarness(width: Self.width, height: Self.height) { environment in
            environment.terminalWidth = Self.width
            environment.terminalHeight = Self.height
            environment.overlayContentHeight = Self.height
        }
    }

    /// The screen of `view`'s next frame, its presentations composited.
    private func screen(_ harness: InputChainHarness, _ view: some View) -> String {
        harness.frame(view)
            .compositingOverlays(
                maxWidth: Self.width, maxHeight: Self.height, palette: harness.context.environment.palette
            ).lines.map(\.stripped).joined(separator: "\n")
    }

    /// Presents the draft, edits it, dismisses it, changes what the next
    /// draft starts from and presents it again: the screen then.
    private func presentedAgain(_ model: DraftModel, _ build: () -> some View) -> (edited: String, again: String) {
        let harness = harness()
        harness.play([.init(key: .enter)], build)
        let edited = screen(harness, build())
        model.presented = false
        harness.frame(build())
        harness.frame(build())
        model.initial = "second"
        model.presented = true
        harness.frame(build())
        return (edited, screen(harness, build()))
    }

    @Test("Presented again from a List row, the sheet's content starts from what it is handed now")
    func listRow() {
        let model = DraftModel()
        let shown = presentedAgain(model) {
            List {
                Text("row").sheet(isPresented: model.binding) { Draft(model.initial) }
            }
        }
        #expect(shown.edited.contains("draft: edited"), "precondition: the draft was edited: \(shown.edited)")
        #expect(shown.again.contains("draft: second"), "the sheet came back as it was left: \(shown.again)")
    }

    @Test("Presented again from a scrolled lazy stack's row, the sheet's content starts from what it is handed now")
    func lazyStackRow() {
        let model = DraftModel()
        // A lazy stack keeps its rows' state where it windows them, in a
        // scroll view.
        let shown = presentedAgain(model) {
            ScrollView {
                LazyVStack {
                    Text("row").sheet(isPresented: model.binding) { Draft(model.initial) }
                    ForEach(0..<40, id: \.self) { Text("filler \($0)") }
                }
            }
        }
        #expect(shown.edited.contains("draft: edited"), "precondition: the draft was edited: \(shown.edited)")
        #expect(shown.again.contains("draft: second"), "the sheet came back as it was left: \(shown.again)")
    }

    @Test("Opened again from a List row, a popover's content starts afresh")
    func popoverInListRow() {
        let model = DraftModel()
        let build = {
            List {
                Text("row").popover(isPresented: model.binding) { Openings() }
            }
        }
        let harness = harness()
        harness.frame(build())
        #expect(screen(harness, build()).contains("opened 1"), "precondition: the popover counted its opening")
        model.presented = false
        harness.frame(build())
        harness.frame(build())
        model.presented = true
        harness.frame(build())
        let again = screen(harness, build())
        #expect(again.contains("opened 1"), "the popover came back as it was left: \(again)")
    }

    @Test("An item popover switched to another item and back starts the first item's content afresh")
    func itemPopoverSwitchedAndBack() {
        let model = DraftModel()
        let build = {
            List {
                Text("row").popover(item: model.itemBinding) { item in Openings(label: item.id) }
            }
        }
        let harness = harness()
        harness.frame(build())
        #expect(screen(harness, build()).contains("A opened 1"), "precondition: the popover counted its opening")
        model.item = DraftItem(id: "B")
        harness.frame(build())
        harness.frame(build())
        model.item = DraftItem(id: "A")
        harness.frame(build())
        let again = screen(harness, build())
        #expect(again.contains("A opened 1"), "item A's popover came back as it was left: \(again)")
    }

    @Test("An item sheet switched to another item and back starts the first item's content afresh")
    func itemSwitchedAndBack() {
        let model = DraftModel()
        let build = {
            List {
                Text("row").sheet(item: model.itemBinding) { item in Draft("\(item.id) \(model.initial)") }
            }
        }
        let harness = harness()
        harness.play([.init(key: .enter)], build)
        #expect(screen(harness, build()).contains("draft: edited"), "precondition: the draft was edited")
        model.item = DraftItem(id: "B")
        harness.frame(build())
        harness.frame(build())
        model.item = DraftItem(id: "A")
        harness.frame(build())
        let again = screen(harness, build())
        #expect(again.contains("draft: A first"), "item A's sheet came back as it was left: \(again)")
    }
}
