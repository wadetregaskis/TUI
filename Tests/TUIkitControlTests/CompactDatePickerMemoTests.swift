//  🖥️ TUIkit — Terminal UI Kit for Swift
//  CompactDatePickerMemoTests.swift
//
//  A row holding a `.compact` date picker is served from the row memo as one
//  holding a `.field` picker is. The compact style carries its calendar's
//  popover even while it is closed, and a closed popover declared a render
//  side effect on every frame — for the section a just-closed one may leave —
//  so no row holding a compact picker was ever stored.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@Observable
@MainActor
private final class Dates {
    var compact = true
    var dates: [Date] = (0..<6).map { Date(timeIntervalSince1970: 1_790_000_000 + Double($0) * 86_400) }
}

private struct DatesApp: App {
    let dates: Dates?

    init() { dates = nil }

    init(_ dates: Dates) { self.dates = dates }

    var body: some Scene {
        WindowGroup {
            if let dates { DatesPage(dates: dates) }
        }
    }
}

private struct DatesPage: View {
    let dates: Dates

    var body: some View {
        let dates = self.dates
        let rows = VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                DatePicker(
                    "", selection: Binding(get: { dates.dates[index] }, set: { dates.dates[index] = $0 }),
                    displayedComponents: .date)
            }
        }
        .environment(\.timeZone, TimeZone(identifier: "UTC")!)
        return Group {
            if dates.compact { rows.datePickerStyle(.compact) } else { rows.datePickerStyle(.field) }
        }
    }
}

@MainActor
private final class Harness {
    let dates = Dates()
    let app: HeadlessApp<DatesApp>
    private var now: Int64 = 0

    init(compact: Bool) {
        dates.compact = compact
        app = HeadlessApp(DatesApp(dates), width: 40, height: 20)
        frame()
        frame()
    }

    func frame() {
        now += 16_666_667
        app.frame(atNanos: now)
    }

    func shows(_ text: String) -> Bool { app.screen.contains { $0.stripped.contains(text) } }

    /// The rows served from the row memo on one quiet frame.
    func servedOnAQuietFrame() -> Int {
        let before = app.renderCache.rowWork.served
        frame()
        return app.renderCache.rowWork.served - before
    }
}

@MainActor
@Suite("Rows holding a compact date picker, served from the row memo")
struct CompactDatePickerMemoTests {
    @Test("A row holding a closed compact picker is served as one holding a field is")
    func rowsAreServed() {
        let field = Harness(compact: false).servedOnAQuietFrame()
        let compact = Harness(compact: true).servedOnAQuietFrame()
        #expect(field >= 4, "precondition: the field pickers' rows are served (\(field))")
        #expect(compact >= field, "served \(compact) compact rows against \(field) field rows")
    }

    /// The third picker's, so that handing the keys back has to restore the
    /// page's focus to it, not merely give them to the page's first stop.
    @Test("The calendar still opens, closes, and hands the keys back to the field it opened from")
    func calendarRoundTrip() {
        let harness = Harness(compact: true)
        let before = harness.dates.dates[2]
        for _ in 0..<2 {
            harness.app.send(KeyEvent(key: .tab))
            harness.frame()
        }
        harness.app.send(KeyEvent(key: .enter))
        harness.frame()
        #expect(harness.shows("Mo Tu We"), "Return did not open the calendar")
        harness.app.send(KeyEvent(key: .escape))
        harness.frame()
        harness.frame()
        #expect(!harness.shows("Mo Tu We"), "Escape left the calendar up")
        // The field has the keys again: Up steps its year.
        harness.app.send(KeyEvent(key: .up))
        harness.frame()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(
            calendar.component(.year, from: harness.dates.dates[2]) == calendar.component(.year, from: before) + 1,
            "Up after the calendar closed did not step the field it opened from")
    }
}
