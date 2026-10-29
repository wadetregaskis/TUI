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
struct DecodedPixels: Equatable {
    private let pixels: [RGBA]

    /// The pixels `image` was decoded into.
    init(_ image: RGBAImage) {
        pixels = image.pixels
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.pixels.withUnsafeBufferPointer { mine in
            rhs.pixels.withUnsafeBufferPointer { theirs in
                mine.baseAddress == theirs.baseAddress && mine.count == theirs.count
            }
        }
    }
}
