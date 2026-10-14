//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SliderHandler.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation

/// A focus handler for slider components.
///
/// `SliderHandler` manages value changes and keyboard input for `Slider`.
/// It handles:
/// - Increment/decrement via arrow keys or +/-
/// - Jump to min/max via Home/End
/// - Clamping values to the defined range
///
/// ## Keyboard Controls
///
/// | Key | Action |
/// |-----|--------|
/// | `→` or `+` | Increment by step |
/// | `←` or `-` | Decrement by step |
/// | `Shift+→` / `Shift+←` | Increment / decrement by 5× the step |
/// | `Home` | Jump to minimum |
/// | `End` | Jump to maximum |
final class SliderHandler<V: BinaryFloatingPoint>: PersistedFocusable where V.Stride: BinaryFloatingPoint {
    /// The unique identifier for this focusable element.
    var focusID: String

    /// ``PersistedFocusable``: answers to `focusID` from now on.
    func repoint(focusID: String) { self.focusID = focusID }

    /// The binding to the current value.
    var value: Binding<V>

    /// The range of valid values.
    ///
    /// Mutable because the handler PERSISTS across renders while the view's
    /// declared range may not: a `Slider(value:in:)` whose range derives from
    /// other state (a maximum that flips with a mode picker) must clamp
    /// against the range the CURRENT render declared, not the one in force
    /// when the handler was first created — `StepperHandler.bounds` documents
    /// the same rule. Worse than stale arrows here: `clampValue()` runs every
    /// render and force-WROTE the app's binding back inside the stale range.
    /// Refreshed every render alongside the value binding.
    var bounds: ClosedRange<V>

    /// The step size for increment/decrement. Mutable for the same reason
    /// as ``bounds``.
    var step: V.Stride

    /// Where the grid of steps starts: the whole range's lower bound, which a
    /// click on the track snaps from too (``stepped(_:by:step:origin:)``).
    /// Mutable for the same reason as ``bounds``.
    var gridOrigin: V

    /// How many steps a Shift-accelerated arrow press takes. Set from
    /// `environment.shiftStepMultiplier` during render (default 5); a plain arrow
    /// (and the `+`/`-` keys) take one. See ``View/shiftStepMultiplier(_:)``.
    var shiftStepMultiplier: Int = 5

    /// Whether this element can currently receive focus.
    var canBeFocused: Bool

    /// Callback triggered when editing begins or ends.
    ///
    /// A span, not an event: a pointer DRAG of the track (press to release), a wheel notch, or an
    /// arrow key. The pointer's span ends with its
    /// release; a wheel notch and a key have no release, so theirs ends when
    /// the control loses focus. Idempotent at both edges — see
    /// ``beginEditingIfNeeded()``.
    var onEditingChanged: ((Bool) -> Void)?

    /// Whether the slider is currently being edited.
    private var isEditing = false

    /// Creates a slider handler.
    ///
    /// - Parameters:
    ///   - focusID: The unique focus identifier.
    ///   - value: The binding to the current value.
    ///   - bounds: The range of valid values.
    ///   - step: The step size for changes.
    ///   - canBeFocused: Whether this element can receive focus. Defaults to `true`.
    init(
        focusID: String,
        value: Binding<V>,
        bounds: ClosedRange<V>,
        step: V.Stride,
        canBeFocused: Bool = true
    ) {
        self.focusID = focusID
        self.value = value
        self.bounds = bounds
        self.step = step
        self.gridOrigin = bounds.lowerBound
        self.canBeFocused = canBeFocused
    }
}

// MARK: - Key Event Handling

