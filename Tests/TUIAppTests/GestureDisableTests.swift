//  🖥️ TUI — A Terminal UI framework for Swift
//  GestureDisableTests.swift
//
//  A disabled view's gestures are given up at the disable, as macOS 15.8
//  gives them up (F2 probes review4b–d; decisions B-F2-2): a `@GestureState`
//  a drag updated resets then, and the frame that does it is asked for, so
//  what the gestures held back runs at the disable rather than at whatever
//  frame or press comes next. `GestureArenaLifetimeTests.disabledRow` pins
//  the clicks around a disabled row.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("A disabled view's gestures are given up at the disable")
struct GestureDisableTests {
    /// A reference the view reads, so a test can disable it between frames
    /// as a model would.
    final class Gone {
        var value = false
    }

    /// A box whose drag writes its translation into a gesture state, logging
    /// each value it draws with and each reset.
    private struct DisablingDrag: View {
        let log: GestureRecord
        let gone: Gone
        @GestureState private var offset: CellSize

        init(log: GestureRecord, gone: Gone) {
            self.log = log
            self.gone = gone
            _offset = GestureState(wrappedValue: CellSize(width: 0, height: 0)) { value, _ in
                log("reset from \(value.width)")
            }
        }

        var body: some View {
            log("draw \(offset.width)")
            return Text("").frame(width: 10, height: 3)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($offset) { value, state, _ in state = value.translation }
                        .onEnded { [log] _ in log("ended") })
                .disabled(gone.value)
                .frame(width: 40, height: 12, alignment: .topLeading)
        }
    }

    /// Measured on macOS 15.8 (F2 probe S1): a drag disabled mid-drag
    /// resets its gesture state at the disable. It reset at the next event of
    /// the left button, a move or the release, however long that took.
    @Test("A drag disabled mid-drag resets its @GestureState at the disable")
    func dragStateResetsAtTheDisable() {
        let log = GestureRecord()
        let gone = Gone()
        let harness = InputChainHarness()
        let view = { DisablingDrag(log: log, gone: gone) }
        harness.frame(view())
        harness.pointer([(.pressed, 1, 1), (.dragged, 4, 1)], view)
        #expect(log.entries.last == "draw 3")
        gone.value = true
        harness.frame(view())  // the walk that disables it
        harness.frame(view())  // the next frame's tick gives it up
        #expect(log.entries.suffix(2) == ["reset from 3", "draw 0"])
        harness.pointer([(.dragged, 6, 1), (.released, 6, 1)], view)
        #expect(!log.entries.contains("ended"), "and it reports nothing more")
    }

    /// A row with a double and a single tap beside a plain box, inside a
    /// tap; below them a button that disables the row.
    struct Page: App {
        static let log = GestureRecord()

        var body: some Scene {
            WindowGroup {
                Rows(log: Self.log)
            }
        }
    }

    struct Rows: View {
        let log: GestureRecord
        @State private var gone = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    Text("ROW")
                        .onTapGesture(count: 2) { log("open") }
                        .onTapGesture { log("select") }
                        .disabled(gone)
                    Text("BOX")
                }
                .onTapGesture { log("outer") }
                Button("Hide") {
                    log("hide")
                    gone = true
                }
            }
        }
    }

    /// Where `text` is drawn on `app`'s screen: its first cell.
    private func cell(of text: String, in app: HeadlessApp<Page>) throws -> (x: Int, y: Int) {
        let lines = app.screen.map(\.stripped)
        let y = try #require(lines.firstIndex { $0.contains(text) })
        let range = try #require(lines[y].range(of: text))
        return (lines[y].distance(from: lines[y].startIndex, to: range.lowerBound), y)
    }

    private func click(_ app: HeadlessApp<Page>, at cell: (x: Int, y: Int)) {
        app.send(MouseEvent(button: .left, phase: .pressed, x: cell.x, y: cell.y))
        app.send(MouseEvent(button: .left, phase: .released, x: cell.x, y: cell.y))
    }

    /// Through the run loop: the walk that disables the row asks for the
    /// next frame, and that frame runs the outer tap for the row's click —
    /// with nothing else to wake the loop, it would have waited for the next
    /// press.
    @Test("The walk that disables a waiting gesture asks for the frame that gives it up")
    func disableAsksForAFrame() throws {
        let log = Page.log
        log.entries = []
        let app = HeadlessApp(Page(), width: 40, height: 10)
        let second: Int64 = 1_000_000_000
        let millisecond: Int64 = 1_000_000
        app.frame(atNanos: second)
        let row = try cell(of: "ROW", in: app)
        let hide = try cell(of: "Hide", in: app)
        click(app, at: (row.x + 1, row.y))
        app.frame(atNanos: second + 16 * millisecond)
        app.frame(atNanos: second + 100 * millisecond)
        click(app, at: (hide.x + 1, hide.y))
        let disabling = second + 116 * millisecond
        app.frame(atNanos: disabling)
        #expect(log.entries == ["hide"])
        #expect(app.nextWake(after: disabling) == disabling + 1)
        app.frame(atNanos: disabling + 1)
        #expect(log.entries == ["hide", "outer"], "the outer tap runs the row's click at the disable")
        #expect(app.nextWake(after: disabling + 1) == nil, "and nothing more is asked for")
    }
}
