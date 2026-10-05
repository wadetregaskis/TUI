//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerSegmentsTests.swift
//
//  The segmented and palette picker styles: one control face, one focus stop,
//  a cursor the arrows move without choosing, and a palette's selection effect
//  deciding how the selection shows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The picker's selection, outside the view.
private final class Choice: @unchecked Sendable {
    var value: Int
    init(_ value: Int = 1) { self.value = value }
    var binding: Binding<Int> { Binding(get: { self.value }, set: { self.value = $0 }) }
}

/// Counts a button's presses.
private final class Presses: @unchecked Sendable {
    var count = 0
}

/// Shows whether the symbol variant in force is `.fill`.
private struct VariantProbe: View {
    let name: String
    @Environment(\.symbolVariants) private var variants
    var body: some View { Text(variants == .fill ? name.uppercased() : name) }
}

@MainActor
@Suite("Segmented and palette pickers")
struct PickerSegmentsTests {
    private func picker(_ choice: Choice) -> some View {
        Picker("Size", selection: choice.binding) {
            Text("S").tag(1)
            Text("M").tag(2)
            Text("L").tag(3)
        }
        .pickerStyle(.segmented)
    }

    /// The picker, then a button after it.
    private func pickerThenButton(_ choice: Choice, _ presses: Presses, disabled: Bool = false) -> some View {
        VStack {
            picker(choice).disabled(disabled)
            Button("Go") { presses.count += 1 }
        }
    }

    /// The column `glyph` is drawn at on `line`, stripped.
    private func column(of glyph: Character, in line: String) -> Int? {
        let row = line.stripped
        return row.firstIndex(of: glyph).map { row.distance(from: row.startIndex, to: $0) }
    }

    @Test("The options are one face: the caps, the labels, and a rule between each pair")
    func oneFace() {
        let drawn = InputChainHarness(width: 40, height: 3).frame(picker(Choice())).lines.map(\.stripped)
        #expect(drawn.first == "Size ▐ S │ M │ L ▌", "\(drawn)")
    }

    @Test("The picker is one Tab stop, however many segments it has")
    func oneTabStop() {
        let presses = Presses()
        let choice = Choice()
        // The picker takes the focus first; one Tab reaches the button.
        InputChainHarness(width: 40, height: 4).play([KeyEvent(key: .tab), KeyEvent(key: .enter)]) {
            pickerThenButton(choice, presses)
        }
        #expect(presses.count == 1, "one Tab did not leave the picker")
        #expect(choice.value == 1)
    }

    @Test("Left and Right move the cursor without choosing; Return or Space chooses")
    func arrowsMoveTheCursor() {
        let choice = Choice(1)
        let harness = InputChainHarness(width: 40, height: 3)
        harness.play([KeyEvent(key: .right)]) { picker(choice) }
        #expect(choice.value == 1, "an arrow chose")
        harness.play([KeyEvent(key: .enter)]) { picker(choice) }
        #expect(choice.value == 2)
        harness.play([KeyEvent(key: .right), KeyEvent(key: .space)]) { picker(choice) }
        #expect(choice.value == 3)
    }

    @Test("The cursor starts on the selection, and wraps at either end")
    func cursorStartsOnTheSelectionAndWraps() {
        let fromFirst = Choice(1)
        InputChainHarness(width: 40, height: 3).play([KeyEvent(key: .left), KeyEvent(key: .enter)]) {
            picker(fromFirst)
        }
        #expect(fromFirst.value == 3, "Left from the first segment did not wrap to the last")

        let fromLast = Choice(3)
        InputChainHarness(width: 40, height: 3).play([KeyEvent(key: .right), KeyEvent(key: .enter)]) {
            picker(fromLast)
        }
        #expect(fromLast.value == 1, "Right from the last segment did not wrap to the first")

        let fromMiddle = Choice(2)
        InputChainHarness(width: 40, height: 3).play([KeyEvent(key: .right), KeyEvent(key: .enter)]) {
            picker(fromMiddle)
        }
        #expect(fromMiddle.value == 3, "the cursor did not start on the selection")
    }

