//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelsPageTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import Example
import TUIkit
@testable import TUIkitApp

extension FilePanelsPage: ExamplePageContent {}

@MainActor
@Suite("The File Panels page's results")
struct FilePanelsPageTests {
    private typealias Driver = ExamplePageDriver<ExamplePageApp<FilePanelsPage>>

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

    @Test("Each of the five panels has a result beside its button, cleared to a dash")
    func fiveResults() {
        #expect(results(driver()) == ["—", "—", "—", "—", "—"], "\(driver().lines)")
    }

    @Test("A cancelled panel says so, and opening it again clears that")
    func cancelledAndCleared() {
        let driver = driver()
        driver.click("page.files.open )")
        driver.press(.escape)
        #expect(results(driver).first == "page.files.cancelled", "\(driver.lines)")
        #expect(Array(results(driver).dropFirst()) == ["—", "—", "—", "—"], "the others are untouched")

        driver.click("page.files.open )")
        #expect(results(driver).first == "—", "opening clears it: \(driver.lines)")
    }

    @Test("Each panel's result is its own: cancelling the folder chooser leaves the file chooser's alone")
    func resultsAreIndependent() {
        let driver = driver()
        driver.click("page.files.open )")
        driver.press(.escape)
        driver.click("page.files.chooseFolder")
        driver.press(.escape)
        let shown = results(driver)
        #expect(shown.count == 5)
        #expect(shown[0] == "page.files.cancelled" && shown[2] == "page.files.cancelled", "\(shown)")
        #expect(shown[1] == "—")
    }
}
