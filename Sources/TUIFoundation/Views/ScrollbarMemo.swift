//  🖥️ TUI — A Terminal UI framework for Swift
//  ScrollbarMemo.swift
//
//  A scrollbar kept with the inputs it was drawn from, and drawn again only
//  when one of them moves: a scroll view's two bars, a list's, a text
//  editor's.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore

// MARK: - The bar drawn last time

/// A scrollbar and the animated runs that pulse it, with the inputs they were
/// drawn from — a vertical bar's column or a horizontal bar's row. See
/// `ScrollViewHandler.verticalScrollbarMemo`.
package struct ScrollbarMemo<Bar> {
    /// Everything the bar's cells and runs are a function of. The palette by
    /// its id and the depth outright, since the cells carry resolved colours;
    /// the emphasis cycle's frames and timing, since the runs carry one render
    /// per frame of it, but not where its clock is (``cycle``).
    package struct Key: Equatable {
        /// The bar's length along its axis: a vertical bar's height, a
        /// horizontal bar's width.
        package let length: Int
        package let extent: Int
        package let viewport: Int
        package let offset: Int
        package let arrows: ScrollbarArrows
        package let proportional: Bool
        package let isFocused: Bool
        package let isScrollEnabled: Bool
        /// Whether the bar's view is enabled: a disabled view's resting thumb
        /// is drawn as a pinned one where there is no colour to draw it in
        /// (``ScrollbarColors/focusIndicating(isFocused:hoveredCell:context:)``).
        package let isEnabled: Bool
        package let hoveredCell: Int?
        /// The palette by value where it can be, not by its id: a palette edited in
        /// place keeps the id, and a key of the id served the bar drawn before the edit.
        package let palette: ComparablePalette
        package let depth: ColorDepth
        /// The colours the terminal had reported when the bar was drawn.
        ///
        /// At sixteen colours an RGB colour is emitted as the slot nearest to what that
        /// slot PAINTS — the colour the terminal reported for it, or xterm's value while
        /// it has reported none — so the bar's bytes are a function of the report as well
        /// as of the palette. A palette whose roles are the terminal's own carries the
        /// report through its grounding, which `ComparablePalette` compares; a palette of
        /// RGB colours carries nothing, and without this a bar drawn before a report was
        /// served to every frame after it.
        ///
        /// By value, not by `TerminalColors.generation`, as the image caches are keyed
        /// (b7a2f35d): a task-local pin changes what a slot measures as without moving the
        /// generation. The render cache's clear on a moved generation does not reach this
        /// memo either — it lives on the handler, not in the cache.
        package let terminalColors: TerminalColors
        /// The focus emphasis's cycle, its clock's step left out
        /// (``SelectionEmphasisCycle/unstepped``), or `nil` for a bar that does
        /// not show the focus. The step moves every 50 ms while the focus is
        /// held, and a key of it missed on nearly every render of a live app:
        /// a key typed in a focused editor drew the bar seventeen times, the
        /// bar and its breath's sixteen frames, though nothing about it had
        /// moved (FREND-1). The frame a breathing bar shows now is one of the
        /// frames the memo keeps, picked by the clock at each render
        /// (``showing(step:)``); a bar that does not breathe is keyed by the
        /// frame it shows (``frame``). The still cycle is keyed too, since a
        /// held (inactive) focus and a bright one draw different shades
        /// (FREND-2).
        package let cycle: SelectionEmphasisCycle?
        /// The frame of ``cycle`` a bar with no breath shows now: a flashing
        /// bar's colour is the breath's shade at this frame. 0 for a bar that
        /// breathes, whose frames the memo keeps whole and picks from.
        package let frame: Int
        /// How strongly a `scrollIndicatorsFlash` lit the bar, or `nil`.
        package let flash: Double?
        /// The bar's width in cells (``View/scrollbarWidth(_:)``).
        package let width: Int
        /// Whether a double-width bar's arrows are corner triangles
        /// (``EnvironmentValues/cornerTrianglesFillTheCell``): it follows the
        /// terminal, which can change under a running app — a tmux attach.
        package let cornerTriangles: Bool

        /// The memberwise initializer, spelled out because the synthesized one
        /// is internal and TUILists makes these, for the lists' scrollbars.
        package init(
            length: Int,
            extent: Int,
            viewport: Int,
            offset: Int,
            arrows: ScrollbarArrows,
            proportional: Bool,
            isFocused: Bool,
            isScrollEnabled: Bool,
            isEnabled: Bool = true,
            hoveredCell: Int?,
            palette: ComparablePalette,
            depth: ColorDepth,
            terminalColors: TerminalColors,
            cycle: SelectionEmphasisCycle?,
            frame: Int = 0,
            flash: Double? = nil,
            width: Int = 1,
            cornerTriangles: Bool = false
        ) {
            self.length = length
            self.extent = extent
            self.viewport = viewport
            self.offset = offset
            self.arrows = arrows
            self.proportional = proportional
            self.isFocused = isFocused
            self.isScrollEnabled = isScrollEnabled
            self.isEnabled = isEnabled
            self.hoveredCell = hoveredCell
            self.palette = palette
            self.depth = depth
            self.terminalColors = terminalColors
            self.cycle = cycle?.unstepped
            self.frame = frame
            self.flash = flash
            self.width = width
            self.cornerTriangles = cornerTriangles
        }
    }

    package let key: Key
    /// The bar as it shows now: for a bar that breathes, the frame of
    /// ``frames`` its cycle's clock is on.
    package let bar: Bar
    /// A breathing bar's every frame, in cycle order, which its runs were cut
    /// from; empty for a still bar.
    package let frames: [Bar]
    package let runs: [AnimatedCellRun]

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUILists makes these, for the lists' scrollbars.
    package init(key: Key, bar: Bar, frames: [Bar] = [], runs: [AnimatedCellRun]) {
        self.key = key
        self.bar = bar
        self.frames = frames
        self.runs = runs
    }

    /// This memo showing frame `step` of its breath: itself for a still bar.
    func showing(step: Int) -> Self {
        guard !frames.isEmpty else { return self }
        return Self(key: key, bar: frames[step % frames.count], frames: frames, runs: runs)
    }
}

