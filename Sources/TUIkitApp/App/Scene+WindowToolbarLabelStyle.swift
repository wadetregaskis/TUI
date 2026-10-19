//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Scene+WindowToolbarLabelStyle.swift
//
//  SwiftUI's window toolbar label style: how the window's bars draw the labels
//  of their items, stated once for the scene.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitChrome
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
        _EnvironmentScene(content: self) { environment in
            environment.toolbarLabelStyle = fixed
            environment.windowChrome?.choosesToolbarLabelStyle = nil
        }
    }

    /// Sets the label style of items in a toolbar and enables user
    /// customization — mirrors SwiftUI's `Scene.windowToolbarLabelStyle(_:)`.
    ///
    /// As ``windowToolbarLabelStyle(fixed:)``, from a binding read every
    /// frame — typically an `@AppStorage`, so the choice outlives the run —
    /// and written when the person chooses a label style in the toolbar's
    /// context menu or its customization panel (`toolbar(id:content:)`):
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
        _EnvironmentScene(content: self) { environment in
            environment.toolbarLabelStyle = toolbarLabelStyle.wrappedValue
            // The person's choice, in the toolbar's context menu and its
            // customization panel, is written back through the binding.
            environment.windowChrome?.choosesToolbarLabelStyle = { style in
                if let style = style as? ToolbarLabelStyle { toolbarLabelStyle.wrappedValue = style }
            }
        }
    }
}
