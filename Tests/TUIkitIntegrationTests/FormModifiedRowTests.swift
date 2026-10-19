//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FormModifiedRowTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitTestSupport

/// A modifier written on a form row keeps the row in its place, as SwiftUI's
/// form keeps it (measured on macOS 15.8 for every modifier tried, the label in
/// the label column and the modifier applied to the row: the semantic audit's
/// item 8). These are the modifiers that are no ``ContentRewrapping`` — padding,
/// a background, help, a tag and an id — which left the row a plain one, its
/// label out of the column, until the form put them back around the row it lays
/// out.
@MainActor
@Suite("Form: modified rows")
struct FormModifiedRowTests {
    private func lines(_ view: some View, width: Int = 50, height: Int = 20) -> [String] {
        renderToBuffer(view, context: makeRenderContext(width: width, height: height))
            .lines.map { $0.stripped }
    }

    /// Where `text` starts on the first line holding it, in cells.
    private func column(of text: String, in out: [String]) -> Int? {
        guard let line = out.first(where: { $0.contains(text) }), let range = line.firstRange(of: text) else { return nil }
        return line.distance(from: line.startIndex, to: range.lowerBound)
    }

    /// A form whose first row is `modified` — `Name`: `Alice`, under some
    /// modifier — and whose second is a bare row with a longer label.
    private func form(_ modified: some View) -> [String] {
        lines(
            Form {
                modified
                LabeledContent("Email address", value: "a@b.c")
            })
    }

    @Test("A background, help, a tag or an id written on a LabeledContent row keeps it on the pillar")
    func labeledRowUnderReadOnlyModifiers() {
        let row = LabeledContent("Name", value: "Alice")
        for (name, out) in [
            ("background colour", form(row.background(.red))),
            ("background view", form(row.background { Text("") })),
            ("help", form(row.help("The name"))),
            ("tag", form(row.tag(1))),
            ("id", form(row.id(1))),
            ("help and a tag", form(row.tag(1).help("The name"))),
            ("a tag under foregroundStyle", form(row.tag(1).foregroundStyle(.red))),
        ] {
            #expect(column(of: "Alice", in: out) != nil && column(of: "Alice", in: out) == column(of: "a@b.c", in: out), "\(name): \(out)")
            #expect(out.first { $0.contains("Alice") }?.hasPrefix("         Name ") == true, "\(name): \(out)")
        }
    }

    @Test("A leading padding on a LabeledContent row widens the label column; the labels stay in it")
    func paddedLabeledRow() {
        // Measured: `.padding(.leading, 40)` on the row with the longer label
        // moved the column's edge 40 points on, the other row's label with it,
        // and both values after it.
        let row = LabeledContent("Name", value: "Alice")
        let narrow = form(row.padding(.leading, 3))
        let wide = form(row.padding(.leading, 12))
        let all = form(row.padding())
        for (name, out) in [("narrow", narrow), ("wide", wide), ("all edges", all)] {
            #expect(column(of: "Alice", in: out) != nil && column(of: "Alice", in: out) == column(of: "a@b.c", in: out), "\(name): \(out)")
            let nameEnd = column(of: "Name", in: out).map { $0 + 4 }
            let emailEnd = column(of: "Email address", in: out).map { $0 + 13 }
            #expect(nameEnd != nil && nameEnd == emailEnd, "\(name): the labels' trailing edges: \(out)")
        }
        // Three cells of padding fit in front of "Name" within the column
        // "Email address" sets; twelve do not, and the column grows to take them.
        #expect(column(of: "Email address", in: narrow) == 0, "\(narrow)")
        #expect(column(of: "Name", in: wide) == 12 && column(of: "Email address", in: wide) == 3, "\(wide)")
        // `.padding()` pads the row's other edges too: a blank line above it.
        #expect(all.first?.trimmingCharacters(in: .whitespaces).isEmpty == true, "\(all)")
    }

