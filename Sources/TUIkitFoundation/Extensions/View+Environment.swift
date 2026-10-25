//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Environment.swift
//
//  Created by LAYERED.work
//  License: MIT

import Observation

// MARK: - Environment

extension View {
    /// Sets an environment value for this view and its children.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the environment value.
    ///   - value: The value to set.
    /// - Returns: A view with the modified environment.
    @inlinable
    public func environment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        _ value: V
    ) -> some View {
        EnvironmentModifier(content: self, keyPath: keyPath, value: value)
    }

    /// Changes an environment value for this view and its children, based on
    /// what it already is.
    ///
    /// Mirrors SwiftUI's `transformEnvironment(_:transform:)`, and exists for
    /// the cases ``View/environment(_:_:)`` cannot express: a value that must be
    /// *derived* from the inherited one. What is inherited is not known where
    /// the view is written — that is the whole point of the environment — so
    /// the closure runs when the subtree renders instead.
    ///
    /// ```swift
    /// // Nudge the scroll step without needing to know what it was.
    /// content.transformEnvironment(\.acceleratedScrollStep) { $0 *= 2 }
    ///
    /// // Adjust one field of a struct value, leaving the rest inherited.
    /// content.transformEnvironment(\.calendar) {
    ///     $0.firstWeekday = 2
    /// }
    /// ```
    ///
    /// The second is the shape that makes this worth having: with
    /// ``View/environment(_:_:)`` you would have to name a whole `Calendar`, which
    /// means deciding every other field of it too — and deciding them without
    /// being able to see what an ancestor set.
    ///
    /// - Parameters:
    ///   - keyPath: The key path to the environment value.
    ///   - transform: A closure that receives the inherited value and modifies
    ///     it in place. It runs on both the measure and the render walk, and so
    ///     must be a pure function of the value it is handed — a closure that
    ///     counted its own calls would neither be stable nor mean anything.
    /// - Returns: A view whose subtree sees the transformed value.
    public func transformEnvironment<V>(
        _ keyPath: WritableKeyPath<EnvironmentValues, V>,
        transform: @escaping (inout V) -> Void
    ) -> some View {
        TransformEnvironmentModifier(content: self, keyPath: keyPath, transform: transform)
    }
}

// MARK: - Observable Objects

extension View {
    /// Injects an observable object into the environment for this view
    /// and its descendants.
    ///
    /// The object is stored by its type. Descendants can read it via
    /// `@Environment(MyModel.self)`.
    ///
    /// # Example
    ///
    /// ```swift
    /// @Observable
    /// class AppModel {
    ///     var count = 0
    /// }
    ///
    /// let model = AppModel()
    /// ContentView()
    ///     .environment(model)
    /// ```
    ///
    /// `nil` clears an object of this type placed further out, so the views
    /// below read none — mirrors SwiftUI, whose `environment(_:)` takes an
    /// optional object (the semantic audit's item 88).
    ///
    /// - Parameter object: The observable object to inject, or `nil` to clear
    ///   one of its type.
    /// - Returns: A view with the object available in the environment.
    public func environment<T: Observable>(_ object: T?) -> some View {
        ObjectEnvironmentModifier(content: self, object: object)
    }
}

// MARK: - Appearance

extension View {
    /// Sets the appearance for this view and its descendants.
    ///
    /// # Example
    ///
    /// ```swift
    /// ContentView()
    ///     .appearance(.rounded)
    ///
    /// // Local override
    /// Panel("Bold Style") {
    ///     content()
    /// }
    /// .appearance(.heavy)
    /// ```
    ///
    /// - Parameter appearance: The appearance to apply.
    /// - Returns: A view with the appearance applied.
    public func appearance(_ appearance: Appearance) -> some View {
        environment(\.appearance, appearance)
    }
}

// MARK: - Palette

extension View {
    /// Sets the color palette for this view and its descendants.
    ///
    /// # Example
    ///
    /// ```swift
    /// ContentView()
    ///     .palette(SystemPalette(.green))
    /// ```
    ///
    /// - Parameter palette: The palette to apply.
    /// - Returns: A view with the palette applied.
    public func palette(_ palette: any Palette) -> some View {
        environment(\.palette, palette)
    }
}
