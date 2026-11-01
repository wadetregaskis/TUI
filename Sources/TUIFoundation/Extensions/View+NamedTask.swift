//  🖥️ TUI — A Terminal UI framework for Swift
//  View+NamedTask.swift
//
//  SwiftUI's `task(name:…)` and `task(id:name:…)`: a view's task, named.
//
//  Created by Wade Tregaskis
//  License: MIT

extension View {
    /// Adds a named task to perform before this view appears — mirrors
    /// SwiftUI's `task(name:priority:file:line:_:)`.
    ///
    /// The task behaves as ``task(priority:_:)``'s: it starts when the view
    /// appears and is cancelled when it disappears, and its action inherits
    /// the isolation it is written in — the main actor, in a view's body.
    /// What this form adds is the name the task carries, which a debugger, a
    /// profiler and `Task.name` inside the action all see.
    ///
    /// ```swift
    /// Text(status)
    ///     .task(name: "status") {
    ///         status = await server.fetchStatus()
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The task's name, or `nil` for one made from `file` and
    ///     `line`. Tasks are named where the runtime names them: macOS 26,
    ///     and Swift 6.2's runtime elsewhere.
    ///   - priority: The task priority. User-initiated by default.
    ///   - file: The file the default name is made from.
    ///   - line: The line the default name is made from.
    ///   - action: The work to do.
    /// - Returns: A view that runs `action` while it is shown.
    nonisolated public func task(
        name: String? = nil,
        priority: TaskPriority = .userInitiated,
        file: String = #fileID,
        line: Int = #line,
        @_inheritActorContext _ action: sending @escaping @isolated(any) @Sendable () async -> Void
    ) -> some View {
        TaskModifier(
            content: self, task: action, priority: priority, id: nil,
            name: name ?? "\(file):\(line)")
    }

    /// Adds a named task to perform before this view appears or when a
    /// specified value changes — mirrors SwiftUI's
    /// `task(id:name:priority:file:line:_:)`.
    ///
    /// The task behaves as ``task(id:priority:_:)``'s: it starts when the view
    /// appears, is cancelled when it disappears, and is cancelled and
    /// restarted when `id` stops being equal to its last value. Each restart
    /// carries the same name.
    ///
    /// ```swift
    /// Text(results)
    ///     .task(id: query, name: "search") {
    ///         results = await search(query)
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - id: The value to observe for changes.
    ///   - name: The task's name, or `nil` for one made from `file` and
    ///     `line`. Tasks are named where the runtime names them: macOS 26,
    ///     and Swift 6.2's runtime elsewhere.
    ///   - priority: The task priority. User-initiated by default.
    ///   - file: The file the default name is made from.
    ///   - line: The line the default name is made from.
    ///   - action: The work to do.
    /// - Returns: A view that runs `action` while it is shown, restarting it
    ///   when `id` changes.
    nonisolated public func task<T: Equatable>(
        id: T,
        name: String? = nil,
        priority: TaskPriority = .userInitiated,
        file: String = #fileID,
        line: Int = #line,
        @_inheritActorContext _ action: sending @escaping @isolated(any) @Sendable () async -> Void
    ) -> some View {
        TaskModifier(
            content: self, task: action, priority: priority, id: AnyEquatableBox(id),
            name: name ?? "\(file):\(line)")
    }
}
