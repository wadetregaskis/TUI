//  🖥️ TUI — A Terminal UI framework for Swift
//  TabChipCapsTests.swift
//
//  A compact tab strip's chips take their caps from the control family, as a
//  button's face does (FB3-OTHERCAPS, 2026-10-23), and are as wide in every
//  family.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITabs
@testable import TUITestSupport

/// A compact strip in lines, its first tab selected: the strip registers first,
/// so it takes the focus and its active chip breathes.
private struct LinesChipsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup {
            TabView(selection: .constant(0)) {
                Tab("One", value: 0) { Text("ONE BODY") }
                Tab("Two", value: 1) { Text("TWO BODY") }
            }
            .tabViewStyle(.compact)
            .tabViewHeaderAlignment(.leading)
            .controlStyle(.lines)
        }
    }
}

@MainActor
@Suite("A compact tab strip's chips take the control family's caps")
struct TabChipCapsTests {
    /// The strip's row, stripped, under `style` and `shape`.
    private func strip(_ style: ControlStyle, _ shape: ButtonBorderShape = .automatic) -> String {
        let view = TabView(selection: .constant(0)) {
            Tab("One", value: 0) { Text("ONE BODY") }
            Tab("Two", value: 1) { Text("TWO BODY") }
            Tab("Three", value: 2) { Text("THREE BODY") }
        }
        .tabViewStyle(.compact)
        .controlStyle(style)
        .buttonBorderShape(shape)
        let lines = renderToBuffer(view, context: makeRenderContext(width: 40, height: 6)).lines.map(\.stripped)
        return lines.first { $0.contains("One") } ?? ""
    }

    @Test("Filled: the active chip between half blocks, as before")
    func filled() {
        #expect(strip(.block).contains("▐ One ▌"), "\(strip(.block))")
    }

    @Test("Lines: the active chip between the shape's line caps; the others have none to show")
    func lines() {
        let capsule = strip(.lines)
        #expect(capsule.contains("( One )  Two    Three  "), "\(capsule)")
        #expect(!capsule.contains("▐") && !capsule.contains("▌"), "\(capsule)")
        let rectangle = strip(.lines, .roundedRectangle)
        #expect(rectangle.contains("│ One │"), "\(rectangle)")
    }

    @Test("Every family draws the strip the same width")
    func sameWidth() {
        let widths = [ControlStyle.block, .lines, .braille, .blank].map { strip($0).count }
        #expect(Set(widths).count == 1, "\(widths)")
    }

    @Test("Lines: a focused chip's caps breathe the focus with its label, as a lines button's do")
    func linesCapsBreathe() throws {
        // Owner, 2026-10-24: "when there are visible brackets or similar they
        // should pulse too, along with the tab label."
        let harness = RenderLoopHarness()
        let loop = harness.loop(LinesChipsApp())
        _ = loop.render()
        _ = loop.render()
        let frame = try #require(loop.replayable, "the render kept no frame to replay")
        let run = try #require(
            frame.runs.first { $0.frame(atIndex: 0).stripped.contains("One") },
            "the focused chip left no run: \(frame.runs)")
        let frames = run.frames.map(paintedCells)
        #expect(frames.allSatisfy { $0.first?.glyph == "(" && $0.last?.glyph == ")" }, "the run is not the chip")
        let opens = Set(frames.map { String(describing: $0.first?.ink) })
        let closes = Set(frames.map { String(describing: $0.last?.ink) })
        let labels = Set(frames.map { String(describing: $0.first { $0.glyph == "O" }?.ink) })
        #expect(opens.count > 1 && closes.count > 1, "the caps hold still while the label breathes")
        // From their own resting inks to one bright end, which they reach together.
        #expect(!opens.isDisjoint(with: labels), "the caps and the label never meet: \(opens) \(labels)")
    }
}
