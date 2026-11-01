//  🖥️ TUI — A Terminal UI framework for Swift
//  GesturesDemoTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import Example
import TUI
import TUITesting

/// The nested boxes as the page builds them, in words short enough to fit the
/// boxes' counts line whatever language the process is in.
private struct Boxes: View {
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
    private func makeApp() -> TestApp {
        TestApp(width: 100, height: 12) { Boxes() }
    }

    /// The two counts lines, left box first.
    private func counts(_ app: TestApp) -> [String] {
        app.screen.lines.flatMap { line in
            line.components(separatedBy: "child ").dropFirst().map { "child " + $0.prefix(while: { $0 != "│" }).trimmingCharacters(in: .whitespaces) }
        }
    }

    @Test("Nothing has been heard to begin with")
    func startsAtZero() {
        #expect(counts(makeApp()) == ["child 0 · parent 0", "child 0 · parent 0"])
    }

    @Test(".highPriorityGesture lets the parent's tap win over the child's: only the parent hears the click on the counts")
    func highPriority() throws {
        let app = makeApp()
        try app.click("child 0 · parent 0")
        #expect(counts(app) == ["child 0 · parent 1", "child 0 · parent 0"], "\(app.screen)")
    }

    @Test(".simultaneousGesture lets the parent and the child both hear the click on the counts")
    func simultaneous() throws {
        let app = makeApp()
        // The right box: the left one reads the same until it is clicked.
        let right = try #require(app.screen.location(of: "both"), "no second box: \(app.screen)")
        app.click(at: CellPoint(x: right.x + 2, y: right.y + 1))
        #expect(counts(app) == ["child 0 · parent 0", "child 1 · parent 1"], "\(app.screen)")
    }

    @Test("A click on a box's title is the parent's alone, in both boxes")
    func titleIsTheParents() throws {
        let app = makeApp()
        try app.click("high")
        try app.click("both")
        #expect(counts(app) == ["child 0 · parent 1", "child 0 · parent 1"], "\(app.screen)")
    }
}
