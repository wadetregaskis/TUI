//  🖥️ TUI — A Terminal UI framework for Swift
//  PickerKeyboardOpenRestingPointerTests.swift
//
//  A `.menu` picker's drop-down the keyboard opens under a resting pointer
//  keeps its choice lit until the pointer moves, as a menu does (lead
//  decision, 2026-11-18; B-MENUS-4; `MenuKeyboardOpenRestingPointerTests`).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIPickers
import TUITesting
@testable import TUITestSupport

/// A `.menu` picker, whose drop-down shares the menus' rows.
private struct FruitApp: App {
    var body: some Scene {
        WindowGroup {
            FruitPage()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .mouseSupport(.full)
    }
}

private struct FruitPage: View {
    @State private var fruit = "Apple"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Fruit", selection: $fruit) {
                Text("Apple").tag("Apple")
                Text("Banana").tag("Banana")
                Text("Cherry").tag("Cherry")
            }
            .pickerStyle(.menu)
            Text("chose \(fruit)")
            Spacer()
        }
    }
}

@MainActor
@Suite("A picker's drop-down the keyboard opens under a resting pointer")
struct PickerKeyboardOpenRestingPointerTests {
    @Test("It keeps its choice lit until the pointer moves, which then takes the row under it")
    func keepsTheChoice() throws {
        let app = TestApp(FruitApp(), width: 60, height: 16)
        if app.screen.location(of: "Cherry") == nil { app.press(.enter) }
        if app.screen.location(of: "Cherry") == nil {
            app.press(.tab)
            app.press(.enter)
        }
        let cherry = try #require(app.screen.location(of: "Cherry"), "Return opens it: \(app.screen)")
        app.press(.escape)
        app.mouse(MouseEvent(button: .none, phase: .moved, x: cherry.x + 1, y: cherry.y))
        app.press(.enter)
        app.press(.enter)
        #expect(app.screen.contains("chose Apple"), "the resting pointer took the row it was over: \(app.screen)")
        // Opened again, a move takes the row under the pointer.
        app.press(.enter)
        app.mouse(MouseEvent(button: .none, phase: .moved, x: cherry.x + 2, y: cherry.y))
        app.press(.enter)
        #expect(app.screen.contains("chose Cherry"), "the pointer's move did not take its row: \(app.screen)")
    }
}
