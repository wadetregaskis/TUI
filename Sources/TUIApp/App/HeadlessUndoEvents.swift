//  🖥️ TUI — A Terminal UI framework for Swift
//  HeadlessUndoEvents.swift
//
//  The end of an event, for a headless app's undo manager: what a running
//  app's run loop does between two events, which a harness sending them one
//  after another never does.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import TUIFoundation

/// Ends the undo group an `UndoManager` opened for an event, once the event
/// has been handled, as a running app's run loop ends it.
///
/// Grouping by event (``UndoManager/groupsByEvent``, the default), an undo
/// manager opens a group at an event's first registration and closes it when
/// the run loop turns, so each event is one undo step. A `HeadlessApp` sends
/// its events one after another from one job, and the run loop never turns
/// between them: every edit of a test became one step, so a kill and the yank
/// after it were undone together.
///
/// Not by calling `endUndoGrouping()` on the manager's behalf: `NSUndoManager`
/// keeps its own note that the event's group is open, and a registration after
/// a group closed under it raises ("must begin a group before registering
/// undo"). It is closed the way it closes itself: the manager is given a run
/// loop mode of its own, and after each event the current run loop is run once
/// in that mode alone, which does the manager's end of the event and nothing
/// else — not the main queue's work, which the common modes carry. A port
/// keeps the mode from being empty, which would return at once and run
/// nothing. Where Foundation has no `UndoManager`, TUI's own ends the event
/// directly.
@MainActor
final class HeadlessUndoEvents {
    let manager: UndoManager

    #if canImport(ObjectiveC)
        /// The mode the manager's end of an event is done in, and nothing else.
        private static let mode = RunLoop.Mode("TUIHeadlessUndoEventEnd")

        /// Keeps ``mode`` from being empty on the run loop it was added to.
        private let keeper = Port()

        /// The run loop ``keeper`` was added to.
        private let runLoop = RunLoop.current
    #endif

    init(_ manager: UndoManager) {
        self.manager = manager
        #if canImport(ObjectiveC)
            manager.runLoopModes = [Self.mode]
            runLoop.add(keeper, forMode: Self.mode)
        #endif
    }

    /// Ends the event's group, if the manager has one open.
    func endEvent() {
        guard manager.groupingLevel > 0 else { return }
        #if canImport(ObjectiveC)
            _ = runLoop.run(mode: Self.mode, before: .distantPast)
        #else
            manager.endEvent()
        #endif
    }

    isolated deinit {
        #if canImport(ObjectiveC)
            keeper.remove(from: runLoop, forMode: Self.mode)
        #endif
    }
}
