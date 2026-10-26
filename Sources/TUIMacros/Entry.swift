//  🖥️ TUI — A Terminal UI framework for Swift
//  Entry.swift
//
//  SwiftUI's `@Entry`, in the opt-in macros module beside `@Animatable`
//  (decisions A52): one line for an environment, transaction, container or
//  focused value, where the key type and the accessors are otherwise written
//  out by hand.
//
//      import TUI
//      import TUIMacros
//
//      extension EnvironmentValues {
//          @Entry var accentLabel: String = "Default"
//      }
//
//  Created by Wade Tregaskis
//  License: MIT

/// Creates an environment values, transaction, container values, or focused
/// values entry — mirrors SwiftUI's `Entry()`.
///
/// ## Environment values
///
/// Extend `EnvironmentValues` with a property and attach the macro to it:
///
/// ```swift
/// extension EnvironmentValues {
///     @Entry var myCustomValue: String = "Default value"
///     @Entry var anotherCustomValue = true
/// }
/// ```
///
/// ## Transaction values
///
/// ```swift
/// extension Transaction {
///     @Entry var myCustomValue: String = "Default value"
/// }
/// ```
///
/// ## Container values
///
/// ```swift
/// extension ContainerValues {
///     @Entry var myCustomValue: String = "Default value"
/// }
/// ```
///
/// ## Focused values
///
/// A focused value is `nil` until a view publishes one, so its entry has an
/// `Optional` type and no default value:
///
/// ```swift
/// extension FocusedValues {
///     @Entry var myCustomValue: String?
/// }
/// ```
///
/// The macro writes what SwiftUI's writes: a getter and a setter on the
/// property that read and write `self[__Key_name.self]`, and a private key
/// type `__Key_name` beside it whose default value is the property's
/// initializer, made anew at each read. An `Optional` with no initializer
/// defaults to `nil`. Anywhere else, or with neither a default nor an
/// `Optional` type, it is an error that says what is missing.
@attached(accessor) @attached(peer, names: prefixed(__Key_))
public macro Entry() = #externalMacro(module: "TUIMacrosPlugin", type: "EntryMacro")

/// The accessor `@Entry` puts on its key's default value, so the default is
/// made at each read. Not for apps to write; public because the expansion is
/// in the app's module.
@attached(accessor)
public macro __EntryDefaultValue() = #externalMacro(module: "TUIMacrosPlugin", type: "EntryDefaultValueMacro")
