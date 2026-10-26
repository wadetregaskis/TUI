//  🖥️ TUI — A Terminal UI framework for Swift
//  KeepsStateWhileHiddenTests.swift
//
//  `.keepsStateWhileHidden()`: a page a `switch` leaves keeps its `@State`
//  while another is shown, and has it back when it returns — where SwiftUI's
//  rule, which TUI keeps everywhere else, gives it fresh state.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUICore

@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("keepsStateWhileHidden")
struct KeepsStateWhileHiddenTests {
    final class Box: @unchecked Sendable {
        var page = 0
    }

    private struct Counter: View {
        @State private var count = 0
        var body: some View {
            Button("count \(count)") { count += 1 }
        }
    }

    private struct Pages: View {
        let box: Box
        let keeps: Bool
        var body: some View {
            VStack {
                switch box.page {
                case 0: Counter()
                default: Text("elsewhere")
                }
            }
            .keepsStateWhileHidden(keeps)
        }
    }

    /// Counts twice on page 0, visits page 1, and comes back: what it shows then.
    private func roundTrip(keeps: Bool) -> String? {
        let box = Box()
        let harness = InputChainHarness()
        let view = Pages(box: box, keeps: keeps)
        harness.frame(view)
        harness.frame(view)
        for _ in 0..<2 {
            harness.press(KeyEvent(key: .enter))
            harness.frame(view)
        }
        box.page = 1
        harness.frame(view)
        harness.frame(view)
        box.page = 0
        return harness.frame(view).lines.map(\.stripped).first { $0.contains("count") }
    }

    @Test("A page left and come back to has its state, where it would have started afresh")
    func keepsAPagesState() {
        #expect(roundTrip(keeps: true)?.contains("count 2") == true)
        #expect(roundTrip(keeps: false)?.contains("count 0") == true, "SwiftUI's rule, without it")
    }
}
