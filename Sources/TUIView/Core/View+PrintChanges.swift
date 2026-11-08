//  🖥️ TUI — A Terminal UI framework for Swift
//  View+PrintChanges.swift
//
//  SwiftUI's `_printChanges()` and `_logChanges()`: called in a body, they say
//  what caused that evaluation of it. The work is `BodyChangeReport`'s.
//
//  Created by Wade Tregaskis
//  License: MIT

extension View {
    /// Called in `body`, prints why this evaluation of it happened: the names
    /// of the view's properties that changed since the last one, `@self` when
    /// the view's value is not the one the last evaluation had, and
    /// `@identity` when the view is new at its place in the hierarchy, its
    /// state just made.
    ///
    /// ```swift
    /// var body: some View {
    ///     let _ = Self._printChanges()
    ///     Text("\(count)")
    /// }
    /// ```
    ///
    /// prints `Counter: @self, @identity, _count changed.` the first time,
    /// then `Counter: _count changed.` after a write to `count`.
    ///
    /// Where TUI's lines differ from SwiftUI's:
    ///
    /// - **Where they go.** stdout is the screen, so not there: to the file
    ///   named by `TUI_DIAGNOSTICS_FILE`, appended at once, or otherwise to
    ///   stderr, held while the app has the terminal and written when it gives
    ///   it back (the last 4,096 lines). `tail -f` the file to watch them live.
    /// - **What is named.** `@self`, `@identity`, the view's own `@State`
    ///   properties, its `@Environment` properties whose values moved (by
    ///   name, `_colorScheme`, as a `@State` is), and `an @Observable
    ///   property` for a write to one the body read. SwiftUI names that
    ///   property by its key path, `\Model.count`; TUI can't, because the only
    ///   API that says which property changed is private to SwiftUI.
    /// - **`@self`** is said when a field of the view compares unequal with
    ///   the last value's, by `==` where the field is `Equatable` and by its
    ///   parts where not.
    /// - **Never a false `unchanged.`** What can't be compared — a closure or
    ///   a `Binding` in the view, whose source may have changed; an
    ///   environment value that is neither `Equatable` nor an object — is
    ///   said as `Counter: @self may have changed.` when nothing certainly
    ///   changed. SwiftUI has no words for that; these are TUI's.
    ///   `unchanged.` means everything was compared and nothing moved, as
    ///   when a parent's body ran and drew this view again with the same
    ///   value.
    /// - **Once a frame.** TUI may evaluate a body to measure it and again to
    ///   draw it; only the first evaluation in a frame prints.
    ///
    /// It costs nothing while no body calls it, and works in a release build,
    /// as SwiftUI's does.
    @MainActor @preconcurrency
    public static func _printChanges() {  // swiftlint:disable:this identifier_name
        BodyChangeReport.request(Self.self, logs: false)
    }

    /// Called in `body`, logs why this evaluation of it happened, in the words
    /// ``_printChanges()`` prints.
    ///
    /// On Apple platforms the line goes to the unified log, subsystem `TUI`,
    /// category `Changed Body Properties`, which
    /// Console and `log stream --predicate 'subsystem == "TUI"'` show. Where
    /// there is no unified log, it goes where ``_printChanges()`` writes.
    @MainActor @preconcurrency
    public static func _logChanges() {  // swiftlint:disable:this identifier_name
        BodyChangeReport.request(Self.self, logs: true)
    }
}

extension ViewModifier {
    /// Called in `body(content:)`, prints why this evaluation of it happened,
    /// as ``View/_printChanges()`` prints it for a view: `@self` for the
    /// modifier's own value, its own `@State` and `@Environment` properties by
    /// name, and `an @Observable property`.
    @MainActor @preconcurrency
    public static func _printChanges() {  // swiftlint:disable:this identifier_name
        BodyChangeReport.request(Self.self, logs: false)
    }

    /// Called in `body(content:)`, logs what ``_printChanges()`` would print,
    /// where ``View/_logChanges()`` logs it.
    @MainActor @preconcurrency
    public static func _logChanges() {  // swiftlint:disable:this identifier_name
        BodyChangeReport.request(Self.self, logs: true)
    }
}
