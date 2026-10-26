//  🖥️ TUI — A Terminal UI framework for Swift
//  UndoStack.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Undo Stack

/// Foundation's `UndoManager`, rebuilt for the platforms whose Foundation has
/// none: swift-corelibs-foundation does not ship the type at all (checked
/// 2026-10-04 against the Swift 6.3.3 static Linux SDK: `UndoManager` is not
/// in scope). The public `UndoManager` there is a thin wrapper over this.
///
/// Compiled on every platform, so its behaviour is tested where the tests run,
/// and modelled on `NSUndoManager`'s, measured on macOS 15:
///
/// - **Groups by event.** With ``groupsByEvent`` on (the default), the first
///   registration of an event opens a group, and the end of the event closes
///   it — on macOS the end of the run loop's pass, here the end of the main
///   actor's current job (``scheduleEndOfEvent``). An explicit
///   ``beginUndoGrouping()`` at the top level opens that event's group first
///   and nests inside it, so two explicit groups in one event are one undo
///   step, as on macOS.
/// - **Undo registers redo.** A registration made while an undo runs goes to
///   the redo stack, and one made while a redo runs to the undo stack, which
///   is how a handler that registers its own inverse gets redo for free.
/// - **A new action forgets redo.** A registration outside undo and redo
///   clears the redo stack.
/// - **`undo()` closes the event's open group** before undoing it, so an undo
///   in the same event as the edit undoes that edit.
///
/// Where `NSUndoManager` raises (an unbalanced `endUndoGrouping`, an undo
/// inside an explicit group, a registration at the top level with grouping by
/// event off), this does the least surprising thing instead: nothing, nothing,
/// and a group of its own for the one action. A terminal app that raised there
/// would die holding the terminal in raw mode. Inside an undo or redo's
/// handler, an unbalanced end does nothing, and an unbalanced begin is closed
/// when the undo or redo ends (see ``run(_:as:)``); `removeAllActions()`
/// forgets everything but the run itself, where `NSUndoManager` raises too.
@MainActor
final class UndoStack {
    /// One registered action: what to run, and the object it was registered
    /// against, so ``removeAllActions(withTarget:)`` can find it.
    private struct Action {
        let target: ObjectIdentifier
        let perform: @MainActor () -> Void
    }

    /// The actions one undo or redo runs, in registration order.
    private struct Group {
        var actions: [Action] = []
        var name = ""
        var isDiscardable = false
        /// The step's user info (``setActionUserInfoValue(_:forKey:)``), by
        /// key.
        var userInfo: [String: Any] = [:]
    }

    private var undoGroups: [Group] = []
    private var redoGroups: [Group] = []

    /// The groups being built, outermost first.
    private var open: [Group] = []

    /// Whether ``open``'s outermost group is the one grouping by event opened.
    private var eventGroupIsOpen = false

    private enum Mode { case normal, undoing, redoing }
    private var mode = Mode.normal

    /// How many of ``open``'s groups an undo or redo that is running opened
    /// itself, and an ``endUndoGrouping()`` in one of its handlers may not
    /// close: the group collecting its inverse. Zero outside one.
    private var runFloor = 0

    private var registrationDisabledCount = 0

    /// Whether the first registration of an event opens a group the event's
    /// end closes. `NSUndoManager`'s default, and this one's.
    var groupsByEvent = true

    /// The most undo steps kept; 0 for no limit. Recording one more drops the
    /// oldest.
    var levelsOfUndo = 0 {
        didSet { trimUndoGroups() }
    }

    /// Runs its argument once the current event is over. The default enqueues
    /// it on the main actor, behind the job that is running now — which, in a
    /// TUI app, is the run loop's pass over the input that just arrived.
    var scheduleEndOfEvent: (@escaping @MainActor () -> Void) -> Void = { body in
        Task { @MainActor in body() }
    }

    init() {}

    // MARK: Grouping

    /// How many groups are open.
    var groupingLevel: Int { open.count }

    /// Opens a group; registrations until the matching ``endUndoGrouping()``
    /// are undone together.
    func beginUndoGrouping() {
        if open.isEmpty, groupsByEvent, mode == .normal { openEventGroup() }
        open.append(Group())
    }

    /// Closes the innermost open group. Does nothing with none open, where
    /// `NSUndoManager` raises — inside an undo or redo's handler too, where
    /// the only group open that the handler did not open is the one
    /// collecting the inverse.
    func endUndoGrouping() {
        guard open.count > runFloor, let group = open.popLast() else { return }
        if open.isEmpty { eventGroupIsOpen = false }
        close(group)
    }

