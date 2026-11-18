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
/// its line, so it keys on the line alone (``rewritingEvery(_:under:with:)``).
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
        // Read by the blend from where they are kept for the whole process, so
        // taken here, as the blend will find them.
        var depth = ColorDepth.current
        var terminalColours = TerminalColors.current
        var widths = TerminalWidthTraits.current
        var hairlines = KittyGraphics.isHairlineSupported
    }

    /// One row as the resolution found it, and what it made of it: `nil` where
    /// it left the line as it was.
    struct Row {
        var line: String
        var covering: [OpacityRegion]
        var rebuilt: String?
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
        keeping(&lines, under: inputs, with: rebuild) { row in
            let covering = claims.filter { $0.spans(row: row) }
            return covering.isEmpty ? nil : covering
        }
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
        keeping(&lines, under: inputs, with: { _, line, _ in rewrite(line) }, covering: { _ in [] })
    }

    /// Rebuilds each of `lines` that `covering` gives claims for (`nil` leaves a
    /// row alone, kept or not), keyed on its line and those claims: what every
    /// use of the reuse shares.
    private func keeping(
        _ lines: inout [String], under inputs: Inputs, with rebuild: (Int, String, [OpacityRegion]) -> String?,
        covering claimsOn: (Int) -> [OpacityRegion]?
    ) {
        if inputs != self.inputs {
            self.inputs = inputs
            rows = []
        }
        if rows.count > lines.count { rows.removeLast(rows.count - lines.count) }
        for row in lines.indices {
            let line = lines[row]
            guard let covering = claimsOn(row) else { continue }
            if rows.indices.contains(row), let kept = rows[row], kept.line == line, kept.covering == covering {
                if let rebuilt = kept.rebuilt { lines[row] = rebuilt }
                continue
            }
            let rebuilt = rebuild(row, line, covering)
            if let rebuilt { lines[row] = rebuilt }
            // A picture's blend asks the store for a copy of it, which a kept
            // answer would not: such a row is rebuilt every frame.
            guard !line.unicodeScalars.contains(.terminalImagePlaceholder) else {
                if rows.indices.contains(row) { rows[row] = nil }
                continue
            }
            if rows.count <= row { rows.append(contentsOf: repeatElement(nil, count: row + 1 - rows.count)) }
            rows[row] = Row(line: line, covering: covering, rebuilt: rebuilt)
        }
    }

    /// Forgets every row.
    package func removeAll() {
        inputs = nil
        rows = []
    }
}
