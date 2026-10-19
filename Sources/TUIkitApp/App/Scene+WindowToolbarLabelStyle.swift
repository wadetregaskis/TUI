//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+WindowToolbarLabelStyle.swift
//
//  SwiftUI's window toolbar label style: how the window's bars draw the labels
//  of their items, stated once for the scene.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - Public Modifiers

extension Scene {
    /// Sets the label style of items in a toolbar — mirrors SwiftUI's
    /// `Scene.windowToolbarLabelStyle(fixed:)`.
    ///
    /// Every ``Label`` in the window's bars' items is drawn in the matching
    /// ``LabelStyle`` (see ``ToolbarLabelStyle``), and the style is what
    /// ``EnvironmentValues/toolbarLabelStyle`` reads everywhere in the scene.
    ///
    /// ```swift
    /// WindowGroup { ContentView() }
    ///     .windowToolbarLabelStyle(fixed: .iconOnly)
    /// ```
    ///
    /// - Parameter fixed: The style to apply.
    /// - Returns: A scene whose toolbar's labels are drawn in `fixed`.
    public func windowToolbarLabelStyle(fixed: ToolbarLabelStyle) -> some Scene {
        _EnvironmentScene(content: self) { $0.toolbarLabelStyle = fixed }
    }

    /// Sets the label style of items in a toolbar and enables user
    /// customization — mirrors SwiftUI's `Scene.windowToolbarLabelStyle(_:)`.
    ///
    /// As ``windowToolbarLabelStyle(fixed:)``, from a binding read every
    /// frame — typically an `@AppStorage`, so the choice outlives the run:
    ///
    /// ```swift
    /// @AppStorage("ToolbarLabelStyle") private var labelStyle: ToolbarLabelStyle = .iconOnly
    ///
    /// var body: some Scene {
    ///     WindowGroup { ContentView() }
    ///         .windowToolbarLabelStyle($labelStyle)
    /// }
    /// ```
    ///
    /// - Parameter toolbarLabelStyle: The label style to apply.
    /// - Returns: A scene whose toolbar's labels are drawn in the binding's
    ///   style.
    public func windowToolbarLabelStyle(_ toolbarLabelStyle: Binding<ToolbarLabelStyle>) -> some Scene {
        _EnvironmentScene(content: self) { $0.toolbarLabelStyle = toolbarLabelStyle.wrappedValue }
    }
}
