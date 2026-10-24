//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SplitViewPageTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUIkit
@testable import TUIkitApp

extension SplitViewPage: ExamplePageContent {}

@MainActor
@Suite("The Split View page")
struct SplitViewPageTests {
    @Test("The NavigationSplitView is first, and the HSplitView and VSplitView demo is below it")
    func holdsBothDemos() {
        let driver = ExamplePageDriver(ExamplePageApp<SplitViewPage>(), width: 100, height: 40)
        #expect(driver.shows("page.splitView.folders"), "the mail split view fills the first screen")
        #expect(!driver.shows("page.splitView.hvSection"), "the other demo is below the fold")

        driver.scroll(row: 5, column: 5, down: 20)
        #expect(driver.shows("page.splitView.hvSection"), "\(driver.lines)")
        #expect(driver.shows("page.splitView.hvExplain"))
        // The left pane is narrow, and shows the start of its key.
        for pane in ["page.splitView.hv.l", "page.splitView.hv.top", "page.splitView.hv.bottom"] {
            #expect(driver.shows(pane), "\(pane) is drawn: \(driver.lines)")
        }
    }
}
