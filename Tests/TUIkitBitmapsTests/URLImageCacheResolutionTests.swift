//  🖥️ TUIkit — Terminal UI Kit for Swift
//  URLImageCacheResolutionTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitBitmaps
@testable import TUIkitFoundation
import TUIkitImage

/// Which cache a URL image loads through: a subtree's own, else its app's —
/// one per app, made when first asked for — and none outside an app. No
/// process-wide cache (CLAUDE.md, No Singletons).
@MainActor
@Suite("A URL image's cache is the subtree's or its app's")
struct URLImageCacheResolutionTests {
    @Test("An app's views share one cache, made when first asked for")
    func oneCachePerApp() {
        var environment = EnvironmentValues()
        environment.appScopedObjects = AppScopedObjects()
        let first = environment.resolvedURLImageCache
        #expect(first != nil)
        #expect(first === environment.resolvedURLImageCache)
    }

    @Test("Two apps have two caches")
    func twoAppsTwoCaches() {
        var one = EnvironmentValues()
        one.appScopedObjects = AppScopedObjects()
        var other = EnvironmentValues()
        other.appScopedObjects = AppScopedObjects()
        #expect(one.resolvedURLImageCache !== other.resolvedURLImageCache)
    }

    @Test("A subtree's own cache wins over the app's")
    func subtreeWins() {
        var environment = EnvironmentValues()
        environment.appScopedObjects = AppScopedObjects()
        let own = URLImageCache()
        environment.urlImageCache = own
        #expect(environment.resolvedURLImageCache === own)
    }

    @Test("Outside an app nothing is cached")
    func noAppNoCache() {
        #expect(EnvironmentValues().resolvedURLImageCache == nil)
    }
}
