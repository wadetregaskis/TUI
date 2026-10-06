//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryCorrectionRateTests.swift
//
//  How often the coordinate-space owners draw a subtree again, on the
//  shapes the design study's correction table names (A2 §6): the acceptance
//  metric of the prediction rungs, pinned here so each rung's effect on it is
//  a reviewed change to these numbers. Under G1 (step 3) the same shape made,
//  per scroll step, a scroll view AND a named-space correction, and one named
//  correction per insertion; rung 1 (step 5) takes both named ones to zero. The Stress `geometry` scenario prints
//  the same counter for a bench on a quiet machine.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

@MainActor
@Suite("Geometry correction rate")
struct GeometryCorrectionRateTests {

    /// The selected row's bounds.
    private struct SelectionKey: PreferenceKey {
        static var defaultValue: Anchor<CellRect>? { nil }
        static func reduce(value: inout Anchor<CellRect>?, nextValue: () -> Anchor<CellRect>?) {
            value = value ?? nextValue()
        }
    }

    /// A list of rows each reading where it is in the list's named space and
    /// in the scroll view's, a marker following the selected row from its
    /// anchor; and above it, under an offset, a reader of the global space.
    private func page(
        rows: Int, offset: Int, position: Binding<ScrollPosition>, selected: Int = 2
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { proxy in Text("g \(proxy.frame(in: .global).minX)") }
                .frame(height: 1)
                .offset(x: offset)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<rows, id: \.self) { index in
                        Text("row \(rows - 1 - index)")
                            .background(alignment: .trailing) {
                                GeometryReader { proxy in
                                    Text("\(proxy.frame(in: .named("list")).minY)/\(proxy.frame(in: .scrollView).minY)")
                                }
                            }
                            .anchorPreference(key: SelectionKey.self, value: .bounds) { index == selected ? $0 : nil }
                    }
                }
                .coordinateSpace(.named("list"))
            }
            .scrollPosition(position)
            .frame(height: 8)
            .overlayPreferenceValue(SelectionKey.self, alignment: .topLeading) { anchor in
                GeometryReader { proxy in
                    if let anchor { Text(">").offset(x: 0, y: proxy[anchor].minY) }
                }
            }
        }
    }

    /// The corrections one frame made, by owner kind.
    private func corrections(
        _ harness: InputChainHarness, _ render: () -> Void
    ) -> GeometryCorrections {
        let before = harness.geometryCorrections
        render()
        let after = harness.geometryCorrections
        var made = GeometryCorrections()
        made.named = after.named - before.named
        made.scrollView = after.scrollView - before.scrollView
        made.root = after.root - before.root
        made.layer = after.layer - before.layer
        made.residual = after.residual - before.residual
        return made
    }

    @Test("Rung 1 (stacks predict): none at rest; one per scroll step; none per insertion; one per offset step")
    func correctionsUnderRung1() {
        let harness = InputChainHarness()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        var rows = 40
        var offset = 0
        let frame = { _ = harness.frame(page(rows: rows, offset: offset, position: binding)) }
        func expect(_ made: GeometryCorrections, named: Int = 0, scrollView: Int = 0, root: Int = 0) {
            #expect(made.named == named)
            #expect(made.scrollView == scrollView)
            #expect(made.root == root)
            #expect(made.layer == 0)
            #expect(made.residual == 0)
        }

        // The first frame: the list's readers are where the stack placed them
        // in its space — predicted, no correction. Nothing predicts the scroll
        // view's space yet (step 6), nor the global reader's place: there is
        // no carried origin above the list until the root has a reader to
        // carry one for, so each of those owners corrects once.
        expect(corrections(harness, frame), scrollView: 1, root: 1)

        // At rest, nothing moves and nothing is corrected — including the
        // frame on which the root starts carrying an origin, whose readers
        // are told what was found for them last frame.
        for _ in 0..<3 { expect(corrections(harness, frame)) }

        // Scrolling moves every row through the viewport, which nothing
        // predicts until the scroll view translates its content's origin (step
        // 6): it corrects every frame. A row entering the lazy stack's band
        // for the first time is placed by the stack, in the list's space:
        // predicted, where G1 corrected the named space every step.
        for step in 1...5 {
            position.scrollTo(y: step)
            expect(corrections(harness, frame), scrollView: 1)
        }

        // A row inserted above moves every row down, in the list's space and
        // in the viewport alike — and the stack's placement moves the
        // prediction with them: no correction (G1 corrected the named space).
        rows += 1
        expect(corrections(harness, frame))

        // The offset above the global reader moves it every step, and no
        // container the prediction follows put it there: the root corrects
        // (step 7's offset conversion takes it to zero).
        for step in 1...3 {
            offset = step
            expect(corrections(harness, frame), root: 1)
        }
    }
}
