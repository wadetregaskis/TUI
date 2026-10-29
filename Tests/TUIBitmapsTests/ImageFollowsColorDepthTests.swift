//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageFollowsColorDepthTests.swift
//
//  An image drawn as glyphs downgrades its colour mode to what the terminal can
//  show (`ASCIIColorMode.effective(for:)`, read from `ColorDepth.current` as the
//  converter runs). The Image view keeps what it drew in its own state, where the
//  render cache's clear on a depth change does not reach, so the key it keeps it
//  under has to carry the depth, or a picture converted at one depth is drawn at
//  another.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing
@testable import TUIBitmaps
import TUIImage

@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUIStyling
@testable import TUITestSupport

@MainActor
@Suite("An image drawn as glyphs is converted again when the colour depth changes")
struct ImageFollowsColorDepthTests {

    /// Effects off, exactly as `ViewRenderer` builds one for a snapshot: the view must
    /// not start a real load over the phase these cases seat.
    private static func snapshotContext() -> TUIContext {
        TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
    }

    /// Draws `_ImageCore` as glyphs through `tui` at `depth`, with the picture already
    /// loaded, so two calls through one context share one cache box
    /// (ImageFollowsReportedSlotsTests' recipe).
    private static func glyphs(
        _ image: RGBAImage, path: String, depth: ColorDepth, in tui: TUIContext
    ) -> [String] {
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.imageCellAspect = 2.0
        environment.imageColorMode = .trueColor
        let context = RenderContext(
            availableWidth: 8, availableHeight: 4, environment: environment,
            tuiContext: tui, identity: ViewIdentity(path: "Root"))
        let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 0), default: .loading)
        phase.value = .success(image)
        let lastSource: StateBox<ImageSource?> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: 1), default: nil)
        lastSource.value = .file(path)
        tui.stateStorage.beginRenderPass()
        defer { tui.stateStorage.endRenderPass() }
        return KittyGraphics.withSupport(false) {
            ColorDepth.withCurrent(depth) {
                renderToBuffer(_ImageCore(source: .file(path)), context: context).lines
            }
        }
    }

    @Test("A picture converted in true colour is converted again for a 256-colour terminal, and back")
    func glyphCacheFollowsTheDepth() throws {
        let fixture = try BitmapFixture(width: 8, height: 4, left: (220, 30, 10), right: (20, 90, 200))
        let image = try PlatformImageLoader().loadImage(from: fixture.path)
        let shared = Self.snapshotContext()

        let truecolor = Self.glyphs(image, path: fixture.path, depth: .truecolor, in: shared)
        let downgraded = Self.glyphs(image, path: fixture.path, depth: .palette256, in: shared)
        let fresh = Self.glyphs(image, path: fixture.path, depth: .palette256, in: Self.snapshotContext())
        #expect(!truecolor.isEmpty, "the first render drew nothing, so the case is vacuous")
        #expect(fresh != truecolor, "the depth must change the picture, or this proves nothing")
        #expect(downgraded == fresh, "the view drew the true-colour conversion on a 256-colour terminal")

        let again = Self.glyphs(image, path: fixture.path, depth: .truecolor, in: shared)
        #expect(again == truecolor, "and back again once the depth is restored")
    }
}
