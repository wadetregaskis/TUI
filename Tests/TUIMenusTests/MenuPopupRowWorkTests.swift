//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuPopupRowWorkTests.swift
//
//  What a Down costs in an open pop-up menu of many rows: how many of its
//  rows' labels are drawn (H-92b, CHROME-10). A Down moves the highlight from
//  one row to the next, so only those two rows draw anything new; every other
//  row is served as it was last drawn.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIMenus
import TUITesting
@testable import TUITestSupport

@MainActor
private final class Counter {
    var labels = 0
}

/// A row's label that counts its body's evaluations.
private struct CountedLabel: View {
    let index: Int
    let counter: Counter

    var body: some View {
        counter.labels += 1
        return Text(verbatim: "Item \(index)")
    }
}

private struct LongMenuApp: App {
    let counter: Counter
    let count: Int

    init() { (counter, count) = (Counter(), 0) }

    init(counter: Counter, count: Int) { (self.counter, self.count) = (counter, count) }

    var body: some Scene {
        WindowGroup {
            let counter = counter
            Menu("Actions") {
                ForEach(0..<count, id: \.self) { index in
                    Button(action: {}, label: { CountedLabel(index: index, counter: counter) })
                }
            }
        }
    }
}

@MainActor
@Suite("What a Down costs in an open pop-up menu")
struct MenuPopupRowWorkTests {
    @Test("A Down in an open menu of 500 rows draws the labels of the two rows the highlight moves between")
    func labelsPerDown() {
        let counter = Counter()
        let app = TestApp(LongMenuApp(counter: counter, count: 500), width: 80, height: 24)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        func key(_ key: Key) {
            app.send(KeyEvent(key: key))
            frame()
        }
        frame()
        frame()
        key(.space)
        #expect(app.screen.contains("Item 0"), "\(app.screen.lines.joined(separator: "\n"))")
        key(.down)
        var perDown: [Int] = []
        for _ in 0..<5 {
            counter.labels = 0
            key(.down)
            perDown.append(counter.labels)
        }
        // Before H-92b: 1,000 a Down — every row's label, twice; after, 4: the
        // two rows the highlight moved between.
        #expect(perDown.allSatisfy { $0 <= 4 }, "labels drawn per Down: \(perDown)")
        #expect(app.screen.contains("Item 6"), "\(app.screen.lines.joined(separator: "\n"))")
    }
}
