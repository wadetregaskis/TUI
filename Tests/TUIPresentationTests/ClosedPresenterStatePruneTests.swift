//  🖥️ TUI — A Terminal UI framework for Swift
//  ClosedPresenterStatePruneTests.swift
//
//  A closed `.alert` or `.sheet` stores nothing in the state storage, so the
//  storage's end-of-pass prune skips its walk on a frame that changed nothing
//  (`PruneWitness`). Each dismissed presenter looked its drag handler up with
//  the creating accessor, on every frame, to reset it: a box made and, since
//  nothing marks a dismissed presenter's identity, dropped at the end of the
//  pass. Every frame of every app with a closed alert or sheet — the menu bar's
//  About alert is one in every app with commands — walked every value.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIPresentation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

/// A counter with state of its own: what the prune walks over.
private struct Counter: View {
    let index: Int
    @State private var taps = 0
    @State private var isOn = false

    var body: some View {
        Text(verbatim: "counter \(index): \(taps) \(isOn)")
    }
}

/// Counters, and beside them a closed alert or a closed sheet.
private struct PrunePage: View {
    let presenter: ClosedPresenterStatePruneTests.Presenter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<20, id: \.self) { Counter(index: $0) }
            switch presenter {
            case .alert:
                Text("page").alert("Delete?", isPresented: .constant(false)) { Button("Delete") {} }
            case .sheet:
                Text("page").sheet(isPresented: .constant(false)) { Text("sheet") }
            }
        }
    }
}

private struct PruneApp: App {
    let presenter: ClosedPresenterStatePruneTests.Presenter

    init() { presenter = .alert }

    init(_ presenter: ClosedPresenterStatePruneTests.Presenter) { self.presenter = presenter }

    var body: some Scene {
        WindowGroup { PrunePage(presenter: presenter) }
    }
}

@MainActor
@Suite("A closed presenter leaves the state prune nothing to walk")
struct ClosedPresenterStatePruneTests {
    enum Presenter: CaseIterable, Sendable { case alert, sheet }

    @Test("A frame that changed nothing skips the state prune's walk under a closed presenter", arguments: Presenter.allCases)
    func closedPresenterLeavesThePruneIdle(_ presenter: Presenter) {
        let app = TestApp(PruneApp(presenter), width: 40, height: 30)
        var now: Int64 = 0
        func frame() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        for _ in 0..<3 { frame() }
        #expect(app.screen.contains("counter 19"))
        let before = app.services.stateStorage.pruneCounts
        for _ in 0..<3 { frame() }
        let after = app.services.stateStorage.pruneCounts
        #expect(after.prunes - before.prunes == 3)
        #expect(after.walks - before.walks == 0, "\(presenter): the state prune \(after.delta(since: before)) idle frames")
    }
}
