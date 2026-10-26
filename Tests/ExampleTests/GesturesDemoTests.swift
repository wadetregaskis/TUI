//  🖥️ TUI — A Terminal UI framework for Swift
//  GesturesDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI
@testable import TUIApp

/// The nested boxes as the page builds them, in words short enough to fit the
/// boxes' counts line whatever language the process is in.
private struct Boxes: ExamplePageContent {
    var body: some View {
        NestedGestureBoxes(
            childLabel: "child", parentLabel: "parent", priorityTitle: "high", simultaneousTitle: "both")
    }
}

/// The two nested boxes of the Mouse page's gestures section behave as the
/// section's explanation says they do.
@MainActor
@Suite("The gestures section's nested boxes")
struct GesturesDemoTests {
    private func driver() -> ExamplePageDriver<ExamplePageApp<Boxes>> {
        ExamplePageDriver(ExamplePageApp<Boxes>(), width: 100, height: 12)
    }

    /// The two counts lines, left box first.
    private func counts(_ driver: ExamplePageDriver<ExamplePageApp<Boxes>>) -> [String] {
        driver.lines.flatMap { line in
            line.components(separatedBy: "child ").dropFirst().map { "child " + $0.prefix(while: { $0 != "│" }).trimmingCharacters(in: .whitespaces) }
        }
    }

    @Test("Nothing has been heard to begin with")
    func startsAtZero() {
        #expect(counts(driver()) == ["child 0 · parent 0", "child 0 · parent 0"])
    }

    @Test(".highPriorityGesture lets the parent's tap win over the child's: only the parent hears the click on the counts")
    func highPriority() {
        let driver = driver()
        driver.click("child 0 · parent 0")
        #expect(counts(driver) == ["child 0 · parent 1", "child 0 · parent 0"], "\(driver.lines)")
    }

    @Test(".simultaneousGesture lets the parent and the child both hear the click on the counts")
    func simultaneous() {
        let driver = driver()
        // The right box: the left one reads the same until it is clicked.
        guard let right = driver.position(of: "both") else {
            Issue.record("no second box: \(driver.lines)")
            return
        }
        driver.click(row: right.row + 1, column: right.column + 2)
        #expect(counts(driver) == ["child 0 · parent 0", "child 1 · parent 1"], "\(driver.lines)")
    }

    @Test("A click on a box's title is the parent's alone, in both boxes")
    func titleIsTheParents() {
        let driver = driver()
        driver.click("high")
        driver.click("both")
        #expect(counts(driver) == ["child 0 · parent 1", "child 0 · parent 1"], "\(driver.lines)")
    }
}
