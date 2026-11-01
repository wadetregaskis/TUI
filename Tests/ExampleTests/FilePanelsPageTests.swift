//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelsPageTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import Example
import TUI
import TUITesting

@MainActor
@Suite("The File Panels page's results")
struct FilePanelsPageTests {
    /// A dash for each panel but the first. The save panel's row needs
    /// CoreTransferable, so Linux has four panels.
    #if canImport(CoreTransferable)
        private static let panelCount = 5
    #else
        private static let panelCount = 4
    #endif
    private static let otherPanelsCleared = Array(repeating: "—", count: panelCount - 1)

    private func makeApp() -> TestApp {
        TestApp(width: 240, height: 50) { FilePanelsPage() }
    }

    /// The results shown beside the buttons, top to bottom.
    private func results(_ app: TestApp) -> [String] {
        app.screen.lines.compactMap { line in
            guard let range = line.range(of: "page.files.result ") else { return nil }
            // Up to a panel's edge, when one is open beside the page.
            return String(line[range.upperBound...].prefix { $0 != "│" }).trimmingCharacters(in: .whitespaces)
        }
    }

    @Test("Each panel has a result beside its button, cleared to a dash")
    func fiveResults() {
        let app = makeApp()
        #expect(results(app) == ["—"] + Self.otherPanelsCleared, "\(app.screen)")
    }

    @Test("A cancelled panel says so, and opening it again clears that")
    func cancelledAndCleared() throws {
        let app = makeApp()
        try app.click("page.files.open ▌")
        app.press(.escape)
        #expect(results(app).first == "page.files.cancelled", "\(app.screen)")
        #expect(Array(results(app).dropFirst()) == Self.otherPanelsCleared, "the others are untouched")

        try app.click("page.files.open ▌")
        #expect(results(app).first == "—", "opening clears it: \(app.screen)")
    }

    @Test("Each panel's result is its own: cancelling the folder chooser leaves the file chooser's alone")
    func resultsAreIndependent() throws {
        let app = makeApp()
        try app.click("page.files.open ▌")
        app.press(.escape)
        try app.click("page.files.chooseFolder")
        app.press(.escape)
        let shown = results(app)
        #expect(shown.count == Self.panelCount)
        #expect(shown[0] == "page.files.cancelled" && shown[2] == "page.files.cancelled", "\(shown)")
        #expect(shown[1] == "—")
    }

    /// The panel judges the session as it opens, off the main actor, so the
    /// notice is a few frames behind the panel.
    @Test("The simulated ssh session's toggle gives the panels their remote-machine notice")
    func simulatedRemoteSession() async throws {
        let app = makeApp()
        let notice = "not your local machine"
        try app.click("page.files.simulateRemote")
        try app.click("page.files.open ▌")
        try await app.wait(for: notice)
        #expect(app.screen.contains("You are browsing the file system on "), "\(app.screen)")
        app.press(.escape)
        // Off again: the panel judges this process's own session, which a
        // test run at the desk or in CI does not show it for. Not asserted:
        // the suite may itself run over ssh.
        try app.click("page.files.simulateRemote")
        #expect(!app.screen.contains(notice), "closed with its panel")
    }
}
