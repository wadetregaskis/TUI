//  🖥️ TUIkit — Terminal UI Kit for Swift
//  GeometryCorrectionRateTests.swift
//
//  How often the coordinate-space owners draw a subtree again, on the
//  shapes the design study's correction table names (A2 §6): the acceptance
//  metric of the prediction rungs, pinned here so each rung's effect on it is
//  a reviewed change to these numbers. The Stress `geometry` scenario prints
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

    @Test("Under G1: none at rest; per scroll step two; one per insertion; one per offset step; no layer's")
    func correctionsUnderG1() {
        let harness = InputChainHarness()
        var position = ScrollPosition()
        let binding = Binding(get: { position }, set: { position = $0 })
        var rows = 40
        var offset = 0
        let frame = { _ = harness.frame(page(rows: rows, offset: offset, position: binding)) }

        // The first frame finds every reader somewhere it was not told: each
        // owner corrects once.
        let first = corrections(harness, frame)
        #expect(first.named == 1 && first.scrollView == 1 && first.root == 1)

        // At rest, nothing moves and nothing is corrected.
        for _ in 0..<3 { #expect(corrections(harness, frame).total == 0) }

        // Scrolling moves every row through the viewport: the scroll view
        // corrects every frame. And each step brings a row into the lazy
        // stack's band for the first time, asking where it is in the list's
        // space with nothing found for it yet: the named space corrects too.
        // (Steps 5 and 6 predict both, and take both to zero.)
        for step in 1...5 {
            position.scrollTo(y: step)
            let made = corrections(harness, frame)
            #expect(made.scrollView == 1)
            #expect(made.named == 1)
        }

        // A row inserted above moves every row in the list's space — and in
        // the viewport (step 5's stack prediction takes both to zero).
        rows += 1
        let inserted = corrections(harness, frame)
        #expect(inserted.named == 1)

        // The offset above the global reader moves it every step: the root
        // corrects (step 7's offset conversion takes it to zero).
        for step in 1...3 {
            offset = step
            #expect(corrections(harness, frame).root == 1)
        }
        // The marker following the selected row resolves its anchor in the
        // frame that draws it, from a reader filling the layer: never a layer
        // correction, however the rows move.
        #expect(harness.geometryCorrections.layer == 0)
        #expect(harness.geometryCorrections.residual == 0)
    }
}
