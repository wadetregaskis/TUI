//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuBar.swift
//
//  The menu bar, with what its app menu's About shows.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitApp
import TUIkitFoundation
import TUIkitPresentation

/// The menu bar the window's chrome host draws for a scene that declares
/// commands: its row of titles (``_MenuBarCore``), and the alert its app menu's
/// About presents — titled as the item is, with the app's name, and its version
/// where the app is bundled with one (`CFBundleShortVersionString`, with
/// `CFBundleVersion` beside it when it differs), as macOS's About panel shows
/// them.
struct _MenuBar: View {
    /// What the scene's commands modifiers gathered.
    let commands: SceneCommands

    /// Whether the About alert is up.
    @State private var showsAbout = false

    var body: some View {
        _MenuBarCore(commands: commands) { showsAbout = true }
            .alert(Text(Self.aboutTitle), isPresented: $showsAbout) {
            } message: {
                Text(Self.aboutMessage)
            }
    }

    /// The alert's title: the app menu's About item's.
    static var aboutTitle: String {
        LocalizedStringKey.substituting(
            [_MenuBarCore.appName], into: LocalizationService.shared.string(for: LocalizationKey.Menu.about))
    }

    /// The alert's message: the app's name, and its version on a line of its
    /// own where it has one.
    static var aboutMessage: String {
        guard let version else { return _MenuBarCore.appName }
        let line = LocalizedStringKey.substituting(
            [version], into: LocalizationService.shared.string(for: LocalizationKey.Menu.aboutVersion))
        return _MenuBarCore.appName + "\n" + line
    }

    /// The app's version, from its bundle, or `nil` for an app with none: a
    /// command-line executable has no Info.plist unless it links one in.
    static var version: String? {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return nil }
        guard let build = info?["CFBundleVersion"] as? String, build != short else { return short }
        return "\(short) (\(build))"
    }
}
