//  🖥️ TUI — A Terminal UI framework for Swift
//  OverlaidIndicatorMotionTests.swift
//
//  A scrolling view placed `.overContent` (the default) draws its indicators
//  for the pointer, and so watches the pointer, which a terminal reports only
//  when asked for motion. It asks only while it has an indicator to show:
//  content that fits shows none, so a page of short lists and tables leaves
//  motion off; one that comes to overflow asks from that frame, and stops
//  asking once it fits again.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("Overlaid indicators ask for motion only with something to show")
struct OverlaidIndicatorMotionTests {
    @MainActor @Observable
    final class Lines {
        var count = 3
    }

    private struct Row: Identifiable {
        let id: Int
        var name: String { "row \(id)" }
    }

    enum Kind: String, CaseIterable, CustomTestStringConvertible {
        case scrollView, list, table, textEditor
        var testDescription: String { rawValue }
    }

    private struct Page: View {
        let kind: Kind
        let lines: Lines
        var body: some View {
            let count = lines.count
            switch kind {
            case .scrollView:
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<count, id: \.self) { Text("row \($0)") }
                    }
                }
                .frame(width: 20, height: 8)
            case .list:
                List(0..<count, id: \.self) { Text("row \($0)") }
                    .frame(width: 20, height: 8)
            case .table:
                Table((0..<count).map(Row.init(id:))) { TableColumn("Name", value: \Row.name) }
                    .frame(width: 20, height: 10)
            case .textEditor:
                TextEditor(text: .constant((0..<count).map { "line \($0)" }.joined(separator: "\n")))
                    .frame(width: 20, height: 8)
            }
        }
    }

    @Test("Motion is asked for while the content overflows, and not while it fits", arguments: Kind.allCases)
    func motionFollowsTheOverflow(_ kind: Kind) {
        let lines = Lines()
        let app = TestApp(width: 30, height: 12) { Page(kind: kind, lines: lines) }
        var now: Int64 = 0
        func frames() -> Bool {
            for _ in 0..<2 {
                now += 16_666_667
                app.frame(atNanos: now)
            }
            return app.services.mouseEventDispatcher.effectiveSupport(baseConfig: .disabled).motion
        }
        #expect(!frames(), "\(kind) fits, and asks for motion: \(app.screen.lines)")
        lines.count = 40
        #expect(frames(), "\(kind) overflows, and does not ask for motion: \(app.screen.lines)")
        lines.count = 3
        #expect(!frames(), "\(kind) fits again, and still asks for motion: \(app.screen.lines)")
    }
}
