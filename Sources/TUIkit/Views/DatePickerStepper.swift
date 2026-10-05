//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DatePickerStepper.swift
//
//  A `.stepperField` date picker's stepper: the `▲▼` pair after the field,
//  drawn where `.datePickerShowsStepper(_:)` asks for it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

// MARK: - Asking for it

private struct DatePickerShowsStepperKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a `.stepperField` ``DatePicker`` draws its stepper — the `▲▼`
    /// pair after the field (default `false`). Set with
    /// ``View/datePickerShowsStepper(_:)``.
    public var datePickerShowsStepper: Bool {
        get { self[DatePickerShowsStepperKey.self] }
        set { self[DatePickerShowsStepperKey.self] = newValue }
    }
}

extension View {
    /// Draws the stepper of every `.stepperField` date picker in this view: a
    /// `▲▼` pair after the field, each a click target that steps the selected
    /// component — up one, or down one, and on and on while it is held.
    ///
    /// ```swift
    /// DatePicker("Starts", selection: $when)
    ///     .datePickerStyle(.stepperField)
    ///     .datePickerShowsStepper()
    /// ```
    ///
    /// Off by default, and TUIkit's own: the pair costs three columns, and the
    /// field already does a stepper's job — Up and Down step the selected
    /// component, and the wheel steps the one under the pointer. Only a
    /// `.stepperField` picker has a stepper to show; every other style ignores
    /// this.
    ///
    /// - Parameter shows: Whether a stepper field draws its stepper.
    /// - Returns: A view whose stepper-field date pickers draw their stepper,
    ///   or do not.
    public func datePickerShowsStepper(_ shows: Bool = true) -> some View {
        environment(\.datePickerShowsStepper, shows)
    }
}

// MARK: - Drawing it

extension _DatePickerCore {
    /// The stepper's two arrows: ▲ steps the selected component up, ▼ down.
    private static var arrows: [(glyph: String, delta: Int)] { [("\u{25B2}", 1), ("\u{25BC}", -1)] }

    /// The cells between the field and its stepper.
    private static var gap: Int { 1 }

    /// Appends the stepper — a space, then `▲▼` — to the field's `line`.
    ///
    /// Dimmed at rest and disabled, as a ``Stepper``'s arrows are; in the
    /// accent while the field has the focus, where the active component already
    /// breathes; lifted under the pointer.
    @MainActor
    func appendStepper(
        to line: inout String, claims: inout [OpacityRegion], isFocused: Bool, isDisabled: Bool,
        context: RenderContext
    ) {
        let palette = context.environment.palette
        let dimmed = palette.foregroundTertiary.opacity(ViewConstants.disabledForeground, over: palette.background)
        var hovered = -1
        if !isDisabled, let storage = context.stateStorage {
            let box: StateBox<Int> = storage.storage(
                for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.hoveredArrow),
                default: -1)
            hovered = box.value
        }
        line += String(repeating: " ", count: Self.gap)
        for (index, arrow) in Self.arrows.enumerated() {
            let resting = isDisabled ? dimmed : isFocused ? palette.accent : dimmed
            let ink = index == hovered ? palette.hoveredGlyph(resting: resting) : resting
            claims.appendCoalescing(
                OpacityRegion.claim(
                    offsetX: line.strippedLength, width: arrow.glyph.strippedLength, height: 1,
                    ink: ink.resolve(with: palette), field: nil))
            line += ANSIRenderer.colorize(arrow.glyph, foreground: ink.opaqueSpelling)
        }
    }

    /// One region per arrow, after the field's `fieldWidth` columns: a press
    /// focuses the field and steps its selected component once, then again and
    /// again while it is held — a ``Stepper``'s arrows' timing — until the
    /// release or a drag off the arrow.
    @MainActor
    func registerStepper(
        at fieldWidth: Int, in buffer: inout FrameBuffer, handler: DatePickerHandler, context: RenderContext
    ) {
        guard !context.isMeasuring, let dispatcher = context.environment.mouseEventDispatcher,
            let stateStorage = context.stateStorage
        else { return }
        let timerBox: StateBox<AutoRepeatTimer> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.stepperTimer),
            default: AutoRepeatTimer())
        let timer = timerBox.value
        let hoverBox: StateBox<Int> = stateStorage.storage(
            for: StateStorage.StateKey(identity: context.identity, propertyIndex: StateIndex.hoveredArrow),
            default: -1)
        let focusManager = context.environment.focusManager
        let focusID = handler.focusID
        var column = fieldWidth + Self.gap
        for (index, arrow) in Self.arrows.enumerated() {
            let delta = arrow.delta
            let id = dispatcher.register(in: context) { event in
                switch event.phase {
                case .entered:
                    hoverBox.value = index
                    return true
                case .exited:
                    if hoverBox.value == index { hoverBox.value = -1 }
                    return true
                default:
                    break
                }
                guard event.button == .left else { return false }
                switch event.phase {
                case .pressed:
                    focusManager?.focus(id: focusID)
                    timer.start { handler.adjust(by: delta) }
                    return true
                case .released, .dragged:
                    timer.stop()
                    return true
                default:
                    return false
                }
            }
            let width = arrow.glyph.strippedLength
            buffer.hitTestRegions.append(
                HitTestRegion(offsetX: column, offsetY: 0, width: width, height: 1, handlerID: id))
            column += width
        }
    }
}
