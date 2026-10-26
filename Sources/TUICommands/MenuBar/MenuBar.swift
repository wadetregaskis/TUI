//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuBar.swift
//
//  The menu bar, with what its app menu's About shows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIApp
import TUIFoundation
import TUIPresentation

/// The menu bar the window's chrome host draws for a scene that declares
/// commands: its row of titles (``_MenuBarCore``), and the alert its app menu's
/// About presents — titled as the item is, with the app's name, its version,
/// credits and copyright, each where the scene states it
/// (``Scene/aboutPanel(applicationName:applicationVersion:version:copyright:credits:)``)
/// or the app is bundled with one, as macOS's About panel shows them.
struct _MenuBar: View {
    /// What the scene's commands modifiers gathered.
    let commands: SceneCommands

    /// What the scene states for About.
    @Environment(\.aboutPanel) private var aboutPanel

    /// Whether the About alert is up.
    @State private var showsAbout = false

    var body: some View {
        let about = (aboutPanel ?? AboutPanelInfo()).resolved(
            bundle: Bundle.main.infoDictionary, processName: ProcessInfo.processInfo.processName)
        _MenuBarCore(commands: commands) { showsAbout = true }
            .alert(Text(about.aboutTitle), isPresented: $showsAbout) {
            } message: {
                Text(about.aboutMessage)
            }
    }
}
