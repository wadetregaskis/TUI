//  🖥️ TUIkit — Terminal UI Kit for Swift
//  FilePanelDriver.swift
//
//  Driving a presented file panel through the whole input chain, and
//  recording what its caller hears.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// What a presented panel's caller heard.
@MainActor
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

/// What an exporter's caller heard.
@MainActor
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

/// A view with a file panel presented over it, drawn and pressed through the
/// whole input chain (``InputChainHarness``), rebuilt for every frame.
@MainActor
final class FilePanelDriver<Page: View> {
    let harness: InputChainHarness
    let width: Int
    let height: Int
    private let build: () -> Page

    init(width: Int = 100, height: Int = 30, _ build: @escaping () -> Page) {
        self.width = width
        self.height = height
        // The terminal's size, as the run loop publishes it: a sheet is sized
        // against it, and without it a panel was drawn for the defaults'
        // 80 × 24 whatever size the test drew at.
        self.harness = InputChainHarness(width: width, height: height) { environment in
            environment.terminalWidth = width
            environment.terminalHeight = height
            environment.overlayContentHeight = height
        }
        self.build = build
    }

    /// Draws a frame and returns the screen, the sheet composited over the page.
    @discardableResult
    func screen() -> String {
        composited().lines.map(\.stripped).joined(separator: "\n")
    }

    /// Draws a frame, the sheet composited over the page, and points the
    /// mouse at what that frame shows: the harness hands the dispatcher the
    /// page's own regions, and the sheet's are where compositing puts them,
    /// as the run loop hands it the composited frame's.
    @discardableResult
    private func composited() -> FrameBuffer {
        let screen = frame().compositingOverlays(
            maxWidth: width, maxHeight: height, palette: harness.context.environment.palette)
        harness.tui.mouseEventDispatcher.setRegions(screen.hitTestRegions)
        return screen
    }

    /// The app storage the page is drawn with, unless it names its own: a
    /// test's own, so a panel's view mode switched in one test is not the
    /// next one's (the panels keep it, `FilePanelViewMode`).
    let storage = MockStorageBackend()

    /// One frame of the page, built afresh.
    @discardableResult
    private func frame() -> FrameBuffer {
        harness.frame(build().defaultAppStorage(storage))
    }

    /// Draws frames until the screen shows `text` — a folder is read on
    /// another thread — and returns that screen.
    @discardableResult
    func waitFor(_ text: String, timeout: Duration = .seconds(60)) async -> String {
        var last = ""
        await settle(
            until: {
                last = screen()
                return last.contains(text)
            }, timeout: timeout)
        return last
    }

    /// Presses `keys`, a frame after each.
    func press(_ keys: [KeyEvent]) {
        for key in keys {
            harness.press(key)
            frame()
        }
    }

    /// Presses `key`, `count` times, a frame after each.
    func press(_ key: Key, times count: Int = 1) {
        press(Array(repeating: KeyEvent(key: key), count: count))
    }

    /// Where `text` first shows on the screen, in cells, or `nil` where it
    /// does not: its row, and the column of its first character. The screen
    /// is the stripped text, so a column is a character's offset — true of
    /// the panel's rows, whose characters before a name are one cell each.
    func position(of text: String) -> (x: Int, y: Int)? {
        for (row, line) in screen().split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if let range = line.range(of: text) {
                return (line.distance(from: line.startIndex, to: range.lowerBound), row)
            }
        }
        return nil
    }

    /// Clicks the first character of `text` where it first shows, with a
    /// frame after the press and after the release; `false` where it does
    /// not show.
    @discardableResult
    func click(_ text: String) -> Bool {
        guard let point = position(of: text) else { return false }
        harness.mouse(MouseEvent(button: .left, phase: .pressed, x: point.x, y: point.y))
        composited()
        harness.mouse(MouseEvent(button: .left, phase: .released, x: point.x, y: point.y))
        composited()
        return true
    }
}
