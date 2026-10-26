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
    private func frames(_ image: RGBAImage, path: String, widths: [Int]) -> [String] {
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
        let identity = ViewIdentity(path: "Root")
        let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: 0), default: .loading)
        phase.value = .success(image)
        return widths.map { width in
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
        // Twice the second box is 160 × 96 pixels; the picture has 100 × 50,
        // and one factor clamps both, so the height binds: 83 × 50.
        let size = owed[1].firstMatch(of: /a=t,[^;]*?s=(\d+),v=(\d+)/)
        #expect(size.map { "\($0.1)×\($0.2)" } == "83×50", "got \(owed[1].prefix(60))")
    }
}
