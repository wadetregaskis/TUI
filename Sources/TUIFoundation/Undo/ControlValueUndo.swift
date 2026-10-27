//  🖥️ TUI — A Terminal UI framework for Swift
//  ControlValueUndo.swift
//
//  The undo of a value a person gives a built-in control — a toggle flipped,
//  a choice picked, a slider moved — as a step in the app's undo manager.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

/// A built-in control's undo of the values a person gives it (owner,
/// 2026-10-26: undo for every built-in control that changes a value).
///
/// TUI-specific: SwiftUI's controls register nothing with the undo manager,
/// and leave it to the app. Here a change a person makes — not one the app
/// makes to the binding — is a step in the app's undo manager
/// (`\.undoManager`): undone, it puts the value back, and redone it puts the
/// change back (``UndoManager/registerRestoring(_:to:actionName:)``), as Ctrl-Z
/// and the Edit menu's Undo do for a text field.
///
/// **One step per change, or per run.** A discrete control — a toggle, a
/// picker — makes a step of every change. A continuous one — a slider, a
/// stepper, a colour's channel — makes one step of a run of changes, as a text
/// field makes one of a run of typing: a change made while its step is still the
/// newest in the manager joins that step, which then undoes the whole run back
/// to where it began. A step registered by anything else in between ends the
/// run (``TextUndoBridge/isNewestStep(_:on:)``).
///
/// Held by the control in its state storage, so a run outlives the frames it
/// is drawn in; one per control.
@MainActor
package final class ControlValueUndo {
    /// The mark of the run's step, while a run may go on.
    private var run: TextUndoMark?

    package init() {}

    /// `binding`, but a person's write to it is a step in `manager` — a run
    /// with the writes before it where `coalescing` and its step is still the
    /// newest. `nil` manager (none in the environment, as under a test that
    /// gives none): the binding as it is.
    ///
    /// Handed to the control's input — its key and pointer handlers — never to
    /// a write the control makes itself while drawing (a value clamped into its
    /// range), which no person made.
    package func binding<Value>(
        _ binding: Binding<Value>, coalescing: Bool, manager: UndoManager?
    ) -> Binding<Value> {
        guard let manager else { return binding }
        return Binding(
            get: { binding.wrappedValue },
            set: { [weak self] newValue in
                let old = binding.wrappedValue
                binding.wrappedValue = newValue
                // A write of the value it already has changes nothing: no step.
                if let before = old as? AnyHashable, let after = newValue as? AnyHashable, before == after { return }
                self?.note(binding, from: old, coalescing: coalescing, manager: manager)
            })
    }

    /// Registers the change of `binding` from `old`, or folds it into the run.
    private func note<Value>(_ binding: Binding<Value>, from old: Value, coalescing: Bool, manager: UndoManager) {
        if coalescing, let run, TextUndoBridge.isNewestStep(run, on: manager) { return }
        let mark = TextUndoMark()
        // Inside a group of its own where the manager does not group by event:
        // the label is put on the step being built, so the group has to be
        // open around both (`registerRestoring` opens and closes one alone).
        let needsGroup = !manager.groupsByEvent && manager.groupingLevel == 0
        if needsGroup { manager.beginUndoGrouping() }
        manager.registerRestoring(binding, to: old)
        TextUndoBridge.label(manager, with: mark)
        if needsGroup { manager.endUndoGrouping() }
        run = coalescing ? mark : nil
    }
}

extension RenderContext {
    /// `binding` for a control's input — its key and pointer handlers — whose
    /// writes are steps in the app's undo manager (``ControlValueUndo``), with
    /// the control's run kept at `propertyIndex` of its identity. On a measure,
    /// or with no state storage, the binding as it is.
    @MainActor
    package func undoable<Value>(
        _ binding: Binding<Value>, coalescing: Bool = false, propertyIndex: Int
    ) -> Binding<Value> {
        guard !isMeasuring, let storage = stateStorage else { return binding }
        let undo: ControlValueUndo = storage.storage(
            for: StateStorage.StateKey(identity: identity, propertyIndex: propertyIndex),
            default: ControlValueUndo()
        ).value
        return undo.binding(binding, coalescing: coalescing, manager: environment.undoManager)
    }
}
