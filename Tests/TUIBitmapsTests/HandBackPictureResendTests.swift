//  🖥️ TUI — A Terminal UI framework for Swift
//  HandBackPictureResendTests.swift
//
//  The app runner's half of H-58: a ⌃Z and a hand-off to another program
//  delete every picture before the alternate screen is left, and the first
//  frame after the terminal is taken back sends each again. Driven through the
//  runner's own seams (`AppRunner.handBackTerminal`, `retakeTerminal`,
//  `handOffTerminal`) on a scripted terminal, as the stop itself (`SIGSTOP`)
//  cannot run in a test.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

/// Everything the runner's terminal writes, in order.
private final class Written {
    private var writes: [String] = []
    var bytes: String { writes.joined() }
    func record(_ write: String) { writes.append(write) }
    func clear() { writes.removeAll() }
}

/// A photo above a caption.
private struct PhotoApp: App {
    init() {}

    private static func photo() -> Image {
        var pixels: [RGBA] = []
        for row in 0..<16 {
            for column in 0..<16 {
                pixels.append(RGBA(r: UInt8(column * 16), g: UInt8(row * 16), b: 128))
            }
        }
        return Image(
            .url("tuikit-test://hand-back-photo"),
            decoded: _DecodedImage(RGBAImage(width: 16, height: 16, pixels: pixels)))
    }

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Self.photo().frame(width: 8, height: 4)
                Text("caption")
            }
        }
    }
}

@MainActor
@Suite("A hand-back's pictures are sent again after the retake", .serialized)
struct HandBackPictureResendTests {

    private static let transmission = /a=t,[^\u{1B}]*?i=(\d+)/

    /// A runner whose terminal writes to `output`, and a loop drawing on that
    /// terminal with the runner's context, which has drawn its first frame and
    /// sent the photo: everything written lands in one record, in order.
    private func launched() throws -> (AppRunner<PhotoApp>, RenderLoop<PhotoApp>, Written, String) {
        let runner = AppRunner(app: PhotoApp(), appState: AppState())
        let output = Written()
        // As `ScriptedTerminalOutput.terminal()` scripts a terminal of its own:
        // the runner's is made with it, and is the one its seams write to.
        unsafe runner.terminal.readSource = { _ in 0 }
        runner.terminal.exchangeTransport = .init(
            send: { [output] in output.record($0) }, waitForInput: { _ in false }, armSignalRestore: { _, _ in })
        runner.terminal.enterAlternateScreen()
        runner.terminal.enableRawMode()
        let harness = RenderLoopHarness(tuiContext: runner.tuiContext)
        let loop = harness.loop(PhotoApp(), on: runner.terminal)
        KittyGraphics.withSupport(true) { _ = loop.render() }
        let id = try #require(output.bytes.firstMatch(of: Self.transmission)?.1, "the first frame sends the photo")
        output.clear()
        KittyGraphics.withSupport(true) { _ = loop.render() }
        #expect(!output.bytes.contains("a=t,"), "steady: the terminal has it")
        output.clear()
        return (runner, loop, output, String(id))
    }

    /// The photo's delete comes before the alternate screen is left.
    private func expectDeletedBeforeLeaving(_ id: String, in bytes: String) throws {
        let delete = try #require(bytes.range(of: "a=d,d=I,q=2,i=\(id)\u{1B}"), "the photo is deleted")
        let leave = try #require(bytes.range(of: ANSIRenderer.exitAlternateScreen))
        #expect(delete.upperBound <= leave.lowerBound)
    }

    @Test("A suspend deletes the photo before leaving the alternate screen, and the frame after the resume sends it again")
    func suspendResendsThePicture() throws {
        let (runner, loop, output, id) = try launched()
        KittyGraphics.withSupport(true) { runner.handBackTerminal(renderer: loop) }
        try expectDeletedBeforeLeaving(id, in: output.bytes)

        output.clear()
        KittyGraphics.withSupport(true) {
            runner.retakeTerminal(renderer: loop)
            _ = loop.render()
        }
        let bytes = output.bytes
        let enter = try #require(bytes.range(of: ANSIRenderer.enterAlternateScreen))
        let sent = try #require(bytes.firstMatch(of: Self.transmission), "the photo is sent again")
        #expect(enter.upperBound <= sent.range.lowerBound, "on the alternate screen")
        #expect(String(sent.1) != id, "under an id of its own")
    }

    @Test("A hand-off deletes the photo before the program runs, and the frame after it sends the photo again")
    func handOffResendsThePicture() throws {
        let (runner, loop, output, id) = try launched()
        var deletedBeforeTheProgram = false
        KittyGraphics.withSupport(true) {
            runner.handOffTerminal(renderer: loop, cursorTimer: CursorTimer(renderNotifier: AppState())) {
                deletedBeforeTheProgram = output.bytes.contains("a=d,d=I,q=2,i=\(id)\u{1B}")
            }
        }
        #expect(deletedBeforeTheProgram)
        try expectDeletedBeforeLeaving(id, in: output.bytes)

        output.clear()
        KittyGraphics.withSupport(true) { _ = loop.render() }
        let sent = try #require(output.bytes.firstMatch(of: Self.transmission), "the photo is sent again")
        #expect(String(sent.1) != id)
    }
}
