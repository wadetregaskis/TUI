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

    /// Loaded at a fraction of its size, as it is drawn small, its pixels
    /// held here: a file's picture the cache does not keep
    /// (``ReducedPicture``). One the cache keeps is ``cached(_:)``.
    case reduced(ReducedPicture)

    /// Loading failed with an error.
    case failure(String)

    /// The phase of `image`, loaded from `source` through `cache`: kept by
    /// the cache when the cache holds this very buffer under `source`'s key —
    /// which it does just after the load put it there, unless it was too big
    /// to keep or another load replaced it — and held here otherwise.
    ///
    /// `image` is the picture at `reduction` of its size, which is `size`
    /// (`image`'s own where not given): a file's picture decoded for the box
    /// it is drawn in (``_ImageCore/reduction(ofPicture:in:zoom:environment:)``).
    static func loaded(
        _ image: RGBAImage, from source: ImageSource, cache: URLImageCache?,
        size: (width: Int, height: Int)? = nil, reduction: Int = 1
    ) -> Self {
        let size = size ?? (image.width, image.height)
        guard let cache, let key = CachedPicture.key(of: source, reducedBy: reduction),
            let entry = cache.entry(key), DecodedPixels(entry.image) == DecodedPixels(image)
        else {
            guard reduction > 1 else { return .success(image) }
            return .reduced(ReducedPicture(image: image, width: size.width, height: size.height, reduction: reduction))
        }
        return .cached(
            CachedPicture(
                key: key, decode: entry.decode, width: size.width, height: size.height, source: source,
                reduction: reduction))
    }

    /// The reduction the pixels it holds were decoded at, 1 for a whole
    /// picture, or `nil` where it holds none.
    var reduction: Int? {
        switch self {
        case .success: 1
        case .cached(let picture): picture.reduction
        case .reduced(let picture): picture.reduction
        case .loading, .failure: nil
        }
    }

    /// The picture's size in pixels, whole — what it is laid out as, however
    /// small its pixels were decoded — or `nil` where nothing has loaded.
    var pictureSize: (width: Int, height: Int)? {
        switch self {
        case .success(let image): (image.width, image.height)
        case .cached(let picture): (picture.width, picture.height)
        case .reduced(let picture): (picture.width, picture.height)
        case .loading, .failure: nil
        }
    }
}

/// A file's picture decoded at a fraction of its size for the box it is drawn
/// in (``ImageLoadingPhase/reduced(_:)``), and the size it has whole.
struct ReducedPicture: Sendable {
    /// The pixels, at ``reduction`` of the picture's size each way.
    let image: RGBAImage
    /// The picture's size, whole: what it is laid out as.
    let width: Int
    let height: Int
    /// The power of two the picture was reduced by.
    let reduction: Int
}

/// A picture the image cache keeps (``ImageLoadingPhase/cached(_:)``): where
/// it is filed, which decode it is, and its size — what a view needs to lay
/// it out, and to find its pixels again.
///
/// Its size is the picture's, whole, whatever size its pixels were decoded
/// at (``reduction``).
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
    /// The power of two its pixels were reduced by: 1 for the picture whole,
    /// more for a file's drawn small. Part of ``key``.
    var reduction = 1

    /// The pixels, while the cache still has this decode.
    func pixels(in cache: URLImageCache?) -> RGBAImage? {
        guard let entry = cache?.entry(key), entry.decode === decode else { return nil }
        return entry.image
    }

    /// The key `source`'s picture is cached under, as the loader files it: a
    /// URL's address, or a file's path, size and modification time.
    static func key(of source: ImageSource) -> String? {
        key(of: source, reducedBy: 1)
    }

    /// The key `source`'s picture decoded at `reduction` of its size is
    /// cached under (``PlatformImageLoader/cacheKey(forFile:reducedBy:)``);
    /// a URL's picture is only ever whole.
    static func key(of source: ImageSource, reducedBy reduction: Int) -> String? {
        switch source {
        case .url(let address): reduction > 1 ? nil : address
        case .file(let path): PlatformImageLoader.cacheKey(forFile: path, reducedBy: reduction)
        }
    }
}
