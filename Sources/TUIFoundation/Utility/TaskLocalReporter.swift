//  🖥️ TUI — A Terminal UI framework for Swift
//  TaskLocalReporter.swift
//
//  Created by Wade Tregaskis
//  License: MIT

/// A function a test binds to a task-local to hear of something the code under
/// test reports: `DroppedMember.reporter`, `ANSIRenderer.translucentReporter`,
/// `AlignmentGuideRun.guideErrorReporter`, `EditorLayout.buildReporter`.
///
/// A struct holding the function, not the function, for a compiler bug: binding
/// a task-local whose value is a function crashes in `swift_task_localValuePush`
/// where Swift 6.3 optimised the code (`-O`), as a release build of the tests
/// is (report "binding a task-local whose value is a function crashes at -O",
/// 2026-11-21; 6.2 and 6.4 are fine). Called as the function was.
package struct TaskLocalReporter<Message>: Sendable {
    /// The function.
    package let report: @Sendable (Message) -> Void

    /// Holds `report`.
    package init(_ report: @escaping @Sendable (Message) -> Void) {
        self.report = report
    }

    /// Reports `message`.
    package func callAsFunction(_ message: Message) {
        report(message)
    }
}

extension TaskLocalReporter where Message == Void {
    /// Holds `report`, for a report that says only that something happened.
    package init(_ report: @escaping @Sendable () -> Void) {
        self.report = { _ in report() }
    }

    /// Reports that it happened.
    package func callAsFunction() {
        report(())
    }
}
