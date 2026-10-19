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
        self.harness = InputChainHarness(width: width, height: height)
        self.build = build
    }

    /// Draws a frame and returns the screen, the sheet composited over the page.
    @discardableResult
    func screen() -> String {
        frame().compositingOverlays(
            maxWidth: width, maxHeight: height, palette: harness.context.environment.palette
        ).lines.map(\.stripped).joined(separator: "\n")
    }

    /// One frame, bracketed by the lifecycle's passes as the run loop brackets
    /// it, which the harness does not: without them a view that leaves and
    /// comes back — a panel dismissed and presented again — is never seen to
    /// have gone, so its `.task` never starts again.
    @discardableResult
    private func frame() -> FrameBuffer {
        harness.tui.lifecycle.beginRenderPass()
        defer { harness.tui.lifecycle.endRenderPass() }
        return harness.frame(build())
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
}
