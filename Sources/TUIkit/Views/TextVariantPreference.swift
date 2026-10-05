//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TextVariantPreference.swift
//
//  `TextVariantPreference` and `Text.textVariant(_:)`: how a text chooses
//  among the sizes of what it can say — the fixed preference, SwiftUI's
//  default, here, and the size-dependent one in `Text+SizeDependent.swift`.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A protocol for controlling the size variant of text views — mirrors
/// SwiftUI's `TextVariantPreference`.
///
/// Certain texts — the live time formats above all — can say the same thing at
/// several widths (`1 hour, 2 minutes`, `1 hr, 2 min`, `1h 2m`). The
/// preference says how one is chosen: ``fixed`` always chooses the widest and
/// is SwiftUI's default, and ``sizeDependent`` the widest that fits.
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
    /// ``TextVariantPreference/fixed`` is what every text does already, so it
    /// draws the text as it is. ``TextVariantPreference/sizeDependent``
    /// chooses the widest of the text's spellings that fits where it is laid
    /// out; see it for which texts have spellings to choose from.
    ///
    /// - Parameter preference: How the variant is chosen.
    /// - Returns: The text, choosing its variant as `preference` says.
    public func textVariant<V: TextVariantPreference>(_ preference: V) -> some View {
        // One view for either preference, not an `if`: a conditional records
        // its branch and allocates a branch identity on every render, which
        // `.fixed` — the default, written out — has no reason to pay.
        _SizeDependentText(text: self, choosesBySize: preference is SizeDependentTextVariant)
    }
}
