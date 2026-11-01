//  🖥️ TUI — A Terminal UI framework for Swift
//  View+SwiftUIUnavailable.swift
//
//  SwiftUI spellings TUI doesn't have, each with a compile error that says what
//  to write instead. The other modules' files of this name hold the spellings
//  that belong to them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

import TUIStyling
import TUIView

// No documentation, and long lines. Nothing here reaches a reader except its message,
// and a message has to be one string literal.
// swiftlint:disable missing_docs line_length

// MARK: - Why these exist

// One modifier the compiler can't find, anywhere in a long view chain, sends the
// type checker through everything it could have meant: 10 to 20 seconds, then
// "unable to type-check this expression" at `var body`, with no hint of which
// line. A declaration it can find ends that search at once: the same mistake
// takes 0.3 seconds, and the error names the line and the fix.
//
// None of this is API. It can't be called, and code completion, the symbol graphs
// that the documentation is built from and Tools/APIParity all leave out what is
// unavailable. `@_alwaysEmitIntoClient` means a function is emitted only into its
// callers, of which there can be none, so these add nothing to a binary.
//
// How they are written:
//
// - The labels are SwiftUI's, because a call that doesn't match falls back to the
//   slow search.
// - A parameter that only has to accept whatever was written is an unconstrained
//   generic, not SwiftUI's type. `.scaleEffect(1.2)` and `.scaleEffect(CGSize(...))`
//   then land on one declaration, where SwiftUI has two.
// - A parameter written as `.large` needs a type with that member, so those types
//   exist too, and are as unavailable as the modifier that takes them.
// - Each returns `Self`, not `some View`, so that the rest of the chain goes on
//   type-checking against the view it started with and reports nothing further.
//
// Tools/APIParity/UnavailableCorpus.swift calls each one and states its error.

// MARK: - Colour

extension View {
    @available(*, unavailable, renamed: "foregroundStyle(_:)", message: "SwiftUI has deprecated foregroundColor too.")
    @_alwaysEmitIntoClient
    nonisolated public func foregroundColor(_ color: Color?) -> Self { self }

    @available(*, unavailable, renamed: "tint(_:)", message: "SwiftUI has deprecated accentColor too.")
    @_alwaysEmitIntoClient
    nonisolated public func accentColor(_ accentColor: Color?) -> Self { self }

    @available(*, unavailable, message: "Set the look of your app with .palette and .appearance instead.")
    @_alwaysEmitIntoClient
    nonisolated public func preferredColorScheme(_ colorScheme: ColorScheme?) -> Self { self }
}

// MARK: - Shape and safe area

extension View {
    @available(*, unavailable, message: "A cell has square corners. For a frame with round ones, use .border(style: .rounded).")
    @_alwaysEmitIntoClient
    nonisolated public func cornerRadius<Radius>(_ radius: Radius, antialiased: Bool = true) -> Self { self }

    @available(*, unavailable, message: "TUI has no safe area to ignore, so delete this. A bar sits beside a view, never behind it.")
    @_alwaysEmitIntoClient
    nonisolated public func edgesIgnoringSafeArea(_ edges: Edge.Set) -> Self { self }

    @available(*, unavailable, message: "TUI has no safe area to ignore, so delete this. A bar sits beside a view, never behind it.")
    @_alwaysEmitIntoClient
    nonisolated public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all) -> Self { self }
}

/// What `ignoresSafeArea(_:edges:)` is told to ignore, there only for that
/// modifier's compile error.
@available(*, unavailable, message: "TUI has no safe area.")
public enum SafeAreaRegions {
    case all, container, keyboard
}

// MARK: - A view as an argument

extension View {
    @available(*, unavailable, message: "Put the view in a closure: .overlay(alignment: .center) { ... }. SwiftUI has deprecated this form too.")
    @_alwaysEmitIntoClient
    nonisolated public func overlay<Overlay: View>(_ overlay: Overlay, alignment: Alignment = .center) -> Self { self }

    @available(*, unavailable, message: "Put the view in a closure: .background(alignment: .center) { ... }. SwiftUI has deprecated this form too.")
    @_alwaysEmitIntoClient
    nonisolated public func background<Background: View>(_ background: Background, alignment: Alignment = .center) -> Self { self }

