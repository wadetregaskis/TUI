//  🖥️ TUI — A Terminal UI framework for Swift
//  OwnDisabledLabelTests.swift
//
//  A picker's or date picker's own `.disabled(_:)`, which returns the control
//  rather than a view under the modifier, reaches its label in `\.isEnabled`,
//  as the modifier does: through the label every labelled control draws
//  (`_CollapsingLabel`), a stepper's and a slider's included.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
import TUIPickers
import TUITesting

/// Says whether the environment it is drawn in is enabled.
private struct EnabledWord: View {
    let name: String
    @Environment(\.isEnabled) private var isEnabled
    var body: some View { Text(verbatim: "\(name)=\(isEnabled ? "on" : "off")") }
}

/// A date picker style whose body reads `\.isEnabled`, as SwiftUI's custom
/// styles do.
private struct WordDatePickerStyle: DatePickerStyle {
    func makeBody(configuration: Configuration) -> some View {
        EnabledWord(name: "styled")
    }
}

@MainActor
@Suite("A picker's own .disabled reaches its label")
struct OwnDisabledLabelTests {
    /// Seen failing before: `styled=on`.
    @Test("A disabled DatePicker's custom style reads isEnabled as false")
    func datePickerStyle() {
        let app = TestApp(width: 60, height: 6) {
            DatePicker("When", selection: .constant(Date(timeIntervalSince1970: 0)))
                .disabled(true)
                .datePickerStyle(WordDatePickerStyle())
        }
        #expect(app.screen.contains("styled=off"), "\(app.screen)")
    }

    /// Seen failing before: `dp=on`.
    @Test("A disabled DatePicker's label reads isEnabled as false")
    func datePickerLabel() {
        let app = TestApp(width: 60, height: 6) {
            DatePicker(selection: .constant(Date(timeIntervalSince1970: 0))) { EnabledWord(name: "dp") }
                .disabled(true)
        }
        #expect(app.screen.contains("dp=off"), "\(app.screen)")
    }

    /// Seen failing before: `pk=on`.
    @Test("A disabled Picker's label reads isEnabled as false")
    func pickerLabel() {
        let app = TestApp(width: 60, height: 6) {
            Picker(selection: .constant(1)) {
                Text(verbatim: "a").tag(1)
            } label: {
                EnabledWord(name: "pk")
            }
            .disabled(true)
        }
        #expect(app.screen.contains("pk=off"), "\(app.screen)")
    }
}
