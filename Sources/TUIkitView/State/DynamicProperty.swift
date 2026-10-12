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
/// Each `@State` is kept for where it is declared in the view, whatever the
/// view's other fields hold. In an enum, a view that is one or a property
/// that is one, a case that replaces another starts the `@State` it holds at
/// their defaults, as SwiftUI's does (measured on macOS 15).
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
/// the properties inside it have been given their values, and what it changes
/// in the property's own stored values is what `body` then reads, as in
/// SwiftUI: the property is written back into the view `body` is evaluated on.
/// What it reads of an `@Observable` object is observed as `body`'s reads
/// are, so a change to it draws the view again, as SwiftUI does (measured on
/// macOS 15).
/// A struct's own fields, an optional's wrapped value and an enum's payload
/// are written back. In an `indirect` enum case, `update()` still runs, on a
/// copy, so what it changes is seen only through what the property holds by
/// reference. A property held `unowned` is updated where it is (it is a
/// class), and one held `weak` is not updated, as in SwiftUI (both measured
/// on macOS 15). What a class property holds is bound, resolved and updated
/// once per render pass, by the first view that reaches the object: one
/// object has one state, whichever views show it.
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

/// A dynamic property TUIkit itself provides that holds properties the walks
/// must reach — `@GestureState` keeps its value in a `@State` — but whose
/// ``DynamicProperty/update()`` does nothing: descended into as an app's
/// property is, but not counted as one, so a view holding it is not copied
/// on every body to run that `update()`.
package protocol FrameworkPropertyContainer: DynamicProperty {}

extension State: FrameworkDynamicProperty {}
extension Binding: FrameworkDynamicProperty {}
extension Environment: FrameworkDynamicProperty {}
