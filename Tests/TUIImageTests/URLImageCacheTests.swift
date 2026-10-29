//  🖥️ TUI — A Terminal UI framework for Swift
//  URLImageCacheTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIImage

/// The URL image cache keeps at most its byte limit, four bytes a pixel,
/// letting the least recently used go first.
@Suite("A URL image cache is bounded in bytes")
struct URLImageCacheTests {
    /// A square image of `side` pixels: `side * side * 4` bytes.
    private func image(_ side: Int) -> RGBAImage {
        RGBAImage(width: side, height: side, pixels: Array(repeating: RGBA(r: 1, g: 2, b: 3), count: side * side))
    }

    @Test("Past its limit the least recently used image goes first, and a read counts as a use")
    func evictsTheLeastRecentlyUsed() {
        // Three 4 × 4 images are 64 bytes each; 150 bytes holds two.
        let cache = URLImageCache(byteLimit: 150)
        cache.set("a", image: image(4))
        cache.set("b", image: image(4))
        #expect(cache.get("a") != nil)  // a is now the more recent
        cache.set("c", image: image(4))
        #expect(cache.get("a") != nil, "a was used after b")
        #expect(cache.get("b") == nil, "b was the least recently used")
        #expect(cache.get("c") != nil)
        #expect(cache.byteCount == 128)
    }

    @Test("An image larger than the whole limit is not kept, and keeps nothing out")
    func oversizedIsNotKept() {
        let cache = URLImageCache(byteLimit: 100)
        cache.set("small", image: image(4))
        cache.set("huge", image: image(10))  // 400 bytes
        #expect(cache.get("huge") == nil)
        #expect(cache.get("small") != nil)
        #expect(cache.byteCount == 64)
    }

    @Test("Storing a URL again replaces its image and its cost")
    func replacingCountsOnce() {
        let cache = URLImageCache(byteLimit: 1_000)
        cache.set("a", image: image(4))
        cache.set("a", image: image(2))
        #expect(cache.byteCount == 16)
        #expect(cache.get("a")?.width == 2)
    }

    @Test("A limit of zero keeps nothing")
    func zeroKeepsNothing() {
        let cache = URLImageCache(byteLimit: 0)
        cache.set("a", image: image(1))
        #expect(cache.get("a") == nil)
        #expect(cache.byteCount == 0)
    }

    /// Sizes as `TUI_IMAGE_CACHE_SIZE` spells them, and the bytes each names.
    /// Typed, as a literal of tuples left to inference takes the type checker
    /// too long.
    private static let sizes: [(text: String, bytes: Int)] = [
        ("0", 0), ("1000", 1000), (" 64k ", 64 << 10), ("64KB", 64 << 10), ("64KiB", 64 << 10),
        ("256M", 256 << 20), ("256 mib", 256 << 20), ("1G", 1 << 30), ("2gb", 2 << 30),
    ]

    /// Values that name no size.
    private static let nonsizes: [String?] = [nil, "", "M", "-5", "+5", "1.5G", "256T", "256b", "lots", "١٢"]

    @Test("TUI_IMAGE_CACHE_SIZE names bytes, or KiB, MiB or GiB by suffix", arguments: sizes)
    func parsesASize(size: (text: String, bytes: Int)) {
        #expect(URLImageCache.byteLimit(named: size.text) == size.bytes)
    }

    @Test("A value TUI_IMAGE_CACHE_SIZE cannot read leaves the default", arguments: nonsizes)
    func ignoresWhatItCannotRead(text: String?) {
        #expect(URLImageCache.byteLimit(named: text) == nil)
    }

    @Test("A size too large for an Int is no bound at all")
    func clampsAnOverflow() {
        #expect(URLImageCache.byteLimit(named: "99999999999999999999") == Int.max)
        #expect(URLImageCache.byteLimit(named: "\(Int.max >> 20)G") == Int.max)
    }
}
