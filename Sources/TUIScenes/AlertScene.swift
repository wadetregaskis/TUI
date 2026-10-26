//  🖥️ TUI — A Terminal UI framework for Swift
//  AlertScene.swift
//
//  SwiftUI's `AlertScene`: an alert that is a scene of its own, presented
//  over the window in front while its binding is true.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIApp
import TUIFoundation
import TUIPresentation

/// A scene that renders itself as a standalone alert dialog — mirrors
/// SwiftUI's `AlertScene`.
///
/// ```swift
/// @main
/// struct MyApp: App {
///     @State private var showLoginAlert = true
///
///     var body: some Scene {
///         WindowGroup { ContentView() }
///         AlertScene("Login Required", isPresented: $showLoginAlert) {
///             Button("OK") { … }
///         }
///     }
/// }
/// ```
///
/// While `isPresented` is `true` the alert is presented over the window in
/// front, whichever that is, as an alert written on a view in it would be:
/// centred, over the dimmed window, holding the keyboard until it is answered.
/// Every action dismisses it, setting `isPresented` to `false`, Escape chooses
/// its cancel button, and with no actions it has an OK button. The scene's
/// dialog modifiers — ``Scene/dialogSeverity(_:)``, ``Scene/dialogIcon(_:)``
/// and ``Scene/dialogSuppressionToggle(_:isSuppressed:)-(LocalizedStringKey,_)`` —
/// reach it, and not the window's own alerts.
public struct AlertScene<Actions: View, Message: View>: Scene {
    /// The title, as shown.
    let title: String

    /// Whether the alert is up.
    let isPresented: Binding<Bool>

    /// The actions, or `nil` for a presenting form whose data is `nil`, which
    /// presents nothing.
    let actions: Actions?

    /// The message, or `nil` for none.
    let message: Message?

    /// `AlertScene` is presented over the window in front by the app's scene
    /// presenter: this is never called.
    public var body: Never {
        fatalError("AlertScene is presented by the scene presenter")
    }
}

extension AlertScene: OverlayScene {
    package var isSettings: Bool { false }

    /// An empty view presenting the alert while `isPresented` is `true` and
    /// the scene has actions to show.
    package func overlay(in presenter: ScenePresenter) -> AnyView {
        guard let actions else { return AnyView(EmptyView()) }
        let isPresented = self.isPresented
        if let message {
            return AnyView(
                EmptyView().alert(title, isPresented: isPresented) { actions } message: { message })
        }
        return AnyView(EmptyView().alert(title, isPresented: isPresented) { actions })
    }
}

// MARK: - Title and Actions

extension AlertScene where Message == EmptyView {
    /// Creates an alert scene with a title and a set of actions — mirrors
    /// SwiftUI's `init(_:isPresented:actions:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized string that is the title of the
    ///     alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert. When the person chooses one of the alert's
    ///     actions, it is set to `false` and the alert is dismissed.
    ///   - actions: A view builder returning the actions for the dialog.
    public init(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> Actions) {
        self.init(title: titleKey.localized, isPresented: isPresented, actions: actions(), message: nil)
    }

    /// Creates an alert scene with a title string and a set of actions —
    /// mirrors SwiftUI's `init(_:isPresented:actions:)`, disfavoured so a
    /// literal is a localized key.
    ///
    /// - Parameters:
    ///   - title: A text string used as the title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - actions: A view builder returning the actions for the dialog.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> Actions) {
        self.init(title: String(title), isPresented: isPresented, actions: actions(), message: nil)
    }

    /// Creates an alert scene with a text view title and a set of actions —
    /// mirrors SwiftUI's `init(_:isPresented:actions:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - actions: A view builder returning the actions for the dialog.
    public init(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> Actions) {
        self.init(title: title.content, isPresented: isPresented, actions: actions(), message: nil)
    }
}

// MARK: - Title, Actions and Message

extension AlertScene {
    /// Creates an alert scene with a title, a set of actions, and a message —
    /// mirrors SwiftUI's `init(_:isPresented:actions:message:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized string that is the title of the
    ///     alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - actions: A view builder returning the actions for the dialog.
    ///   - message: A view builder returning the message for the dialog.
    public init(
        _ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) {
        self.init(title: titleKey.localized, isPresented: isPresented, actions: actions(), message: message())
    }

