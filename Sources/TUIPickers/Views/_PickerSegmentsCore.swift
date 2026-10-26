//  🖥️ TUI — A Terminal UI framework for Swift
//  _PickerSegmentsCore.swift
//
//  The segmented and palette pickers drawn: one control face, `▐ S │ M │ L ▌`
//  (or `( S │ M │ L )` in lines), one focus stop, a cursor the arrows move
//  among the segments.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation

/// `StateStorage` property indices for ``_PickerSegmentsCore``. Lifted out of
/// the generic struct because Swift does not allow static stored properties in
/// generic types.
///
/// From 0: the core is a leaf — it renders its labels at child identities of
/// its own, never caller content at its own identity.
private enum PickerSegmentsStateIndex {
    static let handler = 0
    static let focusID = 1
    /// The segment under the pointer, or `-1` for none: one box for the whole
    /// strip, since the pointer is over one segment at a time.
    static let hoveredIndex = 2
}

/// The rendering core of a ``Picker`` in the segmented or palette style.
///
/// One face, as macOS draws one control: the options between the two end caps,
/// a rule between each pair, `▐ S │ M │ L ▌`. The caps are a button's in the
/// family in force (``ControlEnds``): half blocks round a filled face, `( … )`
/// or `│ … │` in the lines' ink on no field under ``ControlStyle/lines``, as
/// the ``ButtonBorderShape`` picks. The selected option is drawn as a prominent
/// button's label is — in the accent, bold — unless a palette's selection
/// effect says otherwise.
///
/// The ``ControlSize`` is the bordered button's density table, on one row: no
/// space round the options at `.small` (`▐S│M│L▌`) and no caps either at
/// `.mini` (`S│M│L`, the face alone), two spaces at `.extraLarge`
/// (`▐  S  │  M  │  L  ▌`).
///
/// **One focus stop.** The keys are the horizontal radio group's — the two
/// share ``RadioButtonGroupHandler`` — with macOS's choices for a segmented
/// control, measured on 15.8 (a SwiftUI `.segmented` picker, keyed through its
/// `NSSegmentedControl`): the cursor starts on the selected segment, Left and
/// Right move it without choosing, wrapping at the ends, and Space chooses the
/// segment under it — as does Return here. Up and Down leave the control, as
/// they leave a horizontal radio group.
///
/// The cursor is drawn as a list's is, and for the same reason: it is "where
/// the keys go", which breathes. On the selected segment it is a focused,
/// selected row's breath; on any other, the focus wash's
/// (``RowBackground/focusedSelection(in:palette:)``,
/// ``RowBackground/focused(in:palette:)``).
///
/// A click on a segment chooses it and focuses the control; the end caps
/// belong to the segments beside them and the rules to neither. A drag held
/// still over a segment chooses it under `.springLoadingBehavior(.enabled)`,
/// as a segment of macOS's does (measured on 15.8).
///
/// - Important: Framework infrastructure. ``Picker`` returns this from its
///   `body` for the segmented and palette styles; it is never used directly.
struct _PickerSegmentsCore<SelectionValue: Hashable>: View, Renderable, Layoutable {
    /// The resolved options; dividers are a menu's and draw nothing here.
    let entries: [_PickerEntry<SelectionValue>]

    /// A binding to the selected value.
    let selection: Binding<SelectionValue>

    /// Whether this is the palette style, whose selection effect decides how
    /// the selection shows.
    let isPalette: Bool

    /// The explicit focus identifier, or `nil` to derive one.
    let focusID: String?

    /// Whether the picker is disabled.
    let isDisabled: Bool

    /// The selection stands for values that disagree (`Picker(sources:)`): no
    /// segment is marked.
    var isMixed = false

    private typealias StateIndex = PickerSegmentsStateIndex

    var body: Never {
        fatalError("_PickerSegmentsCore renders via Renderable")
    }

