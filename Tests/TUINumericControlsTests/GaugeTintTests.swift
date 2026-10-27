//  🖥️ TUI — A Terminal UI framework for Swift
//  GaugeTintTests.swift
//
//  A gauge's or a progress bar's lit part follows a tint where one is stated
//  and keeps TUI's quiet fill where none is; a gradient tint is painted along
//  the control — across a bar, around a ring — as SwiftUI paints one
//  (`Gradients where a colour is accepted.md` §1).
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUICore
@testable import TUIFoundation
@testable import TUINumericControls
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("Gauges and progress bars follow a stated tint")
struct GaugeTintTests {

    private let ramp = Gradient(colors: [.rgb(255, 0, 0), .rgb(0, 0, 255)])

    private func buffer<V: View>(_ view: V, width: Int = 22, height: Int = 6) -> FrameBuffer {
        let context = RenderContext(
            availableWidth: width, availableHeight: height, tuiContext: TUIContext()
        ).isolatingRenderCache()
        return renderToBuffer(view, context: context)
    }

    /// Every colour `line` draws with, ink or field, cell by cell.
    private func colours(_ line: String) -> [Color] {
        FrameBuffer.cells(in: line, through: line.strippedLength, defaultForeground: .white, surface: .black)
            .compactMap { $0 }.flatMap { [$0.foreground, $0.background].compactMap { $0 } }
    }

    /// The bar's row of a label-less linear gauge.
    private func bar<V: View>(_ view: V) -> String {
        buffer(view).lines.last { !$0.stripped.allSatisfy(\.isWhitespace) } ?? ""
    }

    private func redness(_ colour: Color) -> Int {
        guard let rgb = colour.rgbComponents else { return 0 }
        return Int(rgb.red) - Int(rgb.blue)
    }

    @Test("Untinted, a linear gauge fills with the quiet secondary ink, as before")
    func untinted() {
        let palette = RenderContext(availableWidth: 1, availableHeight: 1, tuiContext: TUIContext()).environment.palette
        let drawn = colours(bar(Gauge(value: 0.5) { EmptyView() }.gaugeStyle(.linearCapacity)))
        #expect(drawn.contains(palette.foregroundSecondary), "\(drawn)")
    }

    @Test("A stated colour tint fills a linear gauge and a progress bar")
    func colourTint() {
        let red = Color.rgb(255, 0, 0)
        let gauge = colours(bar(Gauge(value: 0.5) { EmptyView() }.gaugeStyle(.linearCapacity).tint(red)))
        #expect(gauge.contains(red), "\(gauge)")
        let progress = colours(bar(ProgressView(value: 0.5).tint(red)))
        #expect(progress.contains(red), "\(progress)")
    }

    @Test("A gradient tint runs across the whole bar, the fill uncovering it")
    func gradientAcrossTheBar() throws {
        let half = colours(bar(Gauge(value: 0.5) { EmptyView() }.gaugeStyle(.linearCapacity).tint(ramp)))
        let full = colours(bar(Gauge(value: 1) { EmptyView() }.gaugeStyle(.linearCapacity).tint(ramp)))
        let first = try #require(full.first)
        #expect(redness(first) > 200, "it starts at the first stop: \(first)")
        #expect(full.contains { redness($0) < -200 }, "and ends at the last: \(full)")
        // The ramp is the track's, not the lit part's: the first cell is the same red
        // half full as full, rather than the start of a ramp squeezed into the half.
        #expect(half.first == first, "\(String(describing: half.first)) vs \(first)")
        #expect(!half.contains { redness($0) < -200 }, "half full stops half way: \(half)")
    }

    @Test("A gradient tint runs around a circular gauge, from the start of its sweep")
    func gradientAroundTheRing() {
        let full = buffer(Gauge(value: 1) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(ramp))
        // The sweep starts on the bottom row just left of the break and ends just right
        // of it: red there on the left, blue on the right.
        let bottom = colours(full.lines[2])
        #expect(redness(bottom.first ?? .black) > 150, "the left corner is early in the sweep: \(bottom)")
        #expect(redness(bottom.last ?? .black) < -150, "the right corner, late: \(bottom)")
        let ring = full.lines.prefix(3).flatMap { colours($0) }
        #expect(ring.contains { redness($0) > 150 } && ring.contains { redness($0) < -150 }, "\(ring)")
    }

    @Test("A gradient-tinted ring's unlit cells are the ramp, faintly — not the plain dim rim")
    func unlitCellsAreFaint() {
        let palette = RenderContext(availableWidth: 1, availableHeight: 1, tuiContext: TUIContext()).environment.palette
        let empty = buffer(Gauge(value: 0) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(ramp))
        let ring = empty.lines.prefix(3).flatMap { colours($0) }
        #expect(!ring.contains(palette.foregroundTertiary), "\(ring)")
        #expect(!ring.contains(Color.rgb(255, 0, 0)), "nothing is lit at zero: \(ring)")
    }

    @Test("`.tint` as a style paints the tint as stated, a gradient as its ramp")
    func tintStyleIsTheRamp() {
        var environment = EnvironmentValues()
        environment.tintPaint = Gradient(colors: [.red, .blue]).paint(in: environment)
        guard case .gradient = TintShapeStyle().paint(in: environment) else {
            Issue.record("\(TintShapeStyle().paint(in: environment))")
            return
        }
    }

    @Test("A gradient tint's accent — what the controls derive colours from — is its representative")
    func accentIsTheRepresentative() {
        let seen = SeenTint()
        _ = buffer(TintProbe(seen: seen).tint(ramp))
        #expect(seen.tint == ramp.representative)
    }
}

/// What ``TintProbe`` saw.
@MainActor
private final class SeenTint {
    var tint: Color?
}

/// Records the tint colour its environment holds.
private struct TintProbe: View {
    @Environment(\.tint) private var tint
    let seen: SeenTint

    var body: some View {
        seen.tint = tint
        return EmptyView()
    }
}
