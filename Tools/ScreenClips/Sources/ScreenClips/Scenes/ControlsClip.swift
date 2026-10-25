//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ControlsClip.swift
//
//  `controls`: a settings form used from the keyboard — a field typed into,
//  a toggle flipped, a segmented picker and a slider moved, a stepper
//  stepped, a button pressed — every key through TUIkit's own input path.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkit

@MainActor
let controlsClip = Clip(
    id: "controls",
    title: "Controls",
    columns: 112,
    rows: 30,
    output: 800,
    script: controlsScript(),
    run: { await ControlsApp.main() }
)

/// Types a name, flips the toggle, chooses a theme, moves the slider and the
/// stepper, and saves: one Tab to each control, in the form's order.
private func controlsScript() -> [Step] {
    var script: [Step] = [.camera(Shot(x: 0, y: 2, width: 92, height: 20)), .wait(0.6)]
    script += Step.type("Ada Lovelace", interval: 0.07)
    script += [.wait(0.3), .tab, .wait(0.35), .space, .wait(0.45)]
    script += [.tab, .wait(0.3), .right, .wait(0.3), .space, .wait(0.45)]
    script += [.tab, .wait(0.3)]
    script += Step.repeat(.right, 6, interval: 0.1)
    script += [.wait(0.2), .tab, .wait(0.3)]
    script += Step.repeat(.right, 3, interval: 0.25)
    script += [.wait(0.2), .tab, .wait(0.4), .space, .wait(1.4)]
    return script
}

struct ControlsApp: App {
    var body: some Scene {
        WindowGroup("TUIkit · Controls") {
            ControlsPage()
                .palette(AppleTerminalPalette(.redSands))
        }
    }
}

/// A profile form: one of each kind of control a settings page needs.
struct ControlsPage: View {
    @State private var name = ""
    @State private var notifications = false
    @State private var theme = 0
    @State private var volume = 40.0
    @State private var copies = 1
    @State private var saved = 0

    private let themes = ["Light", "Dark", "System"]

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            form
            preview
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 1)
        .toolbar {
            ToolbarItem(placement: .navigation) { Text(verbatim: "Settings") }
        }
    }

    /// What the settings make: the profile as others see it, live.
    private var preview: some View {
        GroupBox("Preview") {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 1) {
                    Text(verbatim: " \(initials) ")
                        .bold()
                        .foregroundStyle(.palette.background)
                        .background(.palette.accent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: name.isEmpty ? "No name yet" : name).bold()
                        Text(verbatim: notifications ? "🔔 Notifications on" : "🔕 Notifications off")
                            .foregroundStyle(.palette.foregroundSecondary)
                    }
                }
                LabeledContent("Theme", value: themes[theme])
                LabeledContent("Volume") {
                    ProgressView(value: volume, total: 100).frame(width: 12)
                }
                LabeledContent("Copies", value: String(repeating: "▤ ", count: copies))
                Text(verbatim: saved > 0 ? "✓ Saved" : "Not saved")
                    .foregroundStyle(saved > 0 ? .palette.success : .palette.foregroundTertiary)
            }
        }
        .frame(width: 32)
    }

    private var initials: String {
        let letters = name.split(separator: " ").compactMap(\.first).prefix(2)
        return letters.isEmpty ? "?" : String(letters)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 1) {
            Form {
                Section("Profile") {
                    LabeledContent("Name") { TextField("Your name", text: $name) }
                    Toggle("Notifications", isOn: $notifications)
                }
                Section("Preferences") {
                    Picker("Theme", selection: $theme) {
                        ForEach(themes.indices, id: \.self) { index in Text(themes[index]).tag(index) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Volume") { Slider(value: $volume, in: 0...100, step: 5) }
                    Stepper("Copies", value: $copies, in: 1...9)
                }
            }
            .formStyle(.grouped)
            HStack(spacing: 2) {
                Button("Save") { saved += 1 }.buttonStyle(.borderedProminent)
                if saved > 0 {
                    Text("✓ Saved \(name.isEmpty ? "profile" : name)").foregroundStyle(.palette.success)
                }
            }
            .padding(.leading, 2)
            Spacer(minLength: 0)
        }
        .frame(width: 56, alignment: .leading)
    }
}
