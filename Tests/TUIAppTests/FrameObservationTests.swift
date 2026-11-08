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
import TUITesting
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
    nonisolated(unsafe) static var geometry = FrameReadModel()
    nonisolated(unsafe) static var timeline = FrameReadModel()
    nonisolated(unsafe) static var forEach = FrameReadModel()
    nonisolated(unsafe) static var canvas = FrameReadModel()
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
        WindowGroup { unsafe Toggle("lamp", isOn: Bindable(FrameReadModels.toggle).isOn) }
    }
}

private struct StyledButtonApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { unsafe Button("b") {}.buttonStyle(ReadingButtonStyle(model: FrameReadModels.style)) }
    }
}

/// Reads the model in the app's body, which is evaluated under no body scope.
private struct AppBodyReadingApp: App {
    init() {}
    var body: some Scene {
        let title = unsafe FrameReadModels.app.title
        WindowGroup { Text(verbatim: "T:" + title) }
    }
}

/// Reads the model inside a `GeometryReader`'s closure, which runs when the
/// core draws rather than when the enclosing `body` is evaluated.
private struct GeometryReadingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            GeometryReader { _ in
                unsafe Text(verbatim: "G:" + FrameReadModels.geometry.label)
            }
        }
    }
}

/// Reads the model inside a `TimelineView`'s closure, which runs when the
/// core measures or draws rather than when the enclosing `body` is evaluated.
private struct TimelineReadingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            TimelineView(.periodic(from: .distantPast, by: 60)) { _ in
                unsafe Text(verbatim: "TL:" + FrameReadModels.timeline.label)
            }
        }
    }
}

private struct NonEquatableModel {
    let id: Int
}

private enum ForEachTestConfig {
    nonisolated(unsafe) static var count = 1
    nonisolated(unsafe) static var multiMember = false
}

private struct ForEachNestedVStackApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                VStack {
                    unsafe ForEach(Array((0..<ForEachTestConfig.count).map { NonEquatableModel(id: $0) }), id: \.id) { item in
                        if unsafe ForEachTestConfig.multiMember {
                            Text(verbatim: unsafe "FE:\(item.id):" + FrameReadModels.forEach.label)
                            Divider()
                        } else {
                            Text(verbatim: unsafe "FE:\(item.id):" + FrameReadModels.forEach.label)
                        }
                    }
                }
            }
        }
    }
}

private struct CanvasReadingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            Canvas { _, _ in
                _ = unsafe FrameReadModels.canvas.label
            }
        }
    }
}

/// Reads the model inside a `ForEach` closure with a multi-member row over
/// non-`Equatable` elements (`enumerated()`), which runs outside `_MemoizedRow`.
private struct ForEachMultiMemberReadingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            HStack {
                ForEach(Array(["a"].enumerated()), id: \.element) { index, _ in
                    if index > 0 { Divider() }
                    unsafe Text(verbatim: "FE:" + FrameReadModels.forEach.label)
                }
            }
        }
    }
}

@MainActor
@Suite("Frame observation")
struct FrameObservationTests {

    private func draw(_ app: TestApp, at now: inout Int64) -> [String] {
        now += 20_000_000
        app.frame(atNanos: now)
        return app.screen.lines
    }

    @Test("A top-level Toggle bound to an @Observable asks for a frame when the property is written")
    func toggleBinding() {
        unsafe FrameReadModels.toggle = FrameReadModel()
        let app = TestApp(ToggleApp(), width: 30, height: 6)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        let before = draw(app, at: &now)
        _ = app.takeFrameRequest()
        unsafe FrameReadModels.toggle.isOn = true
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(draw(app, at: &now) != before, "the toggle drew as it was")
    }

