//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Animatable.swift
//
//  SwiftUI's `@Animatable` and `@AnimatableIgnored`, in a module of their own
//  that an app imports only if it wants them (decisions A52): a macro is a
//  compiler plugin built against swift-syntax, and only an app that depends
//  on this product builds it.
//
//      import TUIkit
//      import TUIkitMacros
//
//      @Animatable
//      struct Gauge: View {
//          var level: Double
//          @AnimatableIgnored var label: String
//          var body: some View { … }
//      }
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore

/// A member and extension macro that, when applied to a struct, class or
/// enum declaration, synthesizes the conformance to `Animatable` and its
/// requirement, the `animatableData` property, using the existing animatable
/// properties of the type this macro is applied to — mirrors SwiftUI's
/// `Animatable()`.
///
/// ```swift
/// @Animatable
/// struct Meter: View {
///     var width: Double
///     var fill: Double
///     @AnimatableIgnored var isOpaque: Bool
///     // ...
/// }
/// ```
///
/// In the above code, `animatableData` is synthesized from `width` and `fill`
/// — an `AnimatableValues` of their own `AnimatableData`s, in the order they
/// are declared. Since changes to `isOpaque` cannot be animated, it is
/// annotated with ``AnimatableIgnored()``.
///
/// An animatable property is a stored `var` (not `static`, not `lazy`) whose
/// type is written out, so the data's type can be spelt from it; one whose
/// type is inferred is an error that names it. The conformance is not added
/// to a type that already conforms to `Animatable`, and a type with no
/// animatable property is an error, as in SwiftUI.
///
/// TUIkit's `Animatable` is main-actor isolated, so the synthesized
/// `animatableData` is too.
@attached(extension, conformances: Animatable)
@attached(member, names: named(animatableData))
public macro Animatable() = #externalMacro(module: "TUIkitMacrosPlugin", type: "AnimatableMacro")

/// An accessor macro that marks a property of a type to be excluded from the
/// `animatableData` synthesis of ``Animatable()`` — mirrors SwiftUI's
/// `AnimatableIgnored()`.
///
/// ```swift
/// @Animatable
/// struct Meter: View {
///     var width: Double
///     @AnimatableIgnored var isVisible: Bool
///     // ...
/// }
/// ```
///
/// A marker only: the property stores as it did.
@attached(accessor, names: named(willSet))
public macro AnimatableIgnored() = #externalMacro(module: "TUIkitMacrosPlugin", type: "AnimatableIgnoredMacro")
