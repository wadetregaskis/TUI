//  🖥️ TUI — A Terminal UI framework for Swift
//  PaletteSearchIndexStoreTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIImage
@testable import TUIStyling

/// The process-wide store of palette search indexes, as threads meet in it.
///
/// It built each index under its one lock, and a build is tens of milliseconds
/// optimised and seconds not. Every thread asking for ANY palette's index in the
/// meantime — one already built included — blocked on that lock: an image
/// converted on the cooperative pool parked a pool thread behind a build of a
/// palette it does not use.
@Suite("Palette search index store")
struct PaletteSearchIndexStoreTests {

    @Test("A built index is served while another palette's is being built")
    func servedDuringAnotherBuild() async {
        // Colours no other test uses, so the store's other users neither find
        // these keys nor are found by them.
        let ready = ASCIIPalette((0..<20).map { Color.rgb(UInt8($0 * 3), 17, 211) })
        let slow = ASCIIPalette((0..<20).map { Color.rgb(UInt8($0 * 3), 19, 213) })
        let readyEntries = ready.entries
        let slowEntries = slow.entries

        // Waits on threads of its own, not on the pool: see
        // `PaletteSearchIndexTests`' "Why the walks run on threads of their own".
        let served = await withCheckedContinuation { continuation in
            Thread {
                _ = ASCIIPalette.SearchIndexCache.index(for: readyEntries)
                let started = DispatchSemaphore(value: 0)
                let release = DispatchSemaphore(value: 0)
                let done = DispatchSemaphore(value: 0)
                Thread {
                    _ = ASCIIPalette.SearchIndexCache.index(for: slowEntries) { entries in
                        started.signal()
                        release.wait()
                        return ASCIIPalette.SearchIndex(entries: entries)
                    }
                }.start()
                started.wait()
                Thread {
                    _ = ASCIIPalette.SearchIndexCache.index(for: readyEntries)
                    done.signal()
                }.start()
                // A hang-breaker, not a budget: a lookup that does not wait on
                // the build answers in microseconds.
                let inTime = done.wait(timeout: .now() + 30) == .success
                release.signal()
                continuation.resume(returning: inTime)
            }.start()
        }
        #expect(served, "a lookup of a built index waited on another palette's build")
    }
}
