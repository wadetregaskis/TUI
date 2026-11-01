//  🖥️ TUI — A Terminal UI framework for Swift
//  FilePanelDriver.swift
//
//  Driving a presented file panel through the whole input chain, and
//  recording what its caller hears.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUICore
@testable import TUIFilePanels
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

/// What a presented panel's caller heard.
///
/// Observable, as an app's model is: a view that reads `isPresented` through
/// `binding` is drawn again when it changes, and a list row is not served from
/// a frame before the change.
@MainActor
@Observable
final class FilePanelCaller {
    var isPresented = true
    /// Each callback, in order, with whether the binding was still true then.
    var heard: [String] = []
    var chosen: [URL] = []

    var binding: Binding<Bool> {
        Binding(get: { self.isPresented }, set: { self.isPresented = $0 })
    }

    /// The chosen URLs' paths: a URL's own spelling of a folder (a trailing
    /// slash, or none) is not what a test is about.
    var chosenPaths: [String] { chosen.map(\.path) }

    func chose(_ urls: [URL]) {
        heard.append("chose (presented: \(isPresented))")
        chosen = urls
    }

    func cancelled() {
        heard.append("cancelled (presented: \(isPresented))")
    }

    /// `onCompletion` for the importers that hand back several URLs.
    func completed(_ result: Result<[URL], any Error>) {
        if case .success(let urls) = result { chose(urls) }
    }
}

/// What an exporter's caller heard. Observable, as ``FilePanelCaller`` is.
@MainActor
@Observable
final class FileExporterCaller {
    var isPresented = true
    var heard: [String] = []
    var saved: [URL] = []
    var failure: (any Error)?

    var binding: Binding<Bool> {
        Binding(get: { self.isPresented }, set: { self.isPresented = $0 })
    }

    func completed(_ result: Result<URL, any Error>) {
        completedAll(result.map { [$0] })
    }

    func completedAll(_ result: Result<[URL], any Error>) {
        heard.append("completed (presented: \(isPresented))")
        switch result {
        case .success(let urls): saved = urls
        case .failure(let error): failure = error
        }
    }

    func cancelled() {
        heard.append("cancelled (presented: \(isPresented))")
    }
}

/// A view with a file panel presented over it, in a ``TestApp``: with the app
/// storage and the terminal's circumstances a panel's tests are about, and what
/// they read of its screen.
@MainActor
final class FilePanelDriver<Page: View> {
    let app: TestApp

    /// The app storage the page is drawn with, unless it names its own: a
    /// test's own, so a panel's view mode switched in one test is not the
    /// next one's (the panels keep it, `FilePanelViewMode`).
    ///
    /// With the preview closed, as the panels were drawn before it: a panel
    /// 100 columns wide opens it (`FilePanelPreviewVisibility`), which takes
    /// the list's Kind column and puts the splitter's divider, a Tab stop,
    /// before the buttons the tests Tab to. The preview's own tests name a
    /// store of their own.
    let storage: MockStorageBackend

    /// With no icons unless the page asks for them: the SF Symbols are drawn
    /// where the machine has their font, which a test cannot depend on
    /// (`filePanelIcons`). And at the desk unless the page says otherwise: the
    /// remote-machine notice is judged on how the test process was started, and
    /// inside tmux the judgement asks tmux for its clients (`filePanelSession`).
    init(width: Int = 100, height: Int = 30, _ build: @escaping () -> Page) {
        let storage = MockStorageBackend()
        storage.setValue(
            FilePanelPreviewVisibility.hidden.rawValue, forKey: FilePanelPreviewVisibility.storageKey(for: nil))
        self.storage = storage
        self.app = TestApp(width: width, height: height) {
            build().defaultAppStorage(storage).environment(\.filePanelIcons, FilePanelIcon.none)
                .environment(\.filePanelSession, FilePanelSession(judgement: .local, hostName: "desk"))
        }
    }

    /// Draws a frame and returns the screen.
    @discardableResult
    func screen() -> String {
        app.advance(by: .zero)
        return app.screen.lines.joined(separator: "\n")
    }

    /// Draws a frame and returns the screen's rows as drawn, escapes and all.
    func styledRows() -> [String] {
        app.advance(by: .zero)
        return app.screen.styledLines
    }

    /// Draws frames until the screen shows `text` — a folder is read on
    /// another thread — and returns that screen.
    @discardableResult
    func waitFor(_ text: String, timeout: Duration = .seconds(60)) async -> String {
        do {
            try await app.wait(for: text, timeout: timeout)
        } catch {
            Issue.record("\(error)")
        }
        return screen()
    }

    /// Presses `keys`, a frame after each.
    func press(_ keys: [KeyEvent]) {
        for key in keys { app.press(key) }
    }

    /// Presses `key`, `count` times, a frame after each.
    func press(_ key: Key, times count: Int = 1) {
        app.press(key, times: count)
    }

    /// Where `text` first shows on the screen, in cells, or `nil` where it
    /// does not: its row, and the column of its first character.
    func position(of text: String) -> (x: Int, y: Int)? {
        app.screen.location(of: text).map { ($0.x, $0.y) }
    }

    /// Clicks the first character of `text` where it first shows, with a
    /// frame after the press and after the release; `false` where it does
    /// not show.
    @discardableResult
    func click(_ text: String) -> Bool {
        guard let point = app.screen.location(of: text) else { return false }
        app.click(at: point)
        return true
    }
}
