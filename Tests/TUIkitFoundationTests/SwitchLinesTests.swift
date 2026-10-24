//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SwitchLinesTests.swift
//
//  A switch where controls are drawn in lines, Braille dots or not at all: a
//  knob between the caps of the family and the button border shape in force
//  (owner, FB3-OTHERCAPS, 2026-10-24), four cells in every shape.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
@testable import TUIkitTestSupport

@MainActor
@Suite("A switch takes the control family's caps")
struct SwitchLinesTests {
    private func toggle(_ isOn: Bool, _ style: ControlStyle, _ shape: ButtonBorderShape) -> some View {
        Toggle("Wi-Fi", isOn: .constant(isOn)).toggleStyle(.switch)
            .controlStyle(style).buttonBorderShape(shape)
    }

    /// The switch's track alone, stripped, unfocused.
    private func track(_ isOn: Bool, _ style: ControlStyle, _ shape: ButtonBorderShape = .automatic) -> String {
        let line = renderToBuffer(toggle(isOn, style, shape), context: makeBareRenderContext(width: 30, height: 2))
            .lines.first?.stripped ?? ""
        return String(line.prefix { $0 != "W" }.dropLast())
    }

    @Test(
        "Under lines each shape has its caps, and the knob slides between them",
        arguments: [
            (ButtonBorderShape.automatic, "(○ )", "( ●)"),
            (.capsule, "(○ )", "( ●)"),
            (.circle, "(○ )", "( ●)"),
            (.roundedRectangle, "⦗● ⦘", "⦗ ●⦘"),
            (.roundedRectangle(radius: 0), "│● │", "│ ●│"),
            (.underline, "│● │", "│ ●│"),
            (.brackets("❨", "❩"), "❨● ❩", "❨ ●❩"),
        ])
    func linesShapes(_ shape: ButtonBorderShape, off: String, on: String) {
        #expect(track(false, .lines, shape) == off)
        #expect(track(true, .lines, shape) == on)
    }

    @Test("Under lines, bracket glyphs wider than a cell give way to the rectangle's sides")
    func wideBrackets() {
        #expect(track(false, .lines, .brackets("「", "」")) == "│● │")
    }

    @Test("Filled, the switch is the coloured track it was; the ASCII set keeps its brackets in every family")
    func filledAndASCII() {
        #expect(track(false, .automatic) == "▐▌ ")
        #expect(track(true, .block, .roundedRectangle) == " ▐▌")
        for style in [ControlStyle.lines, .braille, .blank] {
            let ascii = renderToBuffer(
                toggle(false, style, .roundedRectangle).toggleCharacterSet(.ascii),
                context: makeBareRenderContext(width: 30, height: 2)
            ).lines.first?.stripped ?? ""
            #expect(ascii.hasPrefix("[o ] Wi-Fi"), "\(style): \(ascii)")
        }
    }

    @Test("Braille takes the shape's dotted ends; blank has no caps")
    func brailleAndBlank() {
        #expect(track(false, .braille, .capsule) == "⢎○ ⡱")
        #expect(track(true, .braille, .roundedRectangle) == "⣏ ●⣹")
        #expect(track(false, .blank) == "○ ")
        #expect(track(true, .blank) == " ●")
    }

    @Test("A switch is four cells in every lines shape, measured as drawn")
    func oneWidth() {
        let shapes: [ButtonBorderShape] = [
            .automatic, .capsule, .circle, .roundedRectangle, .roundedRectangle(radius: 0), .underline,
            .brackets("<", ">"),
        ]
        for shape in shapes {
            for isOn in [false, true] {
                let view = toggle(isOn, .lines, shape).labelsHidden()
                let context = makeBareRenderContext(width: 30, height: 2)
                let drawn = renderToBuffer(view, context: context)
                let measured = measureChild(view, proposal: .unspecified, context: context)
                #expect(drawn.width == 4, "\(shape) \(isOn): \(drawn.lines)")
                #expect(measured.width == drawn.width, "\(shape) \(isOn)")
            }
        }
    }

    @Test("Focused, the caps breathe the accent and the knob holds the state's colour")
    func focusBreathesTheCaps() throws {
        let buffer = renderToBuffer(
            toggle(true, .lines, .capsule), context: makeRenderContext(width: 30, height: 2))
        let run = try #require(buffer.animatedCells.first)
        #expect(run.isAnimating && Set(run.frames).count > 1)
        #expect(run.width == 4 && run.offsetX == 0)
        // The knob's cells are the same in every frame: only the caps move. Each
        // cell is a run of its own, ended by a reset: cap, blank, knob, cap.
        let knobs = Set(run.frames.map { $0.components(separatedBy: "\u{1B}[0m")[1...2].joined() })
        #expect(knobs.count == 1, "\(knobs)")

        let disabled = renderToBuffer(
            toggle(true, .lines, .capsule).disabled(), context: makeRenderContext(width: 30, height: 2))
        #expect(disabled.animatedCells.isEmpty)
    }
}
