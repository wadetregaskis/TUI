//  🖥️ TUI — A Terminal UI framework for Swift
//  UndoManager+Restoring.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUICore

// MARK: - Restoring a binding's value

extension UndoManager {
    /// Registers the undo of a change already made to the value behind
    /// `binding`: undone, it puts `value` back, and registers the redo that
    /// puts back what the undo replaced — so undo and redo go on alternating
    /// for as long as the manager keeps the step.
    ///
    /// TUI-specific: neither Foundation nor SwiftUI has it. SwiftUI leaves
    /// the undo of a list's `onMove` and `onDelete`, and of a drop, to the
    /// app, as TUI does; this is the shortest way to give one, for state a
    /// view owns. Foundation's `registerUndo(withTarget:handler:)` wants a
    /// class to call back, which a `@State` array is not; a binding to it
    /// does the job. Take the value before the change and register after it:
    ///
    /// ```swift
    /// @Environment(\.undoManager) private var undoManager
    /// @State private var items = ["Aurora", "Bloom", "Cinder"]
    ///
    /// List {
    ///     ForEach(items, id: \.self) { Text($0) }
    ///         .onMove { source, destination in
    ///             let before = items
    ///             items.move(fromOffsets: source, toOffset: destination)
    ///             undoManager?.registerRestoring($items, to: before, actionName: "Move")
    ///         }
    /// }
    /// ```
    ///
    /// A change to two values at once — a row moved from one list to another
    /// — is one step: register a binding to both,
    /// `Binding(get: { (queue, backlog) }, set: { (queue, backlog) = $0 })`.
    ///
    /// The step restores the whole value, so it suits a value a person edits
    /// a step at a time, not one that also changes under them meanwhile: an
    /// undo puts back everything the value was, including what changed since
    /// by other means.
    ///
    /// - Parameters:
    ///   - binding: Where the changed value lives.
    ///   - value: What it was before the change.
    ///   - actionName: The change's name — "Move", "Delete" — which the Edit
    ///     menu's Undo and Redo items show, and which the redo keeps; `nil`
    ///     leaves the step's name as it is.
    @MainActor
    public func registerRestoring<Value>(_ binding: Binding<Value>, to value: Value, actionName: String? = nil) {
        // Without grouping by event a registration needs a group around it,
        // or Foundation's `UndoManager` raises (as `TextUndoBridge` does).
        let needsGroup = !groupsByEvent && groupingLevel == 0
        if needsGroup { beginUndoGrouping() }
        let step = RestoringUndoStep(binding: binding, value: value, actionName: actionName, manager: self)
        // The step is captured as well as passed: the manager keeps its
        // target unowned, and the closure is what keeps the step alive.
        registerUndo(withTarget: step) { [step] _ in
            // The manager runs its steps on the main actor. The macOS 15
            // SDK's handler does not say so and is `@Sendable`, hence the
            // isolated step rather than the binding captured here.
            MainActor.assumeIsolated { step.run() }
        }
        if let actionName { setActionName(actionName) }
        if needsGroup { endUndoGrouping() }
    }
}

/// One step of `UndoManager.registerRestoring(_:to:actionName:)`: the
/// binding, the value it puts back, and the manager to register the reverse
/// with, held weakly, as the manager holds the step.
@MainActor
private final class RestoringUndoStep<Value> {
    let binding: Binding<Value>
    let value: Value
    let actionName: String?
    weak var manager: UndoManager?

    init(binding: Binding<Value>, value: Value, actionName: String?, manager: UndoManager) {
        self.binding = binding
        self.value = value
        self.actionName = actionName
        self.manager = manager
    }

    /// Puts the value back, and registers putting back what it replaced:
    /// inside the manager's undo that is the redo, and inside its redo the
    /// undo again.
    func run() {
        let replaced = binding.wrappedValue
        binding.wrappedValue = value
        manager?.registerRestoring(binding, to: replaced, actionName: actionName)
    }
}