    @Test("A padded label column keeps the other rows' values in line when a label is empty")
    func paddingFillsTheColumn() {
        // The row's label takes no width, and its padding is the whole column:
        // the gap after the label still separates its value from the column.
        let out = lines(
            Form {
                LabeledContent { Text("Alice") } label: { EmptyView() }.padding(.leading, 5)
                LabeledContent("Email", value: "a@b.c")
            })
        #expect(column(of: "Alice", in: out) == 6 && column(of: "a@b.c", in: out) == 6, "\(out)")
    }

    @Test("Padding, help, a tag or an id written on a Toggle row keeps it in the control column")
    func modifiedControlRow() {
        func toggleColumn(_ toggle: some View) -> Int? {
            column(of: "Wi-Fi", in: lines(Form { LabeledContent("Email address", value: "a@b.c"); toggle }))
        }
        let toggle = Toggle("Wi-Fi", isOn: .constant(true))
        let bare = toggleColumn(toggle)
        #expect(bare != nil && bare! > 13)
        for (name, column) in [
            ("background", toggleColumn(toggle.background(.red))),
            ("help", toggleColumn(toggle.help("Wireless"))),
            ("tag", toggleColumn(toggle.tag(1))),
            ("id", toggleColumn(toggle.id(1))),
        ] {
            #expect(column == bare, "\(name)")
        }
        // Measured: a toggle's padding moves it on from the control column, by
        // as much as it pads.
        #expect(toggleColumn(toggle.padding(.leading, 2)) == bare.map { $0 + 2 })
    }

    @Test("A lifecycle, event or focus modifier or an overlay written on a LabeledContent row keeps it on the pillar")
    func labeledRowUnderEventModifiers() {
        let row = LabeledContent("Name", value: "Alice")
        for (name, out) in [
            ("onAppear", form(row.onAppear {})),
            ("onDisappear", form(row.onDisappear {})),
            ("task", form(row.task {})),
            ("onChange", form(row.onChange(of: 1) {})),
            ("onTapGesture", form(row.onTapGesture {})),
            ("onHover", form(row.onHover { _ in })),
            ("focusable", form(row.focusable())),
            ("onSubmit", form(row.onSubmit {})),
            ("contextMenu", form(row.contextMenu { Button("Copy") {} })),
            ("overlay", form(row.overlay { Text("") })),
            ("onChange under padding", form(row.onChange(of: 1) {}.padding(.leading, 1))),
        ] {
            #expect(column(of: "Alice", in: out) != nil && column(of: "Alice", in: out) == column(of: "a@b.c", in: out), "\(name): \(out)")
            #expect(out.first { $0.contains("Alice") }?.contains("Name ") == true, "\(name): \(out)")
            #expect(column(of: "Name", in: out).map { $0 + 4 } == column(of: "Email address", in: out).map { $0 + 13 }, "\(name): \(out)")
        }
    }

    @Test("A change action on a Toggle row, or a shortcut on a Button row, keeps it in its place")
    func controlAndButtonRowsUnderEventModifiers() {
        func rows(_ row: some View) -> [String] {
            lines(Form { LabeledContent("Account email", value: "ada@example.com"); row })
        }
        let toggle = Toggle("Wi-Fi", isOn: .constant(true))
        #expect(column(of: "Wi-Fi", in: rows(toggle.onChange(of: 1) {})) == column(of: "Wi-Fi", in: rows(toggle)))
        let button = Button("Sign Out") {}
        let bare = rows(button).first { $0.contains("Sign Out") }
        #expect(bare?.hasPrefix(" ") == true)
        #expect(rows(button.keyboardShortcut(.defaultAction)).first { $0.contains("Sign Out") } == bare)
    }

    @Test("Help written on a Button row keeps it right-aligned")
    func modifiedButtonRow() {
        func buttonRow(_ button: some View) -> String {
            lines(Form { LabeledContent("Account email", value: "ada@example.com"); button })
                .first { $0.contains("Sign Out") } ?? ""
        }
        let bare = buttonRow(Button("Sign Out") {})
        #expect(bare.hasPrefix(" "))
        #expect(buttonRow(Button("Sign Out") {}.help("Leave")) == bare)
    }
}
