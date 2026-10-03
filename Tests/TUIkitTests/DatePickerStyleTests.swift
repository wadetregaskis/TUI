//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DatePickerStyleTests.swift
//
//  `DatePickerStyle`: the field-shaped built-ins draw the editable field, and a
//  custom style builds the picker from its configuration.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkit

/// Shows what the configuration carries.
private struct ReportingStyle: DatePickerStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.label
            Text(configuration.minimumDate == nil ? "open" : "from")
            Text(configuration.maximumDate == nil ? "open" : "to")
            Text(configuration.displayedComponents == .date ? "date" : "other")
        }
    }
}

@MainActor
@Suite("DatePickerStyle")
struct DatePickerStyleTests {
    private func line<V: View>(_ view: V) -> String {
        renderToBuffer(view, context: makeRenderContext(width: 40, height: 2)).lines.first?.stripped ?? ""
    }

    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("The field-shaped built-ins draw the field the picker always drew")
    func fieldShaped() {
        let picker = DatePicker("When", selection: .constant(date), displayedComponents: .date)
        let field = line(picker)
        for styled in [
            line(picker.datePickerStyle(.automatic)), line(picker.datePickerStyle(.field)),
            line(picker.datePickerStyle(.stepperField)), line(picker.datePickerStyle(.compact)),
        ] {
            #expect(styled == field)
        }
    }

    @Test("A custom style sees the label, the bounds and the components")
    func customStyle() {
        let bounded = DatePicker(
            "When", selection: .constant(date), in: date.addingTimeInterval(-60)..., displayedComponents: .date)
        #expect(line(bounded.datePickerStyle(ReportingStyle())) == "When from open date")
        let unbounded = DatePicker("When", selection: .constant(date), displayedComponents: .hourAndMinute)
        #expect(line(unbounded.datePickerStyle(ReportingStyle())) == "When open open other")
    }
}
