//  🖥️ TUI — A Terminal UI framework for Swift
//  SensoryFeedbackTests.swift
//
//  SwiftUI's `sensoryFeedback`: `.error` and `.warning` ring the terminal's
//  bell when the trigger changes — once per change, never for an unchanged
//  trigger or the first value — in all four forms, the `condition:` form
//  and the closure forms that may answer `nil`.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting

// MARK: - Fixtures

/// The trigger the view watches, written by a test between frames.
@Observable
private final class TriggerModel {
    var value = 0
}

/// Which `sensoryFeedback` form the view uses.
private enum Form {
    case plain
    case condition
    case closure
    case closureWithoutValues
}

private struct FeedbackApp: App {
    let model: TriggerModel
    let form: Form
    init() { (model, form) = (TriggerModel(), .plain) }
    init(_ model: TriggerModel, _ form: Form) { (self.model, self.form) = (model, form) }

    var body: some Scene {
        WindowGroup { FeedbackView(model: model, form: form) }
    }
}

private struct FeedbackView: View {
    let model: TriggerModel
    let form: Form

    var body: some View {
        let label = Text(verbatim: "value \(model.value)")
        switch form {
        case .plain:
            label.sensoryFeedback(.error, trigger: model.value)
        case .condition:
            // Only a rise plays.
            label.sensoryFeedback(.warning, trigger: model.value) { oldValue, newValue in newValue > oldValue }
        case .closure:
            // Only an even value plays.
            label.sensoryFeedback(trigger: model.value) { _, newValue in newValue.isMultiple(of: 2) ? .error : nil }
        case .closureWithoutValues:
            label.sensoryFeedback(trigger: model.value) { model.value > 10 ? .warning : nil }
        }
    }
}

// MARK: - Tests

@MainActor
@Suite("sensoryFeedback rings the bell", .serialized)
struct SensoryFeedbackTests {
    private var now: Int64 = 0

    private mutating func launched(_ form: Form) -> (TestApp, TriggerModel) {
        let model = TriggerModel()
        let app = TestApp(FeedbackApp(model, form), width: 30, height: 6)
        frame(app)
        return (app, model)
    }

    private mutating func frame(_ app: TestApp) {
        now += 20_000_000
        app.frame(atNanos: now)
    }

    @Test("A change of trigger rings the bell once; an unchanged trigger, and the first value, ring nothing")
    mutating func ringsOncePerChange() {
        let (app, model) = launched(.plain)
        #expect(app.bellsWritten == 0, "the first value is no change")
        model.value = 1
        frame(app)
        #expect(app.bellsWritten == 1)
        frame(app)
        #expect(app.bellsWritten == 1, "nothing changed")
        model.value = 1
        frame(app)
        #expect(app.bellsWritten == 1, "written, but the same value")
        model.value = 2
        frame(app)
        #expect(app.bellsWritten == 2)
    }

    @Test("Changes between two frames ring once, as the frame sees one change")
    mutating func changesBetweenFramesRingOnce() {
        let (app, model) = launched(.plain)
        model.value = 1
        model.value = 2
        model.value = 3
        frame(app)
        #expect(app.bellsWritten == 1)
    }

    @Test("The condition: form rings only for a change it accepts")
    mutating func conditionForm() {
        let (app, model) = launched(.condition)
        model.value = 3
        frame(app)
        #expect(app.bellsWritten == 1, "a rise")
        model.value = 1
        frame(app)
        #expect(app.bellsWritten == 1, "a fall plays nothing")
        model.value = 2
        frame(app)
        #expect(app.bellsWritten == 2)
    }

    @Test("The closure form rings for a kind and not for nil")
    mutating func closureForm() {
        let (app, model) = launched(.closure)
        model.value = 1
        frame(app)
        #expect(app.bellsWritten == 0, "nil")
        model.value = 2
        frame(app)
        #expect(app.bellsWritten == 1)
        model.value = 3
        frame(app)
        #expect(app.bellsWritten == 1, "nil")
    }

    @Test("The closure form that takes no values rings for a kind and not for nil")
    mutating func closureWithoutValuesForm() {
        let (app, model) = launched(.closureWithoutValues)
        model.value = 5
        frame(app)
        #expect(app.bellsWritten == 0, "nil")
        model.value = 11
        frame(app)
        #expect(app.bellsWritten == 1)
    }

    @Test("The two kinds a terminal plays are told apart, as SwiftUI's are")
    func kinds() {
        #expect(SensoryFeedback.error == .error)
        #expect(SensoryFeedback.error != .warning)
    }
}
