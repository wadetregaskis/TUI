//  🖥️ TUI — A Terminal UI framework for Swift
//  SheetItemSwitchDismissTests.swift
//
//  A `sheet(item:)` whose item the app replaces while it is up is not
//  dismissed: SwiftUI on macOS keeps the sheet up and runs no `onDismiss`
//  (measured, `Tools/SwiftUIProbes/Bug-hunt parity items (1116B)/sheetitem.swift`),
//  and neither does TUI; `onDismiss` runs once the item is `nil`.
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
private final class SheetModel: @unchecked Sendable {
    var item: Item? = Item(id: "A")
    @ObservationIgnored var dismissals = 0
}

private struct Presenter: View {
    let model: SheetModel
    var body: some View {
        Text("page")
            .sheet(
                item: Binding(get: { model.item }, set: { model.item = $0 }),
                onDismiss: { model.dismissals += 1 },
                content: { item in Text("sheet \(item.id)") })
    }
}

private struct Page: App {
    let model: SheetModel
    init() { self.init(model: SheetModel()) }
    init(model: SheetModel) { self.model = model }
    var body: some Scene { WindowGroup { Presenter(model: model) } }
}

@MainActor
@Suite("sheet(item:) switched to another item")
struct SheetItemSwitchDismissTests {
    @Test("Replacing the item runs no onDismiss; nil runs it once")
    func switchIsNotADismissal() {
        let model = SheetModel()
        let app = TestApp(Page(model: model), width: 40, height: 12)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        frame()
        frame()
        #expect(app.screen.styledLines.contains { $0.contains("sheet A") }, "\(app.screen.styledLines)")
        model.item = Item(id: "B")
        frame()
        frame()
        #expect(app.screen.styledLines.contains { $0.contains("sheet B") }, "\(app.screen.styledLines)")
        #expect(model.dismissals == 0, "switching the item ran onDismiss")
        model.item = nil
        frame()
        frame()
        #expect(model.dismissals == 1)
    }
}
