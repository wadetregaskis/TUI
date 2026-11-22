//  🖥️ TUI — A Terminal UI framework for Swift
//  StateOffMainTests.swift
//
//  `State` and `Binding` are `Sendable`, as SwiftUI's are, and a `@State` is
//  read and written off the main actor (the owner's O-25, 2026-11-21). Before
//  it, none of this compiled in Swift 6 mode: a `Binding` could not be handed
//  to a `@Sendable` closure, a detached task among them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
import TUITesting

/// What a test hands its view, and reads back of what it drew.
@MainActor
private final class Captured {
    /// The view's `$log`, taken when it appeared.
    var binding: Binding<[Int]>?
    /// The value of `log` each body read, in order.
    var seen: [[Int]] = []
}

private struct Log: View {
    let captured: Captured
    @State private var log: [Int] = []

    var body: some View {
        // A statement a view builder takes: what each body read, recorded.
        // swiftlint:disable:next redundant_discardable_let
        let _ = captured.seen.append(log)
        Text("Count: \(log.count)")
            .onAppear { captured.binding = $log }
    }
}

/// Runs `body`, which a `@Sendable` closure can only call if what it captures
/// is `Sendable`.
private func sendableClosure(_ body: @escaping @Sendable () -> Void) {
    body()
}

private func requireSendable<T: Sendable>(_: T.Type) {}

@MainActor
@Suite("@State off the main actor")
struct StateOffMainTests {
    @Test("A Binding and a State of a Sendable value are Sendable, as SwiftUI's are")
    func conformances() {
        requireSendable(Binding<Int>.self)
        requireSendable(State<Int>.self)
        let binding = Binding.constant(1)
        let state = State(wrappedValue: 2)
        sendableClosure {
            #expect(binding.wrappedValue + state.wrappedValue == 3)
        }
    }

    @Test("Writes from a detached task while frames are drawn all land, in the order they were made")
    func offMainWritesLandInOrder() async throws {
        let captured = Captured()
        let app = TestApp(width: 20, height: 1) { Log(captured: captured) }
        #expect(app.screen.text == "Count: 0")
        let binding = try #require(captured.binding)
        let writes = 200
        // Each append reads the value back off the main actor first, so a
        // write that was lost or applied out of order shows in the next.
        let writer = Task.detached {
            for index in 0..<writes { binding.wrappedValue.append(index) }
        }
        // Frames drawn while it writes: the main actor makes the posted
        // writes as it yields between them.
        for _ in 0..<writes {
            _ = app.screen
            await Task.yield()
        }
        await writer.value
        #expect(app.screen.text == "Count: \(writes)")
        #expect(binding.wrappedValue == Array(0..<writes))
        for seen in captured.seen {
            #expect(seen == Array(0..<seen.count))
        }
    }

    @Test("A read from a detached task gets a whole value, never older than the last it got")
    func offMainReadIsConsistent() async throws {
        let captured = Captured()
        let app = TestApp(width: 20, height: 1) { Log(captured: captured) }
        _ = app.screen
        let binding = try #require(captured.binding)
        let rounds = 100
        // Under 1,000, so the count draws with no grouping separator.
        let width = 500
        let reader = Task.detached { () -> (whole: Bool, firsts: [Int]) in
            var whole = true
            var firsts: [Int] = []
            for _ in 0..<(rounds * 5) {
                let value = binding.wrappedValue
                let first = value.first ?? 0
                if value.count != (first == 0 ? 0 : width) || value.contains(where: { $0 != first }) { whole = false }
                firsts.append(first)
                await Task.yield()
            }
            return (whole, firsts)
        }
        for round in 1...rounds {
            binding.wrappedValue = Array(repeating: round, count: width)
            _ = app.screen
            await Task.yield()
        }
        let result = await reader.value
        #expect(result.whole)
        #expect(result.firsts == result.firsts.sorted())
        // Published as the main actor made it: the next read off it sees it.
        let last = await Task.detached { binding.wrappedValue.first }.value
        #expect(last == rounds)
        #expect(app.screen.text == "Count: \(width)")
    }
}
