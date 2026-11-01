//  🖥️ TUI — A Terminal UI framework for Swift
//  Text+CustomAttribute.swift
//
//  SwiftUI's `TextAttribute` and `Text.customAttribute(_:)`: a value an app
//  attaches to a span of text for a `TextRenderer` to find on that span's
//  runs (`Text.Layout.Run[T.self]`), as the owner's TEXT-EFFECTS ruling
//  (2026-10-28) asked. Nothing draws differently for an attribute alone.
//
//  Created by Wade Tregaskis
//  License: MIT

/// A value that you can attach to text views and that text renderers can
/// query — mirrors SwiftUI's `TextAttribute`.
///
/// ```swift
/// struct Emphasis: TextAttribute {}
///
/// Text("Hello, \(Text("world").customAttribute(Emphasis()))")
///     .textRenderer(Shimmer())   // reads `run[Emphasis.self]`
/// ```
public protocol TextAttribute: Hashable {}

/// The custom attributes on a run of text, one per type
/// (``Text/customAttribute(_:)``).
///
/// `@unchecked Sendable` because ``Text``, like SwiftUI's, must be `Sendable`,
/// and a `TextAttribute` need not be, as SwiftUI's need not: the source of a
/// program that writes `.customAttribute(_:)` with a class in it has to compile.
/// The values are only compared and handed to a renderer, on the main actor. A
/// lock would change nothing: the values have to come out of it to be compared.
package struct TextAttributes: Hashable, @unchecked Sendable {  // swiftlint:disable:this concurrency_escape
    /// Each attribute, by its type.
    private var values: [ObjectIdentifier: AnyHashable] = [:]

    package init() {}

    /// The attribute of type `T`, or `nil`.
    package subscript<T: TextAttribute>(type: T.Type) -> T? {
        values[ObjectIdentifier(T.self)]?.base as? T
    }

    package var isEmpty: Bool { values.isEmpty }

    /// These attributes with `value` added, replacing one of its type.
    package func adding<T: TextAttribute>(_ value: T) -> Self {
        var copy = self
        copy.values[ObjectIdentifier(T.self)] = AnyHashable(value)
        return copy
    }

    /// These attributes over `base`: one of a type both have is this one's.
    package func merged(over base: Self?) -> Self {
        guard let base else { return self }
        var merged = base
        merged.values.merge(values) { _, own in own }
        return merged
    }
}

extension Text {
    /// Adds a custom attribute to the text view — mirrors SwiftUI's
    /// `Text.customAttribute(_:)`.
    ///
    /// Only one attribute of each type may be attached to each text view: one
    /// written on a text inside a concatenation stays its own, over one written
    /// on the whole, as a fragment's own style does. A text renderer finds it on
    /// the runs of the attributed span (`run[T.self]`); without one, the text
    /// draws as it would without it.
    ///
    /// - Parameter value: The attribute.
    /// - Returns: A text view with the attribute on all of its runs.
    public func customAttribute<T: TextAttribute>(_ value: T) -> Text {
        var text = self
        // Kept on the runs, so concatenation carries it with the words: a text
        // of one fragment becomes a text of one run that carries it.
        let own = runs ?? [Run(text: content, style: TextStyle(), live: nil, link: nil)]
        text.runs = own.map { run in
            var run = run
            run.attributes = (run.attributes ?? TextAttributes()).merged(over: TextAttributes().adding(value))
            return run
        }
        return text
    }
}