extension ScrollbarMemo {
    /// The emphasis cycle a bar's key holds, and the frame a bar with no
    /// breath shows: `nil` and 0 for a bar that does not show the focus.
    @MainActor
    static func cycleKey(
        isFocused: Bool, breathes: Bool, context: RenderContext
    ) -> (cycle: SelectionEmphasisCycle?, frame: Int) {
        guard isFocused, context.environment.isScrollEnabled else { return (nil, 0) }
        let cycle = context.environment.selectionEmphasis.cycle(true)
        return (cycle, breathes ? 0 : cycle.step % cycle.frames.count)
    }
}

// MARK: - A vertical bar, drawn again only when its inputs move

extension ScrollbarMemo where Bar == ClaimingColumn {
    /// The vertical bar a view that holds the focus draws, and the runs that
    /// breathe it while it does: `remembered` when every input it was drawn
    /// from is unchanged, else drawn afresh and kept there.
    ///
    /// A focused bar's runs are one bar render PER PULSE FRAME, which is why
    /// the bar and its runs are kept with their inputs. One function for every
    /// bar that indicates its view's focus (a scroll view's, a text editor's),
    /// so the inputs the memo is keyed by and the ones the drawing reads
    /// cannot drift apart between them.
    ///
    /// - Parameters:
    ///   - remembered: The memo the view's handler keeps; replaced on a miss.
    ///   - hits: Counts the frames `remembered` answered, for the tests that
    ///     pin it answering.
    ///   - length: The bar's height, in cells.
    ///   - extent: The content's height, in the bar's units (lines or rows).
    ///   - viewport: The visible height, in the same units.
    ///   - offset: The scroll offset, in the same units.
    ///   - arrows: The arrow assembly at each end.
    ///   - proportional: Whether the thumb is sized to the viewport.
    ///   - isFocused: Whether the bar indicates the focus: it breathes.
    ///   - hoveredCell: The bar-relative cell under the pointer, if any.
    ///   - flash: How strongly a `scrollIndicatorsFlash` lights the bar this
    ///     frame, or `nil`. A flashing bar is drawn still, without the focus
    ///     breath's runs, which would paint the flash over from their first
    ///     tick.
    ///   - context: The view's context.
    /// - Returns: The bar, in its own coordinates, and its runs: none when
    ///   nothing about it moves.
    @MainActor
    package static func vertical(  // swiftlint:disable:this function_parameter_count
        remembered: inout Self?, hits: inout Int,
        length: Int, extent: Int, viewport: Int, offset: Int,
        arrows: ScrollbarArrows, proportional: Bool,
        isFocused: Bool, hoveredCell: Int?, flash: Double?, context: RenderContext
    ) -> Self {
        let palette = context.environment.palette
        // The same hovered cell the draw lifts. The runs REPLACE those cells
        // from the first tick, so a pulse that does not know about the
        // pointer paints the lift away and it never returns while the pointer
        // sits there.
        let pulse =
            flash == nil
            ? ScrollbarColors.focusPulse(isFocused: isFocused, hoveredCell: hoveredCell, context: context) : nil
        let width = context.environment.scrollbarWidth
        let cornerTriangles = context.environment.cornerTrianglesFillTheCell
        let shown = cycleKey(isFocused: isFocused, breathes: pulse != nil, context: context)
        let key = Key(
            length: length, extent: extent, viewport: viewport,
            offset: offset, arrows: arrows, proportional: proportional,
            isFocused: isFocused, isScrollEnabled: context.environment.isScrollEnabled,
            isEnabled: context.environment.isEnabled,
            hoveredCell: hoveredCell, palette: ComparablePalette(palette),
            depth: ColorDepth.current, terminalColors: TerminalColors.current,
            cycle: shown.cycle, frame: shown.frame, flash: flash, width: width, cornerTriangles: cornerTriangles)
        let step = pulse?.cycle.step ?? 0
        if let remembered, remembered.key == key {
            hits &+= 1
            return remembered.showing(step: step)
        }
        func drawn(_ colors: ScrollbarColors) -> ClaimingColumn {
            ScrollbarRenderer.verticalScrollbar(
                height: length, extent: extent, viewport: viewport, offset: offset,
                arrows: arrows, proportional: proportional, colors: colors,
                width: width, cornerTriangles: cornerTriangles)
        }
        let memo: Self
        if let pulse {
            // A breathing bar shows the frame of its breath the clock is on:
            // the colour `focusIndicating` draws, `colorNow`, is that frame's.
            let frames = pulse.frames.map(drawn)
            let runs = ScrollbarRenderer.verticalScrollbarRuns(frames: frames, pulse: pulse)
            memo = Self(key: key, bar: frames[step % frames.count], frames: frames, runs: runs)
        } else {
            // The bar is its view's focus indicator: it pulses the accent while
            // focused (see ScrollbarColors.focusIndicating).
            let colors = ScrollbarColors.focusIndicating(
                isFocused: isFocused, hoveredCell: hoveredCell, context: context)
            memo = Self(key: key, bar: drawn(flash.map { colors.flashing($0, in: palette) } ?? colors), runs: [])
        }
        remembered = memo
        return memo
    }
}
