//  🖥️ TUI — A Terminal UI framework for Swift
//  NamedTaskTests.swift
//
//  `task(name:…)` and `task(id:name:…)`: the name reaches the task, and the
//  `id:` form still restarts when its id changes.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
@testable import TUITestSupport

/// Whether this runtime names tasks: macOS 26, and Swift 6.2's runtime
/// elsewhere.
private var runtimeNamesTasks: Bool {
    if #available(macOS 26, *) { return true }
    return false
}

/// The name of the task this is called from, where the runtime names tasks.
nonisolated private func currentTaskName() -> String? {
    if #available(macOS 26, *) { return Task.name }
    return nil
}

/// What one run of a task saw: the id it ran for and the name it carried.
private struct Run: Equatable {
    let id: Int
    let name: String?
}

// Each test waits on a task's run, so a task that never runs would wait
// forever: the limit turns that into a failure. Very generous, because the
// task queues on the main actor behind every other main-actor test the process
// has started, so it runs about when they have all finished: more than 600 s on
// a slow CI runner (2026-10-31, in a group that took 933 s), failing all three.
@MainActor
@Suite("A view's task, named", .timeLimit(.minutes(45)))
struct NamedTaskTests {

    /// The name a task carries where the runtime names tasks, and `nil` where
    /// it does not.
    private func expectedName(_ name: String) -> String? {
        runtimeNamesTasks ? name : nil
    }

    @Test("The name reaches the task")
    func nameReachesTheTask() async {
        let (runs, record) = AsyncStream<String?>.makeStream()
        let harness = InputChainHarness(width: 10, height: 1)
        harness.frame(Text("x").task(name: "loader") { record.yield(currentTaskName()) })
        var iterator = runs.makeAsyncIterator()
        #expect(await iterator.next() == expectedName("loader"))
    }

    @Test("No name makes one from the file and line")
    func defaultNameIsTheCallSite() async {
        let (runs, record) = AsyncStream<String?>.makeStream()
        let harness = InputChainHarness(width: 10, height: 1)
        harness.frame(
            Text("x").task(name: nil, file: "Feature/Status.swift", line: 12) {
                record.yield(currentTaskName())
            })
        var iterator = runs.makeAsyncIterator()
        #expect(await iterator.next() == expectedName("Feature/Status.swift:12"))
    }

    @Test("The id form restarts on an id change, named each time")
    func idFormRestartsNamed() async {
        let (runs, record) = AsyncStream<Run>.makeStream()
        let harness = InputChainHarness(width: 10, height: 1)
        func view(_ id: Int) -> some View {
            Text("x").task(id: id, name: "search") { record.yield(Run(id: id, name: currentTaskName())) }
        }
        var iterator = runs.makeAsyncIterator()

        harness.frame(view(1))
        #expect(await iterator.next() == Run(id: 1, name: expectedName("search")))

        // An unchanged id is a non-event; a changed one restarts. Were the
        // second frame to restart too, its run would arrive first, with id 1.
        harness.frame(view(1))
        harness.frame(view(2))
        #expect(await iterator.next() == Run(id: 2, name: expectedName("search")))
    }
}
