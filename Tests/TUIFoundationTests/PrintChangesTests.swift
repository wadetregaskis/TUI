//  🖥️ TUI — A Terminal UI framework for Swift
//  PrintChangesTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIFoundation
@testable import TUIView

/// What a test's views hand out: the lines reported, and a way to write a
/// view's state from outside its body.
@MainActor
private final class Probe {
    var lines: [String] = []
    var count: Binding<Int>?
    var on: Binding<Bool>?
}

private struct Counter: View {
    let probe: Probe
    var label = "n"
    @State private var count = 0

    init(probe: Probe, label: String = "n") {
        self.probe = probe
        self.label = label
    }

    // An explicit `return`, so the body is not a view builder and can hold
    // the statements before it.
    var body: some View {
        Self._printChanges()
        probe.count = $count
        return Text("\(label) \(count)")
    }
}

private struct Quiet: View {
    var body: some View { Text("quiet") }
}

private struct Highlight: ViewModifier {
    let probe: Probe
    var tint = 1
    @State private var isOn = false

    init(probe: Probe, tint: Int = 1) {
        self.probe = probe
        self.tint = tint
    }

    func body(content: Content) -> some View {
        Self._printChanges()
        probe.on = $isOn
        return content
    }
}

private struct ReportTintKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct ReportActionKey: EnvironmentKey {
    static let defaultValue: @Sendable () -> Void = {}
}

extension EnvironmentValues {
    fileprivate var reportTint: Int {
        get { self[ReportTintKey.self] }
        set { self[ReportTintKey.self] = newValue }
    }

    fileprivate var reportAction: @Sendable () -> Void {
        get { self[ReportActionKey.self] }
        set { self[ReportActionKey.self] = newValue }
    }
}

/// Reads one environment value, which it shows.
private struct TintReader: View {
    @Environment(\.reportTint) private var tint

    var body: some View {
        Self._printChanges()
        return Text("tint \(tint)")
    }
}

/// Reads an environment value that can't be compared, a closure.
private struct ActionReader: View {
    @Environment(\.reportAction) private var action

    var body: some View {
        Self._printChanges()
        return Text("action")
    }
}

@Observable
@MainActor
private final class Model {
    var value = 0
}

/// Reads an `@Observable` property in its body.
private struct Watcher: View {
    let model: Model

    var body: some View {
        Self._printChanges()
        return Text("value \(model.value)")
    }
}

/// Holds a closure, which can't be compared.
private struct Holder: View {
    let action: () -> Void

    var body: some View {
        Self._printChanges()
        return Text("holder")
    }
}

/// `_printChanges()`: in a body, a line saying what changed since that body's
/// last evaluation, in SwiftUI's words.
@MainActor
@Suite("_printChanges")
struct PrintChangesTests {
    private let probe = Probe()
    private let context: RenderContext

    init() {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        context = RenderContext(availableWidth: 30, availableHeight: 5, environment: environment, tuiContext: TUIContext())
        let probe = probe
        context.stateStorage!.bodyChangeSink = { probe.lines.append($0) }
    }

    /// Draws `view` as a frame of its own, in the test's environment changed
    /// by `change`, and returns the lines it reported.
    private func frame(_ view: some View, change: (inout EnvironmentValues) -> Void = { _ in }) -> [String] {
        context.stateStorage!.beginRenderPass()
        context.renderCache!.beginRenderPass()
        probe.lines = []
        var context = context
        change(&context.environment)
        _ = renderToBuffer(view, context: context)
        return probe.lines
    }

    @Test("The first evaluation names @self, @identity and each @State")
    func firstEvaluation() {
        #expect(frame(Counter(probe: probe)) == ["Counter: @self, @identity, _count changed."])
    }

    @Test("A write to a @State names that property alone")
    func stateWrite() {
        _ = frame(Counter(probe: probe))
        probe.count?.wrappedValue = 4
        #expect(frame(Counter(probe: probe)) == ["Counter: _count changed."])
    }

    @Test("A new value from the parent is @self")
    func newValue() {
        _ = frame(Counter(probe: probe))
        #expect(frame(Counter(probe: probe, label: "m")) == ["Counter: @self changed."])
    }

    @Test("A body evaluated again with nothing changed says unchanged, or is not evaluated at all")
    func nothingChanged() {
        _ = frame(Counter(probe: probe))
        let again = frame(Counter(probe: probe))
        #expect(again.isEmpty || again == ["Counter: unchanged."], "\(again)")
    }

    @Test("A body measured and then drawn in one frame reports once")
    func oncePerFrame() {
        let lines = frame(
            HStack {
                Counter(probe: probe)
                Text("beside")
            })
        #expect(lines == ["Counter: @self, @identity, _count changed."])
    }

    @Test("A modifier reports on its own value and its own @State")
    func modifier() {
        #expect(frame(Text("x").modifier(Highlight(probe: probe))) == ["Highlight: @self, @identity, _isOn changed."])
        probe.on?.wrappedValue = true
        #expect(frame(Text("x").modifier(Highlight(probe: probe))) == ["Highlight: _isOn changed."])
        #expect(frame(Text("x").modifier(Highlight(probe: probe, tint: 2))) == ["Highlight: @self changed."])
    }

    @Test("A call made outside a body is dropped, not pinned on the next body evaluated")
    func strayCallIsDropped() {
        Counter._printChanges()
        #expect(frame(Quiet()).isEmpty)
        #expect(frame(Counter(probe: probe)) == ["Counter: @self, @identity, _count changed."])
    }

    @Test("An @Environment property whose value moved is named, as a @State is")
    func environmentChange() {
        _ = frame(TintReader()) { $0.reportTint = 1 }
        #expect(frame(TintReader()) { $0.reportTint = 2 } == ["TintReader: _tint changed."])
        let again = frame(TintReader()) { $0.reportTint = 2 }
        #expect(again.isEmpty || again == ["TintReader: unchanged."], "\(again)")
    }

    @Test("An environment value that can't be compared may have changed, never unchanged")
    func uncomparableEnvironment() {
        _ = frame(ActionReader()) { $0.reportAction = {} }
        #expect(frame(ActionReader()) { $0.reportAction = {} } == ["ActionReader: _action may have changed."])
    }

    @Test("A write to an @Observable property the body read is @dependencies")
    func observedChange() {
        let model = Model()
        _ = frame(Watcher(model: model))
        model.value = 3
        #expect(frame(Watcher(model: model)) == ["Watcher: @dependencies changed."])
    }

    @Test("A view holding a closure may have changed, never unchanged")
    func closureInTheValue() {
        _ = frame(Holder {})
        #expect(frame(Holder {}) == ["Holder: @self may have changed."])
    }

    @Test("The line names what certainly changed first, then what may have, then nothing")
    func lineWording() {
        #expect(BodyChangeReport.line(for: Holder.self, causes: ["_a"], unknown: ["@self"]) == "Holder: _a changed.")
        #expect(BodyChangeReport.line(for: Holder.self, causes: [], unknown: ["@self"]) == "Holder: @self may have changed.")
        #expect(BodyChangeReport.line(for: Holder.self, causes: [], unknown: []) == "Holder: unchanged.")
    }

    @Test("A view that doesn't call it reports nothing")
    func silentWithoutTheCall() {
        #expect(frame(VStack { Quiet() }).isEmpty)
    }
}
