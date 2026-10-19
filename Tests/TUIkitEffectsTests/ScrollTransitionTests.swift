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

import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitEffects
@testable import TUIkitFoundation
@testable import TUIkitTestSupport
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

    @Test("Animated: half a view in is the default threshold, where interactive's is all of it")
    func animatedDefaultThresholdIsHalf() {
        let harness = InputChainHarness()
        let phases = Phases()
        // Two-line rows in a seven-line viewport at the top: rows 0–2 are in,
        // row 3's first line is the viewport's last and its second is past it.
        func page(_ configuration: ScrollTransitionConfiguration) -> some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<20, id: \.self) { index in
                        Text("row \(index)").frame(height: 2)
                            .scrollTransition(configuration) { effect, phase in
                                // swiftlint:disable:next redundant_discardable_let
                                let _ = (phases.byRow[index] = phase)
                                return effect
                            }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(width: 20, height: 7)
        }
        harness.frame(page(.animated))
        #expect(phases.byRow[3] == .identity)
        #expect(phases.byRow[4] == .bottomTrailing)
        harness.frame(page(.animated(.linear)))
        #expect(phases.byRow[3] == .identity)
        harness.frame(page(.animated.threshold(.visible)))
        #expect(phases.byRow[3] == .bottomTrailing)
        func depth(_ configuration: ScrollTransitionConfiguration) -> Double {
            configuration.visibleThreshold.point.depth(length: 2, container: 10)
        }
        #expect(depth(.animated) == 1)
        #expect(depth(.animated(.linear).animation(.default)) == 1)
        #expect(depth(.interactive) == 2)
        #expect(depth(.interactive(timingCurve: .linear)) == 2)
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

    /// A seven-row log of `count` rows, each transitioned, glued to its tail.
    private func gluedLog(count: Int, phases: Phases) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    Text("line \(index)")
                        .scrollTransition(.animated) { effect, phase in
                            // swiftlint:disable:next redundant_discardable_let
                            let _ = (phases.byRow[index] = phase)
                            return effect
                        }
                }
            }
        }
        .scrollIndicators(.never)
        .defaultScrollAnchor(.bottom)
        .frame(width: 20, height: 7)
    }

    @Test("A glued log's rows are drawn from where the frame settles: a row arriving dims no row on screen")
    func gluedLogDrawsFromTheSettledOffset() {
        let harness = InputChainHarness()
        let phases = Phases()
        harness.frame(gluedLog(count: 20, phases: phases))
        harness.frame(gluedLog(count: 20, phases: phases))
        for count in 21...24 {
            // The content draws at the tail it had; the glue then moves the
            // offset a row down, past what the rows were told.
            harness.frame(gluedLog(count: count, phases: phases))
            for row in (count - 7)..<count { #expect(phases.byRow[row] == .identity, "row \(row) of \(count)") }
            #expect(phases.byRow[count - 8] == .topLeading)
        }
        #expect(harness.geometryCorrections.residual == 0)
    }

    @Test("A jump to a row draws the rows from where the jump lands, in the same frame")
    func seekDrawsFromWhereItLands() {
        let harness = InputChainHarness()
        let phases = Phases()
        final class Box { var proxy: ScrollViewProxy? }
        let box = Box()
        let page = {
            ScrollViewReader { proxy in
                // swiftlint:disable:next redundant_discardable_let
                let _ = (box.proxy = proxy)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<60, id: \.self) { index in
                            Text("row \(index)")
                                .scrollTransition(.animated) { effect, phase in
                                    // swiftlint:disable:next redundant_discardable_let
                                    let _ = (phases.byRow[index] = phase)
                                    return effect
                                }
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(width: 20, height: 7)
            }
        }
        harness.frame(page())
        harness.frame(page())
        box.proxy?.scrollTo(30, anchor: .top)
        harness.frame(page())
        for row in 30..<37 { #expect(phases.byRow[row] == .identity, "row \(row)") }
        #expect(harness.geometryCorrections.residual == 0)
    }

    @Test("A transition keeps its marker when its content stops stamping one: no correction for it")
    func markerSlotIgnoresContent() {
        let harness = InputChainHarness()
        let phases = Phases()
        let page = { (observed: Bool) in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("above")
                    // A row down that the prediction does not follow: the
                    // transition's residual carries it from frame to frame.
                    UnconvertedContainer {
                        // An `AnyView` draws at the transition's own identity,
                        // so an observer in it claims a marker slot there too.
                        AnyView(
                            observed
                                ? AnyView(Text("row").onScrollVisibilityChange { _ in })
                                : AnyView(Text("row"))
                        )
                        .scrollTransition(.animated) { effect, phase in
                            // swiftlint:disable:next redundant_discardable_let
                            let _ = (phases.byRow[1] = phase)
                            return effect
                        }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(width: 20, height: 7)
        }
        harness.frame(page(true))
        harness.frame(page(true))
        let settled = harness.geometryCorrections
        harness.frame(page(false))
        harness.frame(page(true))
        // The transition's marker is the same marker whatever its content
        // draws, so the residual kept for it is kept, and it is predicted.
        #expect(harness.geometryCorrections == settled)
        #expect(phases.byRow[1] == .identity)
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
