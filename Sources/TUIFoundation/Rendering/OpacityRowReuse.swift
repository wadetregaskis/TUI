//  🖥️ TUI — A Terminal UI framework for Swift
//  OpacityRowReuse.swift
//
//  The rows the screen root's opacity resolution rebuilt, kept for the next
//  frame: a row whose line and claims are what they were comes out as it did,
//  so it is not taken apart and blended again. `Opacity as composition.md` §115.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIStyling

/// What the screen root's opacity resolution made of each row last frame, for a
/// frame that draws the same row again.
///
/// A rebuilt row is a function of its line, the claims covering it, and what the
/// blend reads besides: the surface and the terminal's ink it was resolved
/// against, the two flags that say how a field is stated, the colour depth, the
/// terminal's reported colours, its width traits and whether hairlines are drawn
/// (``Inputs``). At the root nothing else reaches it: there is nothing behind the
/// buffer, so there is no destination row to read and no frost to average. So
/// where the line and the claims are equal to the ones kept, and the inputs are
/// the ones in force, the kept answer is exactly the one a rebuild would give.
///
/// The one exception is a row drawing a picture. Its blend asks the image store
/// for a mixed copy of the picture (`OpacityBlend+Pictures.swift`), which the
/// store keeps track of, so such a row is rebuilt every frame and never kept.
///
/// What it saves is the whole of a row's rebuild: taking the line apart into
/// cells, blending them, spelling the span and splicing it back. A page that
/// carries a claim to the root on every frame (a `Color.clear` under a
/// `TimelineView`, a faded label beside a ticking clock) paid that for every
/// covered row of every frame, changed or not: 38% of a frame of `app-shapes`'s
/// `game-loop`, whose board moves once a second.
///
/// Owned by the run loop's diff writer, and dropped with the rest of its caches
/// when the writer forgets what it drew: one instance for one app's screen,
/// never shared. Where a layer is up the page is resolved before it is drawn
/// over, by the overlay compositing, which keeps its rows the same way in an
/// instance of its own, and its modals' veils theirs (``OverlayRowReuse``,
/// §116): a veil is a rewrite of every row that reads nothing of the row but
/// its line, so it keys on the line alone (``rewritingEvery(_:under:with:)``). And
/// each painted layer's splice into the rows below it keeps the pieces it cut each
/// row into, keyed on the row's line and how wide the layer's line on it is
/// (``splicing(_:layer:under:with:)``, §117).
package final class OpacityRowReuse {

    /// Everything a rebuilt row reads besides its line and the claims over it.
    struct Inputs: Equatable {
        var surface: Color
        var defaultForeground: Color
        var statingTheSurface: Bool
        var fillingStatedTerminalField: Bool
        /// The colour a modal's veil moves the page toward, for the rows a veil
        /// rewrote (``rewritingEvery(_:under:with:)``); `nil` for a resolution's.
        var scrim: Color?
        /// Where a layer's lines went into the rows below them and how, for the rows
        /// a layer's splice made (``splicing(_:layer:under:with:)``); `nil` for a
        /// resolution's and a veil's.
        var splice: Splice?
        // Read by the blend from where they are kept for the whole process, so
        // taken here, as the blend will find them.
        var depth = ColorDepth.current
        var terminalColours = TerminalColors.current
        var widths = TerminalWidthTraits.current
        var hairlines = KittyGraphics.isHairlineSupported
    }

    /// What a painted layer's splice reads besides a row's line and the width of
    /// the layer's line on it
    /// (`FrameBuffer.composited(with:at:overlayIsPainted:terminalForeground:composingRows:)`):
    /// the column the layer's lines go in at and the width every row is padded to.
    struct Splice: Equatable {
        var column: Int
        var width: Int
    }

    /// What a row was made into.
    enum Answer {
        /// A rebuilt line; `nil` where the line was left as it was.
        case line(String?)
        /// The row's line cut round the layer's line on it (or only padded, where
        /// the layer has none there), for a splice: joined round whatever the layer
        /// draws there now, which the pieces do not read.
        case pieces(OverlayRowPieces)
    }

    /// One row as the resolution found it, and what it made of it.
    struct Row {
        var line: String
        var covering: [OpacityRegion]
        /// How wide the layer's line spliced over it is, for a splice's row; `nil`
        /// for every other row, and for a splice's row the layer does not reach.
        var layerWidth: Int?
        var answer: Answer
    }

    private var inputs: Inputs?
    private var rows: [Row?] = []

    package init() {}

    /// Rebuilds each of `lines` that `claims` cover with `rebuild`, or with what it
    /// made of the same line under the same claims last time.
    ///
    /// - Parameters:
    ///   - lines: The buffer's lines, each replaced by its rebuild where it has one.
    ///   - claims: Every claim the resolution spends on them.
    ///   - inputs: What the rebuild reads besides; a row kept under other ones is
    ///     not used, and none is kept past them.
    ///   - rebuild: A row's rebuild, from its index, its line and the claims
    ///     covering it, or `nil` where it leaves the line alone.
    func rebuild(
        _ lines: inout [String], claims: [OpacityRegion], under inputs: Inputs,
        with rebuild: (Int, String, [OpacityRegion]) -> String?
    ) {
        keeping(
            &lines, under: inputs,
            covering: { row in
                let covering = claims.filter { $0.spans(row: row) }
                return covering.isEmpty ? nil : covering
            },
            with: { row, line, covering, _ in .line(rebuild(row, line, covering)) })
    }

    /// Rewrites every one of `lines` with `rewrite`, or with what it made of the
    /// same line last time: a modal's veil (``FrameBuffer/veiledAsBackdrop(by:surface:palette:images:reusing:)``),
    /// which reads nothing of a row but its line and `inputs`, the scrim among
    /// them.
    ///
    /// - Parameters:
    ///   - lines: The buffer's lines, each replaced by its rewrite where it has one.
    ///   - inputs: What the rewrite reads besides; a row kept under other ones is
    ///     not used, and none is kept past them.
    ///   - rewrite: A row's rewrite, or `nil` where it leaves the line alone.
    func rewritingEvery(_ lines: inout [String], under inputs: Inputs, with rewrite: (String) -> String?) {
        keeping(&lines, under: inputs, covering: { _ in [] }, with: { _, line, _, _ in .line(rewrite(line)) })
    }

    /// Splices a painted layer's line into each of `lines` it is on, between the
    /// pieces `pieces` cuts the row's line into, or the ones it cut from the same
    /// line for a layer line as wide last time: a layer's splice into the rows below
    /// it (`FrameBuffer.compositedResolvingOpacity`). The pieces read nothing of a
    /// row but its line, how wide the layer's line on it is, and `inputs`, the
    /// splice's column and width among them; the layer's line itself is put between
    /// them afresh every time, so a layer whose lines change over rows that do not
    /// (a list scrolled in a sheet over the veiled page) still keeps every row's cut.
    ///
    /// - Parameters:
    ///   - lines: The lines below the layer, each replaced by its composed row.
    ///   - layer: The layer's line on a row, or `nil` where it has none there.
    ///   - inputs: What the pieces read besides; a row kept under other ones is
    ///     not used, and none is kept past them.
    ///   - pieces: A row's pieces, from its line and the width of the layer's line
    ///     on it (`nil` where the layer has none there).
    func splicing(
        _ lines: inout [String], layer: (Int) -> String?, under inputs: Inputs,
        with pieces: (String, Int?) -> OverlayRowPieces
    ) {
        keeping(
            &lines, under: inputs, covering: { _ in [] }, layer: layer,
            with: { _, line, _, layerWidth in .pieces(pieces(line, layerWidth)) })
    }

    /// Rebuilds each of `lines` that `covering` gives claims for (`nil` leaves a
    /// row alone, kept or not), keyed on its line, those claims and the width of the
    /// layer's line on it: what every use of the reuse shares.
    private func keeping(
        _ lines: inout [String], under inputs: Inputs, covering claimsOn: (Int) -> [OpacityRegion]?,
        layer layerOn: (Int) -> String? = { _ in nil }, with rebuild: (Int, String, [OpacityRegion], Int?) -> Answer
    ) {
        if inputs != self.inputs {
            self.inputs = inputs
            rows = []
        }
        if rows.count > lines.count { rows.removeLast(rows.count - lines.count) }
        for row in lines.indices {
            let line = lines[row]
            guard let covering = claimsOn(row) else { continue }
            let layerLine = layerOn(row)
            let layerWidth = layerLine?.strippedLength
            func apply(_ answer: Answer) {
                switch answer {
                case .line(let rebuilt): if let rebuilt { lines[row] = rebuilt }
                case .pieces(let pieces): lines[row] = pieces.joined(around: layerLine ?? "")
                }
            }
            if rows.indices.contains(row), let kept = rows[row], kept.line == line, kept.layerWidth == layerWidth,
                kept.covering == covering
            {
                apply(kept.answer)
                continue
            }
            let answer = rebuild(row, line, covering, layerWidth)
            apply(answer)
            // A picture's blend asks the store for a copy of it, which a kept
            // answer would not: such a row is rebuilt every frame. (Nothing of a
            // layer's line is kept, so a picture in it is drawn afresh as it is.)
            guard !line.unicodeScalars.contains(.terminalImagePlaceholder) else {
                if rows.indices.contains(row) { rows[row] = nil }
                continue
            }
            if rows.count <= row { rows.append(contentsOf: repeatElement(nil, count: row + 1 - rows.count)) }
            rows[row] = Row(line: line, covering: covering, layerWidth: layerWidth, answer: answer)
        }
    }

    /// Forgets every row.
    package func removeAll() {
        inputs = nil
        rows = []
    }
}
