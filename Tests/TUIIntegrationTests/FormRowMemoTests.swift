//  🖥️ TUI — A Terminal UI framework for Swift
//  FormRowMemoTests.swift
//
//  A form's rows a loop over comparable data made are memoised by their
//  element, as a `ForEach`'s rows are in a stack (PERFCASE-F7): a frame that
//  changes one of them, or nothing in the form, runs and measures that one
//  and serves the rest. And what the memo keys by is everything such a row is
//  drawn from: its element, and what the form's walk of its content read.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIView

/// One setting a row toggles: an object of its own, so a write to one is
/// observed by its row alone.
@Observable
@MainActor
private final class Setting: Identifiable, Equatable {
    let id: Int
    var isOn = false

    init(id: Int) { self.id = id }

    nonisolated static func == (lhs: Setting, rhs: Setting) -> Bool { lhs === rhs }
}

@Observable
@MainActor
private final class Settings {
    var rows: [Setting]
    /// Read by the loop's closure, where the form reads its content: a title
    /// no row's element carries.
    var prefix = "Option"
    /// Read by a view beside the form: a write to it changes nothing in it.
    var status = 0

    init(count: Int) { rows = (0..<count).map(Setting.init) }
}

private struct Page: View {
    let settings: Settings
    let grouped: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Status(settings: settings)
            if grouped {
                form.formStyle(.grouped)
            } else {
                form.formStyle(.columns)
            }
        }
    }

    private var form: some View {
        let settings = self.settings
        return Form {
            Section("Rows") {
                ForEach(settings.rows) { setting in
                    Toggle(
                        "\(settings.prefix) \(setting.id)",
                        isOn: Binding(get: { setting.isOn }, set: { setting.isOn = $0 }))
                }
            }
        }
    }
}

private struct Status: View {
    let settings: Settings
    var body: some View { Text(verbatim: "status \(settings.status)") }
}

private struct PageApp: App {
    let page: Page?
    // swiftlint:disable:next unavailable_function
    init() { fatalError("built with its page") }
    init(_ page: Page) { self.page = page }
    var body: some Scene { WindowGroup { page } }
}

@MainActor
@Suite("A form's loop rows are memoised by their element", .serialized)
struct FormRowMemoTests {
    private func app(_ settings: Settings, grouped: Bool) -> HeadlessApp {
        HeadlessApp(PageApp(Page(settings: settings, grouped: grouped)), width: 50, height: 80)
    }

    private func settle(_ app: HeadlessApp, nanos: inout Int64, frames: Int = 4) {
        for _ in 0..<frames {
            app.frame(atNanos: nanos)
            nanos += 16_700_000
        }
    }

    private func text(_ app: HeadlessApp) -> String { app.screen.map(\.stripped).joined(separator: "\n") }

    /// The bodies one frame runs after `change`, with the form settled.
    private func bodies(rows: Int, grouped: Bool, change: (Settings) -> Void) -> (bodies: Int, screen: String) {
        let settings = Settings(count: rows)
        let app = app(settings, grouped: grouped)
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        change(settings)
        let before = app.renderCache.rowWork.bodies
        settle(app, nanos: &nanos, frames: 1)
        return (app.renderCache.rowWork.bodies - before, text(app))
    }

    /// A write beside the form, and one to a single row: what the frame runs is
    /// the same for 10 rows as for 40. Before, the form drew every row afresh
    /// each frame, a toggle's body run and measured a dozen times: at 40 rows
    /// the frame ran some 1,500 bodies more than at 10.
    @Test("A frame runs the rows it changed, however many the form has", arguments: [true, false])
    func flatInRows(grouped: Bool) {
        let besideFew = bodies(rows: 10, grouped: grouped) { $0.status += 1 }
        let besideMany = bodies(rows: 40, grouped: grouped) { $0.status += 1 }
        #expect(besideMany.screen.contains("status 1"))
        #expect(
            besideMany.bodies == besideFew.bodies,
            "a write beside the form ran \(besideFew.bodies) bodies at 10 rows and \(besideMany.bodies) at 40")

