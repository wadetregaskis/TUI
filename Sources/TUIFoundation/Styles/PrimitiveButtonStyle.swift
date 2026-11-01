//  🖥️ TUI — A Terminal UI framework for Swift
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

/// A built-in primitive style: one TUI draws procedurally, through the
/// ``ButtonStyle`` appearance it stands for, rather than through a body. That
/// is what keeps `.buttonStyle(.bordered)` as cheap as it has always been — no
/// extra view between the button and its drawing.
protocol BuiltInButtonStyle: PrimitiveButtonStyle {
    /// The appearance this style draws a button with.
    var appearance: any ButtonStyle { get }
}

extension BuiltInButtonStyle {
    /// What a style composing this one gets: a button, drawn with this style.
    /// Each built-in style's own `makeBody(configuration:)` returns it — on
    /// the type rather than here, because a public method on an internal
    /// protocol's extension is not part of the public types' interface.
    @MainActor
    func builtInBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        Button(configuration)
            .environment(\.installedButtonAppearance, appearance)
    }
}

// MARK: - Environment

private struct PrimitiveButtonStyleChainKey: EnvironmentKey {
    static var defaultValue: StyleChain<any PrimitiveButtonStyle>? { nil }
}

extension EnvironmentValues {
    /// The custom primitive button style in force, and the ones outside it —
    /// what ``Button/init(_:)-(PrimitiveButtonStyleConfiguration)`` inside its
    /// body draws with — or `nil` when buttons draw with the ``buttonStyle``
    /// appearance. See ``StyleChain``; `nil` rather than a default style at
    /// the root, because a built-in style clears it.
    var primitiveButtonStyleChain: StyleChain<any PrimitiveButtonStyle>? {
        get { self[PrimitiveButtonStyleChainKey.self] }
        set { self[PrimitiveButtonStyleChainKey.self] = newValue }
    }

    /// ``buttonStyle``, written so that it also ends any custom primitive
    /// style further out: the nearest `.buttonStyle(_:)` wins whichever kind
    /// of style it names. One environment write where two modifiers stood —
    /// and each modifier is a layer that copies the environment and notes its
    /// value on both walks. The cleared chain is a constant for the subtree
    /// (always `nil` below), so it has nothing to note; the appearance is
    /// noted as ``buttonStyle`` always was.
    var installedButtonAppearance: any ButtonStyle {
        get { buttonStyle }
        set {
            buttonStyle = newValue
            if primitiveButtonStyleChain != nil { primitiveButtonStyleChain = nil }
        }
    }

    /// What a `.buttonStyle(_:)` naming a ``PrimitiveButtonStyle`` installs,
    /// as one value, so the modifier is one transform rather than one per key:
    /// a built-in style's appearance, or a custom style pushed on the chain.
    var installedPrimitiveButtonStyle: InstalledPrimitiveButtonStyle {
        get { primitiveButtonStyleChain.map(InstalledPrimitiveButtonStyle.custom) ?? .appearance(buttonStyle) }
        set {
            switch newValue {
            case .appearance(let appearance): installedButtonAppearance = appearance
            case .custom(let chain): primitiveButtonStyleChain = chain
            }
        }
    }
}

/// See ``EnvironmentValues/installedPrimitiveButtonStyle``.
///
/// Compared as its two halves were when each had a modifier of its own: an
/// appearance as an `Equatable` style (every built-in one is), a chain as
/// ``StyleChain`` compares — and, like the chain, saying when it holds a style
/// it cannot compare (`PartiallyComparable`).
enum InstalledPrimitiveButtonStyle: Equatable, PartiallyComparable {
    /// A built-in style's appearance, with no custom style in force.
    case appearance(any ButtonStyle)
    /// A custom style, over the custom styles further out.
    case custom(StyleChain<any PrimitiveButtonStyle>)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.appearance(let left), .appearance(let right)):
            (left as? any Equatable)?.isEqual(to: right) == true
        case (.custom(let left), .custom(let right)):
            left == right
        default:
            false
        }
    }

    var isComparable: Bool {
        switch self {
        case .appearance(let appearance): appearance is any Equatable
        case .custom(let chain): chain.isComparable
        }
    }
}

extension PrimitiveButtonStyle {
    /// This style's body for `configuration`, drawn. Opens the existential so
    /// ``makeBody(configuration:)`` returns its concrete type.
    @MainActor
    func makeBuffer(configuration: Configuration, context: RenderContext) -> FrameBuffer {
        renderToBuffer(
            observingStyleBody(of: Self.self, kind: .styleRender, context: context) {
                makeBody(configuration: configuration)
            }, context: context)
    }

    /// This style's body for `configuration`, measured.
    @MainActor
    func makeSize(
        configuration: Configuration, proposal: ProposedSize, context: RenderContext
    ) -> ViewSize {
        measureChild(
            observingStyleBody(of: Self.self, kind: .styleMeasure, context: context) {
                makeBody(configuration: configuration)
            }, proposal: proposal, context: context)
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
        // A built-in installs itself as the appearance and clears any custom
        // primitive style further out; a custom one goes on top of whatever is
        // in force, which its `Button(configuration)` then draws with.
        return transformEnvironment(\.installedPrimitiveButtonStyle) { installed in
            if let appearance {
                installed = .appearance(appearance)
            } else if case .custom(let outer) = installed {
                installed = .custom(StyleChain(style, outer: outer))
            } else {
                installed = .custom(StyleChain(style))
            }
        }
    }
}
