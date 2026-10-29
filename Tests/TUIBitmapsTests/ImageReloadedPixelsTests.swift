//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageReloadedPixelsTests.swift
//
//  A file rewritten at the same path and size decodes to new pixels: the URL
//  cache keys a file by its size AND modification time, so a view that loads it
//  again — a list row scrolled back into view, whose state outlived its window —
//  gets the new picture. The Image view keyed what it drew on the source's NAME
//  and the decoded size, both unchanged, so it went on drawing the old glyphs,
//  and the terminal went on holding the old picture.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing
@testable import TUIBitmaps
import TUIImage

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("An image draws new pixels loaded under the same source")
struct ImageReloadedPixelsTests {

    /// Effects off, exactly as `ViewRenderer` builds one for a snapshot: the view must
    /// not start a real load over the phase these cases seat.
    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    /// A picture `width` × `height`, left half `left` and right half `right`.
    private static func picture(
        width: Int, height: Int, left: RGBA, right: RGBA
    ) -> RGBAImage {
        var pixels: [RGBA] = []
        pixels.reserveCapacity(width * height)
        for _ in 0..<height {
            for x in 0..<width { pixels.append(x < width / 2 ? left : right) }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// One file's name, both times: what changed is what it decoded to.
    private static let source = ImageSource.file("/rewritten/in/place.png")

    /// Draws `_ImageCore` through `tui` with `image` as the phase a load wrote, as the
    /// load does: in the phase box, under an unchanged source.
    private static func draw(
        _ image: RGBAImage, in tui: TUIContext, pixelsCell: TerminalCellPixels? = nil
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        if let pixelsCell { environment.imageCellPixels = pixelsCell }
        let context = RenderContext(
            availableWidth: 8, availableHeight: 4, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))
        let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0), default: .loading)
        phase.value = .success(image)
        let lastSource: StateBox<ImageSource?> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 1), default: nil)
        lastSource.value = source
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        return ColorDepth.withCurrent(.truecolor) {
            renderToBuffer(_ImageCore(source: source), context: context).lines
        }
    }

    private let before = picture(
        width: 8, height: 8, left: RGBA(r: 220, g: 0, b: 0), right: RGBA(r: 0, g: 0, b: 220))
    private let after = picture(
        width: 8, height: 8, left: RGBA(r: 0, g: 200, b: 0), right: RGBA(r: 240, g: 240, b: 0))

    @Test("Glyphs converted from the old pixels are converted again from the new ones")
    func glyphsFollowTheReload() {
        let shared = Self.snapshotContext()
        let old = KittyGraphics.withSupport(false) { Self.draw(before, in: shared) }
        let reloaded = KittyGraphics.withSupport(false) { Self.draw(after, in: shared) }
        let fresh = KittyGraphics.withSupport(false) { Self.draw(after, in: Self.snapshotContext()) }
        #expect(!old.isEmpty, "the first render drew nothing, so the case is vacuous")
        #expect(fresh != old, "the new pixels must draw differently, or this proves nothing")
        #expect(reloaded == fresh, "the view drew the glyphs it had converted from the old pixels")
    }

    @Test("A picture sent from the old pixels is sent again from the new ones, and not otherwise")
    func pictureFollowsTheReload() {
        let tui = Self.snapshotContext()
        let cell = TerminalCellPixels(width: 8, height: 16)
        KittyGraphics.withSupport(true) {
            _ = Self.draw(before, in: tui, pixelsCell: cell)
            #expect(tui.terminalImageStore.takePending().contains("a=t,"), "the first render sends the picture")
            _ = Self.draw(before, in: tui, pixelsCell: cell)
            #expect(!tui.terminalImageStore.takePending().contains("a=t,"), "nothing changed, so nothing is sent")
            _ = Self.draw(after, in: tui, pixelsCell: cell)
            #expect(
                tui.terminalImageStore.takePending().contains("a=t,"),
                "the source decoded to new pixels, and the terminal kept the old picture")
        }
    }
}