    /// Closes the group grouping by event opened, if it is still open and
    /// nothing opened inside it is: the end of the event.
    func endEvent() {
        guard eventGroupIsOpen, open.count == 1 else { return }
        endUndoGrouping()
    }

    private func openEventGroup() {
        open.append(Group())
        eventGroupIsOpen = true
        scheduleEndOfEvent { [weak self] in self?.endEvent() }
    }

    /// Files a closed group: into its parent if there is one, onto the undo
    /// stack (or, while undoing, the redo stack) if not, and nowhere if empty.
    private func close(_ group: Group) {
        if !open.isEmpty {
            let parent = open.count - 1
            open[parent].actions += group.actions
            if open[parent].name.isEmpty { open[parent].name = group.name }
            open[parent].isDiscardable = open[parent].isDiscardable || group.isDiscardable
            open[parent].userInfo.merge(group.userInfo) { parent, _ in parent }
            return
        }
        guard !group.actions.isEmpty else { return }
        if mode == .undoing {
            redoGroups.append(group)
        } else {
            undoGroups.append(group)
            trimUndoGroups()
        }
    }

    private func trimUndoGroups() {
        guard levelsOfUndo > 0, undoGroups.count > levelsOfUndo else { return }
        undoGroups.removeFirst(undoGroups.count - levelsOfUndo)
    }

    // MARK: Registration

    /// Whether registrations are being recorded.
    var isUndoRegistrationEnabled: Bool { registrationDisabledCount == 0 }

    /// Stops recording registrations until the matching
    /// ``enableUndoRegistration()``. Nests.
    func disableUndoRegistration() {
        registrationDisabledCount += 1
    }

    /// Undoes one ``disableUndoRegistration()``.
    func enableUndoRegistration() {
        if registrationDisabledCount > 0 { registrationDisabledCount -= 1 }
    }

    /// Records `handler`, to be run with `target` on undo.
    func registerUndo<TargetType: AnyObject>(
        withTarget target: TargetType, handler: @escaping @MainActor (TargetType) -> Void
    ) {
        guard isUndoRegistrationEnabled else { return }
        let action = Action(target: ObjectIdentifier(target)) { handler(target) }
        if mode == .normal { redoGroups.removeAll() }
        if open.isEmpty {
            guard groupsByEvent, mode == .normal else {
                // No event to group by: the action is its own step.
                open.append(Group(actions: [action]))
                endUndoGrouping()
                return
            }
            openEventGroup()
        }
        open[open.count - 1].actions.append(action)
    }

    /// Forgets everything: both stacks, every open group, and any disabling.
    ///
    /// Inside an undo or redo's handler, everything but the run itself: the
    /// group collecting its inverse stays open, emptied of what the handler
    /// registered before, for the run to close. So the undo or redo finishes,
    /// and what the handler registers after this is the step that takes it
    /// back. `NSUndoManager` raises there (measured on macOS 15: "endUndoGrouping
    /// called with no matching begin" as the undo ends, grouping by event on
    /// or off), and this used to trap emptying the open groups out from under
    /// the run.
    func removeAllActions() {
        undoGroups.removeAll()
        redoGroups.removeAll()
        if runFloor > 0 {
            // A run is only entered with nothing open, so its group is the
            // first.
            open = [Group(name: open[0].name, isDiscardable: open[0].isDiscardable, userInfo: open[0].userInfo)]
            runFloor = 1
        } else {
            open.removeAll()
        }
        eventGroupIsOpen = false
        registrationDisabledCount = 0
    }

    /// Forgets every action registered against `target`, and any step left
    /// with nothing to do.
    func removeAllActions(withTarget target: AnyObject) {
        let identifier = ObjectIdentifier(target)
        func without(_ group: Group) -> Group {
            var group = group
            group.actions.removeAll { $0.target == identifier }
            return group
        }
        undoGroups = undoGroups.map(without).filter { !$0.actions.isEmpty }
        redoGroups = redoGroups.map(without).filter { !$0.actions.isEmpty }
        open = open.map(without)
    }

    // MARK: Undoing and redoing

    /// Whether there is anything to undo, the event's open group included.
    var canUndo: Bool {
        !undoGroups.isEmpty || open.contains { !$0.actions.isEmpty }
    }

    /// Whether there is anything to redo.
    var canRedo: Bool { !redoGroups.isEmpty }

    /// The undo steps there are, the event's open group included.
    var undoCount: Int {
        undoGroups.count + (open.contains { !$0.actions.isEmpty } ? 1 : 0)
    }

