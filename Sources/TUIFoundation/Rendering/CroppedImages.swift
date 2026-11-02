//  🖥️ TUI — A Terminal UI framework for Swift
//  CroppedImages.swift
//
//  The images sent to a terminal that ignores a placement's source rectangle:
//  each the pixels of one rectangle of a picture, as a picture of its own
//  (`Terminal graphics protocols.md` §15).
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

/// Which crops of the store's images the terminal holds.
///
/// A crop in use is never let go: a frame's placements name it. Past that, what
/// is left in the terminal for a crop to be asked for again — a modal closing and
/// opening, a scroll coming back — is kept up to ``keptLimit`` crops and
/// ``keptByteLimit`` bytes of pixels, the least recently used going first. A
/// scroll leaves one crop behind a frame, so without the limits a terminal would
/// fill with every scroll position there has been.
///
/// Holds no pixels: a crop's are in the terminal, and made from the ones
/// ``DerivedImages`` keeps.
struct CroppedImages {
    /// The rectangle of an image's pixels, as that image was sent.
    struct Key: Hashable {
        let image: KittyGraphics.ImageID
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    /// One crop in the terminal.
    private struct Crop {
        let id: KittyGraphics.ImageID
        let sentWidth: Int
        let sentHeight: Int
        /// The last frame that asked for it.
        var lastUsed: Int

        var bytes: Int { sentWidth * sentHeight * 4 }
    }

    /// The most crops kept with nothing on screen naming them.
    static let keptLimit = 64

    /// The most bytes of pixels kept in the terminal for them, as it holds them.
    static let keptByteLimit = 32 << 20

    private var crops: [Key: Crop] = [:]
    /// The frame in progress, as ``endFrame()`` counts them.
    private var frame = 0

    var isEmpty: Bool { crops.isEmpty }

    /// Whether `id` is a crop's, for the store's id search to skip.
    func contains(_ id: KittyGraphics.ImageID) -> Bool {
        crops.values.contains { $0.id == id }
    }

    /// Every crop's id, in order.
    var ids: [KittyGraphics.ImageID] { crops.values.map(\.id).sorted() }

    /// The crop `key` names, if the terminal holds it, marked as in use this frame.
    mutating func use(_ key: Key) -> (id: KittyGraphics.ImageID, width: Int, height: Int)? {
        guard let crop = crops[key] else { return nil }
        crops[key]?.lastUsed = frame
        return (crop.id, crop.sentWidth, crop.sentHeight)
    }

    /// Records a crop just sent, in use this frame.
    mutating func add(_ key: Key, id: KittyGraphics.ImageID, width: Int, height: Int) {
        crops[key] = Crop(id: id, sentWidth: width, sentHeight: height, lastUsed: frame)
    }

    /// Forgets every crop of image `id`, returning their ids for the store to
    /// delete from the terminal.
    mutating func forget(image id: KittyGraphics.ImageID) -> [KittyGraphics.ImageID] {
        guard !crops.isEmpty else { return [] }
        let gone = crops.filter { $0.key.image == id }
        for key in gone.keys { crops.removeValue(forKey: key) }
        return gone.values.map(\.id).sorted()
    }

    /// Ends a frame, returning the ids of the crops past the limits, for the store
    /// to delete from the terminal: the least recently used of those this frame
    /// did not ask for.
    mutating func endFrame() -> [KittyGraphics.ImageID] {
        defer { frame += 1 }
        let unused = crops.filter { $0.value.lastUsed != frame }
        var bytes = unused.values.reduce(0) { $0 + $1.bytes }
        var count = unused.count
        guard count > Self.keptLimit || bytes > Self.keptByteLimit else { return [] }
        var gone: [KittyGraphics.ImageID] = []
        // By id too: two crops last used in one frame leave in the same order on
        // every run, whatever order a dictionary hands them over in.
        for (key, crop) in unused.sorted(by: { ($0.value.lastUsed, $0.value.id) < ($1.value.lastUsed, $1.value.id) }) {
            guard count > Self.keptLimit || bytes > Self.keptByteLimit else { break }
            crops.removeValue(forKey: key)
            gone.append(crop.id)
            count -= 1
            bytes -= crop.bytes
        }
        return gone
    }
}
