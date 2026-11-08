//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationScreenStateTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUINavigation
@testable import TUITestSupport

/// What a pushed screen keeps while another is pushed over it, and what the bar
/// remembers of it.
///
/// Every pushed screen used to render at one identity, whatever its depth, and a
/// buried one did not render at all. So the screen pushed over another took the
/// state the one below had, and the one below, popped back to, came back with the
/// state of the screen that had covered it, or with none. SwiftUI keeps each
/// screen's state for as long as it is on the path.
@MainActor
@Suite("NavigationStack: buried screens")
struct NavigationScreenStateTests {

    /// Where each screen hands the test its counter, keyed by the screen's number.
    private final class Sink {
        var taps: [Int: Binding<Int>] = [:]
    }

    /// A screen with a `@State` counter the test can write through the sink.
    private struct Counter: View {
        let number: Int
        let sink: Sink
        @State private var taps = 0

        var body: some View {
            Text("screen \(number) taps \(taps)")
                .onAppear { sink.taps[number] = $taps }
        }
    }

    /// A screen of another type, holding state of another type at the same place.
    private struct Other: View {
        let name: String
        @State private var label = "fresh"

        var body: some View {
            Text("other \(name) \(label)")
        }
    }

    /// Draws `view` as one frame of the run loop: state, the render cache and
    /// focus bracketed as they are live, so state that did not render is pruned.
    @MainActor
    private struct Frames {
        let tui = TUIContext()
        let focus = FocusManager()

        func draw(_ view: some View, width: Int = 60) -> String {
            var environment = EnvironmentValues()
            environment.focusManager = focus
            environment.applyRuntimeServices(from: tui)
            let context = RenderContext(
                availableWidth: width, availableHeight: 8, environment: environment, tuiContext: tui)
            tui.preferences.beginRenderPass()
            tui.stateStorage.beginRenderPass()
            tui.renderCache.beginRenderPass()
            focus.beginRenderPass()
            let buffer = renderToBuffer(view, context: context)
            focus.endRenderPass()
            tui.stateStorage.endRenderPass()
            tui.renderCache.removeInactive()
            return buffer.lines.map(\.stripped).joined(separator: "\n")
        }
    }

    private func stack(_ path: Binding<NavigationPath>, sink: Sink) -> some View {
        NavigationStack(path: path) {
            Text("root")
                .navigationDestination(for: Int.self) { Counter(number: $0, sink: sink) }
                .navigationDestination(for: String.self) { Other(name: $0) }
        }
    }

    @Test("A screen pushed over another of its type starts afresh, and the one below keeps its own state")
    func sameTypeScreensKeepTheirOwnState() throws {
        let frames = Frames()
        let sink = Sink()
        var path = NavigationPath()
        let binding = Binding(get: { path }, set: { path = $0 })

        path.append(1)
        _ = frames.draw(stack(binding, sink: sink))
        try #require(sink.taps[1]).wrappedValue = 2
        #expect(frames.draw(stack(binding, sink: sink)).contains("screen 1 taps 2"))

        path.append(2)
        let covered = frames.draw(stack(binding, sink: sink))
        #expect(covered.contains("screen 2 taps 0"), "the screen pushed over took the one below's state:\n\(covered)")
        try #require(sink.taps[2]).wrappedValue = 5
        _ = frames.draw(stack(binding, sink: sink))

        path.removeLast()
        let back = frames.draw(stack(binding, sink: sink))
        #expect(back.contains("screen 1 taps 2"), "the screen popped back to lost its state:\n\(back)")
    }

    @Test("A screen of another type pushed over one does not cost it its state")
    func otherTypeScreenOverOne() throws {
        let frames = Frames()
        let sink = Sink()
        var path = NavigationPath()
        let binding = Binding(get: { path }, set: { path = $0 })

        path.append(1)
        _ = frames.draw(stack(binding, sink: sink))
        try #require(sink.taps[1]).wrappedValue = 3
        _ = frames.draw(stack(binding, sink: sink))

        path.append("deimos")
        #expect(frames.draw(stack(binding, sink: sink)).contains("other deimos fresh"))

        path.removeLast()
        let back = frames.draw(stack(binding, sink: sink))
        #expect(back.contains("screen 1 taps 3"), "the screen popped back to lost its state:\n\(back)")
    }

    @Test("A popped screen pushed again starts afresh")
    func poppedScreenIsForgotten() throws {
        let frames = Frames()
        let sink = Sink()
        var path = NavigationPath()
        let binding = Binding(get: { path }, set: { path = $0 })

        path.append(1)
        _ = frames.draw(stack(binding, sink: sink))
        try #require(sink.taps[1]).wrappedValue = 4
        _ = frames.draw(stack(binding, sink: sink))

        path.removeLast()
        _ = frames.draw(stack(binding, sink: sink))
        path.append(1)
        let again = frames.draw(stack(binding, sink: sink))
        #expect(again.contains("screen 1 taps 0"), "a screen pushed anew kept the popped one's state:\n\(again)")
    }

    @Test("A root title that changes while screens are pushed keeps the middle of the trail")
    func rootTitleChangeKeepsTheMiddleCrumbs() {
        // The root renders every frame, buried, and records its title each
        // time; a changed title was read as a different screen at depth 0 and
        // dropped every depth above it, so the middle crumb came back as "…".
        let frames = Frames()
        var count = 4
        var path = NavigationPath()
        let binding = Binding(get: { path }, set: { path = $0 })
        func view() -> some View {
            NavigationStack(path: binding) {
                Text("inbox")
                    .navigationTitle("Inbox (\(count))")
                    .navigationDestination(for: String.self) { name in
                        Text(name).navigationTitle(name)
                    }
            }
        }

        _ = frames.draw(view())
        path.append("Mars")
        _ = frames.draw(view())
        path.append("Deimos")
        #expect(frames.draw(view()).contains("Inbox (4) › Mars › Deimos"))

        count = 5
        let changed = frames.draw(view())
        #expect(changed.contains("Inbox (5) › Mars › Deimos"), "the middle crumb was lost:\n\(changed)")
    }
}
