//  🖥️ TUI — A Terminal UI framework for Swift
//  FileImageCacheTests.swift
//
//  A file's decoded picture is kept in the app's image cache, under its path,
//  size and modification time, so that a NEW view of a picture another view
//  has shown draws it on its first frame. Before, every new `Image` decoded
//  its file again on a task and drew a blank frame meanwhile: a navigation
//  zoom's photo screen started blank, as would a list row scrolled back in.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIBitmaps
@testable import TUICore
@testable import TUIFoundation
@testable import TUIImage
@testable import TUITestSupport

@MainActor
@Suite("File pictures through the image cache")
struct FileImageCacheTests {

    @Test("A file loaded through the cache is held, and found without a decode")
    func loadedFileIsHeld() throws {
        let fixture = try BitmapFixture(width: 6, height: 4)
        let cache = URLImageCache()
        let loader = PlatformImageLoader()
        #expect(try loader.cachedImage(fromFile: fixture.path, cache: cache, maxPixelCount: nil) == nil)
        let loaded = try loader.loadImage(from: fixture.path, cache: cache, maxPixelCount: nil)
        let held = try loader.cachedImage(fromFile: fixture.path, cache: cache, maxPixelCount: nil)
        #expect(held?.width == loaded.width && held?.height == loaded.height)
    }

    @Test("An edited file is not served as it was")
    func editedFileMisses() throws {
        let fixture = try BitmapFixture(width: 6, height: 4)
        let cache = URLImageCache()
        let loader = PlatformImageLoader()
        _ = try loader.loadImage(from: fixture.path, cache: cache, maxPixelCount: nil)
        let other = try BitmapFixture(width: 8, height: 4)
        try FileManager.default.removeItem(atPath: fixture.path)
        try FileManager.default.copyItem(atPath: other.path, toPath: fixture.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: fixture.path)
        #expect(try loader.cachedImage(fromFile: fixture.path, cache: cache, maxPixelCount: nil) == nil)
        #expect(try loader.loadImage(from: fixture.path, cache: cache, maxPixelCount: nil).width == 8)
    }

    @Test("A held picture still has to clear the asker's limit")
    func heldPictureClearsTheLimit() throws {
        let fixture = try BitmapFixture(width: 6, height: 4)
        let cache = URLImageCache()
        let loader = PlatformImageLoader()
        _ = try loader.loadImage(from: fixture.path, cache: cache, maxPixelCount: nil)
        #expect(throws: ImageLoadError.self) {
            try loader.cachedImage(fromFile: fixture.path, cache: cache, maxPixelCount: 10)
        }
    }

    @Test("A new view of a held picture has it on its first frame")
    func newViewDrawsAtOnce() throws {
        let fixture = try BitmapFixture(width: 6, height: 4)
        let cache = URLImageCache()
        _ = try PlatformImageLoader().loadImage(from: fixture.path, cache: cache, maxPixelCount: nil)

        let tui = TUIContext(
            lifecycle: LifecycleManager(firesEffects: false),
            keyEventDispatcher: KeyEventDispatcher(),
            preferences: PreferenceStorage(),
            stateStorage: StateStorage())
        var environment = EnvironmentValues()
        environment.focusManager = FocusManager()
        environment.applyRuntimeServices(from: tui)
        environment.urlImageCache = cache
        let identity = ViewIdentity(path: "Root")
        let context = RenderContext(
            availableWidth: 12, availableHeight: 6, environment: environment, tuiContext: tui, identity: identity)
        tui.stateStorage.beginRenderPass()
        _ = renderToBuffer(_ImageCore(source: .file(fixture.path)), context: context)
        tui.stateStorage.endRenderPass()

        let phase: StateBox<ImageLoadingPhase> = tui.stateStorage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: 0), default: .loading)
        // Kept by the cache, which the phase names rather than holds.
        guard case .cached(let picture) = phase.value else {
            Issue.record("still \(phase.value) after its first frame")
            return
        }
        #expect(picture.width == 6)
        #expect(picture.pixels(in: cache)?.width == 6)
    }
}