extension SliderHandler {
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        // The symbol keys are taken bare only. A Control or Option chord on one
        // is never that symbol: Ctrl-minus (the legacy byte 0x1F, which Ctrl-_
        // and Ctrl-/ also send) is the app's undo, and Option-_ its redo.
        if case .character = event.key, event.ctrl || event.alt { return false }
        // Holding Shift with an arrow steps by the (env-configured) multiplier,
        // for coarse adjustment. (CSI arrow sequences carry the Shift modifier;
        // a typed symbol's Shift is its case, so `+`/`-` keep the single step.)
        let multiplier = event.shift ? max(1, shiftStepMultiplier) : 1
        switch event.key {
        case .right, .character("+"), .character("="):
            beginEditingIfNeeded()
            increment(multiplier: multiplier)
            return true

        case .left, .character("-"), .character("_"):
            beginEditingIfNeeded()
            decrement(multiplier: multiplier)
            return true

        case .home:
            beginEditingIfNeeded()
            jumpToMinimum()
            return true

        case .end:
            beginEditingIfNeeded()
            jumpToMaximum()
            return true

        default:
            return false
        }
    }
}

// MARK: - Value Manipulation

extension SliderHandler {
    /// Increments the value by `multiplier` step sizes (default one), along
    /// the grid a click snaps to.
    func increment(multiplier: Int = 1) {
        let newValue = Self.stepped(value.wrappedValue, by: multiplier, step: step, origin: gridOrigin)
        value.wrappedValue = min(bounds.upperBound, newValue)
    }

    /// Decrements the value by `multiplier` step sizes (default one), along
    /// the grid a click snaps to.
    func decrement(multiplier: Int = 1) {
        let newValue = Self.stepped(value.wrappedValue, by: -multiplier, step: step, origin: gridOrigin)
        value.wrappedValue = max(bounds.lowerBound, newValue)
    }

    /// The value `steps` steps from `value` along the grid of `step`s from
    /// `origin` — the grid a click on the track snaps to — so the keys, the
    /// wheel and the pointer land on the same values. A value off the grid,
    /// one the app wrote, moves to the grid's next value that way rather than
    /// a whole step past it. Unclamped.
    static func stepped(_ value: V, by steps: Int, step: V.Stride, origin: V) -> V {
        let stride = V(step)
        let position = (value - origin) / stride
        // On the grid — within a millionth of a step of a grid value, the
        // grid's own values carrying the float error of `origin + k * step` —
        // a value moves by whole steps from where it is, as it always has.
        guard stride > 0, abs(position - position.rounded()) > 1e-6 else { return value + stride * V(steps) }
        let from = steps > 0 ? position.rounded(.down) : position.rounded(.up)
        return origin + (from + V(steps)) * stride
    }

    /// Jumps to the minimum value.
    func jumpToMinimum() {
        value.wrappedValue = bounds.lowerBound
    }

    /// Jumps to the maximum value.
    func jumpToMaximum() {
        value.wrappedValue = bounds.upperBound
    }

    /// Clamps the current value to the bounds.
    func clampValue() {
        let clamped = max(bounds.lowerBound, min(bounds.upperBound, value.wrappedValue))
        if clamped != value.wrappedValue {
            value.wrappedValue = clamped
        }
    }
}

// MARK: - Editing State

extension SliderHandler {
    /// Begins editing if not already editing.
    ///
    /// Internal rather than private because the POINTER path has to reach it,
    /// and the pointer is the gesture `onEditingChanged` was designed around:
    /// SwiftUI's own wording is "editing begins when the user starts to drag
    /// the thumb along the slider's track". `Slider` writes the value straight
    /// from its mouse closure — it does not go through this handler — so
    /// without this the one gesture the callback exists for reported nothing,
    /// while the keyboard, which SwiftUI has no equivalent of, reported
    /// everything.
    func beginEditingIfNeeded() {
        guard !isEditing else { return }
        isEditing = true
        onEditingChanged?(true)
    }

    /// Ends editing if currently editing.
    func endEditingIfNeeded() {
        guard isEditing else { return }
        isEditing = false
        onEditingChanged?(false)
    }
}

// MARK: - Focus Lifecycle

extension SliderHandler {
    func onFocusReceived() {
        clampValue()
    }

    func onFocusLost() {
        endEditingIfNeeded()
    }
}
