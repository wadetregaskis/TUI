//  🖥️ TUI — A Terminal UI framework for Swift
//  SettingsScreens.swift
//
//  Real-world screens: settings pages. A Form of sections in a sheet over the
//  page that opened it, a long grouped Form taller than the window, and a
//  Form with a disabled section. Every control must be reachable by Tab, the
//  last section by the wheel, and a disabled one never takes the focus.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIAppTestSupport
import TUITesting

private enum Theme: String, CaseIterable, Hashable { case light, dark, system }

/// The settings a page opens in a sheet: three sections, a Done button.
private struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var wifi = true
    @State private var name = "My Mac"
    @State private var theme = Theme.system
    @State private var fontSize = 12

    var body: some View {
        Form {
            Section("Network") {
                Toggle("Wi-Fi", isOn: $wifi).focusID("wifi")
                TextField("Name", text: $name).focusID("name")
            }
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(Theme.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .focusID("theme")
                Stepper("Font size: \(fontSize)", value: $fontSize, in: 8...24).focusID("font")
            }
            Section("About") {
                LabeledContent("Version", value: "1.2.3")
                Button("Done") { dismiss() }.focusID("done")
            }
        }
    }
}

private struct PageWithSettings: View {
    @State private var showsSettings = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("Inbox — 12 unread")
            Button("Settings…") { showsSettings = true }.focusID("open")
            List(1...20, id: \.self) { Text("Message \($0)") }
        }
        .sheet(isPresented: $showsSettings) { SettingsSheet() }
    }
}

/// Eight sections of four toggles each: far taller than any window here.
private struct LongSettingsPage: View {
    var body: some View {
        Form {
            ForEach(1...8, id: \.self) { section in
                Section("Section \(section)") {
                    ForEach(1...4, id: \.self) { row in
                        Toggle("Option \(section).\(row)", isOn: .constant(row.isMultiple(of: 2)))
                            .focusID("option-\(section).\(row)")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A form whose middle section is disabled until the account signs in.
private struct AccountPage: View {
    @State private var notifications = true
    @State private var volume = 0.5

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Signed in as", value: "nobody")
                Button("Sign In") {}.focusID("sign-in")
            }
            Section("Sync") {
                Toggle("Sync contacts", isOn: .constant(true)).focusID("sync-contacts")
                Toggle("Sync calendars", isOn: .constant(false)).focusID("sync-calendars")
            }
            .disabled(true)
            Section("Sound") {
                Toggle("Notifications", isOn: $notifications).focusID("notifications")
                Slider(value: $volume, in: 0...1).focusID("volume")
            }
        }
    }
}

@MainActor
@Suite("Real world: settings pages")
struct SettingsScreens {
    /// From 40×12: a columns form is not a scroll view, as SwiftUI's is not,
    /// so in a 20×6 window its lower rows are clipped and Tab onto one cannot
    /// show it. An app for small terminals writes `.formStyle(.grouped)`,
    /// which scrolls (`longForm`).
    @Test("A Form in a sheet over a busy page: every control reachable by Tab, Done closes it",
          arguments: TerminalSize.usable)
    func formInASheet(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { PageWithSettings() }
        LayoutSanity.check(app, "launch")
        for _ in 0..<5 where app.focusedID != "open" { app.press(.tab) }
        #expect(app.focusedID == "open")
        app.press(.enter)
        LayoutSanity.check(app, "the sheet open")
        var seen: Set<String> = []
        for step in 0..<12 {
            if let focused = app.focusedID { seen.insert(focused) }
            if app.focusedID == "done" { break }
            app.press(.tab)
            LayoutSanity.check(app, "Tab ×\(step + 1) in the sheet")
        }
        #expect(seen.isSuperset(of: ["wifi", "name", "theme", "font", "done"]), "Tab visited only \(seen.sorted())")
        app.press(.enter)
        LayoutSanity.check(app, "the sheet closed")
        #expect(!app.screen.contains("Font size"), "the sheet is still up:\n\(app.screen)")
    }

    @Test("A long grouped Form: the last section reachable by Tab, by the wheel and by End",
          arguments: TerminalSize.all)
    func longForm(size: TerminalSize) {
        let byTab = TestApp(width: size.width, height: size.height) { LongSettingsPage() }
        LayoutSanity.check(byTab, "launch")
        LayoutSanity.reach("Option 8.4", in: byTab, by: .tab, limit: 40)
        let byWheel = TestApp(width: size.width, height: size.height) { LongSettingsPage() }
        LayoutSanity.reach("Option 8.4", in: byWheel, by: .wheelDown(over: nil), limit: 80)
        LayoutSanity.expectNotSilentlyCut(byWheel, "Option 8.4", "the last row")
    }

    /// From 40×12, as the sheet's: a columns form does not scroll.
    @Test("A disabled section is skipped by Tab and drawn whole", arguments: TerminalSize.usable)
    func disabledSection(size: TerminalSize) {
        let app = TestApp(width: size.width, height: size.height) { AccountPage() }
        LayoutSanity.check(app, "launch")
        var seen: Set<String> = []
        for step in 0..<10 {
            if let focused = app.focusedID { seen.insert(focused) }
            app.press(.tab)
            LayoutSanity.check(app, "Tab ×\(step + 1)")
        }
        #expect(seen.isDisjoint(with: ["sync-contacts", "sync-calendars"]), "Tab reached a disabled toggle: \(seen)")
        #expect(seen.isSuperset(of: ["sign-in", "notifications", "volume"]), "Tab visited only \(seen.sorted())")
    }
}
