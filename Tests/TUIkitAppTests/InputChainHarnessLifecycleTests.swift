//  🖥️ TUIkit — Terminal UI Kit for Swift
//  InputChainHarnessLifecycleTests.swift
//
//  The input-chain harness draws its frames inside the lifecycle's passes, as
//  the run loop does: a view that leaves is seen to go, and one that comes
//  back appears again and starts its task again.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("The input-chain harness brackets its frames with the lifecycle's passes")
struct InputChainHarnessLifecycleTests {
    /// What the view under test heard, by reference so every frame's view
    /// reaches the same record.
    private final class Record {
        var shown = true
        var appearances = 0
        var disappearances = 0
        var taskStarts = 0
    }

    private func page(_ record: Record) -> some View {
        VStack {
            Text("page")
            if record.shown {
                Text("note")
                    .onAppear { record.appearances += 1 }
                    .onDisappear { record.disappearances += 1 }
                    .task { record.taskStarts += 1 }
            }
        }
    }

    @Test("A view that leaves disappears, and one that comes back appears again")
    func leavingAndComingBack() {
        let record = Record()
        let harness = InputChainHarness()
        harness.frame(page(record))
        #expect(record.appearances == 1)
        record.shown = false
        harness.frame(page(record))
        #expect(record.disappearances == 1, "the view that left was never seen to go")
        record.shown = true
        harness.frame(page(record))
        #expect(record.appearances == 2, "the view that came back did not appear again")
    }

    @Test("A view's task starts again when the view comes back")
    func taskStartsAgain() async {
        let record = Record()
        let harness = InputChainHarness()
        harness.frame(page(record))
        await settle(until: { record.taskStarts == 1 })
        record.shown = false
        harness.frame(page(record))
        record.shown = true
        harness.frame(page(record))
        await settle(until: { record.taskStarts == 2 }, timeout: .seconds(5))
        #expect(record.taskStarts == 2, "the task of the view that came back never started again")
    }
}
