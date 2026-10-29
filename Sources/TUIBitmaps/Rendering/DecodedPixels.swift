//  🖥️ TUI — A Terminal UI framework for Swift
//  DecodedPixels.swift
//
//  WHICH decoded pixels a picture was made from: the buffer itself, held.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIImage

/// The pixel buffer a picture was decoded into, kept, and compared by being
/// that buffer — not by what it holds.
///
/// What a picture's source names is not what it decodes to: a file rewritten
/// at the same path and size decodes to new pixels (the URL cache keys a file
/// by its size AND modification time), and a view that loads it again — a row
/// scrolled back into a list, whose state outlived the window — draws the new
/// load under the same name and the same dimensions. A key of those served the
/// glyphs, or the terminal's picture, made from the old pixels.
///
/// One buffer, held by both sides of the comparison, so neither can have
/// changed it in place and its address cannot be handed to another while this
/// holds it — the argument `_TableOutlineRoots.hasSameRows(as:)` makes for its
/// rows. So equal is the same pixels, at the price of two pointer reads. A new
/// load is a new buffer, unequal even where the pixels happen to agree: that
/// costs one conversion, or one transmission, per load, never one per frame.
///
/// Holding the buffer keeps nothing alive the view does not: the phase it was
/// loaded into holds the same one, until the next load replaces both.
///
/// Or, for a picture the image cache keeps rather than the view
/// (``ImageLoadingPhase/cached(_:)``), the decode the cache filed it as
/// (``ImageDecodeID``): the same exactness — one object per decode, held, so
/// never another's — without holding the pixels, which is what lets a row
/// scrolled out of a long list keep its conversion and not its picture.
struct DecodedPixels: Equatable {
    private enum Identity {
        case buffer([RGBA])
        case decode(ImageDecodeID)
    }

    private let identity: Identity

    /// The pixels `image` was decoded into.
    init(_ image: RGBAImage) {
        identity = .buffer(image.pixels)
    }

    /// The pixels the cache filed as `decode`.
    init(decode: ImageDecodeID) {
        identity = .decode(decode)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.identity, rhs.identity) {
        case (.buffer(let mine), .buffer(let theirs)):
            mine.withUnsafeBufferPointer { mine in
                theirs.withUnsafeBufferPointer { theirs in
                    mine.baseAddress == theirs.baseAddress && mine.count == theirs.count
                }
            }
        case (.decode(let mine), .decode(let theirs)):
            mine === theirs
        default:
            false
        }
    }
}
