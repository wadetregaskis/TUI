//  🖥️ TUI — A Terminal UI framework for Swift
//  LocalizationKey+Initializers.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Convenient Localization Extensions

extension LocalizedString {
    /// Creates a localized string view from a typed localization key.
    ///
    /// # Example
    ///
    /// ```swift
    /// LocalizedString(LocalizationKey.Button.ok)
    /// LocalizedString(LocalizationKey.Error.notFound)
    /// ```
    public init(_ key: LocalizationKey.Button) {
        self.init(frameworkKey: key.rawValue)
    }

    /// Creates a localized string view from a label key.
    public init(_ key: LocalizationKey.Label) {
        self.init(frameworkKey: key.rawValue)
    }

    /// Creates a localized string view from an error key.
    public init(_ key: LocalizationKey.Error) {
        self.init(frameworkKey: key.rawValue)
    }

    /// Creates a localized string view from a placeholder key.
    public init(_ key: LocalizationKey.Placeholder) {
        self.init(frameworkKey: key.rawValue)
    }

    /// Creates a localized string view from a menu key.
    public init(_ key: LocalizationKey.Menu) {
        self.init(frameworkKey: key.rawValue)
    }

    /// Creates a localized string view from a dialog key.
    public init(_ key: LocalizationKey.Dialog) {
        self.init(frameworkKey: key.rawValue)
    }

    /// Creates a localized string view from a validation key.
    public init(_ key: LocalizationKey.Validation) {
        self.init(frameworkKey: key.rawValue)
    }

    /// Creates a localized string view from a status bar key.
    public init(_ key: LocalizationKey.StatusBar) {
        self.init(frameworkKey: key.rawValue)
    }
}

extension Text {
    /// Creates a text view with a localized string using a typed localization key.
    ///
    /// # Example
    ///
    /// ```swift
    /// Text(localized: LocalizationKey.Button.ok)
    /// Text(localized: LocalizationKey.Error.notFound)
    /// ```
    public init(localized key: LocalizationKey.Button) {
        self.init(verbatim: LocalizationService.shared.frameworkString(for: key.rawValue))
    }

    /// Creates a text view with a localized string from a label key.
    public init(localized key: LocalizationKey.Label) {
        self.init(verbatim: LocalizationService.shared.frameworkString(for: key.rawValue))
    }

    /// Creates a text view with a localized string from an error key.
    public init(localized key: LocalizationKey.Error) {
        self.init(verbatim: LocalizationService.shared.frameworkString(for: key.rawValue))
    }

    /// Creates a text view with a localized string from a placeholder key.
    public init(localized key: LocalizationKey.Placeholder) {
        self.init(verbatim: LocalizationService.shared.frameworkString(for: key.rawValue))
    }

    /// Creates a text view with a localized string from a menu key.
    public init(localized key: LocalizationKey.Menu) {
        self.init(verbatim: LocalizationService.shared.frameworkString(for: key.rawValue))
    }

    /// Creates a text view with a localized string from a dialog key.
    public init(localized key: LocalizationKey.Dialog) {
        self.init(verbatim: LocalizationService.shared.frameworkString(for: key.rawValue))
    }

    /// Creates a text view with a localized string from a validation key.
    public init(localized key: LocalizationKey.Validation) {
        self.init(verbatim: LocalizationService.shared.frameworkString(for: key.rawValue))
    }

    /// Creates a text view with a localized string from a status bar key.
    public init(localized key: LocalizationKey.StatusBar) {
        self.init(verbatim: LocalizationService.shared.frameworkString(for: key.rawValue))
    }
}
