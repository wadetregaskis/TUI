//  🖥️ TUI — A Terminal UI framework for Swift
//  ProgressViewStyleTests.swift
//
//  `ProgressViewStyle`: the linear styles draw the bar with the progress view's
//  track, the circular one a ring (or a spinner while indeterminate), and a
//  custom style its body — in which `ProgressView(configuration)` draws as the
//  style outside it would, track and all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIFoundation
import TUINumericControls
@testable import TUITestSupport

/// The percentage, as text.
private struct PercentStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        Text("\(Int((configuration.fractionCompleted ?? 0) * 100))%")
    }
}

/// The progress view as it would otherwise look, in brackets.
private struct BracketedStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            Text("[")
            ProgressView(configuration).frame(width: 10)
            Text("]")
        }
    }
}

@MainActor
@Suite("ProgressViewStyle")
struct ProgressViewStyleProtocolTests {
    private func lines<V: View>(_ view: V, width: Int = 12) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: 4)).lines
    }

    @Test("The linear styles are the bar the progress view has always drawn")
    func linear() {
        let bar = ProgressView(value: 0.5)
        #expect(lines(bar.progressViewStyle(.linear)) == lines(bar))
        #expect(lines(bar.progressViewStyle(.automatic)) == lines(bar))
        #expect(lines(bar.trackStyle(.shade).progressViewStyle(.linear)) == lines(bar.trackStyle(.shade)))
        #expect(lines(bar.trackStyle(.shade)) != lines(bar), "the track still decides the bar")
    }

    @Test("A custom style draws its body")
    func custom() {
        #expect(lines(ProgressView(value: 0.25).progressViewStyle(PercentStyle())).first?.stripped.hasPrefix("25%") == true)
    }

    @Test("ProgressView(configuration) draws as the style outside, with the progress view's track")
    func configuration() {
        let shaded = ProgressView(value: 0.5).trackStyle(.shade)
        let bracketed = lines(shaded.progressViewStyle(BracketedStyle()), width: 20).first ?? ""
        let plain = lines(shaded.frame(width: 10), width: 20).first ?? ""
        let expected: String = "[" + plain.stripped.prefix(10) + "]"
        #expect(bracketed.stripped == expected, "\(bracketed.stripped) vs \(plain.stripped)")
    }

    @Test("The circular style is a ring while determinate and a spinner while not")
    func circular() {
        let ring = lines(ProgressView(value: 0.5).progressViewStyle(.circular))
        #expect(ring.count >= 3, "a ring is three rows: \(ring.map(\.stripped))")
        let spinning = lines(ProgressView().progressViewStyle(.circular))
        #expect(spinning.first?.stripped.isEmpty == false)
    }
}