    @Test("A custom ButtonStyle's makeBody reading an @Observable asks for a frame")
    func styleBody() {
        unsafe FrameReadModels.style = FrameReadModel()
        let app = TestApp(StyledButtonApp(), width: 30, height: 6)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        #expect(draw(app, at: &now).contains { $0.contains("[one]") })
        _ = app.takeFrameRequest()
        unsafe FrameReadModels.style.label = "two"
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(draw(app, at: &now).contains { $0.contains("[two]") })
    }

    @Test("The app's body reading an @Observable asks for a frame")
    func appBody() {
        unsafe FrameReadModels.app = FrameReadModel()
        let app = TestApp(AppBodyReadingApp(), width: 30, height: 6)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        _ = draw(app, at: &now)
        _ = app.takeFrameRequest()
        unsafe FrameReadModels.app.title = "second"
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(draw(app, at: &now).contains { $0.contains("T:second") })
    }

    @Test("A property read every frame and never written leaves the frames' scopes behind it retired")
    func framesAreLeased() {
        unsafe FrameReadModels.app = FrameReadModel()
        let app = TestApp(AppBodyReadingApp(), width: 30, height: 6)
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

    @Test("A GeometryReader's closure reading an @Observable asks for a frame")
    func geometryReaderClosure() {
        unsafe FrameReadModels.geometry = FrameReadModel()
        let app = TestApp(GeometryReadingApp(), width: 30, height: 6)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        #expect(draw(app, at: &now).contains { $0.contains("G:one") })
        _ = app.takeFrameRequest()
        unsafe FrameReadModels.geometry.label = "two"
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(draw(app, at: &now).contains { $0.contains("G:two") })
    }

    @Test("A TimelineView's closure reading an @Observable asks for a frame")
    func timelineViewClosure() {
        unsafe FrameReadModels.timeline = FrameReadModel()
        let app = TestApp(TimelineReadingApp(), width: 30, height: 6)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        #expect(draw(app, at: &now).contains { $0.contains("TL:one") })
        _ = app.takeFrameRequest()
        unsafe FrameReadModels.timeline.label = "two"
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(draw(app, at: &now).contains { $0.contains("TL:two") })
    }

    @Test("A ForEach multi-member closure reading an @Observable asks for a frame")
    func forEachMultiMemberClosure() {
        unsafe FrameReadModels.forEach = FrameReadModel()
        let app = TestApp(ForEachMultiMemberReadingApp(), width: 30, height: 6)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        #expect(draw(app, at: &now).contains { $0.contains("FE:one") })
        _ = app.takeFrameRequest()
        unsafe FrameReadModels.forEach.label = "two"
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(draw(app, at: &now).contains { $0.contains("FE:two") })
    }

    @Test(
        "A ForEach nested in a VStack reading an @Observable asks for a frame",
        arguments: [false, true], [1, 20]
    )
    func forEachNestedVStack(multiMember: Bool, count: Int) {
        unsafe ForEachTestConfig.count = count
        unsafe ForEachTestConfig.multiMember = multiMember
        unsafe FrameReadModels.forEach = FrameReadModel()
        let app = TestApp(ForEachNestedVStackApp(), width: 40, height: 45)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        #expect(draw(app, at: &now).contains { $0.contains("FE:0:one") })
        _ = app.takeFrameRequest()
        unsafe FrameReadModels.forEach.label = "two"
        #expect(app.takeFrameRequest(), "the write asked for no frame with count \(count) multiMember \(multiMember)")
        #expect(draw(app, at: &now).contains { $0.contains("FE:0:two") })
    }

    @Test("A Canvas closure reading an @Observable asks for a frame")
    func canvasClosure() {
        unsafe FrameReadModels.canvas = FrameReadModel()
        let app = TestApp(CanvasReadingApp(), width: 30, height: 6)
        var now: Int64 = 0
        _ = draw(app, at: &now)
        _ = app.takeFrameRequest()
        unsafe FrameReadModels.canvas.label = "two"
        #expect(app.takeFrameRequest(), "the write asked for no frame")
    }
}
