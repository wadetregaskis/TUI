//  🖥️ TUI — A Terminal UI framework for Swift
//  OptionalLifecycleActionTests.swift
//
//  `onAppear(perform:)` and `onDisappear(perform:)` take an optional closure, as
//  SwiftUI's do, defaulting to none.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

@Observable
private final class Log: @unchecked Sendable {
    var showsRow = true
    var appeared = 0
    var disappeared = 0
}

@MainActor
@Suite("A lifecycle modifier's action is optional")
struct OptionalLifecycleActionTests {
    private struct Page: App {
        let content: AnyView
        init() { self.init(content: AnyView(EmptyView())) }
        init(content: AnyView) { self.content = content }
        var body: some Scene { WindowGroup { content } }
    }

    private struct Row: View {
        let log: Log
        let appear: (() -> Void)?
        let disappear: (() -> Void)?
        var body: some View {
            VStack {
                if log.showsRow {
                    Text("row").onAppear(perform: appear).onDisappear(perform: disappear)
                }
                Text("anchor")
            }
        }
    }

    private func run(_ log: Log, appear: (() -> Void)?, disappear: (() -> Void)?) {
        let app = HeadlessApp(Page(content: AnyView(Row(log: log, appear: appear, disappear: disappear))), width: 20, height: 4)
        app.frame(atNanos: 16_666_667)
        app.frame(atNanos: 33_333_334)
        #expect(app.screen.contains { $0.stripped.contains("row") })
        log.showsRow = false
        app.frame(atNanos: 50_000_001)
        app.frame(atNanos: 66_666_668)
        #expect(!app.screen.contains { $0.stripped.contains("row") })
    }

    @Test("A closure held in an optional runs")
    func optionalClosureRuns() {
        let log = Log()
        run(log, appear: { log.appeared += 1 }, disappear: { log.disappeared += 1 })
        #expect(log.appeared == 1)
        #expect(log.disappeared == 1)
    }

    @Test("nil is no action, and the view draws and goes as usual")
    func nilIsNoAction() {
        run(Log(), appear: nil, disappear: nil)
    }

    @Test("The argument can be left out")
    func argumentLeftOut() {
        let app = HeadlessApp(Page(content: AnyView(Text("row").onAppear().onDisappear())), width: 20, height: 4)
        app.frame(atNanos: 16_666_667)
        #expect(app.screen.contains { $0.stripped.contains("row") })
    }

    @Test("A trailing closure still binds")
    func trailingClosure() {
        let log = Log()
        let app = HeadlessApp(
            Page(content: AnyView(Text("row").onAppear { log.appeared += 1 })), width: 20, height: 4)
        app.frame(atNanos: 16_666_667)
        app.frame(atNanos: 33_333_334)
        #expect(log.appeared == 1)
    }
}
