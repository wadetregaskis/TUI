//  🖥️ TUI — A Terminal UI framework for Swift
//  AsyncImageTests.swift
//
//  `AsyncImage`: the app's content drawn for each phase — empty while the load
//  runs, success with an image that draws the loaded pixels at once, failure
//  with the error — and a nil URL that stays empty.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIApp
@testable import TUIAppTestSupport
import TUIBitmaps
@testable import TUIFoundation
@testable import TUIImage
@testable import TUITestSupport

@MainActor
@Suite("AsyncImage")
struct AsyncImageTests {

    /// This test's own cache, which no other test sees: the views are handed
    /// it (`.urlImageCache(_:)`).
    private let cache = URLImageCache()

    /// A URL the test's cache answers, so the load succeeds with no network.
    private func cachedURL() -> URL {
        let address = "tuikit-test://async-image/\(UUID().uuidString).png"
        let red = RGBA(r: 255, g: 0, b: 0)
        cache.set(address, image: RGBAImage(width: 4, height: 4, pixels: Array(repeating: red, count: 16)))
        return URL(string: address)!
    }

    private func phaseName(_ phase: AsyncImagePhase) -> String {
        switch phase {
        case .empty: "empty"
        case .success: "success"
        case .failure: "failure"
        }
    }

    @Test("The content sees empty, then success, and the image draws without a second load")
    func loadsToSuccess() async {
        let url = cachedURL()
        let harness = InputChainHarness()
        let view = {
            AsyncImage(url: url) { phase in
                Text(phaseName(phase))
                if let image = phase.image { image.frame(width: 4, height: 2) }
            }
            .urlImageCache(cache)
        }
        let first = harness.frame(view())
        #expect(first.lines.first?.stripped.hasPrefix("empty") == true)
        // The FIRST frame that reports success is the one asked about: an
        // image that loaded its source again would still be a placeholder there.
        var firstSuccess: FrameBuffer?
        await settle(until: {
            let drawn = harness.frame(view())
            guard drawn.lines.first?.stripped.hasPrefix("success") == true else { return false }
            firstSuccess = drawn
            return true
        })
        guard let loaded = firstSuccess else { return }
        #expect(loaded.lines.count >= 3, "the image draws its pixels under the label: \(loaded.lines.map(\.stripped))")
        // The loaded red, drawn at once: an image that was loading again
        // would show its placeholder instead.
        #expect(
            loaded.lines.dropFirst().contains { $0.contains("255;0;0") },
            "\(loaded.lines.dropFirst().map(\.debugDescription))")
    }

    @Test("A URL that cannot load reaches the failure phase, with an error")
    func failsToFailure() async {
        let url = URL(string: "tuikit-unsupported-scheme://nowhere/x.png")!
        let harness = InputChainHarness()
        let view = {
            AsyncImage(url: url) { phase in
                Text(phase.error == nil ? phaseName(phase) : "failure with error")
            }
        }
        harness.frame(view())
        await settle(until: { harness.frame(view()).lines.first?.stripped.hasPrefix("failure with error") == true })
    }

    @Test("The failure phase's error describes itself in words")
    func failureDescribesItself() async {
        let url = URL(string: "tuikit-unsupported-scheme://nowhere/x.png")!
        let harness = InputChainHarness()
        var error: (any Error)?
        func noting(_ phase: AsyncImagePhase) -> EmptyView {
            error = phase.error ?? error
            return EmptyView()
        }
        await settle(until: {
            harness.frame(AsyncImage(url: url) { noting($0) })
            return error != nil
        })
        // Not Foundation's "The operation couldn't be completed. (TUIBitmaps.AsyncImageLoadError error 1.)".
        #expect(error?.localizedDescription.hasPrefix("Image download failed") == true, "\(String(describing: error))")
    }

    @Test("A nil URL stays empty, and the placeholder form shows its placeholder")
    func nilURLAndPlaceholder() {
        let harness = InputChainHarness()
        let drawn = harness.frame(AsyncImage(url: nil) { $0 } placeholder: { Text("waiting") })
        #expect(drawn.lines.first?.stripped.hasPrefix("waiting") == true)
    }
}
