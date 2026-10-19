//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppIsolationTests.swift
//
//  Two apps in one process — two test cases running at once, say — keep what
//  is pending for each apart: a change one app makes under `withAnimation`
//  animates in that app, whichever app draws next.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// A mark that a key slides twenty cells right over one second.
private struct SlidePage: View {
    @State private var moved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("slide") {
                withAnimation(.linear(duration: 1)) { moved.toggle() }
            }
            Text("MARK").offset(x: moved ? 20 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SlideApp: App {
    init() {}

    var body: some Scene {
        WindowGroup { SlidePage() }
    }
}

@MainActor
@Suite("Two apps in one process keep what is pending for each apart")
struct AppIsolationTests {
    /// The column the mark is drawn at in `app`'s screen.
    private func markColumn(_ app: HeadlessApp<SlideApp>) -> Int? {
        for line in app.screen.map(\.stripped) {
            if let range = line.range(of: "MARK") {
                return line.distance(from: line.startIndex, to: range.lowerBound)
            }
        }
        return nil
    }

    /// One app presses, and the other draws a frame before the first does.
    /// The press's transaction is the first app's: the other's frame must not
    /// take it, or the first app's slide lands on its end in one frame — what
    /// the flaky `TransitionMemoTests` saw when another test's app drew between
    /// its press and its frame.
    @Test("A change made under withAnimation animates in its own app, whichever app draws first")
    func pressedAppAnimatesAfterAnotherDraws() {
        let pressed = HeadlessApp(SlideApp(), width: 40, height: 6)
        let other = HeadlessApp(SlideApp(), width: 40, height: 6)
        var tick: Int64 = 0
        func frame(_ apps: [HeadlessApp<SlideApp>]) {
            let now = AnimationClock.nanoseconds(atTick: tick)
            for app in apps { app.frame(atNanos: now) }
            tick += 1
        }
        frame([pressed, other])
        frame([pressed, other])
        let start = markColumn(pressed)
        #expect(start != nil && markColumn(other) == start, "precondition: both marks are drawn where they start")
        guard let start else { return }

        #expect(pressed.send(KeyEvent(key: .enter)), "precondition: the button took the key")
        // The other app draws first.
        frame([other, pressed])
        for _ in 0..<29 { frame([other, pressed]) }
        let halfWay = markColumn(pressed)
        #expect(
            halfWay.map { $0 > start && $0 < start + 20 } == true,
            "the slide is not under way half-way through: the mark is at \(halfWay.map(String.init) ?? "nowhere")")
        #expect(markColumn(other) == start, "the app that was not pressed moved")
        for _ in 0..<45 { frame([other, pressed]) }
        #expect(markColumn(pressed) == start + 20, "the slide did not end where it was going")
    }
}
