//  🖥️ TUI — A Terminal UI framework for Swift
//  PrintChangesTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

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

    /// Draws `view` as a frame of its own, and returns the lines it reported.
    private func frame(_ view: some View) -> [String] {
        context.stateStorage!.beginRenderPass()
        context.renderCache!.beginRenderPass()
        probe.lines = []
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

    @Test("A view that doesn't call it reports nothing")
    func silentWithoutTheCall() {
        #expect(frame(VStack { Quiet() }).isEmpty)
    }
}
