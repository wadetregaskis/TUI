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
    /// - **What is named.** `@self`, `@identity` and the view's own `@State`
    ///   properties. A write to an `@Observable` object, an environment value,
    ///   a `Binding`'s source or state inside a property wrapper of your own is
    ///   not named: a body that ran for one of those prints `unchanged.`, as
    ///   SwiftUI does for a body it can't attribute.
    /// - **`@self`** is said when a field of the view compares unequal with
    ///   the last value's, by `==` where the field is `Equatable` and by its
    ///   parts where not. A closure, or a `Binding`, can't be compared, so a
    ///   change to one alone is not reported.
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
    /// modifier's own value, and its own `@State` properties by name.
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
