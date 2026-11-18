//  🖥️ TUI — A Terminal UI framework for Swift
//  OverlayRowReuse.swift
//
//  The rows a screen's overlay compositing resolved and veiled, kept for the
//  next frame as the root's are (`OpacityRowReuse`). `Opacity as
//  composition.md` §116.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What one site of the screen's overlay compositing made of each row last
/// frame (`FrameBuffer.compositingOverlays`): the page's own resolution, which
/// is the root's where a layer is up, and each modal's veil over what is below
/// it.
///
/// One ``OpacityRowReuse`` for each, never one shared between them: a row is
/// kept by its index, and the resolution and each veil see a different line
/// at the same index, so sharing would trade every row away on every frame.
/// The veils are told apart by their order in the frame, the first modal's
/// veil from the second's (an alert over a sheet veils the sheet too).
///
/// Owned by the window it composites for (`WindowChromeState`), one for the
/// page and one for the whole window: never shared between windows or apps.
package final class OverlayRowReuse {
    /// The page's own resolution, before any layer is drawn over it.
    package let resolution = OpacityRowReuse()

    /// The veils, by their order in the frame.
    private var veils: [OpacityRowReuse] = []

    package init() {}

    /// The reuse for the frame's `index`th veil, counting from 0.
    package func veil(_ index: Int) -> OpacityRowReuse {
        while veils.count <= index { veils.append(OpacityRowReuse()) }
        return veils[index]
    }
}
