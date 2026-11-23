//  🖥️ TUI — A Terminal UI framework for Swift
//  QuitStoreFlushTests.swift
//
//  What is flushed as the app quits: the default store, and every store the
//  app's scenes name with `.defaultAppStorage(_:)`, each once. Only the
//  default was (bug hunt FENV-1, 2026-11-20), so a setting a scene's store
//  kept could miss its file at a quit.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("The stores flushed as the app quits")
struct QuitStoreFlushTests {

    /// The presenter after a frame's catalogue of `scene`.
    private func presenter(_ scene: some Scene) -> ScenePresenter {
        let presenter = ScenePresenter()
        presenter.sync(with: SceneCatalog(scene, identity: ViewIdentity(rootType: Never.self)))
        return presenter
    }

    @Test("Each store a scene names is flushed, once, and no scene store is made to be flushed")
    func scenesStoresAreFlushed() {
        let first = MockStorageBackend()
        let second = MockStorageBackend()
        let scenes = presenter(
            Group {
                WindowGroup { Text("first") }.defaultAppStorage(first)
                WindowGroup { Text("second") }.defaultAppStorage(second).defaultAppStorage(first)
            })
        scenes.synchronizeStores()
        #expect(first.synchronizeCallCount == 1, "named twice, flushed once")
        #expect(second.synchronizeCallCount == 1)
    }
}
