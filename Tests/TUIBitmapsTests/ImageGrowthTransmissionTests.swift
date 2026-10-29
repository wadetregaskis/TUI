//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageGrowthTransmissionTests.swift
//
//  A picture whose box changes frame after frame — an animated frame, a
//  navigation zoom growing a photo into a screen — was sent to the terminal
//  again at every new size: half a megabyte a frame for a photo, and frames a
//  third of a second apart. What a view has sent is now kept wherever it has
//  enough pixels for the box, and a growth past it is sent at twice the box,
//  so a growth costs a send or two.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Image growth transmissions")
struct ImageGrowthTransmissionTests {

    /// One view's picture drawn at each width in turn, in one context, as an
    /// animation's frames draw it: what each frame owed the terminal.
    private func frames(
        _ image: RGBAImage, path: String, widths: [Int], contentMode: ContentMode = .fit,
        atNanos instants: [Int64]? = nil, natural: Bool = false
    ) -> [String] {
        let tui = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        environment.imageCellPixels = TerminalCellPixels(width: 8, height: 16)
        environment.imageContentMode = contentMode
        if natural {
            environment.imageFitTarget = .naturalSize
            environment.imageCellPoints = TerminalCellPoints(width: 7, height: 14)
        }
        let identity = ViewIdentity(path: "Root")
        let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: 0), default: .loading)
        phase.value = .success(image)
        return widths.enumerated().map { index, width in
            environment.frameNowNanos = instants?[index] ?? 0
            let context = RenderContext(
                availableWidth: width, availableHeight: width, environment: environment,
                tuiContext: tui, identity: identity)
            tui.stateStorage.beginRenderPass()
            defer { tui.stateStorage.endRenderPass() }
            _ = renderToBuffer(_ImageCore(source: .file(path)), context: context)
            return tui.terminalImageStore.takePending()
        }
    }

    private func load(width: Int, height: Int) throws -> (image: RGBAImage, path: String) {
        let fixture = try BitmapFixture(width: width, height: height)
        return (try PlatformImageLoader().loadImage(from: fixture.path), fixture.path)
    }

    private func transmits(_ pending: String) -> Bool { pending.contains("a=t") }

    @Test("A growing picture is sent a few times, not once a frame")
    func growthSendsFewTimes() throws {
        let (image, path) = try load(width: 400, height: 200)
        let owed = KittyGraphics.withSupport(true) {
            frames(image, path: path, widths: Array(stride(from: 10, through: 30, by: 2)))
        }
        let sends = owed.filter(transmits).count
        // The first frame, the first growth past it (sent at twice its box),
        // and one more past that: three for eleven frames.
        #expect(sends == 3, "sent \(sends) times over \(owed.count) frames")
        #expect(owed.allSatisfy { $0.contains("a=p,U=1") }, "every frame places the picture in its box")
    }

    @Test("A shrinking picture keeps what it was sent")
    func shrinkSendsNothing() throws {
        let (image, path) = try load(width: 400, height: 200)
        let owed = KittyGraphics.withSupport(true) {
            frames(image, path: path, widths: Array(stride(from: 30, through: 10, by: -2)))
        }
        #expect(owed.filter(transmits).count == 1, "only the first frame sends pixels")
    }

    @Test("Growth is never sent at more pixels than the picture has")
    func growthClampedToThePicture() throws {
        let (image, path) = try load(width: 100, height: 50)
        let owed = KittyGraphics.withSupport(true) {
            frames(image, path: path, widths: [8, 10])
        }
        // Twice the second box is 160 × 96 pixels, more than the picture's
        // own 100 × 50 on both axes: it is sent whole, at its own aspect.
        let size = owed[1].firstMatch(of: /a=t,[^;]*?s=(\d+),v=(\d+)/)
        #expect(size.map { "\($0.1)×\($0.2)" } == "100×50", "got \(owed[1].prefix(60))")
    }

    /// The resolutions each transmission in `owed` sent.
    private func sentSizes(_ owed: [String]) -> [(width: Int, height: Int)] {
        owed.flatMap { pending in
            pending.matches(of: /a=t,[^;]*?s=(\d+),v=(\d+)/).compactMap { match in
                Int(match.1).flatMap { width in Int(match.2).map { (width, $0) } }
            }
        }
    }

    /// A fitted picture is sent at its own aspect at every size, so the
    /// terminal draws it undistorted in every box, whatever the box's whole
    /// cells round to (the owner's PICTURE-ASPECT, 2026-10-28).
    @Test("A fitted picture is always sent at its own aspect")
    func fittedKeepsItsAspect() throws {
        let (image, path) = try load(width: 400, height: 200)
        let owed = KittyGraphics.withSupport(true) {
            frames(image, path: path, widths: Array(stride(from: 9, through: 31, by: 2)))
        }
        let sizes = sentSizes(owed)
        try #require(!sizes.isEmpty)
        #expect(sizes.allSatisfy { abs($0.width - 2 * $0.height) <= 1 }, "\(sizes)")
    }

    /// At its natural size a picture's box is its own rounded to whole cells:
    /// a 20-point square on 7 × 14-point cells is 3 × 1 cells, 24 × 16 pixels.
    /// It is sent square all the same, for the terminal to fit undistorted,
    /// not stretched to 3:2 (2026-10-29 review).
    @Test("A picture at its natural size is sent at its own aspect")
    func naturalSizeKeepsItsAspect() throws {
        let (image, path) = try load(width: 20, height: 20)
        let owed = KittyGraphics.withSupport(true) { frames(image, path: path, widths: [40], natural: true) }
        let sent = try #require(sentSizes(owed).first)
        #expect(sent.width == sent.height, "sent \(sent)")
    }

    /// One box draws the picture the same whatever it was drawn in before: a
    /// 28-column box after a 30-column one sends what a fresh 28-column box
    /// would draw, at the picture's own aspect either way.
    @Test("A box draws a fitted picture the same whatever came before")
    func sameBoxDrawsTheSame() throws {
        let (image, path) = try load(width: 400, height: 200)
        let history = KittyGraphics.withSupport(true) { frames(image, path: path, widths: [30, 28]) }
        let fresh = KittyGraphics.withSupport(true) { frames(image, path: path, widths: [28]) }
        let kept = try #require(sentSizes(history).last)
        let sentFresh = try #require(sentSizes(fresh).last)
        // Both at the picture's aspect, so the terminal fits them to the box
        // alike.
        #expect(abs(kept.width * sentFresh.height - sentFresh.width * kept.height) <= max(kept.width, sentFresh.width))
    }

    /// A filled picture covers its box: sent at the box's aspect — the picture
    /// cropped to it, not stretched — so the terminal fills the box edge to
    /// edge. 8 × 16 pixels a cell.
    @Test("A filled picture is sent at its box's aspect, cropped")
    func filledCoversItsBox() throws {
        let (image, path) = try load(width: 400, height: 200)
        for width in [9, 11, 13] {
            let owed = KittyGraphics.withSupport(true) {
                frames(image, path: path, widths: [width], contentMode: .fill)
            }
            let sent = try #require(sentSizes(owed).first)
            let box = try #require(owed.first?.firstMatch(of: /a=p,U=1[^\u{1B}]*?c=(\d+),r=(\d+)/))
            let (columns, rows) = (Int(box.1) ?? 0, Int(box.2) ?? 0)
            // Within a pixel of the box's own aspect, 8 × 16 pixels a cell.
            #expect(
                abs(sent.width * rows * 16 - sent.height * columns * 8) <= max(columns * 8, rows * 16),
                "box \(columns)×\(rows) cells, sent \(sent)")
        }
    }

    /// A picture at rest is drawn from pixels sent for its exact box: while the
    /// box moves the kept pixels are placed, and once it has held still for
    /// `PictureSettle.delayNanos` it is sent again at the box's own size (the
    /// owner, 2026-10-28; a terminal's scaling measured softer).
    @Test("A shrunk picture is sent again at its exact size once its box holds still")
    func settledPictureIsExact() throws {
        let (image, path) = try load(width: 400, height: 200)
        let quarter = PictureSettle.delayNanos
        let owed = KittyGraphics.withSupport(true) {
            frames(image, path: path, widths: [30, 20, 20, 20], atNanos: [0, 10_000_000, 20_000_000, 20_000_000 + quarter])
        }
        #expect(transmits(owed[0]), "the first frame sends")
        #expect(!transmits(owed[1]) && !transmits(owed[2]), "while it has not settled, the kept pixels are placed")
        #expect(transmits(owed[3]), "settled, it is sent at its box's size")
        let fresh = KittyGraphics.withSupport(true) { frames(image, path: path, widths: [20]) }
        let settledSize = try #require(sentSizes([owed[3]]).last)
        let freshSize = try #require(sentSizes(fresh).last)
        #expect(settledSize.width == freshSize.width && settledSize.height == freshSize.height, "\(settledSize) against a fresh \(freshSize)")
    }
}