    @available(*, unavailable, message: "Put the view in a closure: .mask { ... }. SwiftUI has deprecated this form too.")
    @_alwaysEmitIntoClient
    nonisolated public func mask<Mask: View>(_ mask: Mask) -> Self { self }
}

extension Section where Parent: View, Content: View, Footer: View {
    @available(*, unavailable, message: "Write the header in a closure: Section { ... } header: { ... }. SwiftUI has deprecated this form too.")
    public init(header: Parent, @ViewBuilder content: () -> Content) where Footer == EmptyView {
        self.init(content: content, header: { header }, footer: { EmptyView() })
    }

    @available(*, unavailable, message: "Write the footer in a closure: Section { ... } footer: { ... }. SwiftUI has deprecated this form too.")
    public init(footer: Footer, @ViewBuilder content: () -> Content) where Parent == EmptyView {
        self.init(content: content, header: { EmptyView() }, footer: { footer })
    }

    @available(*, unavailable, message: "Write these in closures: Section { ... } header: { ... } footer: { ... }. SwiftUI has deprecated this form too.")
    public init(header: Parent, footer: Footer, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { header }, footer: { footer })
    }
}

// MARK: - Older forms of what TUI has

extension View {
    @available(*, unavailable, message: "Say which value to watch: .animation(.default, value: x). SwiftUI has deprecated this form too.")
    @_alwaysEmitIntoClient
    nonisolated public func animation(_ animation: Animation?) -> Self { self }

    @available(*, unavailable, message: "The closure takes both values, or none: { oldValue, newValue in ... }. SwiftUI has deprecated this form too.")
    @_alwaysEmitIntoClient
    nonisolated public func onChange<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> Self { self }

    @available(*, unavailable, renamed: "autocorrectionDisabled(_:)", message: "SwiftUI has deprecated this name too.")
    @_alwaysEmitIntoClient
    nonisolated public func disableAutocorrection(_ disable: Bool?) -> Self { self }
}

extension ScrollView {
    @available(*, unavailable, message: "Use ScrollView { ... } and .scrollIndicators(.hidden). SwiftUI has deprecated this form too.")
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool, @ViewBuilder content: () -> Content) {
        self.init(axes, content: content)
    }
}

// MARK: - Text

extension View {
    @available(*, unavailable, message: "Every character takes up whole cells, so the space between them can't change.")
    @_alwaysEmitIntoClient
    nonisolated public func kerning<Value>(_ kerning: Value) -> Self { self }

    @available(*, unavailable, message: "Every character takes up whole cells, so the space between them can't change.")
    @_alwaysEmitIntoClient
    nonisolated public func tracking<Value>(_ tracking: Value) -> Self { self }

    @available(*, unavailable, message: "All text in a terminal is one size, so it can't shrink to fit. Use .lineLimit, .truncationMode or ViewThatFits.")
    @_alwaysEmitIntoClient
    nonisolated public func minimumScaleFactor<Value>(_ factor: Value) -> Self { self }

    @available(*, unavailable, message: "Every character takes up whole cells, so they can't be drawn closer. Use .lineLimit, .truncationMode or ViewThatFits.")
    @_alwaysEmitIntoClient
    nonisolated public func allowsTightening(_ flag: Bool) -> Self { self }
}

extension Text {
    @available(*, unavailable, message: "Join Text with interpolation instead, which keeps each part's style: Text(\"\\(first) \\(second)\").")
    @_alwaysEmitIntoClient
    public static func + (lhs: Text, rhs: Text) -> Text { lhs }
}

extension Font {
    @available(*, unavailable, message: "A terminal draws all text in one font and size. Use a text style such as .title, which changes how strong the text looks.")
    @_alwaysEmitIntoClient
    public static func system<Size>(size: Size, weight: Weight? = nil, design: Design? = nil) -> Font { .body }

    @available(*, unavailable, message: "A terminal draws all text in one font and size. Use a text style such as .title, which changes how strong the text looks.")
    @_alwaysEmitIntoClient
    public static func custom<Size>(_ name: String, size: Size) -> Font { .body }

