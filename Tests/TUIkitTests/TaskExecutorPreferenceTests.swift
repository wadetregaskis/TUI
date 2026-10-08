//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TaskExecutorPreferenceTests.swift
//
//  `task(id:name:executorPreference:…)`: the nonisolated work a view's task
//  awaits runs on the executor it prefers.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization
import Testing

import TUIkit
@testable import TUIkitFoundation

/// An executor that counts the jobs it is given, and runs each at once.
@available(macOS 15, *)
private final class CountingExecutor: TaskExecutor {
    let jobs = Atomic<Int>(0)

    func enqueue(_ job: consuming ExecutorJob) {
        jobs.add(1, ordering: .relaxed)
        job.runSynchronously(on: asUnownedTaskExecutor())
    }
}

/// Nonisolated async work: it runs on the task's preferred executor, if any.
nonisolated private func nonisolatedWork() async -> Int {
    await Task.yield()
    return 1
}

@MainActor
@Suite("A view's task on a preferred executor")
struct TaskExecutorPreferenceTests {

    @Test("The task's nonisolated work runs on the executor it prefers")
    func preferredExecutorRunsTheWork() async {
        guard #available(macOS 15, *) else { return }
        let executor = CountingExecutor()
        let (finished, finish) = AsyncStream<Int>.makeStream()
        let harness = InputChainHarness(width: 10, height: 1)
        harness.frame(
            Text("x").task(id: 1, name: "work", executorPreference: executor) {
                finish.yield(await nonisolatedWork())
            })
        var iterator = finished.makeAsyncIterator()
        #expect(await iterator.next() == 1)
        #expect(executor.jobs.load(ordering: .relaxed) > 0)
    }
}
