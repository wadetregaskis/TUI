//  🖥️ TUIkit — Terminal UI Kit for Swift
//  LocalizedString.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Localized String View

/// A view that displays a localized string using a dot-notation key.
///
/// The string is looked up in the current language from the localization
/// service in the environment, which is the shared one: the render loop
/// republishes it every frame, so this shows the app's language and follows a
/// change to it.
///
/// If the key is missing, falls back to English, then to the key itself.
///
/// A string key is the app's, looked up as ``LocalizationService/string(for:)-(String)``
/// looks it up; a typed key (`LocalizedString(LocalizationKey.Button.ok)`)
/// shows TUIkit's own word, which the app's `Localizable` table does not
/// change — see ``LocalizationService``.
///
/// # Example
///
/// ```swift
/// VStack {
///     LocalizedString("button.ok")
///     LocalizedString("error.invalid_input")
/// }
/// ```
///
/// Use this for all UI strings that need localization.
public struct LocalizedString: View {
    /// The dot-notation key for the string to display.
    private let key: String

    /// Whether the key is one of TUIkit's own, from a typed key, and so is
    /// looked up as TUIkit's controls look theirs up.
    private let isFrameworkKey: Bool

    /// The service that resolves the key, taken from the environment.
    ///
    /// Not `LocalizationService.shared` read directly, which is what this did
    /// before. For an app nothing changes — `applyRuntimeServices` republishes
    /// the shared service into the environment every frame, so the default IS
    /// the shared one — but a view's dependencies should reach it down the
    /// tree rather than around it, and this is the difference between a
    /// subtree being able to render in another language and the whole process
    /// having to switch to do it.
    @Environment(\.localizationService) private var service

    /// Creates a localized string view.
    ///
    /// - Parameter key: The dot-notation key (e.g., "button.ok", "error.invalid_input")
    public init(_ key: String) {
        self.key = key
        self.isFrameworkKey = false
    }

    /// A view of one of TUIkit's own keys — what the typed initialisers make.
    init(frameworkKey key: String) {
        self.key = key
        self.isFrameworkKey = true
    }

    public var body: some View {
        Text(verbatim: isFrameworkKey ? service.frameworkString(for: key) : service.string(for: key))
    }
}

// MARK: - Environment without reflection

extension LocalizedString: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _service.resolveEnvironment(environment)
    }
}
