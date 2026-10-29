//  🖥️ TUI — A Terminal UI framework for Swift
//  TerminalImageStoreHoldTests.swift
//
//  A drawing can stay on screen after the views that drew it have gone: a
//  navigation zoom folds the popped screen away for a few frames after the
//  screen itself disappeared. Its pictures are kept for it by a hold, or the
//  terminal is told to delete them and the zoom draws empty cells.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation

@MainActor
@Suite("Terminal image store holds")
struct TerminalImageStoreHoldTests {

    private func signature(_ label: String) -> TerminalImageSignature {
        TerminalImageSignature(
            source: .file(label), rawWidth: 8, rawHeight: 8,
            pixelWidth: 8, pixelHeight: 8,
            colorMode: .trueColor, toneCurve: nil, edgeContrast: 0, dithering: .none,
            monoInk: RGBA(r: 255, g: 255, b: 255), monoPaper: RGBA(r: 0, g: 0, b: 0),
            terminalColors: .unknown)
    }

    /// One picture drawn by `token`, its rows as a drawing would hold them.
    private func draw(_ label: String, token: String, in store: TerminalImageStore) -> [String] {
        store.placeholderRows(
            token: token, signature: signature(label), columns: 4, rows: 2,
            pixels: { ([UInt8](repeating: 0x80, count: 64 * 4), .rgba, 8, 8) }) ?? []
    }

    @Test("A held picture outlives the view that drew it, and goes with the hold")
    func heldPictureOutlivesItsView() {
        let store = TerminalImageStore()
        let rows = draw("photo", token: "view", in: store)
        _ = store.takePending()

        store.hold(picturesIn: ["text " + rows[0], rows[1]], for: "zoom")
        store.release(token: "view")
        #expect(store.imageCount == 1, "the view went, the hold keeps its picture")
        #expect(store.takeDeletes().isEmpty, "nothing deleted while held")

        store.release(token: "zoom")
        #expect(store.imageCount == 0)
        #expect(store.takeDeletes().contains("a=d"), "the hold's end deletes it")
    }

    @Test("A new hold under the same token keeps what both hold and lets the rest go")
    func rehold() {
        let store = TerminalImageStore()
        let first = draw("first", token: "a", in: store)
        let second = draw("second", token: "b", in: store)
        store.hold(picturesIn: first + second, for: "zoom")
        store.release(token: "a")
        store.release(token: "b")
        _ = store.takePending()
        _ = store.takeDeletes()

        store.hold(picturesIn: second, for: "zoom")
        #expect(store.imageCount == 1, "the first, held by nothing now, went")
        let deletes = store.takeDeletes()
        #expect(deletes.components(separatedBy: "a=d").count == 2, "one delete: got \(deletes.debugDescription)")
        #expect(!store.takePending().contains("a=t"), "the second was kept, not deleted and sent again")
    }

    @Test("Lines with no picture hold nothing")
    func noPictures() {
        let store = TerminalImageStore()
        let rows = draw("photo", token: "view", in: store)
        store.hold(picturesIn: ["just \u{1B}[31mtext"], for: "zoom")
        store.release(token: "view")
        #expect(store.imageCount == 0)
        #expect(!rows.isEmpty)
    }

    @Test("A zoom's scaled placement is forgotten with its picture")
    func scaledBoxGoesWithPicture() throws {
        let store = TerminalImageStore()
        // Every picture a zoom ever scaled used to leave its box behind, for
        // the life of the app.
        for round in 0..<8 {
            _ = draw("photo \(round)", token: "view", in: store)
            // A fresh store's ids count up from 1, and the one picture held
            // is the newest.
            let id = KittyGraphics.ImageID(round + 1)
            try #require(store.scaledPlaceholderRows(of: id, columns: 2, rows: 1) != nil)
            #expect(store.scaledBoxCount == 1)
            store.release(token: "view")
            #expect(store.scaledBoxCount == 0, "round \(round): the box outlived its picture")
            _ = store.takeDeletes()
        }

        _ = draw("last", token: "view", in: store)
        _ = store.scaledPlaceholderRows(of: 9, columns: 2, rows: 1)
        store.releaseAll()
        #expect(store.scaledBoxCount == 0)
    }
}
