//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ScrollTransitionTests.swift
//
//  `scrollTransition`: the phase a view is drawn in follows where it is in
//  its scroll view's viewport, predicted before it is drawn and held to by
//  the scroll view (design study A2 §10 step 6, the owner's answer 5).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore
@testable import TUIkitView

/// What each row's effect was drawn at, by row.
private final class Drawn: @unchecked Sendable {
    var values: [Int: Double] = [:]
}

/// An effect that draws nothing and notes the value it was drawn at — the
/// interpolated one, for an interactive transition.
private struct Probe: VisualEffect {
    let row: Int
    let drawn: Drawn
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    func _applied(to buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        drawn.values[row] = value
        return buffer
    }
}

/// The phase each row's transition was asked for, by row.
@MainActor
private final class Phases {
    var byRow: [Int: ScrollTransitionPhase] = [:]
}

@MainActor
@Suite("Scroll transitions")
struct ScrollTransitionTests {

    /// Twenty one-row rows in a seven-row scroll view, each transitioned.
    private func list(
        position: Binding<ScrollPosition>, @ViewBuilder row: @escaping (Int) -> some View
    ) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(0..<20, id: \.self) { row($0) }
            }
        }
        .scrollIndicators(.never)
        .scrollPosition(position)
        .frame(width: 20, height: 7)
    }

    @Test("Interactive: the effect is interpolated by how far in the row is, towards the threshold")
    func interactiveInterpolates() {
        let harness = InputChainHarness()
        let drawn = Drawn()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let page = {
            self.list(position: binding) { index in
                Text("row \(index)")
                    .scrollTransition(.interactive(timingCurve: .linear).threshold(.centered)) { _, phase in
                        Probe(row: index, drawn: drawn, value: phase.value)
                    }
            }
        }
        harness.frame(page())
        position.scrollTo(y: 10)
        harness.frame(page())
        harness.frame(page())
        // Centred in seven rows is four in from either edge: the row at y 3
        // (row 13) is there; one row nearer an edge is three quarters of the
        // way, and so a quarter of the edge phase's value is left.
        #expect(drawn.values[13] == 0)
        #expect(drawn.values[14] == 0.25)
        #expect(drawn.values[15] == 0.5)
        #expect(drawn.values[16] == 0.75)
        #expect(drawn.values[12] == -0.25)
        #expect(drawn.values[11] == -0.5)
        #expect(drawn.values[10] == -0.75)
    }

    @Test("Animated: the edge phase until the threshold, then identity; each edge its own configuration")
    func animatedSwitchesAtThreshold() {
        let harness = InputChainHarness()
        let phases = Phases()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let page = {
            self.list(position: binding) { index in
                Text("row \(index)")
                    .scrollTransition(
                        topLeading: .identity, bottomTrailing: .animated.threshold(.visible(1))
                    ) { effect, phase in
                        // swiftlint:disable:next redundant_discardable_let
                        let _ = (phases.byRow[index] = phase)
                        return effect
                    }
            }
        }
        harness.frame(page())
        position.scrollTo(y: 5)
        harness.frame(page())
        harness.frame(page())
        // Rows 5–11 are in the viewport; the band draws a row or more past it
        // either way.
        for row in 5...11 { #expect(phases.byRow[row] == .identity) }
        #expect(phases.byRow[12] == .bottomTrailing)
        // Above, the top edge's configuration is the identity one.
        #expect(phases.byRow[4] == .identity)
    }

    @Test("Rows of a lazy stack scrolling through the viewport are predicted: the scroll view draws them once")
    func transitionRowsArePredicted() {
        let harness = InputChainHarness()
        let drawn = Drawn()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        let page = {
            self.list(position: binding) { index in
                Text("row \(index)")
                    .scrollTransition(.interactive(timingCurve: .linear).threshold(.centered)) { _, phase in
                        Probe(row: index, drawn: drawn, value: phase.value)
                    }
            }
        }
        harness.frame(page())
        harness.frame(page())
        let before = harness.geometryCorrections
        for step in 1...12 {
            position.scrollTo(y: step)
            harness.frame(page())
        }
        #expect(harness.geometryCorrections == before)
        #expect(drawn.values[15] == 0)
    }

    @Test("A view in no scroll view is drawn in the identity phase")
    func noScrollViewIsIdentity() {
        let harness = InputChainHarness()
        let phases = Phases()
        harness.frame(
            Text("alone").scrollTransition(.animated) { effect, phase in
                // swiftlint:disable:next redundant_discardable_let
                let _ = (phases.byRow[0] = phase)
                return effect
            })
        harness.frame(Text("alone").scrollTransition(.animated) { effect, phase in
            // swiftlint:disable:next redundant_discardable_let
            let _ = (phases.byRow[0] = phase)
            return effect
        })
        #expect(phases.byRow[0] == .identity)
    }

    @Test("The phase's value and identity, and the thresholds' depths")
    func phaseAndThresholdArithmetic() {
        #expect(ScrollTransitionPhase.topLeading.value == -1)
        #expect(ScrollTransitionPhase.identity.value == 0)
        #expect(ScrollTransitionPhase.bottomTrailing.value == 1)
        #expect(ScrollTransitionPhase.identity.isIdentity)
        typealias Threshold = ScrollTransitionConfiguration.Threshold
        // A 2-row view in a 10-row viewport: how far in each point is met.
        func depth(_ threshold: Threshold) -> Double { threshold.point.depth(length: 2, container: 10) }
        #expect(depth(.hidden) == 0)
        #expect(depth(.visible) == 2)
        #expect(depth(.visible(0.5)) == 1)
        #expect(depth(.visible(3)) == 2)
        #expect(depth(.centered) == 6)
        #expect(depth(.visible.inset(by: 1)) == 3)
        #expect(depth(Threshold.hidden.interpolated(towards: .centered, amount: 0.5)) == 3)
    }
}
