//  🖥️ TUI — A Terminal UI framework for Swift
//  ButtonSizing.swift
//
//  SwiftUI's button sizing: whether a button fits its label or fills the
//  width it is offered.
//
//  Created by Wade Tregaskis
//  License: MIT

/// The sizing behaviour of `Button`s and other button-like controls — mirrors
/// SwiftUI's `ButtonSizing`.
public struct ButtonSizing: Sendable, Hashable {
    private enum Kind: Sendable, Hashable {
        case automatic, fitted, flexible
    }

    private let kind: Kind

    /// The default button sizing behaviour: a button fits its label.
    public static var automatic: Self { Self(kind: .automatic) }

    /// Sizes a button along its primary axis to fit its inner content,
    /// compressing if necessary.
    public static var fitted: Self { Self(kind: .fitted) }

    /// Sizes a button flexibly along its primary axis, filling its available
    /// space.
    ///
    /// A button drawn with a face — `.bordered`, `.borderedProminent` and the
    /// other built-in styles with caps — widens its face to the width it is
    /// offered and centres its label in it. A `.plain`, `.borderless` or
    /// `.link` button has no face to widen and keeps its width.
    public static var flexible: Self { Self(kind: .flexible) }

    /// Whether buttons fill the width they are offered.
    var fills: Bool { kind == .flexible }
}

private struct ButtonSizingKey: EnvironmentKey {
    static let defaultValue = ButtonSizing.automatic
}

extension EnvironmentValues {
    /// The preferred sizing behaviour of buttons in this environment — set
    /// with ``View/buttonSizing(_:)``. A custom style can read it and apply a
    /// frame of its own.
    public var buttonSizing: ButtonSizing {
        get { self[ButtonSizingKey.self] }
        set { self[ButtonSizingKey.self] = newValue }
    }
}

extension View {
    /// The preferred sizing behaviour of buttons in the view hierarchy —
    /// mirrors SwiftUI's `buttonSizing(_:)`.
    ///
    /// ```swift
    /// Button("Open Document…", action: openDocument)
    ///     .buttonSizing(.flexible)
    /// ```
    ///
    /// - Parameter sizing: The sizing behaviour buttons below should use.
    /// - Returns: A view whose buttons size themselves that way.
    nonisolated public func buttonSizing(_ sizing: ButtonSizing) -> some View {
        environment(\.buttonSizing, sizing)
    }
}
