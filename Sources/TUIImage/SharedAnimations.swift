//  🖥️ TUI — A Terminal UI framework for Swift
//  SharedAnimations.swift
//
//  The decoded frames of animated files, shared by every view playing one:
//  one decode, and one set of frames in memory, however many views show it.
//  The image cache's (`URLImageCache.animations`), so it travels with the
//  cache through the environment, as the cache does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Synchronization

/// One animated file's frames, decoded once and held by every view playing
/// them: compared by being this object, as a frame is by its decode.
package final class SharedAnimation: Sendable {
    package let animation: AnimatedImage

    package init(_ animation: AnimatedImage) {
        self.animation = animation
    }
}

/// The frames of the animated files views are playing, by file and pixel
/// limit, held weakly: a file's frames last as long as a view plays them and
/// no longer, as each view's own did, so sharing them costs nothing in
/// memory. Twelve rows of a list showing one spinner decoded it twelve times
/// and held twelve copies of its frames, up to
/// ``AnimatedImageDecoder/byteBudget`` each (hunt H-96, IMAGE-10).
///
/// A view arriving while the file decodes waits on that decode
/// (``JoinedLoads``); one arriving after takes the frames another holds.
/// Frames never change once decoded, so one view's playback cannot disturb
/// another's: what each has made of them (its clock, its conversions, what
/// it sent the terminal) stays its own.
///
/// Not counted against the cache's ``URLImageCache/byteLimit``: what views
/// hold, and nothing more, as before they were shared.
package final class SharedAnimations: Sendable {
    /// A file's frames under one pixel limit, which a decode refuses a file
    /// past.
    private struct Key: Hashable, Sendable {
        let file: String
        let maxPixelCount: Int?
    }

    private struct Held: Sendable {
        weak let animation: SharedAnimation?
    }

    private let held = Mutex<[Key: Held]>([:])
    private let decodes = JoinedLoads<Key, SharedAnimation?>()

    package init() {}

    /// How many times a file's frames have been decoded through this table.
    package var decodeCount: Int {
        decodes.started
    }

    /// The frames of the animated file at `path`, decoded under
    /// `maxPixelCount`, or `nil` if it holds none a decoder here can play
    /// (``AnimatedImageDecoder/decode(atPath:maxPixelCount:)``): another
    /// view's where one holds them, or decoded once for every view that asks
    /// while it runs.
    ///
    /// A file edited since is another file: it is keyed as its still picture
    /// is, by path, size and modification time.
    ///
    /// - Throws: `CancellationError` if the calling task was cancelled while
    ///   it waited; the decode stops only when every view waiting on it has.
    package func animation(atPath path: String, maxPixelCount: Int?) async throws -> SharedAnimation? {
        guard let file = PlatformImageLoader.cacheKey(forFile: path) else {
            return AnimatedImageDecoder.decode(atPath: path, maxPixelCount: maxPixelCount).map(SharedAnimation.init)
        }
        let key = Key(file: file, maxPixelCount: maxPixelCount)
        return try await decodes.value(
            for: key,
            held: { held.withLock { $0[key]?.animation }.map { Optional($0) } },
            land: { [self] decoded in
                guard let decoded else { return nil }
                held.withLock { table in
                    // Let go of what no view holds any more, so the table holds
                    // nothing the views do not.
                    table = table.filter { $0.value.animation != nil }
                    table[key] = Held(animation: decoded)
                }
                return decoded
            },
            load: { AnimatedImageDecoder.decode(atPath: path, maxPixelCount: maxPixelCount).map(SharedAnimation.init) })
    }
}
