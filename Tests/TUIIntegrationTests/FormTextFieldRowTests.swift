//  🖥️ TUI — A Terminal UI framework for Swift
//  FormTextFieldRowTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUI
@testable import TUITestSupport

/// A text field written bare in a form is a field row, as SwiftUI's form lays it
/// out in both styles (measured on macOS 15.8, `Tools/SwiftUIProbes/Form rows/
/// textfield-title.out`): its title in the label column, and only its prompt as
/// the empty field's placeholder. It was a plain row whose title was only the
/// placeholder, so a field with anything typed in it showed no title at all.
@MainActor
@Suite("Form: text field rows")
struct FormTextFieldRowTests {
    private func lines(_ view: some View, width: Int = 60, height: Int = 12) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map { $0.stripped }
    }

    /// The first line holding `text`.
    private func line(with text: String, in out: [String]) -> String {
        out.first { $0.contains(text) } ?? ""
    }

    /// How many times `text` is drawn.
    private func count(of text: String, in out: [String]) -> Int {
        out.reduce(0) { $0 + $1.components(separatedBy: text).count - 1 }
    }

    /// A number format whose output does not depend on where the test runs.
    private static let number = IntegerFormatStyle<Int>().locale(Locale(identifier: "en_US"))

    /// The fields, each titled "Name", holding `text` — and, with text, a field
    /// editing a number, which is never empty.
    private static func fields(_ text: String) -> [(String, AnyView)] {
        var fields: [(String, AnyView)] = [
            ("text field", AnyView(TextField("Name", text: .constant(text)))),
            ("vertical text field", AnyView(TextField("Name", text: .constant(text), axis: .vertical))),
            ("secure field", AnyView(SecureField("Name", text: .constant(text)))),
        ]
        if !text.isEmpty {
            fields.append(("value field", AnyView(TextField("Name", value: .constant(42), format: number))))
        }
        return fields
    }

    @Test("A text field's title is in the label column, the field in the value column")
    func titleInLabelColumn() {
        for (name, field) in Self.fields("typed") {
            let out = lines(Form { LabeledContent("Email address", value: "a@b.c"); field })
            // "Email address" is the column: thirteen cells, then the gap, then
            // the value column at fourteen.
            let row = Array(line(with: "Name", in: out))
            #expect(String(row.prefix(14)) == "         Name ", "\(name): \(out)")
            #expect(row.count > 14 && row[14] != " ", "\(name): the field is not in the value column: \(out)")
        }
    }

    @Test("A titled field draws the row a LabeledContent around an untitled one does")
    func sameAsLabeledContent() {
        for text in ["", "typed"] {
            let bare = lines(Form { LabeledContent("Email address", value: "a@b.c"); TextField("Name", text: .constant(text)) })
            let wrapped = lines(
                Form {
                    LabeledContent("Email address", value: "a@b.c")
                    LabeledContent("Name") { TextField("", text: .constant(text)) }
                })
            #expect(bare == wrapped, "\(text.isEmpty ? "empty" : "typed")")
        }
    }

    @Test("In a form an empty field's placeholder is its prompt, never its title")
    func promptOnlyPlaceholder() {
        for (name, field) in Self.fields("") {
            let out = lines(Form { LabeledContent("Email address", value: "a@b.c"); field })
            #expect(count(of: "Name", in: out) == 1, "\(name): the title is drawn as a placeholder too: \(out)")
        }
        let out = lines(
            Form {
                LabeledContent("Email address", value: "a@b.c")
                TextField("Name", text: .constant(""), prompt: Text("Required"))
            })
        let row = line(with: "Name", in: out)
        #expect(row.hasPrefix("         Name ") && row.contains("Required"), "\(out)")
    }

    @Test("Outside a form the title is still the empty field's placeholder")
    func titlePlaceholderOutsideForm() {
        for (name, field) in Self.fields("") {
            #expect(count(of: "Name", in: lines(VStack { field })) == 1, "\(name)")
        }
    }

    @Test("A field with an empty title and a prompt is in the value column")
    func untitledFieldInValueColumn() {
        let out = lines(
            Form {
                LabeledContent("Email address", value: "a@b.c")
                TextField("", text: .constant(""), prompt: Text("Required"))
            })
        let row = Array(line(with: "Required", in: out))
        #expect(String(row.prefix(14)) == String(repeating: " ", count: 14) && row[14] != " ", "\(out)")
    }

    @Test("In a grouped form a text field's title leads the row")
    func titleLeadsGroupedRow() {
        for (name, field) in Self.fields("typed") {
            let out = lines(
                Form { Section { LabeledContent("Email address", value: "a@b.c"); field } }.formStyle(.grouped))
            #expect(line(with: "Name", in: out).hasPrefix("│  Name "), "\(name): \(out)")
        }
    }

    @Test("labelsHidden() on a field in a form draws no title, as label or placeholder")
    func labelsHiddenDrawsNoTitle() {
        let out = lines(
            Form {
                LabeledContent("Email address", value: "a@b.c")
                TextField("Name", text: .constant("")).labelsHidden()
            })
        #expect(count(of: "Name", in: out) == 0, "\(out)")
    }
}
