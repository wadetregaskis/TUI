//  🖥️ TUI — A Terminal UI framework for Swift
//  StatePersistencePage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import TUI

/// An observable model, demonstrated with `@Bindable` on the page below.
@Observable private final class DemoSettings {
    var name = "Ada"
    var subscribed = false
}

/// A self-contained counter with its own `@State`. When the page re-keys it with
/// `.id(_:)`, it gets a fresh identity and its count resets to zero.
private struct CounterView: View {
    @State private var count = 0

    var body: some View {
        HStack(spacing: 2) {
            Button("\(L("page.state.idCount")): \(count)") { count += 1 }
            Text("page.state.idHint").dim()
        }
    }
}

/// State-persistence demo page.
///
/// Demonstrates `@AppStorage` — values that persist to disk and survive quitting
/// and relaunching the app. The page shows the live values, the on-disk settings
/// file they are written to, and a prompt to quit (⌃Q) and relaunch to see the
/// numbers carry over.
struct StatePersistencePage: View {
    // @AppStorage persists to <config>/settings.json, so these values survive
    // quitting and relaunching the app.
    @AppStorage("state.launchTaps") private var launchTaps: Int = 0
    @AppStorage("state.remembered") private var remembered: Bool = false
    @AppStorage("state.note") private var note: String = ""
    /// Where the user was, rather than what they chose: `@SceneStorage`.
    @SceneStorage("state.lastPanel") private var lastPanel: String = "one"

    /// An @Observable model, projected with @Bindable below.
    @State private var settings = DemoSettings()
    /// Bumping this re-keys the CounterView via `.id`, resetting its @State.
    @State private var resetToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {

            DemoSection("page.state.persistenceSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.state.description")
                        .foregroundStyle(.palette.foregroundSecondary)

                    Button("page.state.tapToIncrement") {
                        launchTaps += 1
                    }
                    Toggle("page.state.rememberMe", isOn: $remembered)

                    HStack(spacing: 2) {
                        ValueDisplayRow("page.state.storedTaps", "\(launchTaps)")
                        ValueDisplayRow(
                            "page.state.remembered",
                            remembered ? L("page.state.yes") : L("page.state.no"))
                    }
                }
            }

            DemoSection("page.state.noteSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.state.noteDescription")
                        .foregroundStyle(.palette.foregroundSecondary)
                    TextField("page.state.notePlaceholder", text: $note)
                        .frame(width: 32)
                }
            }

            DemoSection("page.state.sceneSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.state.sceneDescription")
                        .foregroundStyle(.palette.foregroundSecondary)
                    Picker("page.state.scenePanel", selection: $lastPanel) {
                        Text("page.state.scenePanel.one").tag("one")
                        Text("page.state.scenePanel.two").tag("two")
                        Text("page.state.scenePanel.three").tag("three")
                    }
                    .pickerStyle(.segmented)
                }
            }

            UndoDemo()

            DemoSection("page.state.bindableSection") {
                // Derive Bindings into the @Observable model we already own.
                let bindable = Bindable(settings)
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.state.bindableDescription")
                        .foregroundStyle(.palette.foregroundSecondary)
                    TextField("page.state.bindableName", text: bindable.name)
                        .frame(width: 24)
                    Toggle("page.state.bindableSubscribed", isOn: bindable.subscribed)
                    ValueDisplayRow(
                        "page.state.bindableLive",
                        "\(settings.name) · \(settings.subscribed ? "on" : "off")")
                }
            }

            DemoSection("page.state.idSection") {
                VStack(alignment: .leading, spacing: 1) {
                    Text("page.state.idDescription")
                        .foregroundStyle(.palette.foregroundSecondary)
                    // Re-keying by resetToken restarts CounterView's @State.
                    CounterView().id(resetToken)
                    Button("page.state.idReset") { resetToken += 1 }
                }
            }

            DemoSection("page.state.whereSection") {
                VStack(alignment: .leading, spacing: 1) {
                    ValueDisplayRow("page.state.savedTo", Self.settingsPath)
                    Text("page.state.relaunchHint")
                        .foregroundStyle(.palette.accent)
                }
            }

            Spacer()
        }
        .scrollableDemoPage()
        .navigationTitle("menu.item.statePersistence")
    }

    /// Where `@AppStorage` persists, asked of the framework's default store
    /// rather than worked out again here, so `TUI_CONFIG_DIR` and the app's
    /// name are taken as the framework takes them: a JSON file's own path, or
    /// for `UserDefaults.standard`, on macOS, its preferences domain —
    /// `~/Library/Preferences/<app>.plist` for this CLI binary (a bundled app
    /// would use its `Info.plist` bundle identifier).
    private static var settingsPath: String {
        let full: String
        if let file = StorageDefaults.backend as? JSONFileStorage {
            full = file.fileURL.path
        } else {
            let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
            full = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(domain).plist").path
        }
        // Abbreviate the home prefix to keep the line short.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return full.hasPrefix(home) ? "~" + full.dropFirst(home.count) : full
    }
}
