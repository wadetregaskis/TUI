//  🖥️ TUI — A Terminal UI framework for Swift
//  View+TaskExecutor.swift
//
//  SwiftUI's `task(name:executorPreference:…)` and
//  `task(id:name:executorPreference:…)`: a view's task, named, and preferring
//  a task executor of the app's.
//
//  Created by Wade Tregaskis
//  License: MIT

extension View {
    /// Adds a task to perform before this view appears or when a specified
    /// value changes, on a preferred task executor — mirrors SwiftUI's
    /// `task(id:name:executorPreference:priority:file:line:_:)`.
    ///
    /// The task behaves as ``task(id:priority:_:)``'s: it starts when the view
    /// appears, is cancelled when it disappears, and is cancelled and
    /// restarted when `id` stops being equal to its last value. It runs with
    /// `taskExecutor` as its executor preference, so the nonisolated async
    /// work it awaits runs there; work isolated to an actor — an action
    /// written in a view's body is on the main actor — runs on that actor, as
    /// Swift's executor preferences always leave it.
    ///
    /// ```swift
    /// Text(status)
    ///     .task(id: server, name: "status", executorPreference: ioExecutor) {
    ///         status = await server.fetchStatus()
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - id: The value to observe for changes.
    ///   - name: The task's name, or `nil` for one made from `file` and
    ///     `line`. Tasks are named where the runtime names them: macOS 26,
    ///     and Swift 6.2's runtime elsewhere.
    ///   - taskExecutor: The task executor the task prefers.
    ///   - priority: The task priority. User-initiated by default.
    ///   - file: The file the default name is made from.
    ///   - line: The line the default name is made from.
    ///   - action: The work to do.
    /// - Returns: A view that runs `action` while it is shown, restarting it
    ///   when `id` changes.
    @available(macOS 15, *)
    public func task<T: Equatable>(
        id: T,
        name: String? = nil,
        executorPreference taskExecutor: any TaskExecutor,
        priority: TaskPriority = .userInitiated,
        file: String = #fileID,
        line: Int = #line,
        @_inheritActorContext _ action: sending @escaping @isolated(any) @Sendable () async -> Void
    ) -> some View {
        executorTask(
            id: AnyEquatableBox(id), name: name ?? "\(file):\(line)",
            taskExecutor: taskExecutor, priority: priority, action: action)
    }

    /// Adds a task to perform before this view appears, on a preferred task
    /// executor — mirrors SwiftUI's
    /// `task(name:executorPreference:priority:file:line:action:)`.
    ///
    /// The task behaves as ``task(priority:_:)``'s: it starts when the view
    /// appears and is cancelled when it disappears. It runs with
    /// `taskExecutor` as its executor preference, as
    /// ``task(id:name:executorPreference:priority:file:line:_:)``'s does.
    ///
    /// The action's label is `action:` here and `_` in the `id:` form; both
    /// are SwiftUI's spellings, and a trailing closure reads the same.
    ///
    /// ```swift
    /// Text(status)
    ///     .task(name: "status", executorPreference: ioExecutor) {
    ///         status = await server.fetchStatus()
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - name: The task's name, or `nil` for one made from `file` and
    ///     `line`. Tasks are named where the runtime names them: macOS 26,
    ///     and Swift 6.2's runtime elsewhere.
    ///   - taskExecutor: The task executor the task prefers.
    ///   - priority: The task priority. User-initiated by default.
    ///   - file: The file the default name is made from.
    ///   - line: The line the default name is made from.
    ///   - action: The work to do.
    /// - Returns: A view that runs `action` while it is shown.
    @available(macOS 15, *)
    public func task(
        name: String? = nil,
        executorPreference taskExecutor: any TaskExecutor,
        priority: TaskPriority = .userInitiated,
        file: String = #fileID,
        line: Int = #line,
        @_inheritActorContext action: sending @escaping @isolated(any) @Sendable () async -> Void
    ) -> some View {
        executorTask(
            id: nil, name: name ?? "\(file):\(line)",
            taskExecutor: taskExecutor, priority: priority, action: action)
    }

    /// The task modifier both executor-preferring forms build.
    @available(macOS 15, *)
    private func executorTask(
        id: AnyEquatableBox?,
        name: String,
        taskExecutor: any TaskExecutor,
        priority: TaskPriority,
        action: sending @escaping @isolated(any) @Sendable () async -> Void
    ) -> TaskModifier<Self> {
        // A local for the closure to capture: Swift refuses a capture of the
        // `sending` parameter itself in a closure that runs concurrently.
        let work = action
        return TaskModifier(
            content: self,
            task: { await withTaskExecutorPreference(taskExecutor) { await work() } },
            priority: priority, id: id, name: name)
    }
}
