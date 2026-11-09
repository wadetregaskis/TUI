//  🖥️ TUI — A Terminal UI framework for Swift
//  DemoPageLaunchTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example

@Suite("The page the Example opens on")
struct DemoPageLaunchTests {
    @Test("A page is found by its case name, in any case")
    func namedFindsEveryPage() {
        for page in DemoPage.allCases {
            let name = String(describing: page)
            #expect(DemoPage.named(name) == page)
            #expect(DemoPage.named(name.uppercased()) == page)
        }
        #expect(DemoPage.named("tabviews") == .tabViews)
    }

    @Test("A name that is no page's, or a raw value, finds nothing")
    func namedRejectsOthers() {
        #expect(DemoPage.named("") == nil)
        #expect(DemoPage.named("nonsense") == nil)
        #expect(DemoPage.named("6") == nil)
        #expect(DemoPage.named(" buttons") == nil)
    }

    @Test("TUI_EXAMPLE_PAGE names the page to open on")
    func environmentNamesThePage() {
        let page = DemoPage.launchPage(arguments: ["Example"], environment: ["TUI_EXAMPLE_PAGE": "buttons"])
        #expect(page == .buttons)
    }

    @Test("An unknown or empty TUI_EXAMPLE_PAGE opens the menu")
    func unknownEnvironmentOpensTheMenu() {
        #expect(DemoPage.launchPage(arguments: ["Example"], environment: ["TUI_EXAMPLE_PAGE": "nope"]) == .menu)
        #expect(DemoPage.launchPage(arguments: ["Example"], environment: ["TUI_EXAMPLE_PAGE": ""]) == .menu)
    }

    @Test("Neither the flag nor the variable opens the menu")
    func nothingOpensTheMenu() {
        #expect(DemoPage.launchPage(arguments: ["Example"], environment: [:]) == .menu)
    }

    @Test("--page beats TUI_EXAMPLE_PAGE, even when it names no page")
    func flagBeatsVariable() {
        let environment = ["TUI_EXAMPLE_PAGE": "buttons"]
        #expect(DemoPage.launchPage(arguments: ["Example", "--page", "emoji"], environment: environment) == .emoji)
        #expect(DemoPage.launchPage(arguments: ["Example", "--page", "nope"], environment: environment) == .menu)
        // A trailing flag with no name after it is not a flag naming a page.
        #expect(DemoPage.launchPage(arguments: ["Example", "--page"], environment: environment) == .buttons)
    }

    @Test("The program's own name is never read as a flag")
    func argumentZeroIsSkipped() {
        #expect(DemoPage.launchPage(arguments: ["--page", "emoji"], environment: [:]) == .menu)
    }
}
