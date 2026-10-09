//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DatePicker.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitFoundation

// MARK: - DatePickerComponents

/// The date/time components a ``DatePicker`` shows, mirroring SwiftUI's
/// `DatePickerComponents`.
public struct DatePickerComponents: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    /// The year, month, and day.
    public static let date = Self(rawValue: 1 << 0)
    /// The hour and minute.
    public static let hourAndMinute = Self(rawValue: 1 << 1)
}

// MARK: - DatePicker

/// A control for selecting a date and/or time, mirroring SwiftUI's `DatePicker`.
///
/// It renders inline as an editable field — `YYYY-MM-DD HH:MM`, or just the date
/// or time components requested. When focused, Left/Right move between the
/// components, Up/Down adjust the active one, Page Up/Down move it by a coarse
/// step (a decade, a quarter, a week — see `DateFieldModel.pageStep(_:)`),
/// Home/End send it to the ends of its own range, and typing digits sets it —
/// digits from any script, though the field's own presentation stays ASCII on
/// purpose (see `DateFieldModel`):
///
/// ```swift
/// @State private var when = Date()
/// DatePicker("Starts", selection: $when)
/// DatePicker("Date", selection: $when, displayedComponents: .date)
/// DatePicker("Time", selection: $when, in: earliest..., displayedComponents: .hourAndMinute)
/// ```
///
/// > Note: Unlike SwiftUI, this is an inline stepper-style field — the
/// > `.graphical` style draws a calendar, and a `.compact` field opens one in
/// > a popover — it lays the components out in a fixed `YYYY-MM-DD HH:MM` order
/// > rather than the environment locale's, and it omits the watchOS-only
/// > `.hourMinuteAndSecond` component. Components wrap within their field (no
/// > carry) and the whole date is clamped to the `in:` range.
/// >
/// > What it does take from the environment is the arithmetic:
/// > ``EnvironmentValues/calendar`` and ``EnvironmentValues/timeZone``, so the
/// > field counts in the subtree's calendar and shows the subtree's zone. Only
/// > `\.locale` is deliberately ignored, and only for the layout — a
/// > locale-ordered field would move its columns about under the caret, which
/// > the typing model depends on not happening.
public struct DatePicker<Label: View>: View {
    let selection: Binding<Date>
    let range: ClosedRange<Date>?
    let displayedComponents: DatePickerComponents
    let label: Label
    var focusID: String?
    var isDisabled: Bool

    /// The set of date/time components a picker can show.
    public typealias Components = DatePickerComponents

    /// Designated initializer working in the normalized `ClosedRange<Date>?`.
    init(
        selection: Binding<Date>,
        range: ClosedRange<Date>?,
        displayedComponents: DatePickerComponents,
        label: Label
    ) {
        self.selection = selection
        self.range = range
        self.displayedComponents = displayedComponents
        self.label = label
        self.focusID = nil
        self.isDisabled = false
    }

    @Environment(\.datePickerStyle) private var style

    @ViewBuilder public var body: some View {
        let configuration = DatePickerStyleConfiguration(
            label: DatePickerStyleConfiguration.Label(content: AnyView(label)),
            selection: selection,
            // A one-sided range is stored with the far past or future at its
            // open end, which a configuration reports as no bound at all.
            minimumDate: range.map(\.lowerBound).flatMap { (date: Date) -> Date? in date == .distantPast ? nil : date },
            maximumDate: range.map(\.upperBound).flatMap { (date: Date) -> Date? in date == .distantFuture ? nil : date },
            displayedComponents: displayedComponents)
        // A built-in style is drawn here, with this picker's focus id and
        // disabled state, which a configuration does not carry; a custom style
        // through its body.
        if style is GraphicalDatePickerStyle {
            _GraphicalDatePicker(configuration: configuration, focusID: focusID, isDisabled: isDisabled)
        } else if style is CompactDatePickerStyle {
            _CompactDatePicker(configuration: configuration, focusID: focusID, isDisabled: isDisabled)
        } else if style is StepperFieldDatePickerStyle {
            _DatePickerField(
                configuration: configuration, focusID: focusID, isDisabled: isDisabled, isStepperField: true)
        } else if style is any BuiltInDatePickerStyle {
            _DatePickerField(configuration: configuration, focusID: focusID, isDisabled: isDisabled)
        } else {
            style.makeAnyBody(configuration: configuration)
        }
    }
}

