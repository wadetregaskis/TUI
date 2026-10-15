//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextTimerIntervalTests.swift
//
//  `Text(timerInterval:pauseTime:countsDown:showsHours:)`: the readings SwiftUI
//  draws (measured on macOS 15), its pause — which counting down holds the
//  timer at what it SHOWS — and the seconds it asks to be woken at.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Text(timerInterval:)")
struct TextTimerIntervalTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let environment = LiveTextEnvironment.current

    private func source(
        length: Double, pause: Double? = nil, countsDown: Bool = true, showsHours: Bool = true
    ) -> TimerIntervalSource {
        TimerIntervalSource(
            start: start, end: start.addingTimeInterval(length),
            pauseTime: pause.map { start.addingTimeInterval($0) }, countsDown: countsDown,
            showsHours: showsHours)
    }

    /// The reading `elapsed` seconds after the start.
    private func reading(_ source: TimerIntervalSource, at elapsed: Double) -> String {
        source.text(at: start.addingTimeInterval(elapsed), in: environment)
    }

    /// When the reading next changes, in seconds after the start.
    private func change(_ source: TimerIntervalSource, at elapsed: Double) -> Double? {
        source.nextChange(after: start.addingTimeInterval(elapsed), in: environment)
            .map { $0.timeIntervalSince(start) }
    }

    @Test("Counting down shows the time left rounded up; counting up, the time gone rounded down")
    func readings() {
        // SwiftUI, 30.5 s into a 3,725 s interval.
        #expect(reading(source(length: 3_725), at: 30.5) == "1:01:35")
        #expect(reading(source(length: 3_725, countsDown: false), at: 30.5) == "0:30")
        // 30.5 s into two hours, without hours: the minutes run on.
        #expect(reading(source(length: 7_200, showsHours: false), at: 30.5) == "119:30")
        // Hours as many as it takes.
        #expect(reading(source(length: 400_000.5), at: 0.5) == "111:06:40")
    }

    @Test("Before the interval it holds its start, and after it its end")
    func outsideTheInterval() {
        #expect(reading(source(length: 100), at: -100.5) == "1:40")
        #expect(reading(source(length: 100, countsDown: false), at: -100.5) == "0:00")
        #expect(reading(source(length: 100), at: 200.5) == "0:00")
        #expect(reading(source(length: 100, countsDown: false), at: 200.5) == "1:40")
    }

    /// SwiftUI, 60.5 s into a 600 s interval, with the pause at each offset.
    @Test(
        "Counting down, a pause holds the timer at what it shows; counting up, at the time gone",
        arguments: [
            (-100.0, "9:00", "0:00"), (20, "9:00", "0:20"), (59, "9:00", "0:59"), (61, "9:00", "1:00"),
            (599, "9:59", "1:00"), (700, "10:00", "1:00"),
        ] as [(Double, String, String)])
    func pause(_ pause: Double, _ down: String, _ up: String) {
        #expect(reading(source(length: 600, pause: pause), at: 60.5) == down)
        #expect(reading(source(length: 600, pause: pause, countsDown: false), at: 60.5) == up)
    }

    @Test("A pause holds an unstarted countdown at its length, and a finished one at the pause's offset")
    func pauseOutsideTheInterval() {
        #expect(reading(source(length: 600, pause: 20), at: -100.5) == "10:00")
        #expect(reading(source(length: 600, pause: 20), at: 700.5) == "0:20")
        #expect(reading(source(length: 600, pause: 20, countsDown: false), at: 700.5) == "0:20")
        // SwiftUI's own example: twelve minutes, paused at ten minutes in,
        // "will pause when reaching 10:00".
        let example = source(length: 720, pause: 600)
        #expect(reading(example, at: 0) == "12:00")
        #expect(reading(example, at: 119.5) == "10:01")
        #expect(reading(example, at: 300) == "10:00")
    }

    @Test("It changes a second at a time, and asks for nothing once it cannot change")
    func changes() {
        // Counting down: the seconds left fall at whole seconds before the end.
        #expect(change(source(length: 100), at: 10.3) == 11)
        #expect(change(source(length: 100), at: -50) == 1)
        #expect(change(source(length: 100.5), at: -50) == 0.5)
        #expect(change(source(length: 100), at: 100) == nil)
        // Counting up: at whole seconds after the start.
        #expect(change(source(length: 100, countsDown: false), at: 10.3) == 11)
        #expect(change(source(length: 100, countsDown: false), at: -50) == 1)
        #expect(change(source(length: 100, countsDown: false), at: 99.5) == 100)
        #expect(change(source(length: 100.5, countsDown: false), at: 100.2) == nil)
        // Paused: the countdown stops at the pause's reading.
        #expect(change(source(length: 720, pause: 600), at: 119.5) == 120)
        #expect(change(source(length: 720, pause: 600), at: 120) == nil)
        #expect(change(source(length: 600, pause: 20, countsDown: false), at: 19.5) == 20)
        #expect(change(source(length: 600, pause: 20, countsDown: false), at: 20) == nil)
    }

    @Test("The text draws the reading at the frame's date")
    func drawn() {
        let context = makeRenderContext(width: 20, height: 1)
        context.renderCache?.frameDate = start.addingTimeInterval(30.5)
        let interval = start...start.addingTimeInterval(90)
        let lines = renderToBuffer(Text(timerInterval: interval), context: context).lines.map(\.stripped)
        #expect(lines == ["1:00"])
    }
}