    /// The strip is fixed: its segments lay out at their natural size.
    ///
    /// Worked out from what the strip is made of — the two caps, a rule
    /// between each pair of segments, and each label at its natural width with
    /// the control size's padding either side — where every label measures as
    /// one row of a fixed width and the strip fits the space offered, and by
    /// drawing the strip otherwise: a label of several rows is cut to its first,
    /// a flexible one is drawn at its natural width, which only the drawing
    /// says, and a strip too wide is clipped as a drawing is.
    ///
    /// Drawn every time, the measure drew every label once more than the frame
    /// shows it, each under its own styles, for a strip whose size does not
    /// depend on which segment is selected or under the cursor (2026-10-26:
    /// `_PickerSegmentsCore.sizeThatFits` 26.6% of a frame of the Stress
    /// `pickers` scenario, `drawSegment` 16.3% of it).
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let options = self.options
        guard !options.isEmpty, context.stateStorage != nil else { return ViewSize.fixed(0, 0) }
        let measureContext = fixedMeasureContext(proposal: proposal, context: context)
        let effect = measureContext.environment.paletteSelectionEffect
        let marksSelection = !isPalette || effect.drawsSelection
        let padding = measureContext.environment.controlSize.padding(regular: 1)
        var width = ControlEnds(in: measureContext.environment).width + options.count - 1
        for (index, option) in options.enumerated() {
            let isSelected = !isMixed && option.tag == selection.wrappedValue
            let label = segmentLabel(option.label, isSelected: isSelected, effect: effect)
            let labelContext = Self.labelContext(index: index, in: measureContext)
            let size = measureChild(
                label.bold(isSelected && marksSelection),
                proposal: ProposedSize(width: labelContext.availableWidth, height: labelContext.availableHeight),
                context: labelContext)
            guard size.height <= 1, !size.isWidthFlexible else {
                return measureFixedByRendering(self, proposal: proposal, context: context)
            }
            width += size.width + 2 * padding
        }
        // A strip that does not fit is clipped as a drawing is clipped, which
        // can stop short of the space where a wide glyph straddles its edge:
        // drawn, then, as before.
        guard width <= measureContext.availableWidth, measureContext.availableHeight >= 1 else {
            return measureFixedByRendering(self, proposal: proposal, context: context)
        }
        return ViewSize.fixed(width, 1)
    }

    /// The label a segment draws: a palette's selected option in the variant
    /// its selection effect asks for.
    private func segmentLabel(_ label: AnyView, isSelected: Bool, effect: PaletteSelectionEffect) -> AnyView {
        guard isPalette, isSelected, let variant = effect.selectedVariant else { return label }
        return AnyView(label.symbolVariant(variant))
    }

    /// Where segment `index`'s label is drawn: at a child identity of its own,
    /// one row of a strip at its natural width, whatever the strip was offered.
    private static func labelContext(index: Int, in context: RenderContext) -> RenderContext {
        context.withChildIdentity(erasedType: AnyView.self, index: index)
            .withAvailableWidth(max(context.availableWidth, context.environment.terminalWidth))
    }

    /// The options, in order, without the dividers.
    private var options: [(tag: SelectionValue, label: AnyView)] {
        entries.compactMap { entry in
            guard case .option(let tag, let label) = entry else { return nil }
            return (tag, label)
        }
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let options = self.options
        guard !options.isEmpty, let stateStorage = context.stateStorage else { return FrameBuffer(lines: []) }
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID, defaultPrefix: "segmented",
            propertyIndex: StateIndex.focusID)
        let handler = resolveHandler(
            options: options, focusID: persistedFocusID, isDisabled: isDisabled, storage: stateStorage,
            context: context)
        // A disabled picker is no focus stop at all.
        if !isDisabled {
            FocusRegistration.register(context: context, handler: handler, focusID: persistedFocusID)
        }
        // Drawing only — see `RenderContext.indicatesFocus(_:)`: the arrows
        // still move the cursor, and what goes is the mark saying where it is.
        let isFocused =
            !isDisabled
            && context.indicatesFocus(FocusRegistration.isFocused(context: context, focusID: persistedFocusID))
        let hoverBox: StateBox<Int> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.hoveredIndex),
            default: -1)

        let effect = context.environment.paletteSelectionEffect
        let marksSelection = !isPalette || effect.drawsSelection
        // The ends a button beside it would have, in the family in force: a
        // filled face's, or lines and dots on the surface with no field.
        let ends = ControlEnds(in: context.environment)
        let face = ends.hasField ? palette.restingControlFace : context.environment.enclosingSurface
        let field: Color? = ends.hasField ? face : nil
        // At rest the caps are the face's own colour, so the face reads as one
        // rounded control — exactly a button's at rest; a face of lines rests
        // in the lines' ink, the rules between its segments with it.
        let capInk = ButtonCapCycle(isFocused: false, background: face, palette: palette, context: context).colorNow
        let lineInk = ControlEnds.lineInk(palette: palette, surface: face, hovered: false, disabled: isDisabled)
        let ruleInk = ends.hasField ? palette.foregroundTertiary : lineInk
        // The density table a bordered button's face follows, on one row.
        let padding = context.environment.controlSize.padding(regular: 1)

        // The segment a paused drag rests on draws hovered while the
        // spring-loading pause runs and as it fires (owner ruling B82); asked
        // only while a drag is in the hand.
        let session = context.environment.dragAndDropSession
        let springLoading =
            session?.active == nil
            ? nil
            : options.indices.first { session?.springLoadPhase(of: Self.segmentIdentity($0, in: context)) != nil }

        var row = ClaimingRow()
        var runs: [AnimatedCellRun] = []
        var regions: [(x: Int, width: Int)] = []
        ends.appendCap(ends.open, to: &row, face: capInk, lines: lineInk)
        for (index, option) in options.enumerated() {
            if index > 0 {
                row.append(ControlEnds.rule, cells: 1, ink: ruleInk, field: field)
            }
            let isSelected = !isMixed && option.tag == selection.wrappedValue
            let segment = Segment(
                isSelected: isSelected, marksSelection: marksSelection,
                isCursor: isFocused && index == handler.focusedIndex,
                isHovered: !isDisabled && (index == hoverBox.value || index == springLoading), isDisabled: isDisabled)
            let label = segmentLabel(option.label, isSelected: isSelected, effect: effect)
            let start = row.cells
            drawSegment(
                label, as: segment, index: index, field: field, padding: padding, into: &row, runs: &runs,
                context: context)
            // The caps belong to the segments beside them, so the whole face
            // but its rules is somewhere to click.
            let left = index == 0 ? 0 : start
            regions.append((x: left, width: row.cells - left + (index == options.count - 1 ? ends.width / 2 : 0)))
        }
        ends.appendCap(ends.close, to: &row, face: capInk, lines: lineInk)

        var buffer = FrameBuffer(lines: [row.text])
        buffer.opacityRegions = row.claims
        if !context.isMeasuring { buffer.animatedCells = runs }
        if !isDisabled {
            attachMouse(
                to: &buffer, regions: regions, tags: options.map(\.tag), handler: handler, hoverBox: hoverBox,
                focusID: persistedFocusID, context: context)
        }
        return buffer
    }

    // MARK: - State

    /// The persisted handler, synced to this frame's options and bindings.
    ///
    /// The horizontal radio group's: the same one stop, the same keys — with
    /// the cursor wrapping at the ends, as a segmented control's does on macOS
    /// (measured on 15.8), whatever a radio group around it is told to do.
    private func resolveHandler(
        options: [(tag: SelectionValue, label: AnyView)], focusID: String, isDisabled: Bool,
        storage: StateStorage, context: RenderContext
    ) -> RadioButtonGroupHandler {
        let selection = self.selection
        let erased = Binding<AnyHashable>(
            get: { AnyHashable(selection.wrappedValue) },
            set: { newValue in
                if let typed = newValue.base as? SelectionValue { selection.wrappedValue = typed }
            })
        let values = options.map { AnyHashable($0.tag) }
        let box: StateBox<RadioButtonGroupHandler> = storage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.handler),
            default: RadioButtonGroupHandler(
                focusID: focusID, selection: erased, itemValues: values, orientation: .horizontal,
                canBeFocused: !isDisabled))
        let handler = box.value
        handler.selection = erased
        handler.itemValues = values
        handler.orientation = .horizontal
        handler.canBeFocused = !isDisabled
        handler.edgeBehavior = .wrap
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier
        handler.followSelection()
        handler.focusedIndex = min(max(0, handler.focusedIndex), values.count - 1)
        return handler
    }

    // MARK: - Drawing

    /// What one segment is, for drawing it.
    private struct Segment {
        let isSelected: Bool
        let marksSelection: Bool
        let isCursor: Bool
        let isHovered: Bool
        let isDisabled: Bool
    }

    /// Appends one segment — its label, `padding` spaces either side — to
    /// `row`, and the run its cursor breathes in, if it is the cursor.
    ///
    /// - Parameter field: The face's field, or `nil` for a face of lines,
    ///   whose labels sit on the surface — what the label is drawn on either
    ///   way, and its ink floored against.
    private func drawSegment(
        _ label: AnyView, as segment: Segment, index: Int, field: Color?, padding: Int,
        into row: inout ClaimingRow, runs: inout [AnimatedCellRun], context: RenderContext
    ) {
        let palette = context.environment.palette
        let face = field ?? context.environment.enclosingSurface
        let isMarked = segment.isSelected && segment.marksSelection
        // The cursor's field breathes as a list's cursor row does: a focused,
        // selected row's breath on the selection, the focus wash elsewhere.
        let cursor: RowBackground? =
            segment.isCursor
            ? (isMarked
                ? RowBackground.focusedSelection(in: context, palette: palette)
                : RowBackground.focused(in: context, palette: palette)) : nil

        var labelContext = Self.labelContext(index: index, in: context)
        if let ink = labelInk(for: segment, isMarked: isMarked, face: face, context: context) {
            labelContext = labelContext.settingNotedEnvironment(
                \.foregroundStyle, to: labelContext.environment.foregroundStyle.keepingShadows(on: .color(ink)), paint: true)
        }
        let rendered = TUIView.renderToBuffer(label.bold(isMarked), context: labelContext)
        let pad = String.spaces(padding)
        let text = pad + (rendered.lines.first ?? "") + pad
        let width = text.strippedLength
        let column = row.cells
        for claim in rendered.opacityRegions where claim.offsetY == 0 {
            row.claims.appendCoalescing(claim.shifted(byX: column + padding, y: 0))
        }

        guard let cursor else {
            row.appendFinished(
                field.map { text.withPersistentBackground($0) + ANSIRenderer.reset } ?? text, cells: width)
            return
        }
        row.appendFinished(cursor.painting(text) + ANSIRenderer.reset, cells: width)
        if let fill = cursor.claimableFill,
            let claim = OpacityRegion.claim(offsetX: column, width: width, height: 1, ink: nil, field: fill)
        {
            row.claims.appendCoalescing(claim)
        }
        if !context.isMeasuring, let paints = cursor.framePaints, let timing = cursor.pulseTiming {
            runs.append(
                AnimatedCellRun(
                    offsetX: column, offsetY: 0, width: width,
                    frames: paints.map { $0.painting(text) + ANSIRenderer.reset },
                    frameTicks: timing.frameTicks, clock: timing.clock))
        }
    }

    /// The colour a segment's label is drawn in, or `nil` to leave the label
    /// what the environment makes it.
    ///
    /// - Disabled: the tertiary tier, faded, as every disabled control's label.
    /// - Under the cursor: the page's text colour, as on a list's cursor row —
    ///   the breaths are chosen against it.
    /// - Selected: the accent, as a prominent button's label (bold too).
    /// - Otherwise: the secondary tier, as a bordered button's — unless the
    ///   environment states a colour of its own, which a resting label keeps.
    ///
    /// Each on the face is floored for contrast against it, as a button's
    /// label is, and lifted under the pointer.
    private func labelInk(for segment: Segment, isMarked: Bool, face: Color, context: RenderContext) -> Color? {
        let palette = context.environment.palette
        if segment.isDisabled {
            return palette.foregroundTertiary
                .opacity(ViewConstants.disabledForeground, over: palette.background)
                .ensuringRenderedContrast(atLeast: ViewConstants.disabledLabelContrastFloor, against: face)
        }
        if segment.isCursor { return palette.foreground }
        let resting: Color
        if isMarked {
            resting = palette.accent.ensuringRenderedContrast(atLeast: ViewConstants.labelContrastFloor, against: face)
        } else if let stated = context.environment.foregroundStyle?.representative
            ?? context.environment.styleCascade.resolve(for: [.all, .text, .control(.picker)]).foreground
        {
            guard segment.isHovered else { return nil }
            resting = stated
        } else {
            resting = palette.foregroundSecondary.ensuringRenderedContrast(
                atLeast: ViewConstants.labelContrastFloor, against: face)
        }
        return segment.isHovered ? palette.hoveredLabel(resting) : resting
    }

    // MARK: - Pointer

    /// One region per segment: the pointer lifts the label it is over, and a
    /// click chooses that segment and focuses the control. Each is a
    /// spring-load target too, under `.enabled` — as a `Button` is.
    @MainActor
    private func attachMouse(
        to buffer: inout FrameBuffer, regions: [(x: Int, width: Int)], tags: [SelectionValue],
        handler: RadioButtonGroupHandler, hoverBox: StateBox<Int>, focusID: String, context: RenderContext
    ) {
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher else { return }
        dispatcher.requestFeature(.motion, in: context)
        let focusManager = context.environment.focusManager
        let selection = self.selection
        let springLoads = context.environment.springLoadingBehavior.allows(byDefault: false)
        for (index, region) in regions.enumerated() {
            let tag = tags[index]
            let id = dispatcher.register(in: context) { event in
                switch event.phase {
                case .entered:
                    hoverBox.value = index
                    return true
                case .exited:
                    // Only its own: the next segment's `.entered` may arrive
                    // before this one's `.exited`.
                    if hoverBox.value == index { hoverBox.value = -1 }
                    return true
                case .pressed where event.button == .left:
                    return true
                case .released where event.button == .left:
                    focusManager?.focus(id: focusID)
                    handler.focusedIndex = index
                    selection.wrappedValue = tag
                    return true
                default:
                    return false
                }
            }
            buffer.hitTestRegions.append(
                HitTestRegion(
                    offsetX: region.x, offsetY: 0, width: region.width, height: 1, handlerID: id,
                    // The cursor's segment names the control, so a scroll view
                    // revealing the focus reveals the segment the keys are on.
                    focusID: index == handler.focusedIndex ? focusID : nil))
            if springLoads, let session = context.environment.dragAndDropSession {
                session.registerSpringLoadTarget(
                    DragAndDropSession.SpringLoadTarget(
                        handlerID: id, identity: Self.segmentIdentity(index, in: context),
                        activate: { selection.wrappedValue = tag }),
                    in: context)
            }
        }
    }

    /// The identity segment `index` spring-loads as: one of its own, below the
    /// picker's, so the pause names the segment it rests on (owner ruling B82)
    /// and a drag out of the picker still never activates it.
    private static func segmentIdentity(_ index: Int, in context: RenderContext) -> ViewIdentity {
        context.identity.child(erasedType: SpringLoadedSegment.self, index: index)
    }
}

/// The identity step a segmented picker's segment spring-loads at.
private enum SpringLoadedSegment {}
