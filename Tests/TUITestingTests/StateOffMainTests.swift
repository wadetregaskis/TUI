//  🖥️ TUI — A Terminal UI framework for Swift
//  StateOffMainTests.swift
//
//  `State` and `Binding` are `Sendable`, as SwiftUI's are, and a `@State` is
//  read and written off the main actor (the owner's O-25, 2026-11-21). Before
//  it, none of this compiled in Swift 6 mode: a `Binding` could not be handed
//  to a `@Sendable` closure, a detached task among them. And no access off
//  the main actor waits for it (O-25-FIRSTREAD, 2026-11-22): the first read
//  used to, a deadlock where the main actor waited on the reading thread.
//  And every read in a render pass agrees, a write off the main actor landing
//  mid-pass showing from the next (O25-D-2, 2026-11-22).
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Dispatch)
    import Dispatch
#endif
import Foundation
import Synchronization
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

#if canImport(Dispatch)  // A second thread, which wasip1 does not have.
    /// What a thread of its own read, handed back to the test.
    private final class Handoff: Sendable {
        let read = Mutex<[Int]?>(nil)
    }

    /// Runs `body` on a thread of its own while the main actor waits for it
    /// synchronously — as a semaphore, a `DispatchQueue.sync` or a group's
    /// `wait()` would — and returns whether it finished within ten seconds: it
    /// does in microseconds unless something it does waits for the main actor,
    /// which is then a deadlock the time limit breaks.
    @MainActor
    private func whileMainActorWaits(_ body: @escaping @Sendable () -> Void) -> Bool {
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            body()
            finished.signal()
        }
        return finished.wait(timeout: .now() + .seconds(10)) == .success
    }
#endif

/// What a test hands a view that reads its `@State` more than once in a body,
/// and what each read gave.
@MainActor
private final class Reads {
    /// The view's `$items`, taken when it appeared.
    var binding: Binding<[Int]>?
    /// Run once, by the next body, between its reads.
    var between: (() -> Void)?
    /// What each body read: every read it made, in order.
    var bodies: [[[Int]]] = []
    /// What each child body read through the binding its parent handed it.
    var children: [[Int]] = []

    /// Runs ``between``, once.
    func runBetween() {
        let between = between
        self.between = nil
        between?()
    }
}

/// Reads its state, lets the test act, then reads it again.
private struct ReadsTwice: View {
    let reads: Reads
    @State private var items: [Int] = []

    var body: some View {
        let first = items
        // Statements a view builder takes.
        // swiftlint:disable redundant_discardable_let
        let _ = reads.runBetween()
        let second = items
        let _ = reads.bodies.append([first, second])
        // swiftlint:enable redundant_discardable_let
        Text("Count: \(second.count)")
            .onAppear { reads.binding = $items }
    }
}

/// Reads its state, lets the test act, then hands a child the binding.
private struct HandsDown: View {
    let reads: Reads
    @State private var items: [Int] = []

    var body: some View {
        let first = items
        // Statements a view builder takes.
        // swiftlint:disable redundant_discardable_let
        let _ = reads.runBetween()
        let _ = reads.bodies.append([first])
        // swiftlint:enable redundant_discardable_let
        ReadsThroughBinding(reads: reads, items: $items)
            .onAppear { reads.binding = $items }
    }
}

/// Reads, in its body, the binding its parent hands it.
private struct ReadsThroughBinding: View {
    let reads: Reads
    @Binding var items: [Int]

    var body: some View {
        // A statement a view builder takes.
        // swiftlint:disable:next redundant_discardable_let
        let _ = reads.children.append(items)
        Text("Count: \(items.count)")
    }
}

/// Writes its state in its body, and reads it back.
private struct WritesInBody: View {
    let reads: Reads
    let write: [Int]
    @State private var items: [Int] = []

