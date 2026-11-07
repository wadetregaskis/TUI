//  🖥️ TUI — A Terminal UI framework for Swift
//  DeferredClosureObservationTests.swift
//
//  A closure a view keeps and calls later, in its core — what a toggle
//  governs, a `Group(subviews:)` transform, a preference layer, an
//  environmental modifier's `resolve(in:)`, a toolbar content type's body,
//  a window's content — is the body of what it builds, deferred. Each was
//  called outside any observation scope: a write to an `@Observable` it read,
//  made outside an event, asked for no frame and the screen kept the old
//  value until something else drew. `FrameObservationTests` covers the
//  first such closures (a `GeometryReader`'s, a `TimelineView`'s, …).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

@Observable
private final class ClosureReadModel {
    var label = "one"
}

/// A preference nothing sets: the layer is built from its default.
private struct UnsetPreference: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value = nextValue() }
}

/// Resolves to a modifier showing the model's label beside the content.
private struct LabelResolvingModifier: EnvironmentalModifier {
    let model: ClosureReadModel
    func resolve(in environment: EnvironmentValues) -> LabelBesideModifier {
        LabelBesideModifier(label: model.label)
    }
}

private struct LabelBesideModifier: ViewModifier {
    let label: String
    func body(content: Content) -> some View {
        HStack {
            content
            Text(verbatim: "EM:" + label)
        }
    }
}

/// Toolbar content of the app's own, whose body reads the model.
private struct ReadingToolbarContent: ToolbarContent {
    let model: ClosureReadModel
    var body: some ToolbarContent {
        let label = model.label
        ToolbarItem(placement: .primaryAction) { Text(verbatim: "TB:" + label) }
    }
}

/// The models the apps read: an `App` is made by its type's `init()`.
private enum ClosureReadModels {
    nonisolated(unsafe) static var presented = ClosureReadModel()
    nonisolated(unsafe) static var opened = ClosureReadModel()
}

/// A window group presenting data, whose content closure reads the model.
private struct PresentedReadingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup(for: Int.self) { _ in Text(verbatim: "PW:" + ClosureReadModels.presented.label) }
    }
}

/// A second window group, whose window is opened after launch and built by
/// its content closure then.
private struct OpenedReadingApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("main window") }
        WindowGroup(id: "second") { Text(verbatim: "OW:" + ClosureReadModels.opened.label) }
    }
}

@MainActor
@Suite("Deferred closures are observed", .serialized)
struct DeferredClosureObservationTests {
    private var now: Int64 = 0

    private mutating func draw(_ app: TestApp) -> String {
        now += 20_000_000
        app.frame(atNanos: now)
        return app.screen.lines.joined(separator: "\n")
    }

    /// Draws `app` until `before` shows, writes `"two"` to `model`, and
    /// expects the write to ask for a frame that shows `after`.
    private mutating func expectRedraw(
        _ app: TestApp, model: ClosureReadModel, from before: String, to after: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        _ = draw(app)
        let first = draw(app)
        #expect(first.contains(before), "\(first)", sourceLocation: sourceLocation)
        _ = app.takeFrameRequest()
        model.label = "two"
        #expect(app.takeFrameRequest(), "the write asked for no frame", sourceLocation: sourceLocation)
        let second = draw(app)
        #expect(second.contains(after), "\(second)", sourceLocation: sourceLocation)
    }

    @Test("What a toggle governs, reading an @Observable, asks for a frame")
    mutating func toggleContent() {
        let model = ClosureReadModel()
        let app = TestApp(width: 30, height: 6) {
            Toggle("lamp", isOn: .constant(true)).toggleContent { Text(verbatim: "TC:" + model.label) }
        }
        expectRedraw(app, model: model, from: "TC:one", to: "TC:two")
    }

    @Test("A Group(subviews:) transform reading an @Observable asks for a frame")
    mutating func groupSubviews() {
        let model = ClosureReadModel()
        let app = TestApp(width: 30, height: 6) {
            VStack {
                Group(subviews: Text("a")) { _ in Text(verbatim: "GS:" + model.label) }
            }
        }
        expectRedraw(app, model: model, from: "GS:one", to: "GS:two")
    }

    @Test("A Group(sections:) transform reading an @Observable asks for a frame")
    mutating func groupSections() {
        let model = ClosureReadModel()
        let app = TestApp(width: 30, height: 6) {
            VStack {
                Group(sections: Text("a")) { _ in Text(verbatim: "GX:" + model.label) }
            }
        }
        expectRedraw(app, model: model, from: "GX:one", to: "GX:two")
    }

    @Test("An overlayPreferenceValue transform reading an @Observable asks for a frame")
    mutating func preferenceLayer() {
        let model = ClosureReadModel()
        let app = TestApp(width: 30, height: 6) {
            Text("..........").overlayPreferenceValue(UnsetPreference.self) { _ in
                Text(verbatim: "PL:" + model.label)
            }
        }
        expectRedraw(app, model: model, from: "PL:one", to: "PL:two")
    }

    @Test("An EnvironmentalModifier's resolve(in:) reading an @Observable asks for a frame")
    mutating func environmentalModifier() {
        let model = ClosureReadModel()
        let app = TestApp(width: 30, height: 6) {
            Text("base").modifier(LabelResolvingModifier(model: model))
        }
        expectRedraw(app, model: model, from: "EM:one", to: "EM:two")
    }

    @Test("A ToolbarContent type's body reading an @Observable asks for a frame")
    mutating func toolbarContentBody() {
        let model = ClosureReadModel()
        let app = TestApp(width: 40, height: 8) {
            Text("page").toolbar { ReadingToolbarContent(model: model) }
        }
        expectRedraw(app, model: model, from: "TB:one", to: "TB:two")
    }

    @Test("A WindowGroup(for:) content closure reading an @Observable asks for a frame")
    mutating func presentedWindowContent() {
        ClosureReadModels.presented = ClosureReadModel()
        let app = TestApp(PresentedReadingApp(), width: 30, height: 6)
        expectRedraw(app, model: ClosureReadModels.presented, from: "PW:one", to: "PW:two")
    }

    @Test("A window opened after launch, its content reading an @Observable, asks for a frame")
    mutating func windowOpenedAfterLaunch() {
        ClosureReadModels.opened = ClosureReadModel()
        let app = TestApp(OpenedReadingApp(), width: 30, height: 6)
        _ = draw(app)
        OpenWindowAction(handler: app.scenes.actions)(id: "second")
        expectRedraw(app, model: ClosureReadModels.opened, from: "OW:one", to: "OW:two")
    }
}