    /// Creates an alert scene with a title string, a set of actions, and a
    /// message — mirrors SwiftUI's `init(_:isPresented:actions:message:)`,
    /// disfavoured so a literal is a localized key.
    ///
    /// - Parameters:
    ///   - title: A text string used as the title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - actions: A view builder returning the actions for the dialog.
    ///   - message: A view builder returning the message for the dialog.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) {
        self.init(title: String(title), isPresented: isPresented, actions: actions(), message: message())
    }

    /// Creates an alert scene with a text view title, a set of actions, and a
    /// message — mirrors SwiftUI's `init(_:isPresented:actions:message:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - actions: A view builder returning the actions for the dialog.
    ///   - message: A view builder returning the message for the dialog.
    public init(
        _ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) {
        self.init(title: title.content, isPresented: isPresented, actions: actions(), message: message())
    }
}

// MARK: - Presenting Data

extension AlertScene where Message == EmptyView {
    /// Creates an alert scene using the given data to produce its actions —
    /// mirrors SwiftUI's `init(_:isPresented:presenting:actions:)`. With
    /// `data` `nil`, nothing is presented.
    ///
    /// - Parameters:
    ///   - titleKey: The title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - data: A source of truth passed to the alert to populate its actions.
    ///   - actions: A view builder returning the actions for the dialog.
    public init<T>(
        _ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?,
        @ViewBuilder actions: (T) -> Actions
    ) {
        self.init(title: titleKey.localized, isPresented: isPresented, actions: data.map(actions), message: nil)
    }

    /// Creates an alert scene with a title string, using the given data to
    /// produce its actions — mirrors SwiftUI's
    /// `init(_:isPresented:presenting:actions:)`, disfavoured so a literal is a
    /// localized key.
    ///
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - data: A source of truth passed to the alert to populate its actions.
    ///   - actions: A view builder returning the actions for the dialog.
    @_disfavoredOverload
    public init<S: StringProtocol, T>(
        _ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> Actions
    ) {
        self.init(title: String(title), isPresented: isPresented, actions: data.map(actions), message: nil)
    }

    /// Creates an alert scene with a text view title, using the given data to
    /// produce its actions — mirrors SwiftUI's
    /// `init(_:isPresented:presenting:actions:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - data: A source of truth passed to the alert to populate its actions.
    ///   - actions: A view builder returning the actions for the dialog.
    public init<T>(
        _ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> Actions
    ) {
        self.init(title: title.content, isPresented: isPresented, actions: data.map(actions), message: nil)
    }
}

extension AlertScene {
    /// Creates an alert scene using the given data to produce its actions and
    /// message — mirrors SwiftUI's
    /// `init(_:isPresented:presenting:actions:message:)`. With `data` `nil`,
    /// nothing is presented.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized string that is the title of the
    ///     alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - data: A source of truth passed to the alert to populate its actions
    ///     and message.
    ///   - actions: A view builder returning the actions for the dialog.
    ///   - message: A view builder returning the message for the dialog.
    public init<T>(
        _ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?,
        @ViewBuilder actions: (T) -> Actions, @ViewBuilder message: (T) -> Message
    ) {
        self.init(
            title: titleKey.localized, isPresented: isPresented, actions: data.map(actions), message: data.map(message))
    }

    /// Creates an alert scene with a title string, using the given data to
    /// produce its actions and message — mirrors SwiftUI's
    /// `init(_:isPresented:presenting:actions:message:)`, disfavoured so a
    /// literal is a localized key.
    ///
    /// - Parameters:
    ///   - title: A text string used as the title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - data: A source of truth passed to the alert to populate its actions
    ///     and message.
    ///   - actions: A view builder returning the actions for the dialog.
    ///   - message: A view builder returning the message for the dialog.
    @_disfavoredOverload
    public init<S: StringProtocol, T>(
        _ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> Actions,
        @ViewBuilder message: (T) -> Message
    ) {
        self.init(
            title: String(title), isPresented: isPresented, actions: data.map(actions), message: data.map(message))
    }

    /// Creates an alert scene with a text view title, using the given data to
    /// produce its actions and message — mirrors SwiftUI's
    /// `init(_:isPresented:presenting:actions:message:)`.
    ///
    /// - Parameters:
    ///   - title: The title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to
    ///     present the alert.
    ///   - data: A source of truth passed to the alert to populate its actions
    ///     and message.
    ///   - actions: A view builder returning the actions for the dialog.
    ///   - message: A view builder returning the message for the dialog.
    public init<T>(
        _ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> Actions,
        @ViewBuilder message: (T) -> Message
    ) {
        self.init(
            title: title.content, isPresented: isPresented, actions: data.map(actions), message: data.map(message))
    }
}
