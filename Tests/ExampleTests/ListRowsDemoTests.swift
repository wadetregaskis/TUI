//  🖥️ TUI — A Terminal UI framework for Swift
//  ListRowsDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The Lists page's rows section")
struct ListRowsDemoTests {
    @Test("Switching the tasks off draws the empty list's placeholder in the list")
    func emptyPlaceholderDraws() throws {
        let app = TestApp(width: 100, height: 30) { ListRowsDemo() }
        #expect(app.screen.contains("Buy bread"), "tasks start on: \(app.screen)")
        #expect(!app.screen.contains("page.list.rows.nothingToDo"))

        try app.click("page.list.rows.showTasks")
        #expect(!app.screen.contains("Buy bread"), "the tasks are gone: \(app.screen)")
        #expect(app.screen.contains("page.list.rows.nothingToDo"), "the placeholder draws: \(app.screen)")
        #expect(app.screen.contains("page.list.rows.tasksHint"), "the page says why the list is empty")

        try app.click("page.list.rows.showTasks")
        #expect(
            app.screen.contains("Buy bread") && !app.screen.contains("page.list.rows.nothingToDo"),
            "back on: \(app.screen)")
    }
}
