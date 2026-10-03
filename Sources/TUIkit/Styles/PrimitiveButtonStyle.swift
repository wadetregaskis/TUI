//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PrimitiveButtonStyle.swift
//
//  SwiftUI's PrimitiveButtonStyle: a button style that decides not only how a
//  button looks but how it is operated — it is handed a `trigger()` instead of
//  a pressed state, and the button is whatever its body is. SwiftUI's own
//  built-in styles (`.automatic`, `.bordered`, `.borderedProminent`,
//  `.borderless`, `.plain`, `.link`, the accessory-bar pair) are primitive
//  styles, so this is where their names live.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - Configuration

/// The properties of a button, as a ``PrimitiveButtonStyle`` sees them.
public struct PrimitiveButtonStyleConfiguration {
    /// A type-erased label of a button.
    public typealias Label = ButtonStyleConfiguration.Label

    /// An optional semantic role describing the button.
    public let role: ButtonRole?

    /// A view that describes the effect of calling the button's action.
    public let label: Label

    /// The button's action, as it runs when activated — including closing the
    /// menu the button sits in, where it sits in one.
    let action: () -> Void

    /// Performs the button's action.
    public func trigger() {
        action()
    }
}

// MARK: - The protocol

/// A type that applies custom interaction behavior and a custom appearance to
/// all buttons within a view hierarchy.
///
/// Where a ``ButtonStyle`` decides only how a button looks, a primitive style
/// decides how it is operated too: its body IS the button, and calls the
/// configuration's ``PrimitiveButtonStyleConfiguration/trigger()`` when it
/// should act. A style that wants the current button with something added uses
/// ``Button/init(_:)-(PrimitiveButtonStyleConfiguration)``, which builds the
/// button the style was applied over:
///
/// ```swift
/// struct RedBorderedButtonStyle: PrimitiveButtonStyle {
///     func makeBody(configuration: Configuration) -> some View {
///         Button(configuration)
///             .border(.red)
///     }
/// }
/// ```
///
/// A primitive style that builds no `Button` makes a control the keyboard
/// cannot reach unless its body offers a way — as in SwiftUI, where the style's
/// body is the whole of the control. `Button(configuration)` keeps the focus,
/// the keys and the click a button has.
public protocol PrimitiveButtonStyle: Sendable {
    /// A view that represents the body of a button.
    associatedtype Body: View

    /// Creates a view that represents the body of a button.
    ///
    /// - Parameter configuration: The properties of the button.
    @MainActor @ViewBuilder
    func makeBody(configuration: Configuration) -> Body

    /// The properties of a button.
    typealias Configuration = PrimitiveButtonStyleConfiguration
}

/// A built-in primitive style: one TUIkit draws procedurally, through the
/// ``ButtonStyle`` appearance it stands for, rather than through a body. That
/// is what keeps `.buttonStyle(.bordered)` as cheap as it has always been — no
/// extra view between the button and its drawing.
protocol BuiltInButtonStyle: PrimitiveButtonStyle {
    /// The appearance this style draws a button with.
    var appearance: any ButtonStyle { get }
}

extension BuiltInButtonStyle {
    /// What a style composing this one gets: a button, drawn with this style.
    @MainActor
    public func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        Button(configuration)
            .environment(\.buttonStyle, appearance)
            .environment(\.primitiveButtonStyleEntry, nil)
    }
}

// MARK: - Environment

/// A custom primitive style in force, and the one in force where it was
/// applied — which is what ``Button/init(_:)-(PrimitiveButtonStyleConfiguration)``
/// draws with inside the style's own body, so a style that wraps the current
/// button gets the button it was applied over rather than itself again.
struct PrimitiveButtonStyleEntry: Equatable, Sendable {
    let style: any PrimitiveButtonStyle
    let outer: Box?

    /// The outer entry, boxed because a struct cannot hold itself.
    final class Box: Equatable, Sendable {
        let entry: PrimitiveButtonStyleEntry

        init(_ entry: PrimitiveButtonStyleEntry) {
            self.entry = entry
        }

        static func == (lhs: Box, rhs: Box) -> Bool {
            lhs === rhs || lhs.entry == rhs.entry
        }
    }

    init(style: any PrimitiveButtonStyle, outer: Self?) {
        self.style = style
        self.outer = outer.map(Box.init)
    }

    /// Equal when both styles are `Equatable`, of one type, and equal, and so
    /// are the entries outside them. A style that is not `Equatable` compares
    /// unequal, so the render cache treats its subtree as changed every frame
    /// rather than serving it stale — the same price an uncomparable
    /// ``ButtonStyle`` pays.
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard let left = lhs.style as? any Equatable, left.isEqual(to: rhs.style) else { return false }
        return lhs.outer == rhs.outer
    }
}

private struct PrimitiveButtonStyleEntryKey: EnvironmentKey {
    static let defaultValue: PrimitiveButtonStyleEntry? = nil
}

extension EnvironmentValues {
    /// The custom primitive button style in force, or `nil` when buttons draw
    /// with the ``buttonStyle`` appearance.
    var primitiveButtonStyleEntry: PrimitiveButtonStyleEntry? {
        get { self[PrimitiveButtonStyleEntryKey.self] }
        set { self[PrimitiveButtonStyleEntryKey.self] = newValue }
    }
}

extension PrimitiveButtonStyle {
    /// This style's body for `configuration`, drawn. Opens the existential so
    /// ``makeBody(configuration:)`` returns its concrete type.
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(makeBody(configuration: configuration), context: context)
    }

    /// This style's body for `configuration`, measured.
    @MainActor
    func makeSize(
        configuration: Configuration, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        measureChild(makeBody(configuration: configuration), proposal: proposal, context: context)
    }
}

// MARK: - Applying one

extension View {
    /// Sets the style for buttons within this view to a button style with a
    /// custom appearance and custom interaction behavior.
    ///
    /// ```swift
    /// Button("Sign In") { signIn() }
    ///     .buttonStyle(.borderedProminent)
    /// ```
    ///
    /// The nearest `.buttonStyle(_:)` wins, whichever kind of style it names.
    ///
    /// - Parameter style: The style to apply.
    /// - Returns: A view whose buttons use the style.
    public func buttonStyle<S: PrimitiveButtonStyle>(_ style: S) -> some View {
        let appearance = (style as? any BuiltInButtonStyle)?.appearance
        return
            self
            .transformEnvironment(\.primitiveButtonStyleEntry) { entry in
                entry = appearance == nil ? PrimitiveButtonStyleEntry(style: style, outer: entry) : nil
            }
            .transformEnvironment(\.buttonStyle) { current in
                if let appearance { current = appearance }
            }
        // A built-in installs itself as the appearance and clears any custom
        // primitive style further out; a custom one goes on top of whatever is
        // in force, which its `Button(configuration)` then draws with.
    }
}
