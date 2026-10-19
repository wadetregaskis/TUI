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

    @Test("labelsHidden written on a LabeledContent row hides its label, out of the column, its value in the value column")
    func hiddenLabelRow() {
        // Measured: the hidden label takes no part in the label column, and the
        // row's value starts where the other rows' values do.
        let out = lines(
            Form {
                LabeledContent("A much longer label", value: "Alice").labelsHidden()
                LabeledContent("Email", value: "a@b.c")
            })
        #expect(!out.contains { $0.contains("longer") }, "\(out)")
        #expect(column(of: "a@b.c", in: out) == 6 && column(of: "Alice", in: out) == 6, "\(out)")
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

    /// The modifiers of ``rowsUnderMetadataModifiers()``, each written on `row`.
    private static func metadataModified(_ row: some View) -> [(String, AnyView)] {
        [
            ("onKeyPress", AnyView(row.onKeyPress(.space) { .handled })),
            ("transition", AnyView(row.transition(.opacity))),
            ("zIndex", AnyView(row.zIndex(1))),
            ("layoutPriority", AnyView(row.layoutPriority(1))),
            ("focusedValue", AnyView(row.focusedValue(\.formRowProbe, 1))),
            ("preference", AnyView(row.preference(key: FormRowProbeKey.self, value: 1))),
            ("onGeometryChange", AnyView(row.onGeometryChange(for: Int.self) { $0.size.width } action: { _ in })),
            ("onModifierKeysChanged", AnyView(row.onModifierKeysChanged { _, _ in })),
            ("draggable", AnyView(row.draggable("payload"))),
            ("dropDestination", AnyView(row.dropDestination(for: String.self) { _, _ in true })),
            ("alert", AnyView(row.alert("Sure?", isPresented: .constant(false)) { Button("OK") {} })),
            ("confirmationDialog", AnyView(row.confirmationDialog("Sure?", isPresented: .constant(false)) { Button("OK") {} })),
            ("sheet", AnyView(row.sheet(isPresented: .constant(false)) { Text("Sheet") })),
            ("popover", AnyView(row.popover(isPresented: .constant(false)) { Text("Popover") })),
            ("badge", AnyView(row.badge(3))),
            ("focusSection", AnyView(row.focusSection())),
            ("onKeyPress under padding", AnyView(row.onKeyPress(.space) { .handled }.padding(.leading, 0))),
        ]
    }

    @Test("A key press, a transition, a z-index, a layout priority, a focused value, a presentation or a drag written on a row keeps it in its place")
    func rowsUnderMetadataModifiers() {
        // Measured: SwiftUI's form keeps a row in place under each of these
        // it was tried with, in both styles (`Tools/SwiftUIProbes/Form
        // rows/more-modifiers.out`). Each made the row a plain one, drawn
        // whole, its label out of the column.
        func rows(_ row: some View) -> [String] {
            lines(Form { LabeledContent("Email address", value: "a@b.c"); row })
        }
        let labelled = LabeledContent("Name", value: "Alice")
        for (name, row) in Self.metadataModified(labelled) {
            let out = rows(row)
            #expect(column(of: "Alice", in: out) == 14 && column(of: "Name", in: out) == 9, "labelled content, \(name): \(out)")
        }
        let picker = Picker("Mode", selection: .constant(1)) { Text("One").tag(1) }
        for (name, row) in Self.metadataModified(picker) {
            let out = rows(row)
            #expect(column(of: "Mode", in: out) == 9 && column(of: "One", in: out).map { $0 > 13 } == true, "picker, \(name): \(out)")
        }
        let toggle = Toggle("Wi-Fi", isOn: .constant(true))
        let bareToggle = column(of: "Wi-Fi", in: rows(toggle))
        for (name, row) in Self.metadataModified(toggle) {
            #expect(column(of: "Wi-Fi", in: rows(row)) == bareToggle, "toggle, \(name)")
        }
        let button = Button("Sign Out") {}
        let bareButton = rows(button).first { $0.contains("Sign Out") }
        #expect(bareButton?.hasPrefix(" ") == true)
        for (name, row) in Self.metadataModified(button) {
            #expect(rows(row).first { $0.contains("Sign Out") } == bareButton, "button, \(name)")
        }
    }

    @Test("A default focus, a focus scope or a preference for the default focus written on a row keeps it in its place")
    func rowsUnderFocusScopeModifiers() {
        let out = lines(FocusScopedRows(row: LabeledContent("Name", value: "Alice")))
        let rows = out.filter { $0.contains("Alice") }
        #expect(rows.count == 3, "\(out)")
        for row in rows {
            #expect(row.hasPrefix("         Name Alice"), "\(out)")
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

/// A form whose rows after the first are `row` under a default focus, a focus
/// scope and a preference for the default focus in one, which need a focus
/// state and a namespace of a view's own.
private struct FocusScopedRows<Row: View>: View {
    let row: Row
    @FocusState private var isFocused: Bool
    @Namespace private var namespace

    var body: some View {
        Form {
            LabeledContent("Email address", value: "a@b.c")
            row.defaultFocus($isFocused, true)
            row.focusScope(namespace)
            row.prefersDefaultFocus(in: namespace)
        }
    }
}

/// A focused value for a form row to publish.
private struct FormRowProbeFocusedKey: FocusedValueKey {
    typealias Value = Int
}

extension FocusedValues {
    fileprivate var formRowProbe: Int? {
        get { self[FormRowProbeFocusedKey.self] }
        set { self[FormRowProbeFocusedKey.self] = newValue }
    }
}

/// A preference for a form row to set.
private struct FormRowProbeKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value = nextValue() }
}