// MARK: - ViewBuilder-label initializers

extension DatePicker {
    /// Creates a date picker with a custom label.
    public init(
        selection: Binding<Date>,
        displayedComponents: Components = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.init(selection: selection, range: nil, displayedComponents: displayedComponents, label: label())
    }

    /// Creates a date picker constrained to a closed date range.
    public init(
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: Components = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.init(selection: selection, range: range, displayedComponents: displayedComponents, label: label())
    }

    /// Creates a date picker with a lower bound.
    public init(
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: Components = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            selection: selection, range: range.lowerBound...Date.distantFuture,
            displayedComponents: displayedComponents, label: label())
    }

    /// Creates a date picker with an upper bound.
    public init(
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: Components = [.hourAndMinute, .date],
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            selection: selection, range: Date.distantPast...range.upperBound,
            displayedComponents: displayedComponents, label: label())
    }
}

// MARK: - String-titled initializers

extension DatePicker where Label == Text {
    /// Creates a date picker with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``. The three range-constrained siblings below take
    /// one the same way.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            titleKey.localized, selection: selection,
            displayedComponents: displayedComponents)
    }

    /// Creates a date picker with a localized title, constrained to a range.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            titleKey.localized, selection: selection, in: range,
            displayedComponents: displayedComponents)
    }

    /// Creates a date picker with a localized title and a lower bound.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            titleKey.localized, selection: selection, in: range,
            displayedComponents: displayedComponents)
    }

    /// Creates a date picker with a localized title and an upper bound.
    public init(
        _ titleKey: LocalizedStringKey,
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            titleKey.localized, selection: selection, in: range,
            displayedComponents: displayedComponents)
    }

    /// Creates a date picker with a string title, displayed as written.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            selection: selection, range: nil, displayedComponents: displayedComponents,
            label: Text(String(title)))
    }

    /// Creates a date picker with a string title, as written, within a range.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            selection: selection, range: range, displayedComponents: displayedComponents,
            label: Text(String(title)))
    }

    /// Creates a date picker with a string title, as written, and a lower bound.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: PartialRangeFrom<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            selection: selection, range: range.lowerBound...Date.distantFuture,
            displayedComponents: displayedComponents, label: Text(String(title)))
    }

    /// Creates a date picker with a string title, as written, and an upper bound.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        displayedComponents: Components = [.hourAndMinute, .date]
    ) {
        self.init(
            selection: selection, range: Date.distantPast...range.upperBound,
            displayedComponents: displayedComponents, label: Text(String(title)))
    }
}

// MARK: - Modifiers

extension DatePicker {
    /// Disables the picker.
    public func disabled(_ disabled: Bool = true) -> DatePicker {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets a custom focus identifier.
    public func focusID(_ id: String) -> DatePicker {
        var copy = self
        copy.focusID = id
        return copy
    }
}

// MARK: - Internal Core

enum DatePickerStateIndex {
    static let handler = 0
    static let focusID = 1
    static let isHovered = 2
    /// The press-and-hold repeat of a stepper field's arrows.
    static let stepperTimer = 3
    /// Which of a stepper field's arrows is under the pointer: `0` ▲, `1` ▼,
    /// `-1` neither.
    static let hoveredArrow = 4
}

/// Renders the inline date/time field with the active component highlighted, and
/// wires focus + keyboard + click. Fixed size (it hugs the field).
struct _DatePickerCore: View, Renderable, Layoutable {
    let selection: Binding<Date>
    let range: ClosedRange<Date>?
    let displayedComponents: DatePickerComponents
    let focusID: String?
    let isDisabled: Bool

    /// Whether this is a `.stepperField` picker's field, which draws its
    /// stepper — the `▲▼` pair after it — where `.datePickerShowsStepper(_:)`
    /// asks for one.
    var isStepperField = false

