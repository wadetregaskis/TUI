//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextVariantPreference.swift
//
//  `TextVariantPreference` and `Text.textVariant(_:)`: how a text chooses
//  among the sizes of what it can say. TUIkit has the fixed preference,
//  SwiftUI's default; the size-dependent one is not here yet (decisions
//  A32), so asking for it does not compile.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A protocol for controlling the size variant of text views — mirrors
/// SwiftUI's `TextVariantPreference`.
///
/// Certain texts — the live time formats above all — can say the same thing at
/// several widths (`1 hour, 2 minutes`, `1 hr, 2 min`, `1h 2m`). The
/// preference says how one is chosen. TUIkit offers ``fixed``, which always
/// chooses the widest and is SwiftUI's default. SwiftUI's `.sizeDependent`,
/// which chooses the widest that fits, is not offered yet, so code that asks
/// for it does not compile rather than quietly getting the widest.
public protocol TextVariantPreference {}

/// The default text variant preference that chooses the largest available
/// variant — mirrors SwiftUI's `FixedTextVariant`.
///
/// Made only through ``TextVariantPreference/fixed``, as SwiftUI's is.
public struct FixedTextVariant: TextVariantPreference, Sendable {}

extension TextVariantPreference where Self == FixedTextVariant {
    /// The default text variant preference. It always chooses the largest
    /// available variant.
    public static var fixed: FixedTextVariant { FixedTextVariant() }
}

extension Text {
    /// Controls the way text size variants are chosen — mirrors SwiftUI's
    /// `textVariant(_:)`.
    ///
    /// The one preference TUIkit offers, ``TextVariantPreference/fixed``, is
    /// what every text does already, so this returns the text as it is.
    ///
    /// - Parameter preference: How the variant is chosen.
    /// - Returns: The text, choosing its variant as `preference` says.
    public func textVariant<V: TextVariantPreference>(_ preference: V) -> some View {
        self
    }
}
