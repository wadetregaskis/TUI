//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerSegmentsTests.swift
//
//  The segmented and palette picker styles: the options side by side as
//  touching buttons, the selected one prominent, and a palette's selection
//  effect deciding how the selection shows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// The picker's selection, outside the view.
private final class Choice: @unchecked Sendable {
    var value = 1
    var binding: Binding<Int> { Binding(get: { self.value }, set: { self.value = $0 }) }
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

    @Test("The options sit side by side on one row, after the label")
    func oneRow() {
        let drawn = InputChainHarness(width: 40, height: 3).frame(picker(Choice())).lines.map(\.stripped)
        let row = drawn.first { $0.contains("S") } ?? ""
        #expect(row.contains("Size") && row.contains("M") && row.contains("L"), "\(drawn)")
    }

    @Test("Return on a segment, or a click on it, selects it")
    func selecting() {
        let choice = Choice()
        let harness = InputChainHarness(width: 40, height: 3)
        // Focus starts on the first segment; Tab to the second, Return.
        harness.play([KeyEvent(key: .tab), KeyEvent(key: .enter)]) { picker(choice) }
        #expect(choice.value == 2)

        let row = harness.frame(picker(choice)).lines.first?.stripped ?? ""
        let column = row.firstIndex(of: "L").map { row.distance(from: row.startIndex, to: $0) } ?? 0
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: column, y: 0))
        harness.mouse(MouseEvent(button: .left, phase: .released, x: column, y: 0))
        #expect(choice.value == 3)
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
            return renderToBuffer(view, context: makeRenderContext(width: 30, height: 2)).lines
        }
        let automatic = drawn(.automatic)
        let custom = drawn(.custom)
        let filled = drawn(.symbolVariant(.fill))
        #expect(automatic != custom, "automatic marks the selection; custom draws none of its own")
        #expect(filled.first?.stripped.contains("B") == true, "the selected item's symbols take the variant")
        #expect(filled.first?.stripped.contains("a") == true, "and only the selected one's")
        #expect(custom.first?.stripped.contains("b") == true)
    }
}
