//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PickerCurrentValueLabelTests.swift
//
//  Picker's `currentValueLabel:` initialisers: a menu picker's collapsed
//  control shows that label in place of the selected option's; the styles that
//  show every option do not use it.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitFoundation
import TUIkitPickers
@testable import TUIkitTestSupport

@MainActor
@Suite("Picker currentValueLabel")
struct PickerCurrentValueLabelTests {
    private func text<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 40, height: 6)).lines.map(\.stripped).joined(separator: "\n")
    }

    @Test("A menu picker shows the current-value label in place of the selection's")
    func menuShowsIt() {
        let picker = Picker("Size", selection: .constant(2)) {
            Text("Small").tag(1)
            Text("Large").tag(2)
        } currentValueLabel: {
            Text("L")
        }
        .pickerStyle(.menu)
        let drawn = text(picker)
        #expect(drawn.contains("Size") && drawn.contains(" L "), "\(drawn)")
        #expect(!drawn.contains("Large"))
    }

    @Test("Without one, the selected option's label is shown")
    func menuWithout() {
        let drawn = text(
            Picker("Size", selection: .constant(2)) {
                Text("Small").tag(1)
                Text("Large").tag(2)
            }.pickerStyle(.menu))
        #expect(drawn.contains("Large"))
    }

    @Test("A radio group shows every option and does not use it")
    func radioGroupIgnoresIt() {
        let options = Picker(selection: .constant(1)) {
            Text("Small").tag(1)
            Text("Large").tag(2)
        } label: {
            Text("Size")
        } currentValueLabel: {
            Text("current")
        }
        .pickerStyle(.radioGroup)
        let drawn = text(options)
        #expect(drawn.contains("Small") && drawn.contains("Large") && !drawn.contains("current"))
    }

    @Test("The SF Symbol forms take one too")
    func symbolForm() {
        let drawn = text(
            Picker("Size", systemImage: "ruler", selection: .constant(1)) {
                Text("Small").tag(1)
            } currentValueLabel: {
                Text("S")
            }.pickerStyle(.menu))
        #expect(drawn.contains("Size") && drawn.contains(" S "), "\(drawn)")
    }
}

@MainActor
@Suite("horizontalRadioGroupLayout")
struct HorizontalRadioGroupLayoutTests {
    private func lines<V: View>(_ view: V) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: 40, height: 6)).lines.map(\.stripped)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    @Test("A radio-group picker lays its options out in a row")
    func row() {
        let picker = Picker("Size", selection: .constant(1)) {
            Text("S").tag(1)
            Text("M").tag(2)
            Text("L").tag(3)
        }
        .pickerStyle(.radioGroup)
        #expect(lines(picker).count == 3, "a column by default")
        let row = lines(picker.horizontalRadioGroupLayout())
        #expect(row.count == 1, "\(row)")
        #expect(row.first.map { $0.contains("S") && $0.contains("M") && $0.contains("L") } == true)
    }
}
