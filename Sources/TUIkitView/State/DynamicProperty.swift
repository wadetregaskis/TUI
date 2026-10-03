//  🖥️ TUIkit — Terminal UI Kit for Swift
//  DynamicProperty.swift
//
//  SwiftUI's protocol for a stored property that the framework updates before a
//  view's body runs — what lets an app write its own property wrapper out of
//  `@State`, `@Environment` and friends.
//
//  Created by Wade Tregaskis
//  License: MIT

/// An interface for a stored variable that updates an external property of a
/// view.
///
/// Conform a property wrapper to it and the `@State`, `@Environment` and other
/// dynamic properties it holds behave as they would on the view itself: the
/// state is kept for the place the view is in the tree, and the environment is
/// the one in force there.
///
/// ```swift
/// @propertyWrapper
/// struct Shouting: DynamicProperty {
///     @Environment(\.locale) private var locale
///     let text: String
///
///     var wrappedValue: String { text.uppercased(with: locale) }
/// }
/// ```
///
/// ``update()`` is called before every evaluation of the view's `body`, after
/// the properties inside it have been given their values.
///
/// - Note: SwiftUI writes back what `update()` does to the property's own
///   stored values; TUIkit calls it on the value the view holds and does not,
///   so a change `update()` makes must go into a `@State`, or into an object it
///   holds by reference, to be seen by `body`. Reading, and refreshing a
///   reference-typed cache, behave the same in both.
public protocol DynamicProperty {
    /// Updates the underlying value of the stored value.
    ///
    /// Called before the view's `body` is evaluated. The default does nothing.
    mutating func update()
}

extension DynamicProperty {
    /// Does nothing: most dynamic properties have nothing to update.
    public mutating func update() {}
}

/// The dynamic properties TUIkit itself provides, which the property walks
/// handle directly and need not look inside.
package protocol FrameworkDynamicProperty: DynamicProperty {}

extension State: FrameworkDynamicProperty {}
extension Binding: FrameworkDynamicProperty {}
extension Environment: FrameworkDynamicProperty {}

/// What the property walks do with one stored value that is not itself bound
/// or resolved: descend into it if it holds properties of its own — an app's
/// ``DynamicProperty`` or a ``ViewModifier`` — and say whether it is one.
///
/// A ``FrameworkDynamicProperty`` that the walk did not otherwise handle is a
/// leaf, not a container: looking inside a `Binding` finds only its closures.
enum NestedProperties {
    /// The value, if the walk should descend into it.
    static func container(_ value: Any) -> Any? {
        if value is any FrameworkDynamicProperty { return nil }
        if value is any DynamicProperty || value is any ViewModifier { return value }
        return nil
    }

    /// Runs an app's ``DynamicProperty/update()`` on the value the walk found,
    /// once its own properties have their values.
    static func update(_ value: Any) {
        guard var property = value as? any DynamicProperty,
            !(property is any FrameworkDynamicProperty)
        else { return }
        property.update()
    }
}