    var body: some View {
        let first = items
        // Statements a view builder takes.
        // swiftlint:disable redundant_discardable_let
        let _ = (items = write)
        let second = items
        let _ = reads.bodies.append([first, second])
        // swiftlint:enable redundant_discardable_let
        Text("Count: \(second.count)")
    }
}

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

    #if canImport(Dispatch)  // A second thread, which wasip1 does not have.
        @Test("The first read off the main actor waits for nothing: the main actor waiting on that thread is no deadlock")
        func firstOffMainReadNeverWaits() throws {
            let captured = Captured()
            let app = TestApp(width: 20, height: 1) { Log(captured: captured) }
            #expect(app.screen.text == "Count: 0")
            let binding = try #require(captured.binding)
            binding.wrappedValue = [7]
            let handoff = Handoff()
            // The box's first read off the main actor, while the main actor is
            // blocked until it returns. SwiftUI's never waits (O-25-FIRSTREAD).
            let finished = whileMainActorWaits {
                let value = binding.wrappedValue
                handoff.read.withLock { $0 = value }
            }
            #expect(finished)
            #expect(handoff.read.withLock { $0 } == [7])
        }

        @Test("A write off the main actor waits for nothing, its thread reads it back at once, and the main actor's next turn sees it")
        func offMainWriteNeverWaits() async throws {
            let captured = Captured()
            let app = TestApp(width: 20, height: 1) { Log(captured: captured) }
            #expect(app.screen.text == "Count: 0")
            let binding = try #require(captured.binding)
            let handoff = Handoff()
            let finished = whileMainActorWaits {
                binding.wrappedValue = [42]
                let value = binding.wrappedValue
                handoff.read.withLock { $0 = value }
            }
            #expect(finished)
            #expect(handoff.read.withLock { $0 } == [42])
            // One turn of the main actor: whatever the write left to make there
            // was posted before it.
            await Task.yield()
            #expect(binding.wrappedValue == [42])
            #expect(app.screen.text == "Count: 1")
        }

        @Test("A body's reads of its state agree when a write off the main actor lands between them; the next frame shows it")
        func bodyReadsAgreeAcrossAnOffMainWrite() async throws {
            let reads = Reads()
            let app = TestApp(width: 20, height: 1) { ReadsTwice(reads: reads) }
            #expect(app.screen.text == "Count: 0")
            let binding = try #require(reads.binding)
            // Between the next body's two reads, a write from a thread of its own,
            // which the body waits for: no timing, the write has landed.
            reads.between = {
                #expect(whileMainActorWaits { binding.wrappedValue = [1, 2] })
            }
            reads.bodies.removeAll()
            // A write on the main actor, so the next frame runs the body.
            binding.wrappedValue = [1]
            #expect(app.screen.text == "Count: 1")
            #expect(reads.between == nil, "the body ran")
            #expect(reads.bodies.allSatisfy { $0 == [[1], [1]] }, "\(reads.bodies)")
            // The write's report, posted to the main actor, asks for the next
            // frame, a pass of its own, which reads the write.
            await Task.yield()
            reads.bodies.removeAll()
            #expect(app.screen.text == "Count: 2")
            #expect(!reads.bodies.isEmpty, "the body ran again")
            #expect(reads.bodies.allSatisfy { $0 == [[1, 2], [1, 2]] }, "\(reads.bodies)")
        }

        @Test("A child reads through a Binding what its parent read, a write off the main actor landing between them")
        func bindingReadAgreesWithParent() async throws {
            let reads = Reads()
            let app = TestApp(width: 20, height: 1) { HandsDown(reads: reads) }
            #expect(app.screen.text == "Count: 0")
            let binding = try #require(reads.binding)
            reads.between = {
                #expect(whileMainActorWaits { binding.wrappedValue = [1, 2] })
            }
            reads.bodies.removeAll()
            reads.children.removeAll()
            binding.wrappedValue = [1]
            #expect(app.screen.text == "Count: 1")
            #expect(reads.between == nil, "the parent's body ran")
            #expect(!reads.children.isEmpty, "the child's body ran")
            #expect(reads.bodies.allSatisfy { $0 == [[1]] }, "\(reads.bodies)")
            #expect(reads.children.allSatisfy { $0 == [1] }, "\(reads.children)")
            await Task.yield()
            reads.children.removeAll()
            #expect(app.screen.text == "Count: 2")
            #expect(!reads.children.isEmpty, "the child's body ran again")
            #expect(reads.children.allSatisfy { $0 == [1, 2] }, "\(reads.children)")
        }
    #endif

    @Test("A body that writes its state on the main actor reads its write back")
    func bodyReadsItsOwnWriteBack() {
        let reads = Reads()
        let app = TestApp(width: 20, height: 1) { WritesInBody(reads: reads, write: [5, 6, 7]) }
        #expect(app.screen.text == "Count: 3")
        #expect(reads.bodies.first == [[], [5, 6, 7]], "\(reads.bodies)")
    }
}
