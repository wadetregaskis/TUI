//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelRemoteNotice.swift
//
//  The line a file panel shows when it browses a machine the user is not at:
//  "⚠️ You are browsing the file system on <host>, not your local machine."
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation
import TUIkitPresentation
import TUIkitTerminalHost

/// Where the file system a panel browses is, for its notice: TUIkit's
/// judgement of where the user is (``SessionLocality/judgement()``), and the
/// name of the machine the app — and so the panel — runs on.
package struct FilePanelSession: Equatable, Sendable {
    /// Whether the user is at this machine, at another, or neither can be
    /// told.
    package var judgement: SessionLocality.Judgement

    /// The machine the app runs on, as `hostname` prints it.
    package var hostName: String

    package init(judgement: SessionLocality.Judgement, hostName: String) {
        self.judgement = judgement
        self.hostName = hostName
    }

    /// This process's, now. Off the main actor: inside tmux the judgement
    /// asks tmux for its clients, a subprocess, and where `gethostname`
    /// gives no name `ProcessInfo` may look one up.
    @concurrent
    static func current() async -> Self {
        Self(
            judgement: SessionLocality.judgement(),
            hostName: TerminalClient.localHostName ?? ProcessInfo.processInfo.hostName)
    }

    /// The machine a panel's notice names under `visibility`: judged on
    /// `pinned` where it is set (``EnvironmentValues/filePanelSession``),
    /// else on this process's session, off the main actor.
    static func noticeHost(pinned: Self?, visibility: Visibility) async -> String? {
        guard visibility != .hidden else { return nil }
        if let pinned { return pinned.notice(visibility) }
        return await current().notice(visibility)
    }

    /// The machine the notice names under `visibility`
    /// (`fileDialogRemoteNotice(_:)`), or `nil` for no notice: `.automatic`
    /// on evidence that the user is elsewhere, `.visible` wherever they are
    /// not known to be here, `.hidden` never.
    func notice(_ visibility: Visibility) -> String? {
        switch visibility {
        case .automatic: judgement == .remote ? hostName : nil
        case .visible: judgement == .local ? nil : hostName
        case .hidden: nil
        }
    }
}

private struct FilePanelSessionKey: EnvironmentKey {
    static let defaultValue: FilePanelSession? = nil
}

extension EnvironmentValues {
    /// The session a file panel's notice is judged on, where something pins
    /// it: `nil`, as in an app, for this process's (``FilePanelSession/current()``).
    /// A test pins it, as what a test shows must not depend on how its
    /// process was started (over ssh, in tmux), nor ask tmux for clients; the
    /// Example pins a remote one to show the notice at the desk.
    package var filePanelSession: FilePanelSession? {
        get { self[FilePanelSessionKey.self] }
        set { self[FilePanelSessionKey.self] = newValue }
    }
}

/// The notice: a warning sign — the alert's ⚠️ where the terminal draws emoji
/// chrome legibly, else a bold `!` — and the sentence naming the machine, in
/// the palette's warning colour, on one line.
struct FilePanelRemoteNotice: View {
    let hostName: String

    @Environment(\.supportsEmojiChrome) private var supportsEmojiChrome

    var body: some View {
        HStack(spacing: 1) {
            if supportsEmojiChrome {
                Text(verbatim: AlertPanelMark.warning)
            } else {
                Text(verbatim: "!").bold()
            }
            Text(
                verbatim: String(
                    format: LocalizationService.shared.string(for: LocalizationKey.FilePanel.remoteNotice), hostName)
            )
            .lineLimit(1)
        }
        .foregroundStyle(.palette.warning)
    }
}
