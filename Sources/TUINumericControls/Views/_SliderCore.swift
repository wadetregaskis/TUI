//  🖥️ TUI — A Terminal UI framework for Swift
//  _SliderCore.swift
//
//  The slider's procedural core: the arrows, the track and the read-out, and
//  the keyboard, wheel and pointer handling behind them.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Internal Core View

/// StateStorage property indices for ``_SliderCore``. Lifted
/// out of the generic struct because Swift does not allow
/// static stored properties in generic types.
enum SliderStateIndex {
    static let handler = 0
    static let focusID = 1
    static let isHovered = 2
    static let leftArrowRepeat = 3
    static let rightArrowRepeat = 4
    /// The slider's undo (``ControlValueUndo``): a run of moves is one step.
    static let undo = 5
}

/// Internal view that handles the actual rendering of Slider.
struct _SliderCore: View, Renderable, Layoutable {
    let value: Binding<Double>
    let bounds: ClosedRange<Double>
    let step: Double
    let trackStyle: TrackStyle
    let focusID: String?
    let isDisabled: Bool
    let onEditingChanged: ((Bool) -> Void)?

    /// Where the fill starts — SwiftUI's `neutralValue:` — or `nil` for the
    /// low end.
    var neutralValue: Double?

    /// The values the user may select — SwiftUI's `enabledBounds:` — or `nil`
    /// for all of `bounds`. The track outside them is drawn disabled.
    var enabledBounds: ClosedRange<Double>?

    /// The marks drawn under the track.
    var ticks: [_SliderTickMark] = []

    /// The values the keyboard, the wheel and the pointer may land on: the
    /// enabled bounds, within the bounds.
    var selectableBounds: ClosedRange<Double> {
        guard let enabledBounds else { return bounds }
        return enabledBounds.clamped(to: bounds)
    }

    /// Minimum track width.
    private let minTrackWidth = 10

    /// Default track width when no explicit frame is set.
    private let defaultTrackWidth = 20

    /// Width of the value field, in columns: the width of the widest value the
    /// slider can show, `"100%"`. Shorter values are padded to this width (see
    /// ``valueLabelText``) so the field — and therefore the track and arrows —
    /// never change size as the value changes.
    private var valueFieldWidth: Int { 4 }

    /// The `"NN%"` value drawn at the trailing edge, padded to a FIXED field
    /// (``valueFieldWidth``) so the slider keeps a constant length and the right
    /// arrow doesn't shift when the value crosses 10%/100%. Shorter values are
    /// left-aligned with trailing spaces (`"50% "`), matching a fixed numeric
    /// field; this also fills the trailing cell the old hard-coded chrome left
    /// blank. The fraction is clamped exactly as it is for display, so the
    /// width is stable across the value-clamping that happens mid-render.
    private var valueLabelText: String {
        let text = valueDisplayText
        guard text.count < valueFieldWidth else { return text }
        return text + String.spaces(valueFieldWidth - text.count)
    }

    /// The value read-out with **no** field padding (`"52%"`) — the part the
    /// slider actually styles. Kept separate from ``valueLabelText`` so a themed
    /// style (colour / underline) applies to the digits only, not the trailing
    /// blank cell the fixed field pads to.
    private var valueDisplayText: String {
        let range = bounds.upperBound - bounds.lowerBound
        let fraction = range > 0
            ? min(1.0, max(0.0, (value.wrappedValue - bounds.lowerBound) / range))
            : 0
        return "\(Int((fraction * 100).rounded()))%"
    }

