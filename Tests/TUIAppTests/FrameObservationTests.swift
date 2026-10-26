//  🖥️ TUI — A Terminal UI framework for Swift
//  FrameObservationTests.swift
//
//  A read no body makes and no kept result is beneath — a control's
//  `Binding`, a custom style's `makeBody`, the app's body — asks for a frame
//  when it changes. Each was unobserved: written outside an event, it asked
//  for nothing, and the screen kept the old value until something else drew.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@Observable
private final class FrameReadModel: @unchecked Sendable {
    var isOn = false
    var label = "one"
    var title = "first"
}

/// The models the apps read: an `App` is made by its type's `init()`.
private enum FrameReadModels {
    nonisolated(unsafe) static var toggle = FrameReadModel()
    nonisolated(unsafe) static var style = FrameReadModel()
    nonisolated(unsafe) static var app = FrameReadModel()
}

private struct ReadingButtonStyle: ButtonStyle, Equatable {
    let model: FrameReadModel
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.model === rhs.model }
    func makeBody(configuration: Configuration) -> some View {
        Text(verbatim: "[\(model.label)]")
    }
}

private struct ToggleApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Toggle("lamp", isOn: Bindable(FrameReadModels.toggle).isOn) }
    }
}

private struct StyledButtonApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Button("b") {}.buttonStyle(ReadingButtonStyle(model: FrameReadModels.style)) }
    }
}

/// Reads the model in the app's body, which is evaluated under no body scope.
private struct AppBodyReadingApp: App {
    init() {}
    var body: some Scene {
        let title = FrameReadModels.app.title
        WindowGroup { Text(verbatim: "T:" + title) }
    }
}

@MainActor
@Suite("Frame observation")
struct FrameObservationTests {

    private func draw<A: App>(_ app: HeadlessApp<A>, at now: inout Int64) -> [String] {
        now += 20_000_000
        app.frame(atNanos: now)
        return app.screen.map(\.stripped)
    }

    @Test("A top-level Toggle bound to an @Observable asks for a frame when the property is written")
    func toggleBinding() {
        FrameReadModels.toggle = FrameReadModel()
        let app = HeadlessApp(ToggleApp(), width: 30, height: 6)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        let before = draw(app, at: &now)
        _ = app.takeFrameRequest()
        FrameReadModels.toggle.isOn = true
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(draw(app, at: &now) != before, "the toggle drew as it was")
    }

    @Test("A custom ButtonStyle's makeBody reading an @Observable asks for a frame")
    func styleBody() {
        FrameReadModels.style = FrameReadModel()
        let app = HeadlessApp(StyledButtonApp(), width: 30, height: 6)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        #expect(draw(app, at: &now).contains { $0.contains("[one]") })
        _ = app.takeFrameRequest()
        FrameReadModels.style.label = "two"
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(draw(app, at: &now).contains { $0.contains("[two]") })
    }

    @Test("The app's body reading an @Observable asks for a frame")
    func appBody() {
        FrameReadModels.app = FrameReadModel()
        let app = HeadlessApp(AppBodyReadingApp(), width: 30, height: 6)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        _ = draw(app, at: &now)
        _ = app.takeFrameRequest()
        FrameReadModels.app.title = "second"
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(draw(app, at: &now).contains { $0.contains("T:second") })
    }

    @Test("A property read every frame and never written leaves the frames' scopes behind it retired")
    func framesAreLeased() {
        FrameReadModels.app = FrameReadModel()
        let app = HeadlessApp(AppBodyReadingApp(), width: 30, height: 6)
        let census = ObservationCensus()
        app.observationCensus = census
        var now: Int64 = 0
        for _ in 0..<40 { _ = draw(app, at: &now) }
        // Forty frames armed a scope each on `title`; the leases retired all
        // but those of the frame on screen and the frame being drawn, and the
        // first, which taught the cache that frames read.
        let counts = census.snapshot
        #expect(counts.armed(.frame) >= 40)
        #expect(counts.live(.frame) <= 3, "frame scopes alive after 40 frames: \(counts.live(.frame))")
    }
}
