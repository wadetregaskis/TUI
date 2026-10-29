//  🖥️ TUI — A Terminal UI framework for Swift
//  ImageSource.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIFoundation
import TUIImage

// MARK: - Image Source

/// Describes where to load an image from.
public enum ImageSource: Sendable, Equatable {
    /// Load from a local file path.
    case file(String)

    /// Load from a URL (cached per session).
    case url(String)
}

// MARK: - Image Loading Phase

/// Represents the current state of an async image loading operation.
enum ImageLoadingPhase: Sendable {
    /// Loading has not started yet or is in progress.
    case loading

    /// The raw image was successfully loaded and is ready for conversion,
    /// its pixels held here: pixels that came with the image (an
    /// `AppKit`/`CGImage` picture, an `RGBAImage` handed over), or a picture
    /// the cache does not keep (none in the environment, or one larger than
    /// it holds).
    case success(RGBAImage)

    /// Loaded, its pixels kept by the image cache rather than here: a row's
    /// state, which lives as long as its list, holds a few words for the
    /// picture, and the cache, bounded in bytes, holds the pixels. The view
    /// holds them too while it is drawn (``ImagePixelPin``).
    case cached(CachedPicture)

    /// Loading failed with an error.
    case failure(String)

    /// The phase of `image`, loaded from `source` through `cache`: kept by
    /// the cache when the cache holds this very buffer under `source`'s key —
    /// which it does just after the load put it there, unless it was too big
    /// to keep or another load replaced it — and held here otherwise.
    static func loaded(_ image: RGBAImage, from source: ImageSource, cache: URLImageCache?) -> Self {
        guard let cache, let key = CachedPicture.key(of: source),
            let entry = cache.entry(key), DecodedPixels(entry.image) == DecodedPixels(image)
        else { return .success(image) }
        return .cached(
            CachedPicture(key: key, decode: entry.decode, width: image.width, height: image.height, source: source))
    }
}

/// A picture the image cache keeps (``ImageLoadingPhase/cached(_:)``): where
/// it is filed, which decode it is, and its size — what a view needs to lay
/// it out, and to find its pixels again.
struct CachedPicture: Sendable {
    /// The key the cache files it under.
    let key: String
    /// Which decode it is: the cache files a new one under the same key once
    /// the old is evicted and the source loaded again.
    let decode: ImageDecodeID
    let width: Int
    let height: Int
    /// What loads it again, once the cache has let it go.
    let source: ImageSource

    /// The pixels, while the cache still has this decode.
    func pixels(in cache: URLImageCache?) -> RGBAImage? {
        guard let entry = cache?.entry(key), entry.decode === decode else { return nil }
        return entry.image
    }

    /// The key `source`'s picture is cached under, as the loader files it: a
    /// URL's address, or a file's path, size and modification time.
    static func key(of source: ImageSource) -> String? {
        switch source {
        case .url(let address): address
        case .file(let path): PlatformImageLoader.cacheKey(forFile: path)
        }
    }
}
