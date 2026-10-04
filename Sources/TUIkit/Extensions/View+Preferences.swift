//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Preferences.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Preference

extension View {
    /// Sets a preference value for this view.
    ///
    /// Preferences propagate up the view hierarchy, allowing child views
    /// to communicate values to their ancestors.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text("Page Title")
    ///     .preference(key: NavigationTitleKey.self, value: "Home")
    /// ```
    ///
    /// - Parameters:
    ///   - key: The preference key type.
    ///   - value: The value to set.
    /// - Returns: A view that sets the preference.
    public func preference<K: PreferenceKey>(key: K.Type, value: K.Value) -> some View {
        PreferenceModifier<Self, K>(content: self, value: value)
    }

    /// Adds an action to perform when a preference value changes.
    ///
    /// # Example
    ///
    /// ```swift
    /// NavigationView {
    ///     content
    /// }
    /// .onPreferenceChange(NavigationTitleKey.self) { title in
    ///     self.title = title
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - key: The preference key type.
    ///   - action: The action to perform with the new value.
    /// - Returns: A view that reacts to preference changes.
    public func onPreferenceChange<K: PreferenceKey>(
        _ key: K.Type,
        perform action: @escaping (K.Value) -> Void
    ) -> some View where K.Value: Equatable {
        OnPreferenceChangeModifier<Self, K>(content: self, action: action)
    }

    /// Applies a transformation to a preference value.
    ///
    /// The transform sees the value this view's subtree reduced — the key's
    /// default when nothing below set it — and what it leaves is what this
    /// view's ancestors receive.
    ///
    /// ```swift
    /// SectionContent()
    ///     .transformPreference(RowCountKey.self) { $0 += 1 } // count the header too
    /// ```
    ///
    /// - Parameters:
    ///   - key: The preference key type.
    ///   - callback: Rewrites the value in place.
    /// - Returns: A view that transforms the preference.
    public func transformPreference<K: PreferenceKey>(
        _ key: K.Type = K.self, _ callback: @escaping (inout K.Value) -> Void
    ) -> some View {
        TransformPreferenceModifier<Self, K>(content: self, transform: callback)
    }

    /// Reads the specified preference value from the view, using it to
    /// produce a second view that is applied as an overlay to the original
    /// view.
    ///
    /// The overlay is laid out in this view's frame, centred, as
    /// ``View/overlay(alignment:content:)`` lays its content.
    ///
    /// - Parameters:
    ///   - key: The preference key type whose value is to be read.
    ///   - transform: A function that produces the overlay view from the
    ///     preference value read from this view's subtree.
    /// - Returns: A view that layers a second view in front of this view.
    public func overlayPreferenceValue<Key: PreferenceKey, T: View>(
        _ key: Key.Type = Key.self, @ViewBuilder _ transform: @escaping (Key.Value) -> T
    ) -> some View {
        PreferenceLayerModifier<Self, Key, T>(
            base: self, transform: transform, alignment: .center, isBackground: false)
    }

    /// Reads the specified preference value from the view, using it to
    /// produce a second view that is applied as an overlay to the original
    /// view, placed by `alignment`.
    ///
    /// - Parameters:
    ///   - key: The preference key type whose value is to be read.
    ///   - alignment: Where the overlay goes in this view's frame.
    ///   - transform: A function that produces the overlay view from the
    ///     preference value read from this view's subtree.
    /// - Returns: A view that layers a second view in front of this view.
    public func overlayPreferenceValue<K: PreferenceKey, V: View>(
        _ key: K.Type, alignment: Alignment = .center, @ViewBuilder _ transform: @escaping (K.Value) -> V
    ) -> some View {
        PreferenceLayerModifier<Self, K, V>(
            base: self, transform: transform, alignment: alignment, isBackground: false)
    }

    /// Reads the specified preference value from the view, using it to
    /// produce a second view that is applied as the background of the
    /// original view.
    ///
    /// The background is laid out in this view's frame, centred, as
    /// ``View/background(alignment:content:)`` lays its content.
    ///
    /// - Parameters:
    ///   - key: The preference key type whose value is to be read.
    ///   - transform: A function that produces the background view from the
    ///     preference value read from this view's subtree.
    /// - Returns: A view that layers a second view behind this view.
    public func backgroundPreferenceValue<Key: PreferenceKey, T: View>(
        _ key: Key.Type = Key.self, @ViewBuilder _ transform: @escaping (Key.Value) -> T
    ) -> some View {
        PreferenceLayerModifier<Self, Key, T>(
            base: self, transform: transform, alignment: .center, isBackground: true)
    }

