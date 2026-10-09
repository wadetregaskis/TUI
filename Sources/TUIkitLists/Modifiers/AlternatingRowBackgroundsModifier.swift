//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AlternatingRowBackgroundsModifier.swift
//
//  `alternatingRowBackgrounds(_:)` — whether the lists and tables in a subtree
//  tint every other row.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation

// MARK: - AlternatingRowBackgroundBehavior

/// The styling of views with respect to alternating row backgrounds.
///
/// Use values of this type with the ``View/alternatingRowBackgrounds(_:)``
/// modifier.
public struct AlternatingRowBackgroundBehavior: Hashable, Sendable {
    private enum Kind: Hashable, Sendable { case automatic, enabled, disabled }

    private let kind: Kind

    /// The automatic alternating row background behavior.
    ///
    /// This defers to the component, as on macOS (measured): a `Table`
    /// stripes under every style, and a `List` stripes only when its style
    /// asks (`ListStyle.alternatingRowColors`), which none of the built-in
    /// ones does.
    public static let automatic = Self(kind: .automatic)

    /// Alternating row backgrounds will be enabled.
    public static let enabled = Self(kind: .enabled)

    /// Alternating row backgrounds will be disabled.
    public static let disabled = Self(kind: .disabled)

    /// Whether rows stripe, given what the component does on its own.
    func stripes(byDefault componentDefault: Bool) -> Bool {
        switch kind {
        case .automatic: componentDefault
        case .enabled: true
        case .disabled: false
        }
    }
}

// MARK: - Environment

/// EnvironmentKey for the alternating row background behavior of a subtree.
private struct AlternatingRowBackgroundsKey: EnvironmentKey {
    static let defaultValue: AlternatingRowBackgroundBehavior = .automatic
}

extension EnvironmentValues {
    /// Whether the lists and tables in this subtree stripe their rows.
    var alternatingRowBackgrounds: AlternatingRowBackgroundBehavior {
        get { self[AlternatingRowBackgroundsKey.self] }
        set { self[AlternatingRowBackgroundsKey.self] = newValue }
    }
}

// MARK: - Modifier

extension View {
    /// Overrides whether lists and tables in this view have alternating row
    /// backgrounds.
    ///
    /// A striped row is tinted with the palette's accent at low opacity — the
    /// tint a `ListStyle` that asks for stripes has always drawn — under every
    /// other row: the second, the fourth and so on, counting from each
    /// section's first row however far the content has scrolled, so the
    /// stripes stay on their rows. A focused or selected row keeps its own
    /// highlight.
    ///
    /// ```swift
    /// Table(people) {
    ///     TableColumn("Name", value: \.name)
    /// }
    /// .alternatingRowBackgrounds()
    /// ```
    ///
    /// - Parameter behavior: Whether alternating row backgrounds are enabled
    ///   or not.
    /// - Returns: A view whose lists and tables stripe as `behavior` says.
    public func alternatingRowBackgrounds(
        _ behavior: AlternatingRowBackgroundBehavior = .enabled
    ) -> some View {
        environment(\.alternatingRowBackgrounds, behavior)
    }
}