    /// The redo steps there are.
    var redoCount: Int { redoGroups.count }

    /// Whether an undo is running.
    var isUndoing: Bool { mode == .undoing }

    /// Whether a redo is running.
    var isRedoing: Bool { mode == .redoing }

    /// Undoes the latest step, closing the event's group first if it is the
    /// only one open. Does nothing inside an explicit group, where
    /// `NSUndoManager` raises.
    func undo() {
        if eventGroupIsOpen, open.count == 1 { endUndoGrouping() }
        guard open.isEmpty, mode == .normal, let group = undoGroups.popLast() else { return }
        run(group, as: .undoing)
    }

    /// Redoes the latest undone step.
    func redo() {
        if eventGroupIsOpen, open.count == 1 { endUndoGrouping() }
        guard open.isEmpty, mode == .normal, let group = redoGroups.popLast() else { return }
        run(group, as: .redoing)
    }

    /// Undoes the latest step: `NSUndoManager`'s nested form, which here is
    /// ``undo()``, there being no nested group open whenever it can run.
    func undoNestedGroup() {
        undo()
    }

    /// Runs a step's actions newest first, collecting what they register into
    /// a step of the opposite kind under the same name.
    ///
    /// A handler's unbalanced grouping does not escape the run, where
    /// `NSUndoManager` raises: an `endUndoGrouping()` with nothing of its own
    /// open does nothing (``runFloor``), and a group it opened and left open
    /// is closed when the run ends, into the inverse. Before, the first popped
    /// the inverse's group and the run trapped taking it back, and the second
    /// left the inverse open for good, so `undo()` never ran again and every
    /// later registration gathered in it.
    private func run(_ group: Group, as running: Mode) {
        mode = running
        open.append(Group(name: group.name, isDiscardable: group.isDiscardable, userInfo: group.userInfo))
        runFloor = open.count
        for action in group.actions.reversed() { action.perform() }
        runFloor = 0
        while open.count > 1 { endUndoGrouping() }
        let inverse = open.removeLast()
        mode = .normal
        guard !inverse.actions.isEmpty else { return }
        if running == .undoing {
            redoGroups.append(inverse)
        } else {
            undoGroups.append(inverse)
            trimUndoGroups()
        }
    }

    // MARK: Names

    /// Names the step being built — or, with none open, the latest undo step.
    func setActionName(_ name: String) {
        if !open.isEmpty {
            open[0].name = name
        } else if !undoGroups.isEmpty {
            undoGroups[undoGroups.count - 1].name = name
        }
    }

    /// The name of the step ``undo()`` would undo.
    var undoActionName: String {
        open.first { !$0.actions.isEmpty }?.name ?? undoGroups.last?.name ?? ""
    }

    /// The name of the step ``redo()`` would redo.
    var redoActionName: String { redoGroups.last?.name ?? "" }

    /// Marks the step being built as one an app may drop without losing work.
    func setActionIsDiscardable(_ discardable: Bool) {
        if !open.isEmpty {
            open[0].isDiscardable = discardable
        } else if !undoGroups.isEmpty {
            undoGroups[undoGroups.count - 1].isDiscardable = discardable
        }
    }

    /// Whether the step ``undo()`` would undo is discardable.
    var undoActionIsDiscardable: Bool {
        (open.first { !$0.actions.isEmpty } ?? undoGroups.last)?.isDiscardable ?? false
    }

    /// Whether the step ``redo()`` would redo is discardable.
    var redoActionIsDiscardable: Bool { redoGroups.last?.isDiscardable ?? false }

    // MARK: User info

    /// Sets a value in the user info of the step being built, `nil` taking
    /// the key out; it goes with the step to the redo stack and back, as its
    /// name does. With no step being built it does nothing, where
    /// `NSUndoManager` raises ("must begin a group before setting undo action
    /// user info"; measured on macOS 15.8, as is everything here).
    func setActionUserInfoValue(_ info: Any?, forKey key: String) {
        guard !open.isEmpty else { return }
        open[0].userInfo[key] = info
    }

    /// A value from the user info of the step ``undo()`` would undo — the one
    /// being built, once it has an action, as with its name.
    func undoActionUserInfoValue(forKey key: String) -> Any? {
        (open.first { !$0.actions.isEmpty } ?? undoGroups.last)?.userInfo[key]
    }

    /// A value from the user info of the step ``redo()`` would redo.
    func redoActionUserInfoValue(forKey key: String) -> Any? {
        redoGroups.last?.userInfo[key]
    }
}