    /// Reads the specified preference value from the view, using it to
    /// produce a second view that is applied as the background of the
    /// original view, placed by `alignment`.
    ///
    /// - Parameters:
    ///   - key: The preference key type whose value is to be read.
    ///   - alignment: Where the background goes in this view's frame.
    ///   - transform: A function that produces the background view from the
    ///     preference value read from this view's subtree.
    /// - Returns: A view that layers a second view behind this view.
    public func backgroundPreferenceValue<K: PreferenceKey, V: View>(
        _ key: K.Type, alignment: Alignment = .center, @ViewBuilder _ transform: @escaping (K.Value) -> V
    ) -> some View {
        PreferenceLayerModifier<Self, K, V>(
            base: self, transform: transform, alignment: alignment, isBackground: true)
    }
}

// MARK: - Navigation Title

extension View {
    /// Sets the navigation title for this view.
    ///
    /// # Example
    ///
    /// ```swift
    /// VStack {
    ///     Text("Content")
    /// }
    /// .navigationTitle("Home")
    /// ```
    ///
    /// A string **literal** binds here, so the title is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameter titleKey: The key for the navigation title.
    /// - Returns: A view with the navigation title preference set.
    public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View {
        preference(key: NavigationTitleKey.self, value: titleKey.localized)
    }

    /// Sets the navigation title from a string, displayed as written.
    ///
    /// - Parameter title: The navigation title.
    /// - Returns: A view with the navigation title preference set.
    @_disfavoredOverload
    public func navigationTitle<S: StringProtocol>(_ title: S) -> some View {
        preference(key: NavigationTitleKey.self, value: String(title))
    }

    /// Sets the navigation title for this view from a ``Text``.
    ///
    /// Mirrors SwiftUI's `navigationTitle(_:)` `Text` overload. The navigation
    /// title renders as a plain string, so the `Text`'s styling (colour, bold, …)
    /// is not carried — a terminal text-richness limit, not a parity gap.
    ///
    /// - Parameter title: The navigation title as a `Text`.
    /// - Returns: A view with the navigation title preference set.
    public func navigationTitle(_ title: Text) -> some View {
        preference(key: NavigationTitleKey.self, value: title.content)
    }

    /// Configures the view's subtitle for purposes of navigation. Mirrors
    /// SwiftUI's `navigationSubtitle(_:)`.
    ///
    /// macOS draws the subtitle under the window's title. A pushed screen's
    /// navigation bar here is one row, so the subtitle follows the title on
    /// it, in the secondary colour, taking only the room the title and the
    /// crumb trail leave and truncating before they do. Like the title, it is
    /// drawn for a pushed screen, the root having no bar.
    ///
    /// A string **literal** binds here, so the subtitle is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameter subtitleKey: The key for the subtitle.
    public func navigationSubtitle(_ subtitleKey: LocalizedStringKey) -> some View {
        preference(key: NavigationSubtitleKey.self, value: subtitleKey.localized)
    }

    /// Configures the view's subtitle from a string, displayed as written.
    ///
    /// - Parameter subtitle: The subtitle.
    @_disfavoredOverload
    public func navigationSubtitle<S: StringProtocol>(_ subtitle: S) -> some View {
        preference(key: NavigationSubtitleKey.self, value: String(subtitle))
    }

    /// Configures the view's subtitle from a ``Text``, drawn as a plain string
    /// as the title is.
    ///
    /// - Parameter subtitle: The subtitle.
    public func navigationSubtitle(_ subtitle: Text) -> some View {
        preference(key: NavigationSubtitleKey.self, value: subtitle.content)
    }

    /// Hides the navigation bar's Back control for this screen.
    ///
    /// Mirrors SwiftUI's `navigationBarBackButtonHidden(_:)`. Apply it inside a
    /// pushed screen; the enclosing ``NavigationStack`` reads it when it draws
    /// the bar above that screen.
    ///
    /// ```swift
    /// .navigationDestination(for: Step.self) { step in
    ///     Wizard(step)
    ///         .navigationBarBackButtonHidden(step.isCommitting)
    /// }
    /// ```
    ///
    /// The **breadcrumb trail goes with it**. On a wide terminal the bar draws
    /// the trail instead of a Back button, and every crumb in it pops — so a
    /// bar that dropped the button and kept the trail would have hidden one way
    /// back and left three, which is not what the modifier says. The title
    /// stays, and takes the width the button was using.
    ///
    /// **Escape still goes back.** SwiftUI hides the button without disabling
    /// the swipe-back gesture, and Escape is this framework's counterpart to
    /// that gesture rather than to the button. A screen that must not be left
    /// at all wants this *and* something that consumes Escape — an
    /// `.onKeyEvent(keys: [.escape])` on the screen, which the stack asks
    /// before it pops.
    ///
    /// - Parameter hidesBackButton: Whether to hide the control. Default `true`.
    /// - Returns: A view that publishes the preference.
    public func navigationBarBackButtonHidden(_ hidesBackButton: Bool = true) -> some View {
        preference(key: NavigationBackButtonHiddenKey.self, value: hidesBackButton)
    }
}