        let oneFew = bodies(rows: 10, grouped: grouped) { $0.rows[3].isOn = true }
        let oneMany = bodies(rows: 40, grouped: grouped) { $0.rows[3].isOn = true }
        #expect(
            oneMany.bodies == oneFew.bodies,
            "toggling one row ran \(oneFew.bodies) bodies at 10 rows and \(oneMany.bodies) at 40")
    }

    /// A row drawn from what the walk of the form's content read, not from its
    /// element: the loop's closure reads the prefix where the form reads its
    /// content, a place beside the rows, so the write clears the form and that
    /// place but not the rows. Served by their elements alone, every row kept
    /// the old title.
    @Test("A row's title the loop's closure read from elsewhere is drawn again", arguments: [true, false])
    func walkReadsReachTheRows(grouped: Bool) {
        let settings = Settings(count: 12)
        let app = app(settings, grouped: grouped)
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        #expect(text(app).contains("Option 11"))
        settings.prefix = "Choice"
        settle(app, nanos: &nanos, frames: 2)
        let screen = text(app)
        #expect(!screen.contains("Option"), "a row kept the title it was drawn with:\n\(screen)")
        #expect(screen.contains("Choice 0") && screen.contains("Choice 11"))
    }

    /// A form whose content walk is cleared on every frame — here by a title
    /// the loop's closure reads, written each frame; in an app, by a page that
    /// reads a clock above the form — draws its rows afresh from the third
    /// such frame on, keeping nothing of them: memoised, every row's picture
    /// and sizes were stored to be cleared at the next frame. Once a frame
    /// leaves the walk alone the rows are memoised again, and a write beside
    /// the form runs as many bodies at 40 rows as at 10.
    @Test("A form cleared every frame stops keeping its rows, and keeps them again after", arguments: [true, false])
    func clearedEveryFrame(grouped: Bool) {
        func play(rows: Int) -> (stores: [Int], screen: String, beside: Int) {
            let settings = Settings(count: rows)
            let app = app(settings, grouped: grouped)
            var nanos: Int64 = 0
            settle(app, nanos: &nanos)
            var stores: [Int] = []
            for step in 0..<4 {
                settings.prefix = "Pass\(step)"
                let before = app.renderCache.stats.stores
                settle(app, nanos: &nanos, frames: 1)
                stores.append(app.renderCache.stats.stores - before)
            }
            let screen = text(app)
            settle(app, nanos: &nanos, frames: 3)
            settings.status += 1
            let before = app.renderCache.rowWork.bodies
            settle(app, nanos: &nanos, frames: 1)
            return (stores, screen, app.renderCache.rowWork.bodies - before)
        }
        let many = play(rows: 40)
        // The first two frames of the run still memoise (a one-off clear is
        // worth keeping the rows for); the later ones store none of them.
        #expect(many.stores[0] >= 40 && many.stores[1] >= 40, "\(many.stores)")
        #expect(many.stores[2] < 40 && many.stores[3] < 40, "rows kept on every frame: \(many.stores)")
        #expect(many.screen.contains("Pass3 0") && many.screen.contains("Pass3 39"))
        #expect(!many.screen.contains("Pass2"))
        let few = play(rows: 10)
        #expect(many.beside == few.beside, "after the run, a write beside ran \(few.beside) bodies at 10, \(many.beside) at 40")
    }

    /// A row whose element changed, and a row whose setting was toggled, are
    /// drawn again; the rows between them are not disturbed.
    @Test("A changed row is drawn again", arguments: [true, false])
    func changedRows(grouped: Bool) {
        let settings = Settings(count: 12)
        let app = app(settings, grouped: grouped)
        var nanos: Int64 = 0
        settle(app, nanos: &nanos)
        let before = app.screen.map(\.stripped)
        settings.rows[2].isOn = true
        settle(app, nanos: &nanos, frames: 2)
        let toggled = app.screen.map(\.stripped)
        let moved = zip(before, toggled).filter { $0 != $1 }
        #expect(moved.count == 1 && moved.allSatisfy { $0.1.contains("Option 2") }, "\(moved)")

        settings.rows[5] = Setting(id: 99)
        settle(app, nanos: &nanos, frames: 2)
        let screen = text(app)
        #expect(screen.contains("Option 99") && !screen.contains("Option 5"))
        #expect(screen.contains("Option 4") && screen.contains("Option 6"))
    }
}