    @available(*, unavailable, message: "A terminal draws all text in one font and size. Use a text style such as .title, which changes how strong the text looks.")
    @_alwaysEmitIntoClient
    public static func custom<Size>(_ name: String, size: Size, relativeTo textStyle: TextStyle) -> Font { .body }

    @available(*, unavailable, message: "A terminal draws all text in one font and size. Use a text style such as .title, which changes how strong the text looks.")
    @_alwaysEmitIntoClient
    public static func custom<Size>(_ name: String, fixedSize: Size) -> Font { .body }
}

extension Font.Design {
    @available(*, unavailable, message: "The terminal chooses the font, so a text style can't ask for this design.")
    @_alwaysEmitIntoClient
    public static var serif: Self { .default }

    @available(*, unavailable, message: "The terminal chooses the font, so a text style can't ask for this design.")
    @_alwaysEmitIntoClient
    public static var rounded: Self { .default }
}

// MARK: - Symbols

extension View {
    @available(*, unavailable, message: "A symbol is one character, at the terminal's font size, so it has no scale of its own. Delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func imageScale(_ scale: Image.Scale) -> Self { self }

    @available(*, unavailable, message: "A symbol is one character, in one colour. To colour it, use .foregroundStyle.")
    @_alwaysEmitIntoClient
    nonisolated public func symbolRenderingMode(_ mode: SymbolRenderingMode?) -> Self { self }
}

@MainActor extension Image {
    /// The sizes `imageScale(_:)` offers, there only for that modifier's compile error.
    @available(*, unavailable, message: "A symbol is one character, at the terminal's font size, so it has no scale of its own.")
    public enum Scale {
        case small, medium, large
    }
}

/// The modes `symbolRenderingMode(_:)` offers, there only for that modifier's
/// compile error.
@available(*, unavailable, message: "A symbol is one character, in one colour.")
public enum SymbolRenderingMode {
    case hierarchical, monochrome, multicolor, palette
}

// MARK: - Events from outside

extension View {
    @available(*, unavailable, message: "Nothing can send a URL to a program run in a terminal. Read one from the command line instead.")
    @_alwaysEmitIntoClient
    nonisolated public func onOpenURL(perform action: @escaping (URL) -> Void) -> Self { self }

    // The closure takes `Any` because naming `Publisher` here would load Combine
    // into every app that imports TUI. A closure that uses its value as what it
    // really is reports that too, after this error.
    @available(*, unavailable, message: "TUI doesn't use Combine. Use a .task, or an @Observable model.")
    @_alwaysEmitIntoClient
    nonisolated public func onReceive<Publisher>(_ publisher: Publisher, perform action: @escaping (Any) -> Void) -> Self { self }

    @available(*, unavailable, message: "A terminal has no haptics, so delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func sensoryFeedback<Trigger: Equatable>(_ feedback: SensoryFeedback, trigger: Trigger) -> Self { self }

    @available(*, unavailable, message: "A terminal has no haptics, so delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func sensoryFeedback<Trigger: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: Trigger,
        condition: @escaping (Trigger, Trigger) -> Bool
    ) -> Self { self }
}

/// The kinds `sensoryFeedback(_:trigger:)` offers, there only for that
/// modifier's compile error.
@available(*, unavailable, message: "A terminal has no haptics.")
public enum SensoryFeedback {
    case alignment, decrease, error, impact, increase, levelChange, pathComplete, selection, start, stop, success, warning
}

// MARK: - Accessibility

extension View {
    @available(*, unavailable, message: "A terminal has no accessibility tree. A screen reader reads the text on screen, so say it there, and delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityLabel<Label>(_ label: Label, isEnabled: Bool = true) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree. A screen reader reads the text on screen, so say it there, and delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityHint<Hint>(_ hint: Hint, isEnabled: Bool = true) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree. A screen reader reads the text on screen, so say it there, and delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityValue<Value>(_ value: Value, isEnabled: Bool = true) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree. A screen reader reads the text on screen, so say it there, and delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityInputLabels<Label>(_ inputLabels: [Label], isEnabled: Bool = true) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree. A screen reader reads the text on screen, so delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityHidden(_ hidden: Bool, isEnabled: Bool = true) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree, so delete this. To name a control for its focus, use .focusID.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityIdentifier(_ identifier: String, isEnabled: Bool = true) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree. A screen reader reads the text on screen, so delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilitySortPriority<Priority>(_ sortPriority: Priority) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree. A screen reader reads the text on screen, so delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree. A screen reader reads the text on screen, so delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree. A screen reader reads the text on screen, so delete this.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree. To act on a key, use .onKeyPress or .keyboardShortcut.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityAction(_ actionKind: AccessibilityActionKind = .default, _ handler: @escaping () -> Void) -> Self { self }

    @available(*, unavailable, message: "A terminal has no accessibility tree. To act on a key, use .onKeyPress or .keyboardShortcut.")
    @_alwaysEmitIntoClient
    nonisolated public func accessibilityAction<Name>(named name: Name, _ handler: @escaping () -> Void) -> Self { self }
}

/// The traits `accessibilityAddTraits(_:)` offers, there only for that modifier's
/// compile error.
@available(*, unavailable, message: "A terminal has no accessibility tree.")
public enum AccessibilityTraits: ExpressibleByArrayLiteral {
    case isButton, isHeader, isImage, isKeyboardKey, isLink, isModal, isSearchField, isSelected, isStaticText
    case isSummaryElement, isTabBar, isToggle

