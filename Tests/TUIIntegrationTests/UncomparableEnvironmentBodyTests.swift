//  🖥️ TUI — A Terminal UI framework for Swift
//  UncomparableEnvironmentBodyTests.swift
//
//  A value handed down with `.environment(\.key, value)` that is not
//  `Equatable`, beside a running timeline: tuiarcade's TUI-FEEDBACK.md,
//  Milestone 3 item 3, where every body below a model object ran twice a frame.
//
//  Counted, not compared: a buffer served and one drawn again look the same.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUI
import TUITesting

@MainActor private var countedBodies = 0
@MainActor private var timelineEntries = 0
@MainActor private var canvasDraws = 0

@MainActor
private final class Service {}

/// Not `Equatable`, and nothing in it can be compared: a closure.
private struct Callback: Sendable {
    let run: @Sendable () -> Void
}

private struct ServiceKey: EnvironmentKey {
    static let defaultValue: Service? = nil
}

private struct CallbackKey: EnvironmentKey {
    static let defaultValue = Callback(run: {})
}

extension EnvironmentValues {
    fileprivate var service: Service? {
        get { self[ServiceKey.self] }
        set { self[ServiceKey.self] = newValue }
    }

    fileprivate var callback: Callback {
        get { self[CallbackKey.self] }
        set { self[CallbackKey.self] = newValue }
    }
}

private struct Counted: View {
    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = MainActor.assumeIsolated { countedBodies += 1 }
        Text("counted")
    }
}

/// The feedback's repro: a body that counts itself beside a 60 Hz timeline.
private struct Ticking: View {
    var body: some View {
        VStack {
            Counted()
            TimelineView(.animation) { timeline in
                Color.clear.frame(width: 0, height: 0)
                    .onChange(of: timeline.date) { _, _ in timelineEntries += 1 }
            }
        }
    }
}

/// A picture that is drawn only when something it shows changes: an
/// `.equatable()` canvas, as tuiarcade's launcher previews are.
private struct Picture: View, Equatable {
    var body: some View {
        Canvas { _, _ in
            MainActor.assumeIsolated { canvasDraws += 1 }
        }
        .frame(width: 4, height: 2)
    }
}

/// What a second of the timeline costs `Counted`: its bodies, and the frames.
@MainActor
private func countOverASecond(_ app: TestApp) -> (bodies: Int, frames: Int) {
    _ = app.screen
    app.advance(by: .milliseconds(100))
    countedBodies = 0
    timelineEntries = 0
    app.advance(by: .seconds(1))
    return (countedBodies, timelineEntries)
}

@MainActor
@Suite(.serialized) struct UncomparableEnvironmentBodyTests {
    @Test func `with nothing above, the timeline's frames run no body beside it`() {
        let counts = countOverASecond(TestApp(width: 20, height: 4) { Ticking() })
        #expect(counts.frames > 30)
        #expect(counts.bodies <= 2)
    }

    @Test func `an object handed down compares by identity, so nothing below runs again`() {
        let service = Service()
        let counts = countOverASecond(TestApp(width: 20, height: 4) { Ticking().environment(\.service, service) })
        #expect(counts.frames > 30)
        #expect(counts.bodies <= 2)
    }

    @Test func `an optional object set to nil compares, so nothing below runs again`() {
        let counts = countOverASecond(TestApp(width: 20, height: 4) { Ticking().environment(\.service, nil) })
        #expect(counts.frames > 30)
        #expect(counts.bodies <= 2)
    }

    /// tuiarcade's launcher test failed four runs in five: a frame that changed
    /// nothing drew its previews again under the model object, and a preview
    /// that fills its colours in a dictionary's order came out different.
    @Test func `a frame that changes nothing draws nothing again below an object handed down`() {
        let service = Service()
        let app = TestApp(width: 20, height: 4) { Picture().equatable().environment(\.service, service) }
        _ = app.screen
        app.advance(by: .milliseconds(100))
        canvasDraws = 0
        app.advance(by: .seconds(3))
        #expect(canvasDraws == 0)
    }

    @Test func `a value nothing can compare runs each body below it once a frame, not twice`() {
        let counts = countOverASecond(
            TestApp(width: 20, height: 4) { Ticking().environment(\.callback, Callback(run: {})) })
        #expect(counts.frames > 30)
        #expect(counts.bodies <= counts.frames + 2)
    }
}
