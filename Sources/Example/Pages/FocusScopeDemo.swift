//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusScopeDemo.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUI

/// Where the focus starts in a part of the screen, and putting it back there:
/// `.focusScope(_:)` marks the part, `.prefersDefaultFocus(in:)` the control
/// that should have the focus first — here the sheet's name field, not its
/// first toggle — and `@Environment(\.resetFocus)` returns it there on request.
///
/// In a sheet because a preference applies when its scope first appears and
/// nothing holds the focus yet: on the page itself it would take the focus the
/// moment the page opened, half a screen down.
struct FocusScopeDemo: View {
    @Namespace private var settings
    @Environment(\.resetFocus) private var resetFocus
    @State private var isPresented = false
    @State private var wrapsLines = true
    @State private var showsHidden = false
    @State private var name = ""

    var body: some View {
        DemoSection("page.focus.scope") {
            VStack(alignment: .leading, spacing: 1) {
                Text("page.focus.scopeExplain")
                    .foregroundStyle(.palette.foregroundSecondary)
                Button("page.focus.scopeOpen") { isPresented = true }
            }
        }
        .sheet(isPresented: $isPresented) {
            Dialog(title: "page.focus.scopeTitle") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.focus.scopeSheetExplain")
                        .foregroundStyle(.palette.foregroundSecondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle("page.focus.scopeWrap", isOn: $wrapsLines)
                        Toggle("page.focus.scopeHidden", isOn: $showsHidden)
                        TextField("page.focus.scopeName", text: $name)
                            .prefersDefaultFocus(in: settings)
                    }
                    HStack(spacing: 2) {
                        Button("page.focus.scopeReset") { resetFocus(in: settings) }
                        Spacer()
                        Button("button.close") { isPresented = false }
                    }
                }
            }
            .focusScope(settings)
        }
    }
}
