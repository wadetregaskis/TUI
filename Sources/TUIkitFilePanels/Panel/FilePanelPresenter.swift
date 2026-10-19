//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelPresenter.swift
//
//  The modifier every file panel is presented through: a sheet holding the
//  panel while the binding is true, and the panel's end turned into the
//  caller's callbacks in SwiftUI's order.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIkitFoundation
import TUIkitPresentation

/// Presents a ``FilePanel`` in a sheet while `isPresented` is true, and turns
/// how it ends into the caller's callbacks.
///
/// SwiftUI's order: when the user chooses, `isPresented` is set to `false`
/// and then `onChoose` is called; when the panel is dismissed any other way —
/// Cancel, Escape, or the app clearing the binding — `isPresented` is false
/// and `onCancel` is called instead, once, after the sheet has gone.
///
/// The panel opens on the folder it was last confirmed in, for as long as
/// this view lives, and on the request's start folder before that.
struct FilePanelPresenter<Content: View>: View {
    let content: Content
    let isPresented: Binding<Bool>

    /// What the panel is asked for, made when it is presented: a request
    /// changed while the panel is up applies the next time, as SwiftUI's does.
    let request: () -> FilePanelRequest

    /// The user chose these URLs; `isPresented` is already false.
    let onChoose: ([URL]) -> Void

    /// The panel was dismissed without a choice.
    let onCancel: () -> Void

    /// What one presentation has to remember past the frame that ends it: a
    /// reference, since the sheet's dismissal callback reads it after the
    /// choice was made.
    @State private var session = Session()

    /// The locale the panel writes its sizes and dates in.
    @Environment(\.locale) private var locale

    private final class Session {
        /// Whether this presentation ended in a choice.
        var chose = false
        /// The folder the last choice was made in.
        var lastDirectory: URL?
        /// The request this presentation was made with.
        var current: FilePanelRequest?
    }

    var body: some View {
        content
            .sheet(isPresented: isPresented, onDismiss: dismissed) {
                FilePanel(request: currentRequest(), finish: finish)
                    .presentationSizing(.page)
            }
    }

    /// The request this presentation was made with: made the first time the
    /// sheet's content is built, and kept until it is dismissed.
    private func currentRequest() -> FilePanelRequest {
        if let current = session.current { return current }
        var made = request()
        made.rule.locale = locale
        if let lastDirectory = session.lastDirectory { made.startDirectory = lastDirectory }
        session.current = made
        return made
    }

    private func finish(_ outcome: FilePanelOutcome) {
        switch outcome {
        case .chose(let urls, let folder):
            session.chose = true
            session.lastDirectory = folder
            isPresented.wrappedValue = false
            onChoose(urls)
        case .cancelled:
            isPresented.wrappedValue = false
        }
    }

    /// The sheet has gone: a cancellation, unless the panel chose.
    private func dismissed() {
        let chose = session.chose
        session.chose = false
        session.current = nil
        if !chose { onCancel() }
    }
}