    /// What Return and a click on the field do besides what a field does: a
    /// `.compact` picker opens its calendar. `nil` for every other field.
    var onActivate: (() -> Void)?

    typealias StateIndex = DatePickerStateIndex

    var body: Never {
        fatalError("_DatePickerCore renders via Renderable")
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    /// The active component's cell on its block — one description, used for
    /// the frame drawn now and for every frame of the run that replays it.
    ///
    /// The ink is the opaque spelling; its alpha is claimed by `claimCell` below,
    /// once, which is right for every frame because only the BLOCK breathes here
    /// and `accentFillPulse` spends a faded accent at both ends, so no frame of
    /// this run states a translucent colour of its own (§29.2, §68.4).
    ///
    /// Reversed, both sides are stated opaque beside the 7 and the cell claims
    /// nothing at all, as every reversal does (§86, §89).
    private static func activeCell(
        _ text: String, on block: HighlightFill, underlined: Bool, palette: any Palette
    ) -> String {
        var style = TextStyle()
        style.isUnderlined = underlined
        switch block {
        case .reversed(let ink, let field):
            style.isInverted = true
            style.foregroundColor = ink.opaqueSpelling
            style.backgroundColor = field.opaqueSpelling
        case .fill(let color), .pulse(_, let color):
            style.backgroundColor = color
            style.foregroundColor = palette.foreground.opaqueSpelling
        case .reversingPulse:
            return activeCell(text, on: block.stillFill, underlined: underlined, palette: palette)
        }
        return ANSIRenderer.render(text, with: style.resolved(with: palette))
    }

    /// The active component's cell on a breath with reverse video in it — at 16
    /// colours where the palette's picks run out, and without colour, by weight
    /// (`RowBackground.reversingEnds(of:)`): the frame drawn now, and the run that
    /// replays every frame. Nothing is claimed: a reversal claims nothing, and the
    /// fill end is an opaque slot.
    @MainActor
    private static func reversingCell(
        _ text: String, ends: (dim: RowBackground.Paint, bright: RowBackground.Paint),
        cycle: SelectionEmphasisCycle, at column: Int, underlined: Bool, palette: any Palette
    ) -> (drawn: String, run: AnimatedCellRun?) {
        func drawn(_ paint: RowBackground.Paint) -> String {
            var style = TextStyle()
            style.isUnderlined = underlined
            switch paint {
            case .fill(let colour):
                style.backgroundColor = colour
                style.foregroundColor = palette.foreground.opaqueSpelling
            case .reversed(let ink, let field, let bold):
                style.isInverted = true
                style.isBold = bold
                style.foregroundColor = ink.opaqueSpelling
                style.backgroundColor = field.opaqueSpelling
            }
            return ANSIRenderer.render(text, with: style.resolved(with: palette))
        }
        let frames = cycle.brightFrames().map { drawn($0 ? ends.bright : ends.dim) }
        let run = cycle.run(drawn: frames, offsetX: column, offsetY: 0).flatMap { $0.isAnimating ? $0 : nil }
        return (frames[cycle.step % max(1, frames.count)], run)
    }

    /// The persisted handler, synced to this frame: its binding, its model —
    /// rebuilt every frame, so a change of calendar or zone takes effect on the
    /// next — and an active component the model still has.
    private func resolveHandler(
        focusID: String, isDisabled: Bool, storage: StateStorage, context: RenderContext
    ) -> DatePickerHandler {
        // The subtree's calendar, in the subtree's zone. Both are read here
        // rather than baked into the handler, because the model is rebuilt each
        // frame and reassigned below — so changing either takes effect on the
        // next frame, without the picker having to notice.
        var calendar = context.environment.calendar
        calendar.timeZone = context.environment.timeZone
        let model = DateFieldModel(
            calendar: calendar, components: displayedComponents, range: range)

        let handlerKey = StateStorage.StateKey(
            identity: context.identity, propertyIndex: StateIndex.handler)
        let handlerBox: StateBox<DatePickerHandler> = storage.storage(
            for: handlerKey,
            default: DatePickerHandler(
                focusID: focusID, selection: selection, model: model,
                canBeFocused: !isDisabled))
        let handler = handlerBox.value
        handler.selection = selection
        handler.model = model
        handler.canBeFocused = !isDisabled
        handler.onActivate = isDisabled ? nil : onActivate
        handler.activeIndex = min(max(0, handler.activeIndex), max(0, model.orderedKinds().count - 1))
        return handler
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let isDisabled = self.isDisabled || !context.environment.isEnabled
        let palette = context.environment.palette
        let stateStorage = context.stateStorage!

        let persistedFocusID = FocusRegistration.persistFocusID(
            context: context, explicitFocusID: focusID,
            defaultPrefix: "datepicker", propertyIndex: StateIndex.focusID)

        let handler = resolveHandler(
            focusID: persistedFocusID, isDisabled: isDisabled, storage: stateStorage, context: context)
        let model = handler.model
        // Keep the bound date within range (the binding is the source of truth).
        //
        // Only when it is actually out of range. Writing a binding writes a
        // `StateBox`, which invalidates the render cache and asks for another
        // render — and this runs on every render pass, including a measure. An
        // unconditional store therefore made every frame schedule the next one,
        // forever, drawing an identical picture; see the same shape in
        // `_TabViewCore.tabContentSizes`. `Date` is not `Equatable`-constrained
        // in `Binding`, so nothing upstream can notice the value did not change.
        let clamped = model.clamp(selection.wrappedValue)
        if clamped != selection.wrappedValue { selection.wrappedValue = clamped }

        FocusRegistration.register(
            context: context, handler: handler, focusID: persistedFocusID)
        // Drawing only — see `RenderContext.indicatesFocus(_:)`. The arrows
        // still move between fields and still change the value; what goes is
        // the mark saying which field they are on.
        //
        // That mark reads like this control's caret, and the first version of
        // `focusEffectDisabled` kept it for that reason. It is not: a caret
        // says where TYPING goes, and there is no typing here — the field is
        // active because the control is focused, so the mark is an announcement
        // of focus like any other. A `TextField`'s caret stays; this does not.
        let isFocused = context.indicatesFocus(
            FocusRegistration.isFocused(context: context, focusID: persistedFocusID))

        let isHovered =
            !isDisabled
            && (context.stateStorage!.storage(
                for: StateStorage.StateKey(
                    identity: context.identity, propertyIndex: StateIndex.isHovered),
                default: false) as StateBox<Bool>).value
        let cells = model.cells(date: selection.wrappedValue, activeIndex: isFocused ? handler.activeIndex : -1)
        let activeKind: DateFieldModel.Kind? = isFocused ? handler.activeKind : nil

        // The focused, active component is drawn as a dark glyph on a *pulsing
        // accent* block, in explicit palette colours, so it's readable on every
        // palette and visibly breathes while focused, the same affordance
        // List/Picker rows use. Where the accent or the page has no RGB there is
        // nothing between them to breathe (`Documentation/Opacity as composition.md`
        // §75) and the CELL is reversed instead — with the palette's pair stated
        // beside the 7. Never a bare `ESC[7m`, which is what this site has always
        // said: that exchanges the colours in force, which after a reset are the
        // TERMINAL's defaults, and on a mid-tone theme it collapses to
        // dark-on-dark (§89).
        //
        // The whole cycle, not the live phase: reading the phase marks the frame
        // as having consulted the clock, so every tick re-rendered the page to
        // repaint two or three cells. The block is left as an
        // ``AnimatedCellRun`` instead. Gated on `!isMeasuring` so the measure
        // pass never asks at all; it's colour-only, so the width is identical
        // whether or not it's applied.
        let emphasis = palette.emphasisFill()
        let showsActive = isFocused && !context.isMeasuring
        // A breath with reverse video in it — at 16 colours where the palette's picks
        // run out, and without colour, by weight — as a list's cursor row draws it.
        let reversing =
            showsActive
            ? RowBackground.reversingEnds(of: palette.highlightedRowFill(appearsActive: true, reversing: true)) : nil
        // No cycle is built for a still reversal: it has no phase to advance, and
        // building one is sixteen frames and a pulse ramp for a picture that cannot
        // change.
        let breathes = showsActive && (!emphasis.isReversed || reversing != nil)
        let cycle = context.environment.selectionEmphasis.cycle(breathes)
        let (dimBlock, brightBlock) = palette.accentFillPulse()

        var line = ""
        var runs: [AnimatedCellRun] = []
        var claims: [OpacityRegion] = []

        /// What the cell about to be appended owes, at the column `line` has already
        /// reached — so it is called BEFORE the bytes go on, and exactly once per
        /// cell rather than once per run frame.
        ///
        /// Resolved first: a palette slot may be `.semantic`, and both halves have to
        /// be asked of the same concrete colour or the claim states an alpha the
        /// emitter never sees (and the emitter would `fatalError` on the spelling).
        func claimCell(_ text: String, ink: Color?, field: Color? = nil) {
            claims.appendCoalescing(
                OpacityRegion.claim(
                    offsetX: line.strippedLength, width: text.strippedLength, height: 1,
                    ink: ink?.resolve(with: palette), field: field?.resolve(with: palette)))
        }

        for cell in cells {
            var style = TextStyle()
            if cell.kind == nil {
                // Separators (the "-", ":" and spaces) stay quiet.
                claimCell(cell.text, ink: palette.foregroundSecondary)
                style.foregroundColor = palette.foregroundSecondary.opaqueSpelling
            } else if let activeKind, cell.kind == activeKind, showsActive {
                // Bright text on the pulsing accent block — the same
                // high-contrast, readable affordance List/Picker focused rows use.
                // The block breathes on its own, at the column it lands in. Where it
                // cannot be measured the cell is reversed instead, which is steady:
                // no run to leave, and nothing to claim, since both sides are stated
                // opaque.
                if let ends = reversing, cycle.isAnimating {
                    let (drawn, run) = Self.reversingCell(
                        cell.text, ends: ends, cycle: cycle, at: line.strippedLength, underlined: !isDisabled,
                        palette: palette)
                    if let run { runs.append(run) }
                    line += drawn
                } else if breathes && !emphasis.isReversed {
                    if let run = cycle.run(
                        dim: dimBlock, bright: brightBlock, offsetX: line.strippedLength, offsetY: 0,
                        draw: { Self.activeCell(cell.text, on: .fill($0), underlined: !isDisabled, palette: palette) })
                    {
                        runs.append(run)
                    }
                    claimCell(cell.text, ink: palette.foreground)
                    line += Self.activeCell(
                        cell.text, on: .fill(cycle.colorNow(dim: dimBlock, bright: brightBlock)), underlined: !isDisabled,
                        palette: palette)
                } else {
                    line += Self.activeCell(cell.text, on: emphasis, underlined: !isDisabled, palette: palette)
                }
                continue
            } else {
                // Every editable component is underlined so the field reads as
                // fillable even before it takes focus.
                let resting =
                    isDisabled ? palette.foregroundTertiary : palette.foreground
                // …and lifts under the pointer, unless the field already has
                // the focus and is saying so with its pulsing block.
                let ink = isHovered ? palette.hoveredForeground(resting) : resting
                claimCell(cell.text, ink: ink)
                style.foregroundColor = ink.opaqueSpelling
                style.isUnderlined = !isDisabled
            }
            line += ANSIRenderer.render(cell.text, with: style.resolved(with: palette))
        }

        let fieldWidth = line.strippedLength
        let showsStepper = isStepperField && context.environment.datePickerShowsStepper
        if showsStepper {
            appendStepper(to: &line, claims: &claims, isFocused: isFocused, isDisabled: isDisabled, context: context)
        }
        var buffer = FrameBuffer(lines: [line])
        buffer.animatedCells = runs
        buffer.opacityRegions = claims
        registerMouse(
            context: context, buffer: &buffer, width: fieldWidth, handler: handler, cells: cells,
            isDisabled: isDisabled)
        if showsStepper, !isDisabled {
            registerStepper(at: fieldWidth, in: &buffer, handler: handler, context: context)
        }
        return buffer
    }

    /// One wide region: a left-click focuses the field and selects the component
    /// under the cursor; the wheel steps the component under the pointer (the
    /// active one if the pointer is on a separator) and is swallowed, so it
    /// never also scrolls an enclosing page.
    ///
    /// A `.compact` field's click opens its calendar too (``onActivate``) —
    /// on the date, not on the time. macOS draws a compact picker of both as
    /// two fields and only the date's opens the calendar; here they are one,
    /// and a click on the hour that opened the calendar handed the keyboard
    /// to it, away from the hour the click had just chosen.
    @MainActor
    private func registerMouse(
        context: RenderContext, buffer: inout FrameBuffer, width: Int, handler: DatePickerHandler,
        cells: [DateFieldModel.Cell], isDisabled: Bool
    ) {
        guard !isDisabled, !context.isMeasuring,
            let mouseDispatcher = context.environment.mouseEventDispatcher
        else { return }
        let focusManager = context.environment.focusManager
        let focusID = handler.focusID
        let hoverBox: StateBox<Bool> = context.stateStorage!.storage(
            for: StateStorage.StateKey(
                identity: context.identity, propertyIndex: StateIndex.isHovered),
            default: false)
        // Where the time begins, if the field shows one: the hour's first
        // column. A click there or after it is on the time.
        let timeStart = cells.first { $0.kind == .hour }?.columns.lowerBound
        // An editable field answers the pointer like every other control.
        mouseDispatcher.requestFeature(.motion, in: context)
        let handlerID = mouseDispatcher.register(in: context) { event in
            switch event.phase {
            case .entered, .moved:
                hoverBox.value = true
                return true
            case .exited:
                hoverBox.value = false
                return true
            default:
                break
            }
            switch event.button {
            case .scrollUp, .scrollDown:
                // The field under the pointer takes the step and becomes the
                // active one; over a separator the active field keeps it.
                if let index = componentIndex(at: event.x, cells: cells) {
                    handler.activeIndex = index
                }
                focusManager?.focus(id: focusID)
                // Wheel up goes towards SMALLER/earlier, as it does on every
                // other wheel control here (Stepper, Slider, and the scrollers
                // themselves). Rolling the wheel is scrolling THROUGH the
                // values, not pressing the Up arrow — the two need not agree,
                // and consistency across controls is what a user actually
                // carries from one to the next.
                handler.adjust(by: event.button == .scrollUp ? -1 : 1)
                // Swallowed, not chained: this is a value control, so the
                // wheel must not also scroll the page underneath it.
                return true
            default:
                break
            }
            switch event.phase {
            case .pressed where event.button == .left:
                // Claim the press so the dispatcher's drag capture pins the
                // matching release to this handler — without it, a press here
                // released over a neighbouring control acts as a click the
                // other control's handler never saw the press for (every
                // sibling control claims its press; see Menu's rationale).
                return true
            case .released where event.button == .left:
                focusManager?.focus(id: focusID)
                // Select the component whose columns contain the click.
                if let index = componentIndex(at: event.x, cells: cells) {
                    handler.activeIndex = index
                }
                if event.x < timeStart ?? Int.max { handler.onActivate?() }
                return true
            default:
                return false
            }
        }
        buffer.hitTestRegions.append(
            HitTestRegion(
                offsetX: 0, offsetY: 0, width: width, height: buffer.height,
                handlerID: handlerID, focusID: focusID))
    }

    /// The editable-component index whose columns contain `column`, if any.
    private func componentIndex(at column: Int, cells: [DateFieldModel.Cell]) -> Int? {
        var editableIndex = 0
        for cell in cells where cell.kind != nil {
            if cell.columns.contains(column) { return editableIndex }
            editableIndex += 1
        }
        return nil
    }
}

// MARK: - Environment without reflection

extension DatePicker: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _style.resolveEnvironment(environment)
    }
}
