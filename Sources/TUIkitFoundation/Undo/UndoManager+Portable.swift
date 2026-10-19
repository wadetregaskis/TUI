//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UndoManager+Portable.swift
//
//  Created by Wade Tregaskis
//  License: MIT

// Foundation's `UndoManager` is `NSUndoManager`, an Objective-C class, and
// swift-corelibs-foundation does not provide one at all (Swift 6.3.3's static
// Linux SDK: "cannot find 'UndoManager' in scope"). Where Objective-C is there,
// so is Foundation's, and this file declares nothing.
#if !canImport(ObjectiveC)

import Foundation

// MARK: - UndoManager

/// A general-purpose recorder of operations for undo and redo — Foundation's
/// `UndoManager`, for the platforms whose Foundation has none.
///
/// Its Swift surface is Foundation's, less the parts only Objective-C can
/// offer: there is no `registerUndo(withTarget:selector:object:)` and no
/// `prepare(withInvocationTarget:)`, and no notifications are posted. Code
/// that uses those fails to compile here rather than doing nothing.
///
/// It behaves as `NSUndoManager` does on macOS, including grouping each
/// event's registrations into one undo step (``groupsByEvent``); see
/// `UndoStack`, which is where that behaviour lives and is tested. Where
/// `NSUndoManager` would raise, this does nothing instead.
@MainActor
open class UndoManager {
    /// The recorder this forwards to.
    let stack = UndoStack()

    /// Creates an undo manager.
    public init() {}

    // MARK: Grouping

    /// Marks the beginning of an undo group.
    open func beginUndoGrouping() { stack.beginUndoGrouping() }

    /// Marks the end of an undo group.
    open func endUndoGrouping() { stack.endUndoGrouping() }

    /// The number of nested undo groups in the current event loop.
    open var groupingLevel: Int { stack.groupingLevel }

    /// Whether the receiver automatically creates undo groups around each
    /// event.
    open var groupsByEvent: Bool {
        get { stack.groupsByEvent }
        set { stack.groupsByEvent = newValue }
    }

    /// The maximum number of top-level undo groups the receiver holds; 0, the
    /// default, for no limit.
    open var levelsOfUndo: Int {
        get { stack.levelsOfUndo }
        set { stack.levelsOfUndo = newValue }
    }

    // MARK: Registration

    /// Disables the recording of undo operations.
    open func disableUndoRegistration() { stack.disableUndoRegistration() }

    /// Enables the recording of undo operations.
    open func enableUndoRegistration() { stack.enableUndoRegistration() }

    /// Whether the recording of undo operations is enabled.
    open var isUndoRegistrationEnabled: Bool { stack.isUndoRegistrationEnabled }

    /// Registers a handler to run, with `target`, when the operation it
    /// records is undone. A registration made while undoing records the redo.
    public func registerUndo<TargetType: AnyObject>(
        withTarget target: TargetType, handler: @escaping @MainActor (TargetType) -> Void
    ) {
        stack.registerUndo(withTarget: target, handler: handler)
    }

    /// Clears the undo and redo stacks and re-enables the receiver.
    open func removeAllActions() { stack.removeAllActions() }

    /// Clears the undo and redo stacks of every operation registered against
    /// `target`.
    open func removeAllActions(withTarget target: Any) {
        stack.removeAllActions(withTarget: target as AnyObject)
    }

    // MARK: Undoing and redoing

    /// Whether the receiver has any actions to undo.
    open var canUndo: Bool { stack.canUndo }

    /// Whether the receiver has any actions to redo.
    open var canRedo: Bool { stack.canRedo }

    /// The number of top-level undo groups.
    open var undoCount: Int { stack.undoCount }

    /// The number of top-level redo groups.
    open var redoCount: Int { stack.redoCount }

    /// Closes the top-level undo group if necessary and undoes it.
    open func undo() { stack.undo() }

    /// Redoes the last undone group.
    open func redo() { stack.redo() }

    /// Undoes the last undo group.
    open func undoNestedGroup() { stack.undoNestedGroup() }

    /// Whether the receiver is in the process of performing its undo method.
    open var isUndoing: Bool { stack.isUndoing }

    /// Whether the receiver is in the process of performing its redo method.
    open var isRedoing: Bool { stack.isRedoing }

    // MARK: Names

    /// Sets the name of the action associated with the Undo or Redo command.
    open func setActionName(_ actionName: String) { stack.setActionName(actionName) }

    /// The name identifying the undo action.
    open var undoActionName: String { stack.undoActionName }

    /// The name identifying the redo action.
    open var redoActionName: String { stack.redoActionName }

    /// The complete title of the Undo menu command: "Undo" and the action's
    /// name, in the app's language.
    open var undoMenuItemTitle: String { undoMenuTitle(forUndoActionName: undoActionName) }

    /// The complete title of the Redo menu command.
    open var redoMenuItemTitle: String { redoMenuTitle(forUndoActionName: redoActionName) }

    /// The complete, localized title of the Undo menu command for the action
    /// identified by `actionName`.
    open func undoMenuTitle(forUndoActionName actionName: String) -> String {
        Self.title(LocalizationService.shared.string(for: LocalizationKey.Menu.undo), actionName)
    }

    /// The complete, localized title of the Redo menu command for the action
    /// identified by `actionName`.
    open func redoMenuTitle(forUndoActionName actionName: String) -> String {
        Self.title(LocalizationService.shared.string(for: LocalizationKey.Menu.redo), actionName)
    }

    private static func title(_ verb: String, _ actionName: String) -> String {
        actionName.isEmpty ? verb : "\(verb) \(actionName)"
    }

    /// Sets whether the next undo or redo action is discardable.
    open func setActionIsDiscardable(_ discardable: Bool) { stack.setActionIsDiscardable(discardable) }

    /// Whether the next undo action is discardable.
    open var undoActionIsDiscardable: Bool { stack.undoActionIsDiscardable }

    /// Whether the next redo action is discardable.
    open var redoActionIsDiscardable: Bool { stack.redoActionIsDiscardable }

    // MARK: User info

    /// A key in an undo action's user info.
    public struct UserInfoKey: Hashable, RawRepresentable, Sendable {
        public let rawValue: String

        public init(_ rawValue: String) {
            self.rawValue = rawValue
        }

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    /// Sets a value in the user info of the undo action being built. Does
    /// nothing with no undo group open, where `NSUndoManager` raises.
    open func setActionUserInfoValue(_ info: Any?, forKey key: UserInfoKey) {
        stack.setActionUserInfoValue(info, forKey: key.rawValue)
    }

    /// A value from the user info of the action ``undo()`` would undo.
    open func undoActionUserInfoValue(forKey key: UserInfoKey) -> Any? {
        stack.undoActionUserInfoValue(forKey: key.rawValue)
    }

    /// A value from the user info of the action ``redo()`` would redo.
    open func redoActionUserInfoValue(forKey key: UserInfoKey) -> Any? {
        stack.redoActionUserInfoValue(forKey: key.rawValue)
    }
}

#endif
