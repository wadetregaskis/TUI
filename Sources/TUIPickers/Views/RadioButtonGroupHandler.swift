//  🖥️ TUI — A Terminal UI framework for Swift
//  RadioButtonGroupHandler.swift
//
//  The focus and keyboard half of a radio group, split from the rendering
//  half (`_RadioButtonGroupCore` in RadioButton.swift) so each stays readable:
//  the cursor, what the keys do, and where the focus lands.
//
//  Created by LAYERED.work
//  License: MIT

import TUIFoundation

// MARK: - Radio Button Handler

/// Internal handler class for radio button group focus and selection management.
///
/// Persisted across renders via StateStorage to maintain focusedIndex and enable
/// Tab navigation between radio button groups. A segmented or palette
/// `Picker` (`_PickerSegmentsCore`) keys through one too: a horizontal group
/// whose cursor wraps.
final class RadioButtonGroupHandler: PersistedFocusable {
    var focusID: String

    /// ``PersistedFocusable``: answers to `focusID` from now on.
    func repoint(focusID: String) { self.focusID = focusID }

    var selection: Binding<AnyHashable>
    var itemValues: [AnyHashable]
    /// The options that cannot be chosen (``RadioButtonItem/disabled(_:)``),
    /// by index: the arrows pass over them and Return chooses none.
    var disabledIndices: Set<Int> = []
    /// Mutable because the handler persists across renders while a responsive
    /// layout may flip the group between vertical and horizontal — a stale
    /// orientation kept the OLD arrow-axis mapping (Up/Down navigating a
    /// now-horizontal group, Left/Right relinquishing). Re-synced every
    /// render; same stale-handler-field class as `SliderHandler.bounds`.
    var orientation: RadioButtonOrientation
    var canBeFocused: Bool

    /// What an on-axis arrow past the first/last item does — contain (stay,
    /// the default), escape (relinquish to the neighbour), or wrap. Synced
    /// each render from the environment. See
    /// ``View/radioButtonGroupEdgeBehavior(_:)``.
    var edgeBehavior: RadioButtonGroupEdgeBehavior = .contain

    /// How many options a Shift-accelerated on-axis arrow jumps. Synced from
    /// `environment.shiftStepMultiplier` during render (default 5); a plain arrow
    /// moves one. See ``View/shiftStepMultiplier(_:)``. (Terminal.app strips
    /// Shift from Up/Down, so on a *vertical* group the accelerator only fires
    /// where the terminal keeps it — Home/End/Page always work regardless.)
    var shiftStepMultiplier: Int = 5

    /// Whether a key that moves the cursor chooses the option it lands on
    /// (``View/selectionFollowsCursor(_:)``). Synced from the environment
    /// during render, for event time.
    var selectionFollowsCursor = false

    /// The currently focused item index within the group.
    /// Persisted across renders to maintain focus position.
    var focusedIndex: Int = 0

    /// The selection as the last render found it (``followSelection()``).
    private var lastSeenSelection: AnyHashable?

    init(
        focusID: String,
        selection: Binding<AnyHashable>,
        itemValues: [AnyHashable],
        orientation: RadioButtonOrientation,
        canBeFocused: Bool
    ) {
        self.focusID = focusID
        self.selection = selection
        self.itemValues = itemValues
        self.orientation = orientation
        self.canBeFocused = canBeFocused

        // Find current focused index based on selection
        if let currentIndex = itemValues.firstIndex(of: selection.wrappedValue) {
            self.focusedIndex = currentIndex
        }
    }
}

// MARK: - Focus Lifecycle

extension RadioButtonGroupHandler {
    /// Moves the cursor onto the selection when the selection changed since the
    /// last render without the group choosing it: a status-bar key, a menu, a
    /// second control over the same binding. As on macOS, the focus is on the
    /// selected option. The cursor stayed where it was, and a focused group
    /// then marked two options, the new selection and the focused one, both
    /// with the selected bullet (the Example's image controls, cycled from
    /// their status bar).
    ///
    /// The group's own choice needs nothing: it selects the option the cursor
    /// is on. Called from every render's sync, measuring ones included; the
    /// second call of a render finds nothing changed.
    func followSelection() {
        let current = selection.wrappedValue
        defer { lastSeenSelection = current }
        guard let last = lastSeenSelection, last != current,
            let index = itemValues.firstIndex(of: current)
        else { return }
        focusedIndex = index
    }

    /// Takes this render's options, the cursor going with its option: to the
    /// option's new place when the options were reordered, and onto the last
    /// option when its own is gone and its place is past the end. The cursor
    /// was a place alone: reordered, it sat on another option, and a focused
    /// group whose options shrank from under it showed the focus on none until
    /// a key clamped it.
    func adopt(itemValues newValues: [AnyHashable]) {
        defer { itemValues = newValues }
        guard newValues != itemValues else { return }
        if itemValues.indices.contains(focusedIndex), let moved = newValues.firstIndex(of: itemValues[focusedIndex]) {
            focusedIndex = moved
        } else {
            focusedIndex = max(0, min(focusedIndex, newValues.count - 1))
        }
    }

    /// The cursor starts on the selection, wherever that is now: it may have
    /// been chosen elsewhere while the group did not hold the focus — a second
    /// control over the same binding — and a Space on a cursor left where the
    /// selection used to be chose the old value back. A click focuses first and
    /// then moves the cursor to the option it landed on, so this does not undo
    /// it.
    func onFocusReceived() {
        if let selectedIndex = itemValues.firstIndex(of: selection.wrappedValue) {
            focusedIndex = selectedIndex
        }
    }

