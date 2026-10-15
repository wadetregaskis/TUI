//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ProgressViewTimerTests.swift
//
//  `ProgressView(timerInterval:countsDown:)`: the bar follows the clock through
//  the interval, a second at a time, and the default label reads out the time
//  left (or gone); a finished timer stops moving.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitFoundation
@testable import TUIkitNumericControls
@testable import TUIkitTestSupport

@MainActor
@Suite("ProgressView(timerInterval:)")
struct ProgressViewTimerTests {
    private func lines<V: View>(_ view: V) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 24, height: 3)).lines.map(\.stripped)
    }

    /// 30 seconds gone of 120: SwiftUI's own example, a quarter of the way.
    private var quarterGone: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-30)...now.addingTimeInterval(90)
    }

    @Test("Counting down, the bar shows what is left and the label the time left")
    func countsDown() {
        let timer = lines(ProgressView(timerInterval: quarterGone))
        let plain = lines(ProgressView(value: 0.75) { EmptyView() } currentValueLabel: { Text("1:30") })
        #expect(timer == plain, "\(timer) vs \(plain)")
    }

    @Test("Counting up, the bar shows what has passed and the label the time gone")
    func countsUp() {
        let timer = lines(ProgressView(timerInterval: quarterGone, countsDown: false) { Text("Boil") })
        let plain = lines(ProgressView(value: 0.25) { Text("Boil") } currentValueLabel: { Text("0:30") })
        #expect(timer == plain, "\(timer) vs \(plain)")
    }

    @Test("A finished timer shows its end and asks for no more entries")
    func finished() {
        let now = Date()
        let done = now.addingTimeInterval(-120)...now.addingTimeInterval(-60)
        #expect(lines(ProgressView(timerInterval: done))
            == lines(ProgressView(value: 0.0) { EmptyView() } currentValueLabel: { Text("0:00") }))
        let schedule = TimerIntervalSchedule(
            start: done.lowerBound.timeIntervalSinceReferenceDate, end: done.upperBound.timeIntervalSinceReferenceDate)
        let entries = Array(schedule.entries(from: now, mode: .normal))
        #expect(entries == [done.upperBound], "only the end, which is past")
    }

    @Test("Inside the interval the schedule steps a whole second at a time, then lands on the end")
    func schedule() {
        let schedule = TimerIntervalSchedule(start: 100, end: 102.5)
        let entries = Array(schedule.entries(from: Date(timeIntervalSinceReferenceDate: 100.7), mode: .normal))
            .map(\.timeIntervalSinceReferenceDate)
        #expect(entries == [100, 101, 102, 102.5])
    }

    @Test("The label reads minutes and seconds, and hours from an hour")
    func labelFormat() {
        #expect(DefaultDateProgressLabel.timerText(seconds: 5) == "0:05")
        #expect(DefaultDateProgressLabel.timerText(seconds: 725) == "12:05")
        #expect(DefaultDateProgressLabel.timerText(seconds: 3723) == "1:02:03")
    }
}