    // So that `[.isButton, .isLink]` lands on the same modifier. A second overload
    // would cost a call the search these stubs exist to avoid.
    public init(arrayLiteral elements: Self...) { self = .isButton }
}

/// The behaviours `accessibilityElement(children:)` offers, there only for that
/// modifier's compile error.
@available(*, unavailable, message: "A terminal has no accessibility tree.")
public enum AccessibilityChildBehavior {
    case combine, contain, ignore
}

/// The kinds `accessibilityAction(_:_:)` offers, there only for that modifier's
/// compile error.
@available(*, unavailable, message: "A terminal has no accessibility tree.")
public enum AccessibilityActionKind {
    case `default`, delete, escape, magicTap, showMenu
}

// MARK: - ObservableObject's property wrappers

/// SwiftUI's owner of an `ObservableObject`, there only for its compile error.
///
/// `ObservableObject` itself isn't stubbed. On macOS it comes from Foundation, so
/// that `class Model: ObservableObject` still compiles, and there it stays:
/// <doc:ComingFromSwiftUI> warns about it.
@available(*, unavailable, message: "TUI watches only @Observable models. Mark the class @Observable, and use @State here.")
@propertyWrapper
public struct StateObject<ObjectType> {
    private let thunk: () -> ObjectType
    public init(wrappedValue thunk: @autoclosure @escaping () -> ObjectType) { self.thunk = thunk }
    public var wrappedValue: ObjectType { thunk() }
    public var projectedValue: Binding<ObjectType> { .constant(thunk()) }
}

/// SwiftUI's watcher of an `ObservableObject`, there only for its compile error.
@available(*, unavailable, message: "TUI watches only @Observable models. Mark the class @Observable, and use a plain property here, or @Bindable to bind to it.")
@propertyWrapper
public struct ObservedObject<ObjectType> {
    public var wrappedValue: ObjectType
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    public var projectedValue: Binding<ObjectType> { .constant(wrappedValue) }
}

/// SwiftUI's reader of an environment object, there only for its compile error.
@available(*, unavailable, message: "TUI watches only @Observable models. Mark the class @Observable, and read it with @Environment(Model.self).")
@propertyWrapper
public struct EnvironmentObject<ObjectType> {
    public init() {}
    public var wrappedValue: ObjectType { fatalError("EnvironmentObject is unavailable") }
    public var projectedValue: Binding<ObjectType> { fatalError("EnvironmentObject is unavailable") }
}

extension View {
    @available(*, unavailable, message: "TUI watches only @Observable models. Mark the class @Observable, and pass it with .environment(model).")
    @_alwaysEmitIntoClient
    nonisolated public func environmentObject<Object>(_ object: Object) -> Self { self }
}

// swiftlint:enable missing_docs line_length
