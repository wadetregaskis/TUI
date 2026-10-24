//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ListRowsDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUIkit
@testable import TUIkitApp

extension ListRowsDemo: ExamplePageContent {}

@MainActor
@Suite("The Lists page's rows section")
struct ListRowsDemoTests {
    @Test("Switching the tasks off draws the empty list's placeholder in the list")
    func emptyPlaceholderDraws() {
        let driver = ExamplePageDriver(ExamplePageApp<ListRowsDemo>(), width: 100, height: 30)
        #expect(driver.shows("Buy bread"), "tasks start on: \(driver.lines)")
        #expect(!driver.shows("page.list.rows.nothingToDo"))

        driver.click("page.list.rows.showTasks")
        #expect(!driver.shows("Buy bread"), "the tasks are gone: \(driver.lines)")
        #expect(driver.shows("page.list.rows.nothingToDo"), "the placeholder draws: \(driver.lines)")
        #expect(driver.shows("page.list.rows.tasksHint"), "the page says why the list is empty")

        driver.click("page.list.rows.showTasks")
        #expect(driver.shows("Buy bread") && !driver.shows("page.list.rows.nothingToDo"), "back on: \(driver.lines)")
    }
}
