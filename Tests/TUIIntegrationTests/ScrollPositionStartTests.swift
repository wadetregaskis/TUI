//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollPositionStartTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUI
import TUITesting

/// A bound `ScrollPosition`'s first value places the view as it appears, in
/// an app as SwiftUI's does (measured, `Tools/SwiftUIProbes/Scroll position
/// bound to a changing value/starting.swift`): an offset, one asked for by
/// `scrollTo`, an edge, and an offset past the end, which lands on the last
/// offset — in a `ScrollView` and in a `List`.
@MainActor
@Suite("A starting ScrollPosition in an app")
struct ScrollPositionStartTests {
    /// The first row label each line of `screen` draws, in order.
    private func rows(_ screen: String) -> [String] {
        screen.split(separator: "\n").compactMap { line in
            line.range(of: #"row \d+"#, options: .regularExpression).map { String(line[$0]) }
        }
    }

    private static func position(named name: String) -> ScrollPosition {
        switch name {
        case "scrollTo(y: 10)":
            var position = ScrollPosition()
            position.scrollTo(y: 10)
            return position
        case "edge: .bottom": return ScrollPosition(edge: .bottom)
        case "y: 500": return ScrollPosition(y: 500)
        default: return ScrollPosition(y: 10)
        }
    }

    @Test(
        "A starting position places the view on its first frame",
        arguments: ["y: 10", "scrollTo(y: 10)", "edge: .bottom", "y: 500"], [false, true])
    func startingPosition(name: String, inList: Bool) {
        let start = Self.position(named: name)
        let app = TestApp(width: 30, height: 6) {
            StartingPage(start: start, inList: inList)
        }
        let shown = rows(app.screen.text)
        let label = "\(inList ? "List" : "ScrollView") \(name): \(app.screen)"
        if name.hasPrefix("edge") || name == "y: 500" {
            // At the last offset: the last row on screen, the first not.
            #expect(shown.contains("row 39") && !shown.contains("row 0"), "\(label)")
        } else {
            #expect(shown.first == "row 10", "\(label)")
        }
    }

    @Test("A starting constant position places a scroll view on its first frame")
    func startingConstant() {
        let app = TestApp(width: 30, height: 6) {
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }
            }
            .scrollPosition(.constant(ScrollPosition(y: 10)))
        }
        #expect(rows(app.screen.text).first == "row 10", "\(app.screen)")
    }
}

/// Forty rows in a scroll view or a list, bound to a position held in state.
private struct StartingPage: View {
    let inList: Bool
    @State private var position: ScrollPosition

    init(start: ScrollPosition, inList: Bool) {
        self.inList = inList
        _position = State(initialValue: start)
    }

    var body: some View {
        if inList {
            List(0..<40, id: \.self) { Text("row \($0)") }
                .scrollPosition($position)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) { ForEach(0..<40, id: \.self) { Text("row \($0)") } }
            }
            .scrollPosition($position)
        }
    }
}
