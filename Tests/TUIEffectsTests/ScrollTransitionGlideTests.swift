//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollTransitionGlideTests.swift
//
//  A scroll transition under an animated programmatic scroll (decisions
//  B27-ANIMATING): every frame of the glide is a frame, so an interactive
//  transition follows each line the glide passes — and the frame a glide
//  starts on is drawn at its start, not at the target the content was first
//  drawn at to find it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUICore
@testable import TUIEffects
@testable import TUIFoundation
@testable import TUITestSupport
@testable import TUIView

/// The value one row's effect was drawn at, frame by frame.
private final class DrawnValues: @unchecked Sendable {
    var values: [Double] = []
}

/// An effect that draws nothing and notes the interpolated value it was
/// drawn at.
private struct ValueProbe: VisualEffect {
    let drawn: DrawnValues
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func _applied(to buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        drawn.values.append(value)
        return buffer
    }
}

@MainActor
@Suite("Scroll transitions under a glide")
struct ScrollTransitionGlideTests {

    @Test("An interactive transition follows the glide's intermediate lines, from its start")
    func interactiveFollowsTheGlide() {
        let tuiContext = TUIContext()
        let focusManager = FocusManager()
        let scheduler = AnimationScheduler()
        let drawn = DrawnValues()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let view = ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<40, id: \.self) { index in
                    if index == 4 {
                        Text("row 4")
                            .scrollTransition(.interactive(timingCurve: .linear).threshold(.centered)) { _, phase in
                                ValueProbe(drawn: drawn, value: phase.value)
                            }
                    } else {
                        Text("row " + String(index))
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .scrollPosition(binding)
        .frame(width: 20, height: 7)

        func frame(at nanos: Int64, _ transaction: Transaction = Transaction()) -> [Double] {
            var environment = EnvironmentValues()
            environment.focusManager = focusManager
            environment.applyRuntimeServices(from: tuiContext)
            environment.animationScheduler = scheduler
            environment.animationFrame = AnimationFrame(nowNanos: nanos, step: 0, canAnimate: true)
            environment.transaction = transaction
            let context = RenderContext(
                availableWidth: 20, availableHeight: 7, environment: environment, tuiContext: tuiContext)
            drawn.values.removeAll()
            tuiContext.preferences.beginRenderPass()
            tuiContext.stateStorage.beginRenderPass()
            tuiContext.renderCache.beginRenderPass()
            focusManager.beginRenderPass()
            scheduler.beginFrame()
            _ = renderToBuffer(view, context: context)
            scheduler.endFrame()
            focusManager.endRenderPass()
            tuiContext.stateStorage.endRenderPass()
            tuiContext.renderCache.removeInactive()
            return drawn.values
        }

        let start: Int64 = 1_000_000_000
        _ = frame(at: start)
        let resting = frame(at: start)
        position.scrollTo(y: 4)
        let requested = frame(at: start, Transaction(animation: .linear(duration: 0.25)))
        #expect(requested.last == resting.last, "drawn where the view stands: \(requested) vs \(resting)")
        var seen: [Double] = []
        var now = start
        while let wake = scheduler.nextFiring(after: now) {
            now = wake
            if let value = frame(at: wake).last { seen.append(value) }
        }
        // Row 4 moves from four lines down a seven-line view to its top: its
        // value passes each line's on the way.
        #expect(Set(seen).count >= 3, "intermediate lines: \(seen)")
        #expect(seen.first != seen.last, "\(seen)")
    }
}
