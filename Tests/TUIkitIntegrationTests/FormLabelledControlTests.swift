//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormLabelledControlTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitTestSupport

/// A labelled control written bare in a form is a field row, as SwiftUI's form
/// lays it out (measured on macOS 15.8, `Tools/SwiftUIProbes/Form rows`): a
/// `Picker` of every style, a `Slider`, a `Stepper`, a `DatePicker` and a
/// `ColorPicker` put their label in the label column, right-aligned to the
/// others, and the control in the value column after it; in a grouped form the
/// label leads the row and the control trails it. Each was a plain row, its
/// label drawn beside the control wherever the row began (the semantic audit's
/// verifier finding on labelled controls).
@MainActor
@Suite("Form: labelled controls")
struct FormLabelledControlTests {
    private func lines(_ view: some View, width: Int = 60, height: Int = 24) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map { $0.stripped }
    }

    /// A date well away from midnight in every time zone.
    private static let date = Date(timeIntervalSince1970: 200 * 86_400)

    /// The labelled controls, each labelled `label`.
    private static func controls(_ label: String) -> [(String, AnyView)] {
        [
            ("menu picker", AnyView(Picker(label, selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) })),
            (
                "segmented picker",
                AnyView(
                    Picker(label, selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }
                        .pickerStyle(.segmented))
            ),
            (
                "radio group picker",
                AnyView(
                    Picker(label, selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }
                        .pickerStyle(.radioGroup))
            ),
            ("slider", AnyView(Slider(value: .constant(0.5)) { Text(label) })),
            ("stepper", AnyView(Stepper(label, value: .constant(3)))),
            ("date picker", AnyView(DatePicker(label, selection: .constant(date), displayedComponents: .date))),
            ("colour picker", AnyView(ColorPicker(label, selection: .constant(.red)))),
        ]
    }

    /// The first line holding `text`.
    private func line(with text: String, in out: [String]) -> String {
        out.first { $0.contains(text) } ?? ""
    }

    @Test("A labelled control's label is in the label column, the control in the value column")
    func fieldRowInColumns() {
        for (name, control) in Self.controls("Notify me") {
            let out = lines(Form { LabeledContent("Email address", value: "a@b.c"); control })
            // "Email address" is the column: thirteen cells, then the gap, then
            // the value column at fourteen.
            let row = Array(line(with: "Notify me", in: out))
            #expect(String(row.prefix(14)) == "    Notify me ", "\(name): \(out)")
            #expect(row.count > 14 && row[14] != " ", "\(name): the control is not in the value column: \(out)")
        }
    }

    @Test("A radio group picker's options line up in the value column")
    func radioGroupInValueColumn() {
        let out = lines(
            Form {
                LabeledContent("Email address", value: "a@b.c")
                Picker("Notify me", selection: .constant(1)) { Text("One").tag(1); Text("Two").tag(2) }
                    .pickerStyle(.radioGroup)
            })
        let first = line(with: "One", in: out)
        let second = line(with: "Two", in: out)
        #expect(first.firstRange(of: "One")?.lowerBound.utf16Offset(in: first) == second.firstRange(of: "Two")?.lowerBound.utf16Offset(in: second), "\(out)")
        #expect(second.hasPrefix(String(repeating: " ", count: 14)) && Array(second)[14] != " ", "\(out)")
    }

    @Test("In a grouped form a labelled control's label leads the row and the control trails it")
    func fieldRowInGroupedForm() {
        for (name, control) in Self.controls("Notify me") where name != "slider" && name != "colour picker" {
            let out = lines(
                Form { Section { LabeledContent("Email address", value: "a@b.c"); control } }.formStyle(.grouped))
            let row = line(with: "Notify me", in: out)
            #expect(row.hasPrefix("│  Notify me "), "\(name): \(out)")
            // The control ends where the value above it ends: at the trailing
            // edge, two cells inside the box.
            #expect(row.hasSuffix("  │") && !row.hasSuffix("   │"), "\(name): \(out)")
        }
    }

    @Test("labelsHidden on a labelled control hides its label and keeps the control in the value column")
    func hiddenLabel() {
        let out = lines(
            Form {
                LabeledContent("Email address", value: "a@b.c")
                Picker("A much longer label", selection: .constant(1)) { Text("One").tag(1) }.labelsHidden()
            })
        #expect(!out.contains { $0.contains("longer") }, "\(out)")
        let row = Array(line(with: "One", in: out))
        #expect(row.count > 14 && String(row.prefix(14)).allSatisfy { $0 == " " } && row[14] != " ", "\(out)")
    }

    @Test("A form whose labels are hidden draws the labelled controls with no label column")
    func formWideHiddenLabels() {
        let out = lines(
            Form {
                LabeledContent("Email address", value: "a@b.c")
                Stepper("Copies", value: .constant(3))
            }
            .labelsHidden())
        #expect(!out.contains { $0.contains("Copies") }, "\(out)")
        #expect(line(with: "3", in: out).first.map { $0 != " " } == true, "\(out)")
    }

    @Test("A modifier written on a labelled control keeps it a field row")
    func modifiedFieldRow() {
        let picker = Picker("Notify me", selection: .constant(1)) { Text("One").tag(1) }
        for (name, row) in [
            ("onChange", AnyView(picker.onChange(of: 1) {})),
            ("help", AnyView(picker.help("When to notify"))),
            ("padding", AnyView(picker.padding(.leading, 2))),
        ] {
            let out = lines(Form { LabeledContent("Email address", value: "a@b.c"); row })
            let labelEnd = line(with: "Notify me", in: out).firstRange(of: "Notify me").map {
                $0.upperBound.utf16Offset(in: line(with: "Notify me", in: out))
            }
            #expect(labelEnd == 13, "\(name): \(out)")
        }
    }

    /// A date picker style of the app's own, which places the label itself.
    private struct LabelledDateStyle: DatePickerStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 1) {
                configuration.label
                Text("[date]")
            }
        }
    }

    @Test("A date picker under a style of the app's own is a row drawn whole, its label where the style puts it")
    func customDateStyleIsAPlainRow() {
        let out = lines(
            Form {
                LabeledContent("Email address", value: "a@b.c")
                DatePicker("Due", selection: .constant(Self.date), displayedComponents: .date)
                    .datePickerStyle(LabelledDateStyle())
            })
        #expect(line(with: "[date]", in: out).hasPrefix("Due [date]"), "\(out)")
    }
}
