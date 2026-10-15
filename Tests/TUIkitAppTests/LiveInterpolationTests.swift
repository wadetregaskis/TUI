//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LiveInterpolationTests.swift
//
//  The `LocalizedStringKey` interpolations that read the clock: a `Text` made
//  from such a key is live — read at each frame, woken at each change, looked
//  up as any key is — and anything else that takes the key reads it once.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("Live LocalizedStringKey interpolations")
struct LiveInterpolationTests {
    /// 2026-05-09 06:13:20 UTC.
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// The text's one line at a frame dated `base`, in en_US and UTC.
    private func drawn(_ text: Text) -> String {
        let context = makeRenderContext(width: 60, height: 1) { environment, _ in
            environment.locale = Locale(identifier: "en_US")
            environment.calendar = Calendar(identifier: .gregorian)
            environment.timeZone = TimeZone(identifier: "UTC")!
        }
        context.renderCache?.frameDate = base
        return renderToBuffer(text, context: context).lines.first?.stripped ?? ""
    }

    @Test("A date style interpolated into a key draws at the frame's date, as SwiftUI drew it")
    func dateStyle() {
        #expect(drawn(Text("Ends \(base.addingTimeInterval(-125.5), style: .relative) ago")) == "Ends 2 min, 5 sec ago")
        #expect(drawn(Text("At \(base, style: .time)")) == "At 6:13\u{202F}AM" || drawn(Text("At \(base, style: .time)")) == "At 6:13 AM")
    }

    @Test("A timer interpolated into a key counts at the frame's date")
    func timer() {
        let interval = base.addingTimeInterval(-0.5)...base.addingTimeInterval(90)
        #expect(drawn(Text("Left: \(timerInterval: interval)")) == "Left: 1:30")
        #expect(drawn(Text("Gone: \(timerInterval: interval, countsDown: false)")) == "Gone: 0:00")
    }

    @Test("The key is the literal with a placeholder, and a translation reorders around the live value")
    func lookedUp() {
        LocalizationService.shared.register(translations: [
            "en": ["test.w11a.live %@": "%@ is how long ago it was"]
        ])
        let key: LocalizedStringKey = "test.w11a.live \(base.addingTimeInterval(-61.5), style: .relative)"
        #expect(key.key == "test.w11a.live %@")
        #expect(drawn(Text(key)) == "1 min, 1 sec is how long ago it was")
    }

    @Test("An interpolated live Text stays live")
    func interpolatedLiveText() {
        let text = Text("Updated \(Text(base.addingTimeInterval(-9.5), style: .relative)) ago")
        #expect(text.isLive)
        #expect(drawn(text) == "Updated 9 sec ago")
    }

    @Test("A key with no live value makes a plain text")
    func plainKeyStaysPlain() {
        let count = 3
        #expect(Text("Rows: \(count)").runs == nil)
        #expect(Text("plain").runs == nil)
    }

    @Test("Anything else that takes the key reads it once, when it is built")
    func otherConsumersReadOnce() {
        // Read in the process's own locale, whatever this machine's is (an
        // en_AU one writes "2 min."), and a minute from its next change.
        let started = Date().addingTimeInterval(-3_725.5)
        let key: LocalizedStringKey = "Started \(started, style: .relative) ago"
        let reading = DateStyleSource(date: started, style: .relative).text(at: Date(), in: .current)
        #expect(key.localized == "Started \(reading) ago")
        #expect(reading.hasPrefix("1 hr, 2 min"))
    }

    @Test("A text from a live key asks for a frame at the next change")
    func wakes() throws {
        let tui = TUIContext()
        let scheduler = AnimationScheduler()
        var environment = EnvironmentValues()
        environment.applyRuntimeServices(from: tui)
        environment.animationScheduler = scheduler
        environment.frameNowNanos = 0
        let context = RenderContext(availableWidth: 40, availableHeight: 1, environment: environment, tuiContext: tui)
        tui.renderCache.beginRenderPass()
        tui.renderCache.frameDate = base
        scheduler.beginFrame()
        _ = renderToBuffer(Text("Ends \(base.addingTimeInterval(-125.5), style: .relative) ago"), context: context)
        scheduler.endFrame()
        // Half a second to 2 min, 6 sec, and the millisecond of slack.
        #expect(try #require(scheduler.nextFiring(after: 0)) == 501_000_000)
    }
}
