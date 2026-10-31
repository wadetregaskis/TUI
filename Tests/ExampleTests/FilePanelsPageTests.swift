//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelsPageTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import Example
import TUI
@testable import TUIApp

extension FilePanelsPage: ExamplePageContent {}

@MainActor
@Suite("The File Panels page's results")
struct FilePanelsPageTests {
    private typealias Driver = ExamplePageDriver<ExamplePageApp<FilePanelsPage>>

    /// A dash for each panel but the first. The save panel's row needs
    /// CoreTransferable, so Linux has four panels.
    #if canImport(CoreTransferable)
        private static let panelCount = 5
    #else
        private static let panelCount = 4
    #endif
    private static let otherPanelsCleared = Array(repeating: "—", count: panelCount - 1)

    private func driver() -> Driver {
        ExamplePageDriver(ExamplePageApp<FilePanelsPage>(), width: 240, height: 50)
    }

    /// The results shown beside the buttons, top to bottom.
    private func results(_ driver: Driver) -> [String] {
        driver.lines.compactMap { line in
            guard let range = line.range(of: "page.files.result ") else { return nil }
            // Up to a panel's edge, when one is open beside the page.
            return String(line[range.upperBound...].prefix { $0 != "│" }).trimmingCharacters(in: .whitespaces)
        }
    }

    @Test("Each panel has a result beside its button, cleared to a dash")
    func fiveResults() {
        #expect(results(driver()) == ["—"] + Self.otherPanelsCleared, "\(driver().lines)")
    }

    @Test("A cancelled panel says so, and opening it again clears that")
    func cancelledAndCleared() {
        let driver = driver()
        driver.click("page.files.open ▌")
        driver.press(.escape)
        #expect(results(driver).first == "page.files.cancelled", "\(driver.lines)")
        #expect(Array(results(driver).dropFirst()) == Self.otherPanelsCleared, "the others are untouched")

        driver.click("page.files.open ▌")
        #expect(results(driver).first == "—", "opening clears it: \(driver.lines)")
    }

    @Test("Each panel's result is its own: cancelling the folder chooser leaves the file chooser's alone")
    func resultsAreIndependent() {
        let driver = driver()
        driver.click("page.files.open ▌")
        driver.press(.escape)
        driver.click("page.files.chooseFolder")
        driver.press(.escape)
        let shown = results(driver)
        #expect(shown.count == Self.panelCount)
        #expect(shown[0] == "page.files.cancelled" && shown[2] == "page.files.cancelled", "\(shown)")
        #expect(shown[1] == "—")
    }

    /// The panel judges the session as it opens, off the main actor, so the
    /// notice is a few frames behind the panel.
    @Test("The simulated ssh session's toggle gives the panels their remote-machine notice")
    func simulatedRemoteSession() async throws {
        let driver = driver()
        let notice = "not your local machine"
        driver.click("page.files.simulateRemote")
        driver.click("page.files.open ▌")
        for _ in 0..<500 where !driver.shows(notice) {
            try await Task.sleep(for: .milliseconds(10))
            driver.advance()
        }
        #expect(driver.shows("You are browsing the file system on "), "\(driver.lines)")
        driver.press(.escape)
        // Off again: the panel judges this process's own session, which a
        // test run at the desk or in CI does not show it for. Not asserted:
        // the suite may itself run over ssh.
        driver.click("page.files.simulateRemote")
        #expect(!driver.shows(notice), "closed with its panel")
    }
}
