//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SliderTicksTests.swift
//
//  The macOS 26 slider additions: a fill from a neutral value, enabled bounds
//  that clamp every input and draw the rest of the track disabled, ticks with
//  labels under the track, a hidden thumb, and a current-value label.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
import TUIkitNumericControls
@testable import TUIkitTestSupport

@MainActor
@Suite("Slider ticks, neutral value and enabled bounds")
struct SliderTicksTests {

    private func lines(_ view: some View, width: Int = 40) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 4)).lines.map(\.stripped)
    }

    /// The track as drawn, between `"◀ "` and `" ▶"`.
    private func track(_ line: String) -> String {
        let afterLeft = line.drop { $0 != "◀" }.dropFirst(2)
        return String(afterLeft.prefix { $0 != "▶" }).trimmingCharacters(in: .whitespaces)
    }

    @Test("A neutral value fills from itself to the value, on either side")
    func neutralFill() {
        var value = 0.25
        let binding = Binding(get: { value }, set: { value = $0 })
        let below = track(lines(Slider(value: binding, neutralValue: 0.5) { EmptyView() })[0])
        let head = below.firstIndex(of: "●")!
        #expect(below[..<head].allSatisfy { $0 == "─" }, "empty below the value: \(below)")
        #expect(below[below.index(after: head)...].contains("━"), "filled up to the neutral value: \(below)")
        #expect(below.hasSuffix("─"), "and empty past it: \(below)")

        value = 0.75
        let above = track(lines(Slider(value: binding, neutralValue: 0.5) { EmptyView() })[0])
        #expect(above.hasPrefix("─"), "empty below the neutral value: \(above)")
        #expect(above.contains("━━"), "filled from it to the value: \(above)")
    }

    @Test("Enabled bounds clamp the value, the keys and the drawn track")
    func enabledBoundsClamp() {
        var value = 0.9
        let binding = Binding(get: { value }, set: { value = $0 })
        let bounded = Slider(value: binding, enabledBounds: 0.2...0.6) { EmptyView() }
        let drawn = renderToBuffer(bounded, context: makeRenderContext(width: 40, height: 2))
        #expect(value == 0.6, "a value outside is brought inside: \(value)")
        let plain = renderToBuffer(
            Slider(value: binding) { EmptyView() }, context: makeRenderContext(width: 40, height: 2))
        #expect(drawn.lines[0] != plain.lines[0], "the track outside the bounds is drawn differently")
        #expect(drawn.lines[0].stripped == plain.lines[0].stripped, "in colour only")
    }

    @Test("Ticks draw a mark under each value and the labels under those")
    func ticksAndLabels() {
        var value = 0.5
        let rows = lines(
            Slider(value: Binding(get: { value }, set: { value = $0 })) {
                EmptyView()
            } ticks: {
                SliderTick(0.0) { Text("lo") }
                SliderTick(0.5)
                SliderTick("hi", 1.0)
            })
        #expect(rows.count == 3, "\(rows)")
        #expect(rows[1].filter { $0 == "╵" }.count == 3, "\(rows)")
        #expect(rows[2].contains("lo") && rows[2].contains("hi"), "\(rows)")
        let markColumns = rows[1].enumerated().filter { $0.element == "╵" }.map(\.offset)
        let headColumn = rows[0].distance(from: rows[0].startIndex, to: rows[0].firstIndex(of: "●")!)
        #expect(markColumns.contains(headColumn), "a tick sits under the head on its value: \(rows)")
    }

    @Test("Unlabelled ticks take one row, and a tick per step comes from tick:")
    func tickPerStep() {
        var value = 2.0
        let rows = lines(
            Slider(value: Binding(get: { value }, set: { value = $0 }), in: 0...4, step: 1) {
                EmptyView()
            } tick: { SliderTick($0) })
        #expect(rows.count == 2)
        #expect(rows[1].filter { $0 == "╵" }.count == 5, "\(rows)")
    }

    @Test("A hidden thumb draws no knob")
    func hiddenThumb() {
        var value = 0.5
        let shown = lines(Slider(value: Binding(get: { value }, set: { value = $0 })))[0]
        let hidden = lines(Slider(value: Binding(get: { value }, set: { value = $0 })).sliderThumbVisibility(.hidden))[0]
        #expect(shown.contains("●") && !hidden.contains("●"), "\(hidden)")
        #expect(hidden.count == shown.count)
    }

    @Test("A current-value label stands in for the read-out")
    func currentValueLabel() {
        var value = 0.5
        let row = lines(
            Slider(value: Binding(get: { value }, set: { value = $0 })) {
                EmptyView()
            } currentValueLabel: {
                Text("half")
            })[0]
        #expect(row.contains("half") && !row.contains("50%"), "\(row)")
    }
}
