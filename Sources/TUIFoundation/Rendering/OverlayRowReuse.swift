//  🖥️ TUI — A Terminal UI framework for Swift
//  OverlayRowReuse.swift
//
//  The rows a screen's overlay compositing resolved, veiled and spliced, kept for
//  the next frame as the root's are (`OpacityRowReuse`). `Opacity as
//  composition.md` §116 and §117.
//
//  Created by Wade Tregaskis
//  License: MIT

/// What one site of the screen's overlay compositing made of each row last
/// frame (`FrameBuffer.compositingOverlays`): the page's own resolution, which
/// is the root's where a layer is up, each modal's veil over what is below
/// it, and each layer's splice into the rows below it.
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

    /// Each layer's splice into the rows below it, by the layer's order in the
    /// frame (§117).
    private var splices: [OpacityRowReuse] = []

    /// How many of a frame's layers keep their splice's rows: every row of the
    /// screen, kept once for each, and a frame can draw hundreds of small layers (a
    /// panel's shadow, content past a region), whose rows a splice past these
    /// makes afresh.
    static let keptSplices = 8

    package init() {}

    /// The reuse for the frame's `index`th veil, counting from 0.
    package func veil(_ index: Int) -> OpacityRowReuse {
        while veils.count <= index { veils.append(OpacityRowReuse()) }
        return veils[index]
    }

    /// The reuse for the splice of the frame's `index`th layer, counting from 0, or
    /// `nil` past the first ``keptSplices``.
    ///
    /// A layer is told from another by its order alone, which is enough: what a
    /// splice keeps of a row is the cut of the row's own line, keyed on everything
    /// the cut reads (the line, the column, the widths), and nothing of the layer's
    /// line, so a frame whose layers come in another order cuts afresh or finds a
    /// cut that is as good for the layer now there.
    package func splice(_ index: Int) -> OpacityRowReuse? {
        guard index < Self.keptSplices else { return nil }
        while splices.count <= index { splices.append(OpacityRowReuse()) }
        return splices[index]
    }
}