    func onFocusLost() {
        // Reset focusedIndex to the selected item when the group loses focus
        if let selectedIndex = itemValues.firstIndex(of: selection.wrappedValue) {
            focusedIndex = selectedIndex
        }
    }
}

// MARK: - Key Event Handling

extension RadioButtonGroupHandler {
    func handleKeyEvent(_ event: KeyEvent) -> Bool {
        guard !itemValues.isEmpty else { return false }

        // Clamp focusedIndex to valid range in case items changed
        focusedIndex = min(focusedIndex, itemValues.count - 1)

        // `.selectionFollowsCursor()`: every key here that moves the cursor
        // moves it to an option that can be chosen, so the option it lands on
        // is chosen, as a macOS radio group's arrows choose. Space and Return
        // leave the cursor where it is.
        let cursor = focusedIndex
        defer {
            if selectionFollowsCursor, focusedIndex != cursor, itemValues.indices.contains(focusedIndex),
                !disabledIndices.contains(focusedIndex)
            {
                selection.wrappedValue = itemValues[focusedIndex]
            }
        }

        // Home/End/Page and a Shift-accelerated on-axis arrow jump to a clamped
        // destination within the group (shared with the other option lists —
        // Picker, Menu, combo-box). A radio group has no scrolling viewport, so
        // Page collapses onto Home/End (pageSize == count). The on-axis arrows
        // follow the group's orientation, so Shift+Left/Right accelerates a
        // horizontal group and Shift+Up/Down a vertical one — the cross-axis
        // arrow still relinquishes below.
        let (onForward, onBackward): (Key, Key) =
            orientation == .vertical ? (.down, .up) : (.right, .left)
        if let destination = OptionListNavigation.clampedDestination(
            for: event, from: focusedIndex, count: itemValues.count,
            onAxisForward: onForward, onAxisBackward: onBackward,
            multiplier: shiftStepMultiplier, pageSize: itemValues.count)
        {
            // Onto the nearest option that can be chosen, back toward where the
            // cursor was, if the destination cannot.
            focusedIndex = nearestEnabled(to: destination, toward: focusedIndex)
            return true
        }

        switch event.key {
        // On the group's movement axis, an interior press moves focus within the
        // group; a press *past* the edge follows `edgeBehavior` (contain by
        // default — see `radioButtonGroupEdgeBehavior`). A cross-axis press
        // always relinquishes so a single-axis group can be left by arrow.
        case .up:
            return moveOnAxis(.vertical, forward: false)

        case .down:
            return moveOnAxis(.vertical, forward: true)

        case .left:
            return moveOnAxis(.horizontal, forward: false)

        case .right:
            return moveOnAxis(.horizontal, forward: true)

        case .enter, .space:
            // Select the currently focused item (make it the selection), unless
            // it is disabled, which the cursor rests on only when nothing else
            // could take it.
            if !disabledIndices.contains(focusedIndex) { selection.wrappedValue = itemValues[focusedIndex] }
            return true

        default:
            return false
        }
    }

    /// Handles an arrow press along `axis` (`forward` = down / right).
    ///
    /// A cross-axis press (the group's orientation differs from `axis`)
    /// relinquishes focus — returning `false` lets `FocusManager` move to the
    /// neighbouring control in that direction. This is what makes Up/Down step
    /// OUT of a horizontal group (to the control above / below) and Left/Right
    /// step out of a vertical one. (It was previously a consumed no-op, which
    /// swallowed Up on a horizontal group so you could never arrow back to the
    /// control above it.) It is INDEPENDENT of ``edgeBehavior``: a single-axis
    /// group has nowhere to move cross-axis, so relinquishing is the only way
    /// to leave it that way.
    ///
    /// On the movement axis an interior press steps `focusedIndex` and consumes
    /// the event; a press past the first/last item follows ``edgeBehavior``:
    /// `.contain` stays put and consumes (the default — you can't overshoot out
    /// of the group, which matters inside a scroll view), `.escape` returns
    /// `false` to relinquish to the neighbour, `.wrap` cycles to the far end.
    private func moveOnAxis(_ axis: RadioButtonOrientation, forward: Bool) -> Bool {
        guard orientation == axis else { return false }  // cross-axis: relinquish focus
        let step = forward ? 1 : -1
        // The next option that can be chosen that way, passing over disabled
        // ones (``RadioButtonItem/disabled(_:)``); `nil` past the edge.
        var next = focusedIndex + step
        while itemValues.indices.contains(next), disabledIndices.contains(next) { next += step }
        if itemValues.indices.contains(next) {
            focusedIndex = next
            return true
        }
        switch edgeBehavior {
        case .contain:
            return true  // stay on the edge item; consume so focus doesn't leave
        case .escape:
            return false  // relinquish to the neighbouring control
        case .wrap:
            focusedIndex = nearestEnabled(to: forward ? 0 : itemValues.count - 1, toward: focusedIndex)
            return true
        }
    }

    /// `index`, or the nearest option from it toward `origin` that can be
    /// chosen; `origin` itself where none between can.
    func nearestEnabled(to index: Int, toward origin: Int) -> Int {
        var candidate = index
        let step = origin >= index ? 1 : -1
        while candidate != origin, disabledIndices.contains(candidate) { candidate += step }
        return candidate
    }
}
