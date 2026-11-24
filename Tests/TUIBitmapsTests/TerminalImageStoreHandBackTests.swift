//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalImageStoreHandBackTests.swift
//
//  A ⌃Z, a hand-off to another program and the recovery from an external stop
//  give the terminal to someone else for a while. The image store deletes its
//  pictures as the terminal is handed back and forgets them, so the first frame
//  after it is taken back sends each picture again (H-58): a terminal with a
//  store per screen may have freed them with the alternate screen.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation

@MainActor
@Suite("Terminal image store hand-back")
struct TerminalImageStoreHandBackTests {

    private func signature(_ label: String) -> TerminalImageSignature {
        TerminalImageSignature(
            source: .file(label), rawWidth: 8, rawHeight: 8,
            pixelWidth: 8, pixelHeight: 8,
            colorMode: .trueColor, toneCurve: nil, edgeContrast: 0, dithering: .none,
            monoInk: RGBA(r: 255, g: 255, b: 255), monoPaper: RGBA(r: 0, g: 0, b: 0),
            terminalColors: .unknown)
    }

    /// One picture drawn by `token`, its rows as a frame would write them.
    @discardableResult
    private func draw(_ label: String, token: String, in store: TerminalImageStore) -> [String] {
        store.placeholderRows(
            token: token, signature: signature(label), columns: 4, rows: 2,
            pixels: { ([UInt8](repeating: 0x80, count: 64 * 4), .rgba, 8, 8) }) ?? []
    }

    @Test("The hand-back deletes every picture, and the next request for one sends it again")
    func handBackForgetsWhatTheTerminalHolds() {
        let store = TerminalImageStore()
        draw("photo", token: "view", in: store)
        draw("other", token: "second", in: store)
        _ = store.takePending()
        draw("photo", token: "view", in: store)
        #expect(store.takePending().isEmpty, "steady: the terminal has it")

        let farewell = store.handBack()
        #expect(farewell == KittyGraphics.delete(id: 1) + KittyGraphics.delete(id: 2))
        #expect(store.imageCount == 0)
        #expect(store.farewell().isEmpty, "nothing more owed")

        let rows = draw("photo", token: "view", in: store)
        let pending = store.takePending()
        #expect(pending.contains("a=t,"), "sent again: \(pending.prefix(60).debugDescription)")
        #expect(pending.contains("i=3"), "under an id of its own, after the deleted ones")
        #expect(!rows.isEmpty)
    }

    @Test("Escapes queued before the hand-back are dropped: they name only deleted pictures")
    func handBackDropsQueuedEscapes() {
        let store = TerminalImageStore()
        draw("photo", token: "view", in: store)
        #expect(store.handBack() == KittyGraphics.delete(id: 1))
        #expect(store.takePending().isEmpty, "the transmit not yet written is not written after its delete")
        #expect(store.takeDeletes().isEmpty)
    }

    /// `releaseAll` cleared the images and left the holds behind it, harmless
    /// only because it ran at a quit.
    @Test("A hold is forgotten with its pictures, and a picture held again is sent again")
    func handBackForgetsHolds() {
        let store = TerminalImageStore()
        let rows = draw("photo", token: "view", in: store)
        store.hold(picturesIn: rows, for: "zoom")
        _ = store.takePending()

        _ = store.handBack()
        store.release(token: "zoom")
        store.release(token: "view")
        #expect(store.takeDeletes().isEmpty, "nothing left to delete")

        draw("photo", token: "view", in: store)
        #expect(store.takePending().contains("a=t,"))
    }

    @Test("A picture the terminal was playing by itself is played from its frames again")
    func handBackForgetsPlayedPictures() {
        let store = TerminalImageStore()
        func play() {
            draw("clip", token: "clip", in: store)
            store.advancePlayedPicture(
                token: "clip", to: 1,
                timing: PlayedPictureTiming(
                    frameCount: 2, durationNanos: 200_000_000, plays: nil, elapsedNanos: 100_000_000, nowNanos: 0),
                delayNanos: { _ in 100_000_000 }, size: (8, 8),
                pixels: { _ in ([UInt8](repeating: 0x40, count: 64 * 4), .rgba) }, whenCopied: {})
        }
        play()
        #expect(store.hasHandedOverPlayedPicture(token: "clip"))
        _ = store.takePending()

        _ = store.handBack()
        #expect(!store.hasHandedOverPlayedPicture(token: "clip"))
        play()
        let pending = store.takePending()
        #expect(pending.contains("a=t,"), "the first frame sent again")
        #expect(pending.contains("a=f,"), "and the second")
    }

    @Test("A quit's release forgets as much as a hand-back, and queues its deletes")
    func releaseAllIsAHandBack() {
        let store = TerminalImageStore()
        let rows = draw("photo", token: "view", in: store)
        store.hold(picturesIn: rows, for: "zoom")
        _ = store.takePending()
        store.releaseAll()
        #expect(store.takePending() == KittyGraphics.delete(id: 1))
        store.release(token: "zoom")
        #expect(store.takeDeletes().isEmpty)
    }
}
