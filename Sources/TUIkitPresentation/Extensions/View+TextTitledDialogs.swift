//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+TextTitledDialogs.swift
//
//  The alert and confirmation-dialog forms whose title is a `Text`, as
//  SwiftUI's are (the semantic audit's item 121): each draws as the
//  `StringProtocol` form does with the text's string.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// The title's string, and not its styling: a dialog draws its title in its
// own style (`alert`'s `titleColor:`), as the string forms do. A `Text`
// made from a key was looked up when it was made, so its string is the
// translation.

// MARK: - Alerts

extension View {
    /// Presents an alert with a message when a given condition is true,
    /// using a text view for the title — mirrors SwiftUI's
    /// `alert(_:isPresented:actions:message:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - isPresented: A binding to whether the alert is presented.
    ///   - actions: The alert's actions.
    ///   - message: The message for the alert.
    /// - Returns: A view that presents the alert.
    public func alert<Actions: View, Message: View>(
        _ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        alert(title.content, isPresented: isPresented, actions: actions, message: message)
    }

    /// Presents an alert when a given condition is true, using a text view
    /// for the title — mirrors SwiftUI's `alert(_:isPresented:actions:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - isPresented: A binding to whether the alert is presented.
    ///   - actions: The alert's actions.
    /// - Returns: A view that presents the alert.
    public func alert<Actions: View>(
        _ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        alert(title.content, isPresented: isPresented, actions: actions)
    }

    /// Presents an alert with a message using the given data, using a text
    /// view for the title — mirrors SwiftUI's
    /// `alert(_:isPresented:presenting:actions:message:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - isPresented: A binding to whether the alert is presented.
    ///   - data: The data the actions and message are made from.
    ///   - actions: The alert's actions, given the data.
    ///   - message: The message for the alert, given the data.
    /// - Returns: A view that presents the alert.
    public func alert<Actions: View, Message: View, T>(
        _ title: Text, isPresented: Binding<Bool>, presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions, @ViewBuilder message: @escaping (T) -> Message
    ) -> some View {
        alert(title.content, isPresented: isPresented, presenting: data, actions: actions, message: message)
    }

    /// Presents an alert using the given data, using a text view for the
    /// title — mirrors SwiftUI's `alert(_:isPresented:presenting:actions:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - isPresented: A binding to whether the alert is presented.
    ///   - data: The data the actions are made from.
    ///   - actions: The alert's actions, given the data.
    /// - Returns: A view that presents the alert.
    public func alert<Actions: View, T>(
        _ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: @escaping (T) -> Actions
    ) -> some View {
        alert(title.content, isPresented: isPresented, presenting: data, actions: actions)
    }
}

// MARK: - Confirmation Dialogs

extension View {
    /// Presents a confirmation dialog with a message when a given condition
    /// is true, using a text view for the title — mirrors SwiftUI's
    /// `confirmationDialog(_:isPresented:titleVisibility:actions:message:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the dialog.
    ///   - isPresented: A binding to whether the dialog is presented.
    ///   - titleVisibility: The visibility of the dialog's title.
    ///   - actions: The dialog's actions.
    ///   - message: The message for the dialog.
    /// - Returns: A view that presents the dialog.
    public func confirmationDialog<Actions: View, Message: View>(
        _ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> Actions, @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        confirmationDialog(
            title.content, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions,
            message: message)
    }

    /// Presents a confirmation dialog when a given condition is true, using a
    /// text view for the title — mirrors SwiftUI's
    /// `confirmationDialog(_:isPresented:titleVisibility:actions:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the dialog.
    ///   - isPresented: A binding to whether the dialog is presented.
    ///   - titleVisibility: The visibility of the dialog's title.
    ///   - actions: The dialog's actions.
    /// - Returns: A view that presents the dialog.
    public func confirmationDialog<Actions: View>(
        _ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        confirmationDialog(title.content, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions)
    }

    /// Presents a confirmation dialog with a message using the given data,
    /// using a text view for the title — mirrors SwiftUI's
    /// `confirmationDialog(_:isPresented:titleVisibility:presenting:actions:message:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the dialog.
    ///   - isPresented: A binding to whether the dialog is presented.
    ///   - titleVisibility: The visibility of the dialog's title.
    ///   - data: The data the actions and message are made from.
    ///   - actions: The dialog's actions, given the data.
    ///   - message: The message for the dialog, given the data.
    /// - Returns: A view that presents the dialog.
    public func confirmationDialog<Actions: View, Message: View, T>(
        _ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions, @ViewBuilder message: @escaping (T) -> Message
    ) -> some View {
        confirmationDialog(
            title.content, isPresented: isPresented, titleVisibility: titleVisibility, presenting: data,
            actions: actions, message: message)
    }

    /// Presents a confirmation dialog using the given data, using a text view
    /// for the title — mirrors SwiftUI's
    /// `confirmationDialog(_:isPresented:titleVisibility:presenting:actions:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the dialog.
    ///   - isPresented: A binding to whether the dialog is presented.
    ///   - titleVisibility: The visibility of the dialog's title.
    ///   - data: The data the actions are made from.
    ///   - actions: The dialog's actions, given the data.
    /// - Returns: A view that presents the dialog.
    public func confirmationDialog<Actions: View, T>(
        _ title: Text, isPresented: Binding<Bool>, titleVisibility: Visibility = .automatic, presenting data: T?,
        @ViewBuilder actions: @escaping (T) -> Actions
    ) -> some View {
        confirmationDialog(
            title.content, isPresented: isPresented, titleVisibility: titleVisibility, presenting: data,
            actions: actions)
    }
}
