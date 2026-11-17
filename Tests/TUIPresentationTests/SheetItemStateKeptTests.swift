//  🖥️ TUI — A Terminal UI framework for Swift
//  SheetItemStateKeptTests.swift
//
//  The owner's ruling SHEET-ITEM-STATE (2026-11-16), through the run loop: an
//  `item:` presentation switched from item A to item B and back shows A's
//  content as it was left — its `@State` and where the focus was in it — with
//  its `onAppear` run again, as a tab's is when it comes back into view; no
//  `onDismiss` runs until the item is `nil`, and presented again after that,
//  A starts fresh. macOS keeps ONE state across items instead (measured,
//  `Tools/SwiftUIProbes/Bug-hunt parity items (1116B)/sheetitem.swift`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUIPresentation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

private struct Item: Identifiable {
    let id: String
}

@Observable
private final class EditorModel: @unchecked Sendable {
    var item: Item? = Item(id: "A")
    @ObservationIgnored var dismissals = 0
    @ObservationIgnored var appearances: [String: Int] = [:]
}

/// A count only its own button raises, and a second button to leave the
/// focus on.
private struct CountingEditor: View {
    let item: Item
    let model: EditorModel
    @State private var count = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(item.id) count=\(count)")
            Button("Up") { count += 1 }.focusID("up-\(item.id)")
            Button("Other") {}.focusID("other-\(item.id)")
        }
        .onAppear { model.appearances[item.id, default: 0] += 1 }
    }
}

private struct Presenter: View {
    let model: EditorModel
    var body: some View {
        Text("page")
            .sheet(
                item: Binding(get: { model.item }, set: { model.item = $0 }),
                onDismiss: { model.dismissals += 1 },
                content: { item in CountingEditor(item: item, model: model) })
    }
}

private struct Page: App {
    let model: EditorModel
    init() { self.init(model: EditorModel()) }
    init(model: EditorModel) { self.model = model }
    var body: some Scene { WindowGroup { Presenter(model: model) } }
}

@MainActor
@Suite("sheet(item:) keeps each item's state while it is up")
struct SheetItemStateKeptTests {
    @Test("Back to A: A's count and focus as left, onAppear again, no onDismiss; dismissed, A starts fresh")
    func backToAKeepsItsState() {
        let model = EditorModel()
        let app = TestApp(Page(model: model), width: 40, height: 12)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        func shows(_ text: String) -> Bool { app.screen.styledLines.contains { $0.contains(text) } }
        frame()
        frame()
        #expect(app.focusedID == "up-A", "sanity: the sheet's first control takes the focus")
        _ = app.press(.enter, times: 2)
        _ = app.press(.tab)
        frame()
        #expect(shows("A count=2"), "sanity: \(app.screen.styledLines)")
        #expect(app.focusedID == "other-A", "sanity")

        model.item = Item(id: "B")
        frame()
        frame()
        #expect(shows("B count=0"), "B opened with another item's state: \(app.screen.styledLines)")
        _ = app.press(.enter)

        model.item = Item(id: "A")
        frame()
        frame()
        #expect(shows("A count=2"), "A's count was lost while B was shown: \(app.screen.styledLines)")
        #expect(app.focusedID == "other-A", "the focus did not go back to where it was in A")
        #expect(model.appearances["A"] == 2, "A's onAppear did not run again on its return, as a tab's does")
        #expect(model.dismissals == 0, "switching the item ran onDismiss")

        model.item = nil
        frame()
        frame()
        #expect(model.dismissals == 1)
        model.item = Item(id: "A")
        frame()
        frame()
        #expect(shows("A count=0"), "presented again after a dismissal, A kept its count: \(app.screen.styledLines)")
    }
}
