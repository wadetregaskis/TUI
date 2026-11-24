//  🖥️ TUI — A Terminal UI framework for Swift
//  CaseControlView.swift
//
//  The perf cases' control pages: a grid, forms, a column of buttons, the
//  value controls, a menu (`CaseLeaf.isControl`). Every string shown is the
//  rows' own or written here verbatim: a case adds nothing to a translation
//  table (B-PERFCASE-5).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUI

/// One of the control leaves, over the case's rows.
struct CaseControlView: View {
    let leaf: CaseLeaf
    let rows: CaseRows

    var body: some View {
        switch leaf {
        case .grid:
            AnyView(CaseGrid(rows: rows))
        case .formGrouped:
            AnyView(CaseForm(rows: rows).formStyle(.grouped))
        case .formColumns:
            AnyView(CaseForm(rows: rows).formStyle(.columns))
        case .controls:
            AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.rows) { row in Button(rows.title(row)) {} }
                })
        case .values:
            AnyView(VStack(alignment: .leading, spacing: 0) { CaseValueControls(rows: rows) })
        case .menu:
            AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    Menu(Self.menuTitle) {
                        ForEach(rows.rows) { row in Button(rows.title(row)) {} }
                    }
                    Text(verbatim: Self.menuTitle)
                })
        case .picker:
            AnyView(
                VStack(alignment: .leading, spacing: 0) {
                    Stepper(
                        Self.pickerLabels[0], value: Binding(get: { rows.amount }, set: { rows.amount = $0 }),
                        in: 0...1_000)
                    Picker(
                        Self.pickerLabels[1],
                        selection: Binding(get: { rows.selection ?? 0 }, set: { rows.selection = $0 })
                    ) {
                        ForEach(rows.rows) { row in Text(verbatim: rows.title(row)).tag(row.id) }
                    }
                    Text(verbatim: Self.menuTitle)
                })
        default:
            AnyView(Text(verbatim: "\(leaf.rawValue) is not a control leaf"))
        }
    }

    /// The menu's title, as a string rather than a literal: a literal is a
    /// localization key, and a case adds none.
    static let menuTitle = "Actions"

    /// The picker page's stepper and picker titles, likewise.
    static let pickerLabels = ["Amount", "Row"]
}

/// The rows in a `Grid`, four cells a row.
private struct CaseGrid: View {
    let rows: CaseRows

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 1, verticalSpacing: 0) {
            ForEach(rows.rows) { row in
                GridRow {
                    Text(verbatim: rows.name(row))
                    Text(verbatim: rows.slug(row))
                    Text(verbatim: rows.status(row))
                    Text(verbatim: "\(rows.size(row))")
                }
            }
        }
    }
}

/// A form: the value controls in a section, then a toggle per row.
private struct CaseForm: View {
    let rows: CaseRows

    var body: some View {
        Form {
            Section {
                CaseValueControls(rows: rows)
            } header: {
                Text(verbatim: "Values")
            }
            Section {
                ForEach(rows.rows) { row in
                    Toggle(rows.title(row), isOn: checked(row.id))
                }
            } header: {
                Text(verbatim: "Rows")
            }
        }
    }

    private func checked(_ id: Int) -> Binding<Bool> {
        Binding(
            get: { rows.checked.contains(id) },
            set: { isOn in
                if isOn { rows.checked.insert(id) } else { rows.checked.remove(id) }
            })
    }
}

/// A `Stepper`, a `Slider` and a `DatePicker`, bound to the rows' values.
///
/// The date picker is drawn in UTC with a Gregorian calendar, in a style
/// that draws no "today" (`.stepperField`), so its bytes depend neither on the
/// machine's time zone nor on the day the case is played.
private struct CaseValueControls: View {
    let rows: CaseRows

    var body: some View {
        Stepper(Self.labels[0], value: Binding(get: { rows.amount }, set: { rows.amount = $0 }), in: 0...1_000)
        Slider(value: Binding(get: { rows.level }, set: { rows.level = $0 }), in: 0...100, step: 1) {
            Text(verbatim: Self.labels[1])
        }
        DatePicker(
            Self.labels[2], selection: Binding(get: { rows.day }, set: { rows.day = $0 }),
            displayedComponents: .date
        )
        .datePickerStyle(.stepperField)
        .environment(\.timeZone, Self.utc)
        .environment(\.calendar, Self.calendar)
    }

    static let labels = ["Amount", "Level", "Date"]
    static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()
}