    /// Columns consumed by everything other than the track:
    /// `"◀ " + track + " ▶ " + value field`, i.e. the two arrows, the three
    /// spaces around them, and the fixed-width value field.
    ///
    /// Constant (5 + ``valueFieldWidth`` = 9), because the value field is padded
    /// to a fixed width — so the track and arrows hold a constant position as
    /// the value changes (the slider never changes length). Used by BOTH
    /// `sizeThatFits` and `renderToBuffer` so the two agree, and because the
    /// field is padded the track + chrome fills the available width exactly
    /// (the value padding occupies the cell the old hard-coded 9 left blank for
    /// values narrower than "100%").
    private func chromeWidth(showsValue: Bool, gap: Int) -> Int {
        // "◀" + the gap (before track) + the gap + "▶", then " " (after the
        // arrow) and the value field: 5 columns of chrome at `.regular`, where
        // the gap is one. With the value hidden the trailing space + field
        // drop, leaving "◀ track ▶" — 4 columns of chrome.
        let arrows = 2 + 2 * gap
        guard showsValue else { return arrows }
        return arrows + 1 + valueLabelText.count
    }

    var body: Never {
        fatalError("_SliderCore renders via Renderable")
    }

    /// Returns the size this slider needs.
    ///
    /// Slider is width-flexible: it has a minimum width but expands
    /// to fill available horizontal space in HStack.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let chrome = chromeWidth(
            showsValue: context.environment.sliderShowsValue, gap: Self.arrowGap(in: context.environment))
        let proposedWidth = proposal.width ?? (defaultTrackWidth + chrome)
        let trackWidth = max(minTrackWidth, proposedWidth - chrome)
        return ViewSize(
            width: trackWidth + chrome,
            height: 1 + tickRowCount,
            isWidthFlexible: true,
            isHeightFlexible: false
        )
    }

    private typealias StateIndex = SliderStateIndex

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let stateStorage = context.stateStorage!
        let palette = context.environment.palette

        // Slider expands to fill available width. `sizeThatFits` REQUESTS at
        // least `minTrackWidth` of track, but at render time we fit whatever
        // width layout actually granted (e.g. a narrower explicit `.frame`):
        // flooring the track here would push the trailing chrome — the right
        // arrow and value field — past `availableWidth`, where it gets clipped
        // and overlaps the next view. Chrome integrity beats track length.
        let showsValue = context.environment.sliderShowsValue
        let gap = Self.arrowGap(in: context.environment)
        let trackWidth = max(1, context.availableWidth - chromeWidth(showsValue: showsValue, gap: gap))

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context,
            explicitFocusID: focusID,
            defaultPrefix: "slider",
            propertyIndex: StateIndex.focusID
        )

        // Get or create persistent handler from state storage
        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<SliderHandler<Double>> = stateStorage.storage(
            for: handlerKey,
            default: SliderHandler(
                focusID: persistedFocusID,
                value: value,
                bounds: selectableBounds,
                step: step,
                canBeFocused: !isDisabled
            )
        )
        let handler = handlerBox.value

        // Keep handler in sync with current values — EVERY field the view
        // declares, or the persisted handler keeps the creation render's
        // (stale bounds made clampValue force-write the app's value back
        // inside a range the view no longer declares).
        // A person's moves are steps in the app's undo manager, a run of them
        // one step; the slider's own clamp is not a person's, and writes the
        // binding as it is.
        handler.value = context.undoable(value, coalescing: true, propertyIndex: StateIndex.undo)
        handler.plainValue = value
        handler.bounds = selectableBounds
        handler.step = step
        handler.gridOrigin = bounds.lowerBound
        handler.canBeFocused = !isDisabled
        // Captured at render so Shift+arrow can accelerate at event time.
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        handler.onEditingChanged = onEditingChanged
        handler.clampValue()

        FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        // Everything below this line is drawing, so the gate goes here —
        // see `RenderContext.indicatesFocus(_:)`. Key handling is the
        // registered handler's and is untouched: the slider still moves.
        let isFocused = context.indicatesFocus(
            FocusRegistration.isFocused(context: context, focusID: persistedFocusID))

        let hoverKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.isHovered)
        let hoverBox: StateBox<Bool> = stateStorage.storage(
            for: hoverKey, default: false)
        let isHovered = !isDisabled && hoverBox.value

        // Calculate fraction, clamped to [0, 1] to handle out-of-bounds values
        let range = bounds.upperBound - bounds.lowerBound
        let fraction = range > 0 ? min(1.0, max(0.0, (value.wrappedValue - bounds.lowerBound) / range)) : 0

        // The whole cycle, not the live phase: the arrows are handed to the run
        // loop to breathe on their own (see `AnimatedCellRun`). Asking for the
        // phase would mark the frame as having consulted the clock, and every
        // tick would then re-render the entire page to repaint two cells.
        let cycle = context.environment.selectionEmphasis.cycle(isFocused && !isDisabled)

        // Build the slider content. The track's DRAWN width comes back with it:
        // a coarse (multi-cell) track style renders narrower than it was asked
        // for, and everything positioned AFTER the track — the right arrow's
        // breathing run, its click zone, the drag mapping — has to be measured
        // from what was drawn, exactly as `Stepper.arrowRuns` measures its own
        // arrows from `buffer.width`. Taking the requested width put the run one
        // column past the arrow, on the blank before the read-out, where the
        // loop replayed a SECOND ▶ breathing out of step with the real one.
        let (content, drawnTrackWidth, valueClaim, trackClaims) = buildContent(
            fraction: fraction,
            isFocused: isFocused,
            isHovered: isHovered,
            palette: palette,
            indicator: cycle,
            trackWidth: trackWidth,
            gap: gap,
            valueStyle: context.environment.styleCascade.resolve(
                for: [.all, .text, .control(.slider)]),
            legibilityWeight: context.environment.legibilityWeight,
            isDisabled: isDisabled,
            showsValue: showsValue,
            fillScaling: context.environment.trackFillGradientScaling,
            backgroundScaling: context.environment.trackBackgroundGradientScaling,
            graphics: context.gradientGraphics(token: "track-\(context.identity.path)"),
            showsThumb: context.environment.sliderThumbVisibility != .hidden
        )

        var buffer = FrameBuffer(
            lines: [content] + tickRows(drawnTrackWidth: drawnTrackWidth, isDisabled: isDisabled, context: context))
        buffer.opacityRegions += valueClaim.map { [$0] } ?? []
        // The track's own claims, in the track's coordinates, moved to where the
        // layout actually puts it: `"◀ "`, two cells at `.regular`, which
        // `arrowRuns` states as `trackLeft(gap:)` and this must not spell a
        // second time. A disabled slider
        // produces none — `forState` composites every colour through
        // `opacity(_:over:)` and stamps the result opaque, so its alpha is spent
        // against the page rather than claimed. One colour, two answers, decided by
        // `isEnabled`; §31.3.
        buffer.opacityRegions += trackClaims.map { $0.shifted(byX: Self.trackLeft(gap: gap), y: 0) }
        if !context.isMeasuring {
            buffer.animatedCells = arrowRuns(
                cycle: cycle, palette: palette, drawnTrackWidth: drawnTrackWidth, gap: gap)
        }

        attachMouseHandlers(
            to: &buffer,
            context: context,
            handler: handler,
            hoverBox: hoverBox,
            persistedFocusID: persistedFocusID,
            stateStorage: stateStorage,
            track: TrackGeometry(left: Self.trackLeft(gap: gap), width: drawnTrackWidth, gap: gap)
        )

        return buffer
    }

    // MARK: - Mouse handler wiring

    /// Registers the slider's single buffer-wide mouse handler
    /// (which routes wheel + arrow + track behaviour) and emits
    /// its hit-test region. The handler is composed from the
    /// per-axis helpers below.
    @MainActor
    private func attachMouseHandlers(
        to buffer: inout FrameBuffer,
        context: RenderContext,
        handler: SliderHandler<Double>,
        hoverBox: StateBox<Bool>,
        persistedFocusID: String,
        stateStorage: StateStorage,
        track: TrackGeometry
    ) {
        // Own AND cascaded — `renderToBuffer`'s shadowing local does not reach
        // this helper, so the bare `self.isDisabled` here answered only for a
        // slider disabled by its own modifier. One inside a `.disabled()`
        // container, or under an unselected radio option, kept every mouse
        // handler it had: it dragged, it wheeled, and clicking it took the
        // focus that the keyboard could not reach.
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        mouseDispatcher.requestFeature(.motion, in: context)

        let focusManager = context.environment.focusManager

        let leftArrowTimer = autoRepeatTimer(
            stateStorage: stateStorage,
            context: context,
            propertyIndex: StateIndex.leftArrowRepeat
        )
        let rightArrowTimer = autoRepeatTimer(
            stateStorage: stateStorage,
            context: context,
            propertyIndex: StateIndex.rightArrowRepeat
        )

        let handlerID = mouseDispatcher.register(
            in: context,
            mouseHandler(
                handler: handler,
                hoverBox: hoverBox,
                focusManager: focusManager,
                focusID: persistedFocusID,
                leftArrowTimer: leftArrowTimer,
                rightArrowTimer: rightArrowTimer,
                track: track
            )
        )
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0,
                offsetY: 0,
                width: buffer.width,
                height: buffer.height,
                handlerID: handlerID,
                focusID: persistedFocusID
            )
        )
    }

    /// The single mouse handler for the slider's hit-test
    /// region. Routes hover, wheel, arrow-click + auto-repeat,
    /// and track drag-set behaviour. Returns a closure rather
    /// than a method so the captures (which include the
    /// `value` and `bounds` from the surrounding view) are
    /// fixed at the moment of registration.
    /// Where the track sits in the slider's own buffer: the three numbers the
    /// arrow zones and the drag mapping are all measured from.
    ///
    /// One value because they are one fact and always travel together — and
    /// because carrying them separately is what pushed this closure's
    /// signature past what the linter will accept, which is the linter being
    /// right about it.
    private struct TrackGeometry {
        /// The track's first column. `"◀ "` precedes it, the arrow and the gap.
        let left: Int
        /// One past its last column; from here on is `" ▶ "` and the value.
        let right: Int
        /// `right - left`.
        let width: Int
        /// The cells between each arrow and the track — one at `.regular`.
        let gap: Int

        /// The column the `"◀"` glyph occupies — the whole of the left arrow,
        /// not everything before the track: the gap between them is chrome and
        /// adjusts nothing.
        var leftArrow: Int { left - 1 - gap }

        /// The column the `"▶"` glyph occupies. The gap before it is chrome,
        /// and `rightArrow + 1` onwards is the space and the value read-out —
        /// six cells that are NOT the arrow, which is why the zone is this one
        /// column rather than everything from `right` on.
        var rightArrow: Int { right + gap }

        init(left: Int, width: Int, gap: Int) {
            self.left = left
            self.width = width
            self.right = left + width
            self.gap = gap
        }
    }

    private func mouseHandler(
        handler: SliderHandler<Double>,
        hoverBox: StateBox<Bool>,
        focusManager: FocusManager?,
        focusID: String,
        leftArrowTimer: AutoRepeatTimer,
        rightArrowTimer: AutoRepeatTimer,
        track: TrackGeometry
    ) -> @MainActor (MouseEvent) -> Bool {
        // The handler's: a person's moves, steps in the app's undo manager.
        let value = handler.value
        let bounds = self.bounds
        let selectable = self.selectableBounds
        let step = self.step

        // Along the grid a click snaps to, as the keys step.
        let decrementOnce: @MainActor () -> Void = {
            value.wrappedValue = min(
                selectable.upperBound,
                max(
                    selectable.lowerBound,
                    SliderHandler.stepped(value.wrappedValue, by: -1, step: step, origin: bounds.lowerBound)))
        }
        let incrementOnce: @MainActor () -> Void = {
            value.wrappedValue = min(
                selectable.upperBound,
                max(
                    selectable.lowerBound,
                    SliderHandler.stepped(value.wrappedValue, by: 1, step: step, origin: bounds.lowerBound)))
        }
        let stopArrowTimers: @MainActor () -> Void = {
            leftArrowTimer.stop()
            rightArrowTimer.stop()
        }

        return { event in
            switch event.phase {
            case .entered:
                hoverBox.value = true
                return true
            case .exited:
                hoverBox.value = false
                return true
            default:
                break
            }
            switch event.button {
            case .scrollUp:
                // Wheel up scrolls toward smaller / earlier values; wheel down
                // advances. Matches Stepper, Menu, List and ScrollView — the
                // slider previously had this inverted, so a horizontal slider
                // adjusted the opposite way from every other wheel control.
                //
                // A notch is a discrete adjustment like an arrow KEY, not a
                // drag: it begins the edit and, like a key, leaves the end to
                // focus loss. There is no release to end it on.
                handler.beginEditingIfNeeded()
                decrementOnce()
                focusManager?.focus(id: focusID)
                return true
            case .scrollDown:
                handler.beginEditingIfNeeded()
                incrementOnce()
                focusManager?.focus(id: focusID)
                return true
            case .left:
                return Self.handleLeftButton(
                    event: event,
                    handler: handler,
                    value: value,
                    bounds: bounds,
                    selectable: selectable,
                    step: step,
                    track: track,
                    leftArrowTimer: leftArrowTimer,
                    rightArrowTimer: rightArrowTimer,
                    decrementOnce: decrementOnce,
                    incrementOnce: incrementOnce,
                    stopArrowTimers: stopArrowTimers,
                    focusManager: focusManager,
                    focusID: focusID
                )
            default:
                return false
            }
        }
    }

    /// Dispatches a `.left`-button mouse event among the zones
    /// Slider supports: the left arrow's cell, the right arrow's
    /// cell, the track in between, and the chrome around them
    /// (the spaces beside each arrow and the value read-out),
    /// which focuses but adjusts nothing. Static so it doesn't
    /// capture `self`, avoiding a reference cycle through the
    /// parent closure.
    private static func handleLeftButton( // swiftlint:disable:this function_parameter_count
        event: MouseEvent,
        handler: SliderHandler<Double>,
        value: Binding<Double>,
        bounds: ClosedRange<Double>,
        selectable: ClosedRange<Double>,
        step: Double,
        track: TrackGeometry,
        leftArrowTimer: AutoRepeatTimer,
        rightArrowTimer: AutoRepeatTimer,
        decrementOnce: @escaping @MainActor () -> Void,
        incrementOnce: @escaping @MainActor () -> Void,
        stopArrowTimers: @MainActor () -> Void,
        focusManager: FocusManager?,
        focusID: String
    ) -> Bool {
        switch event.phase {
        case .pressed, .dragged:
            // Each zone is the cells it DRAWS, not the half-plane on its side
            // of the track: the arrows are one glyph each, and the spaces
            // around them plus the value read-out belong to neither. Splitting
            // on `< track.left` / `>= track.right` handed the right arrow the
            // six cells after the track, so a click on the read-out — the
            // natural place to click a slider to focus it — incremented the
            // value and a hold there auto-repeated. `Stepper` bounds its arrows
            // to one cell each for the same reason (see `attachMouseHandlers`
            // there); this does it inside one region because the slider's track
            // drag has to stay continuous across all three zones.
            switch event.x {
            case track.leftArrow:
                // The gesture `onEditingChanged` was designed around — SwiftUI:
                // "editing begins when the user starts to drag the thumb along
                // the slider's track". `.dragged` as well as `.pressed` because
                // a drag can arrive here having begun outside the track; the
                // guard inside makes the second and later reports free.
                handler.beginEditingIfNeeded()
                if event.phase == .pressed {
                    stopArrowTimers()
                    leftArrowTimer.start(action: decrementOnce)
                } else {
                    // .dragged onto the arrow from elsewhere —
                    // stop any track dragging, don't restart
                    // the auto-repeat.
                    stopArrowTimers()
                }
            case track.rightArrow:
                handler.beginEditingIfNeeded()
                if event.phase == .pressed {
                    stopArrowTimers()
                    rightArrowTimer.start(action: incrementOnce)
                } else {
                    stopArrowTimers()
                }
            case track.left..<track.right:
                handler.beginEditingIfNeeded()
                stopArrowTimers()
                applyTrackValue(
                    eventX: event.x,
                    value: value,
                    bounds: bounds,
                    selectable: selectable,
                    step: step,
                    track: track
                )
            default:
                // Chrome: the gaps beside the arrows and the value read-out.
                // The click is still claimed and still focuses the slider (it
                // is the slider's own row), but it adjusts nothing — and it
                // reports no edit either, because `onEditingChanged` describes
                // a drag of the thumb and no value is about to move.
                stopArrowTimers()
            }
            focusManager?.focus(id: focusID)
            return true
        case .released:
            stopArrowTimers()
            handler.endEditingIfNeeded()
            return true
        default:
            return false
        }
    }

    /// Maps a track-area cursor x to a snapped slider value and
    /// applies it. Snaps to the nearest multiple of `step` so
    /// keyboard and mouse adjustments stay in lockstep —
    /// dragging across the track lands on the same values you'd
    /// reach by tapping →.
    private static func applyTrackValue(
        eventX: Int,
        value: Binding<Double>,
        bounds: ClosedRange<Double>,
        selectable: ClosedRange<Double>,
        step: Double,
        track: TrackGeometry
    ) {
        let pos = max(0, min(track.width - 1, eventX - track.left))
        let range = bounds.upperBound - bounds.lowerBound
        let raw = bounds.lowerBound + (track.width > 1
            ? Double(pos) / Double(track.width - 1)
            : 0) * range
        let snapped: Double
        if step > 0 {
            let stepsFromLow = ((raw - bounds.lowerBound) / step).rounded()
            snapped = bounds.lowerBound + stepsFromLow * step
        } else {
            snapped = raw
        }
        // Mapped across the whole track, and kept to what may be selected. A
        // press and drag on the track is one gesture producing a sequence of
        // values, which is what `Transaction.isContinuous` names.
        withTransaction(\.isContinuous, true) {
            value.wrappedValue = min(selectable.upperBound, max(selectable.lowerBound, snapped))
        }
    }

    /// Fetches (or creates) the auto-repeat timer at the given
    /// `propertyIndex` on the current view identity.
    private func autoRepeatTimer(
        stateStorage: StateStorage,
        context: RenderContext,
        propertyIndex: Int
    ) -> AutoRepeatTimer {
        let key = StateStorage.StateKey(
            identity: context.identity, propertyIndex: propertyIndex)
        let box: StateBox<AutoRepeatTimer> = stateStorage.storage(
            for: key, default: AutoRepeatTimer())
        return box.value
    }

    /// Where the track starts: `"◀ "`, two cells at `.regular` — the arrow and
    /// the gap after it.
    ///
    /// One number, because three things now depend on it — the right arrow's run, the
    /// value read-out's offset, and the track's own opacity claims — and a claim that
    /// disagreed with the runs by one cell would fade the arrow instead of the rail.
    static func trackLeft(gap: Int) -> Int { 1 + gap }

    /// The cells between each arrow and the track at the ``ControlSize`` in
    /// `environment`: the bordered button's padding — one at `.regular` and
    /// `.large`, none at `.small` and `.mini`, two at `.extraLarge`. The arrows
    /// stay at every size: they are the slider's buttons.
    static func arrowGap(in environment: EnvironmentValues) -> Int {
        environment.controlSize.padding(regular: 1)
    }

    /// The runs that breathe the two arrows, so the loop can advance them
    /// without walking the view tree. Empty unless the slider is focused and
    /// the indicator style actually animates.
    ///
    /// The offsets follow the one layout `buildContent` emits — `"◀ TRACK ▶"` —
    /// and the same `trackLeft` the mouse handler maps clicks through, so the
    /// cells a run claims are the cells the arrows were drawn in.
    ///
    /// `drawnTrackWidth`, never the width the track was ASKED for: a coarse
    /// (multi-cell) track style renders narrower than its request, so the two
    /// differ by up to a glyph, and a run one column off the arrow is a second
    /// arrow the loop breathes out of step with the real one.
    @MainActor
    private func arrowRuns(
        cycle: SelectionEmphasisCycle, palette: any Palette, drawnTrackWidth: Int, gap: Int
    ) -> [AnimatedCellRun] {
        guard cycle.isAnimating else { return [] }
        let (dim, bright) = palette.accentPulse()
        let trackLeft = Self.trackLeft(gap: gap)
        return [
            cycle.run(
                TerminalSymbols.leftArrow, dim: dim, bright: bright, offsetX: 0, offsetY: 0),
            cycle.run(
                TerminalSymbols.rightArrow, dim: dim, bright: bright,
                offsetX: trackLeft + drawnTrackWidth + gap, offsetY: 0),
        ].compactMap { $0 }
    }

    // Builds the rendered slider content. The nine inputs are all distinct render
    // parameters (geometry, the resolved interaction state, and the value-readout
    // style); bundling them into a throwaway struct only to satisfy the
    // parameter-count ceiling would scatter closely-related render inputs.
    // swiftlint:disable:next function_parameter_count
    private func buildContent(
        fraction: Double,
        isFocused: Bool,
        isHovered: Bool,
        palette: any Palette,
        indicator: SelectionEmphasisCycle,
        trackWidth: Int,
        gap: Int,
        valueStyle: StyleAttributes,
        legibilityWeight: LegibilityWeight?,
        isDisabled: Bool,
        showsValue: Bool,
        fillScaling: TrackGradientScaling,
        backgroundScaling: TrackGradientScaling,
        graphics: GradientGraphicsContext?,
        showsThumb: Bool
    ) -> (
        content: String, drawnTrackWidth: Int, valueClaim: OpacityRegion?,
        trackClaims: [OpacityRegion]
    ) {
        // Arrow colors:
        //   - Focused: pulsing accent
        //   - Hovered: static accent at the hoverBackground tint, so the
        //     affordance is visible, or where that tint cannot be measured the
        //     dimmed arrow lifted (`hoveredGlyph`). Focus wins on these
        //     particular cells — they are the only thing either state has to
        //     say here, and a pointer resting on the arrow it already focused
        //     must not freeze the pulse. The hover still shows elsewhere on the
        //     control.
        //   - Otherwise: dimmed foregroundTertiary
        let dimmedArrow = palette.foregroundTertiary.opacity(
            ViewConstants.disabledForeground, over: palette.background)
        let arrowColor: Color
        if isDisabled {
            arrowColor = dimmedArrow
        } else if isFocused {
            let (dimAccent, brightAccent) = palette.accentPulse()
            arrowColor = indicator.colorNow(dim: dimAccent, bright: brightAccent)
        } else if isHovered {
            arrowColor = palette.hoveredGlyph(resting: dimmedArrow)
        } else {
            // Dimmed arrows when unfocused
            arrowColor = dimmedArrow
        }

        // Build track. Every colour it is drawn from FADES toward the page when
        // the slider is disabled — the same treatment the arrows and the value
        // read-out already had, and the same expression. Only the filled colour
        // used to change, and only some track styles draw with it: `.bar` and
        // the gradients fill in the ACCENT, which was handed over undimmed, so
        // a disabled slider on the green palette drew a track indistinguishable
        // from a live one and only its label said otherwise.
        func forState(_ color: Color) -> Color {
            guard isDisabled else { return color }
            return color.opacity(ViewConstants.disabledForeground, over: palette.background)
        }
        // A neutral value or enabled bounds draw the track in pieces, which a
        // picture cannot be cut into, so the cells are drawn instead.
        let enabled = enabledFractions
        func drawTrack(_ colour: (Color) -> Color, graphics: GradientGraphicsContext?) -> ClaimingRow {
            TrackRenderer.render(
                fraction: fraction,
                width: trackWidth,
                style: trackStyle,
                fillColor: colour(palette.foregroundSecondary),
                backgroundColor: colour(palette.foregroundTertiary),
                accentColor: colour(palette.accent),
                fillScaling: fillScaling,
                backgroundScaling: backgroundScaling,
                palette: palette,
                graphics: graphics,
                neutralFraction: neutralFraction,
                showsHead: showsThumb
            )
        }
        var track = drawTrack(forState, graphics: enabled == nil ? graphics : nil)
        if let enabled {
            // The values that cannot be selected, drawn as a disabled slider
            // draws its whole track.
            let outside = drawTrack(
                { $0.opacity(ViewConstants.disabledForeground, over: palette.background) }, graphics: nil)
            track = Self.splice(track, outside: outside, enabled: enabled)
        }

        // Build arrows
        let leftArrow = ANSIRenderer.colorize(TerminalSymbols.leftArrow, foreground: arrowColor)
        let rightArrow = ANSIRenderer.colorize(TerminalSymbols.rightArrow, foreground: arrowColor)

        // Build value label (percentage) — the same source of truth that
        // `chromeWidth` measures, so the label always fits the space reserved.
        // Its colour/weight inherit the slider's scoped style cascade
        // (`.sliderTextStyle { … }`) as soft overrides.
        let valueDisplay = valueDisplayText
        let valueLabelColor =
            isDisabled
            ? palette.foregroundTertiary
            : (valueStyle.foreground?.resolve(with: palette) ?? palette.foregroundSecondary)
        // Style only the digits; append the field padding UNSTYLED so a themed
        // underline sits under "52%", never the blank fourth cell.
        let padding = String.spaces(max(0, valueFieldWidth - valueDisplay.count))
        let valueLabel = ANSIRenderer.colorize(
            valueDisplay,
            foreground: valueLabelColor.opaqueSpelling,
            // A tier heavier under a bold legibility weight: the read-out is text.
            bold: legibilityWeight.applied(bold: !isDisabled && (valueStyle.bold ?? false), faint: false).bold,
            underline: !isDisabled && (valueStyle.underline ?? false)) + padding

        // What the track came back as, in CELLS — which is not always the
        // `trackWidth` it was asked for. A multi-cell fill, unfilled or ramp
        // glyph quantises the track, and `TrackRenderer.renderCoarsePattern` then
        // shrinks it to the largest whole multiple of that quantum that fits;
        // deliberately and permanently, so a bar's width cannot wobble with its
        // fill ratio. Everything drawn to the RIGHT of the track moves with it,
        // so say where the track actually ended rather than let the caller
        // assume it got what it asked for.
        let drawnTrackWidth = track.cells

        // Pulsing arrows indicate focus - no extra markers needed. The value
        // read-out is omitted when `.sliderShowsValue(false)` (some surrounding
        // control shows the value instead).
        // The space between each arrow and the track, the control size's.
        let gapText = String.spaces(gap)
        guard showsValue else {
            return (
                leftArrow + gapText + track.text + gapText + rightArrow, drawnTrackWidth, nil, track.claims)
        }
        // Where the read-out's digits start: `"◀ "` + the track as DRAWN + `" ▶ "`,
        // the gaps one cell each at `.regular`.
        // `drawnTrackWidth` and not `trackWidth`, for the reason `arrowRuns` takes
        // the same number — a coarse track renders narrower than it was asked for,
        // and everything to its right moves with it.
        //
        // The digits only. The field padding is appended unstyled on purpose (see
        // above), so it owes nothing, and the TRACK is deliberately not claimed:
        // its colours are §16.1 row 8, still open, and a rectangle over them here
        // would multiply with the claim that migration adds.
        return (
            leftArrow + gapText + track.text + gapText + rightArrow + " " + valueLabel, drawnTrackWidth,
            OpacityRegion.claim(
                offsetX: 3 + 2 * gap + drawnTrackWidth, width: valueDisplay.strippedLength, height: 1,
                ink: valueLabelColor),
            track.claims)
    }
}