    @Test("A click chooses the segment under it, the end caps included; a rule chooses nothing")
    func clicking() {
        let choice = Choice(2)
        let harness = InputChainHarness(width: 40, height: 3)
        func click(_ x: Int) {
            harness.mouse(MouseEvent(button: .left, phase: .pressed, x: x, y: 0))
            harness.mouse(MouseEvent(button: .left, phase: .released, x: x, y: 0))
            harness.frame(picker(choice))
        }
        let line = harness.frame(picker(choice)).lines.first ?? ""
        guard let large = column(of: "L", in: line), let cap = column(of: "▐", in: line),
            let rule = column(of: "│", in: line)
        else {
            Issue.record("the strip did not draw: \(line.stripped)")
            return
        }
        click(large)
        #expect(choice.value == 3)
        click(cap)
        #expect(choice.value == 1, "the open cap is the first segment's")
        click(rule)
        #expect(choice.value == 1, "a rule chose a segment")
    }

    @Test("A disabled picker is no focus stop and takes no click")
    func disabled() {
        let presses = Presses()
        let choice = Choice(1)
        let harness = InputChainHarness(width: 40, height: 4)
        // No Tab: the button is the first focus stop.
        harness.play([KeyEvent(key: .enter)]) { pickerThenButton(choice, presses, disabled: true) }
        #expect(presses.count == 1, "the disabled picker took the focus")

        let line = harness.frame(pickerThenButton(choice, presses, disabled: true)).lines.first ?? ""
        let large = column(of: "L", in: line) ?? 0
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: large, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: large, y: 0))
        #expect(choice.value == 1)
    }

    @Test("The cursor's segment breathes while the picker has the focus, and nothing does without it")
    func theCursorBreathes() {
        let choice = Choice(2)
        let harness = InputChainHarness(width: 40, height: 3)
        harness.frame(picker(choice))
        let focused = harness.frame(picker(choice))
        let middle = column(of: "M", in: focused.lines.first ?? "") ?? -1
        #expect(focused.animatedCells.count == 1, "\(focused.animatedCells.map(\.offsetX))")
        #expect(
            focused.animatedCells.first.map { ($0.offsetX..<$0.offsetX + $0.width).contains(middle) } == true,
            "the breath is not on the selected segment the cursor starts on")

        harness.play([KeyEvent(key: .right)]) { picker(choice) }
        let moved = harness.frame(picker(choice))
        let large = column(of: "L", in: moved.lines.first ?? "") ?? -1
        #expect(
            moved.animatedCells.first.map { ($0.offsetX..<$0.offsetX + $0.width).contains(large) } == true,
            "the breath did not follow the cursor")

        let unfocused = renderToBuffer(picker(choice), context: makeBareRenderContext(width: 40, height: 3))
        #expect(unfocused.animatedCells.isEmpty)
    }

    @Test("The selected segment is drawn as a prominent button's label: bold")
    func theSelectionIsMarked() {
        // Unfocused, so the cursor's own drawing is not what is measured.
        let line = renderToBuffer(picker(Choice(2)), context: makeBareRenderContext(width: 40, height: 3))
            .lines.first ?? ""
        let segments = line.components(separatedBy: "│")
        #expect(segments.count == 3, "\(line.debugDescription)")
        let bold = "\u{1B}[1;"
        #expect(segments.count == 3 && segments[1].contains(bold), "\(segments.map(\.debugDescription))")
        #expect(segments.count == 3 && !segments[0].contains(bold) && !segments[2].contains(bold))
    }

    @Test("A palette's selection effect decides how the selection shows")
    func paletteEffects() {
        func drawn(_ effect: PaletteSelectionEffect) -> [String] {
            let view = Picker("", selection: .constant(2)) {
                VariantProbe(name: "a").tag(1)
                VariantProbe(name: "b").tag(2)
            }
            .pickerStyle(.palette)
            .paletteSelectionEffect(effect)
            return renderToBuffer(view, context: makeBareRenderContext(width: 30, height: 2)).lines
        }
        let automatic = drawn(.automatic)
        let custom = drawn(.custom)
        let filled = drawn(.symbolVariant(.fill))
        #expect(automatic != custom, "automatic marks the selection; custom draws none of its own")
        #expect(filled.first?.stripped.contains("B") == true, "the selected item's symbols take the variant")
        #expect(filled.first?.stripped.contains("a") == true, "and only the selected one's")
        #expect(custom.first?.stripped.contains("b") == true)
        #expect(custom == drawn(.symbolVariant(.fill)).map { $0.replacingOccurrences(of: "B", with: "b") })
    }
}
