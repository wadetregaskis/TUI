//  🖥️ TUI — A Terminal UI framework for Swift
//  StyleModifier.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUICore
import TUIView

// MARK: - Style cascade modifier

/// Appends a scoped style entry to the environment's ``StyleCascade`` for its
/// content's subtree. The read-modify-write of the cascade happens at render
/// time, so this mirrors ``EnvironmentModifier`` (View + Renderable + Layoutable)
/// rather than using the plain `.environment(_:_:)` setter.
public struct StyleCascadeModifier<Content: View>: View {
    public let content: Content
    public let scope: StyleScope
    public let attributes: StyleAttributes

    public init(content: Content, scope: StyleScope, attributes: StyleAttributes) {
        self.content = content
        self.scope = scope
        self.attributes = attributes
    }

    /// Not used during rendering — ``Renderable`` conformance takes priority.
    public var body: some View { content }

    private func modifiedContext(_ context: RenderContext) -> RenderContext {
        // Noted, as `EnvironmentModifier` notes the value it writes: a memo
        // below — a `List`'s looped rows, an `.equatable()` view — keys on its
        // own value and size, not on the cascade, so `.bold(flag)` turned on
        // between two frames was served the plain picture, and the rows of a
        // `List { ForEach(…) }.bold(flag)` kept the weight they were first
        // drawn with. The ENTRY is noted, not the cascade it makes: the
        // entries above it are their own writers' to note, as `TintModifier`
        // notes its tint and not the palette it derives. Not ink alone — a
        // cascaded `textCase` turns "ß" into "SS" — so the sizes go too, as
        // `ThemeModifier`'s do for its styles.
        if let cache = context.renderCache,
            case .changed = cache.noteAppliedEnvironment(
                StyleCascade.Entry(scope: scope, attributes: attributes), identity: context.identity,
                keyPath: \EnvironmentValues.styleCascade, depth: context.environmentApplicationDepth)
        {
            cache.clearAffected(by: context.identity)
        }
        let cascade = context.environment.styleCascade.appending(scope, attributes)
        var modified = context.withEnvironment(context.environment.setting(\.styleCascade, to: cascade))
        modified.environmentApplicationDepth += 1
        return modified
    }
}

extension StyleCascadeModifier: Renderable {
    public func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIView.renderToBuffer(content, context: modifiedContext(context))
    }
}

extension StyleCascadeModifier: Layoutable {
    public func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: modifiedContext(context))
    }
}

// MARK: - Generic scoped-style modifiers

extension View {
    /// Applies `attributes` to every descendant matching `scope`. The general
    /// form of the styling cascade; the typed conveniences below build on it.
    public func style(_ scope: StyleScope, _ attributes: StyleAttributes) -> some View {
        StyleCascadeModifier(content: self, scope: scope, attributes: attributes)
    }

    /// Applies attributes built in the closure to every descendant matching `scope`.
    public func style(_ scope: StyleScope, _ build: (inout StyleAttributes) -> Void) -> some View {
        var attributes = StyleAttributes()
        build(&attributes)
        return style(scope, attributes)
    }
}

// MARK: - Broad text-attribute modifiers (SwiftUI parity)

extension View {
    /// Applies a bold style to all text in this view's subtree.
    ///
    /// Cascades through the environment; a descendant can opt out with
    /// `.bold(false)`. (`Text`'s own `.bold()` continues to return `Text`.)
    public func bold(_ enabled: Bool = true) -> some View {
        style(.text, StyleAttributes(bold: enabled))
    }

    /// Applies an italic style to all text in this view's subtree.
    public func italic(_ enabled: Bool = true) -> some View {
        style(.text, StyleAttributes(italic: enabled))
    }

    /// Underlines all text in this view's subtree — mirrors SwiftUI's
    /// `underline(_:pattern:color:)`.
    ///
    /// The line is drawn as the terminal can: see ``Text/LineStyle``.
    ///
    /// - Parameters:
    ///   - isActive: Whether the text is underlined. `false` overrides an
    ///     ancestor's underline.
    ///   - pattern: The line's pattern.
    ///   - color: The line's colour, or `nil` for the text's own.
    public func underline(
        _ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil
    ) -> some View {
        style(
            .text,
            StyleAttributes(underline: isActive, underlineStyle: Text.LineStyle(pattern: pattern, color: color)))
    }

    /// Strikes through all text in this view's subtree — mirrors SwiftUI's
    /// `strikethrough(_:pattern:color:)`.
    ///
    /// A terminal's strikethrough is one solid line, whatever the pattern,
    /// and only iTerm2 colours it: see ``Text/LineStyle``.
    ///
    /// - Parameters:
    ///   - isActive: Whether the text is struck through. `false` overrides an
    ///     ancestor's strikethrough.
    ///   - pattern: The line's pattern.
    ///   - color: The line's colour, or `nil` for the text's own.
    public func strikethrough(
        _ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil
    ) -> some View {
        style(
            .text,
            StyleAttributes(
                strikethrough: isActive, strikethroughStyle: Text.LineStyle(pattern: pattern, color: color)))
    }

    /// Sets the font weight for all text in this view's subtree. On a terminal,
    /// weight maps to bold / normal / faint (see ``FontWeight``).
    ///
    /// `nil` removes the effect of any weight set further out, as SwiftUI
    /// documents: "Providing `nil` removes the effect of any font weight
    /// modifier applied higher in the view hierarchy." It resolves to
    /// ``FontWeight/regular``, which states not-bold and not-faint rather than
    /// saying nothing — and saying nothing is what it used to do, leaving an
    /// inherited `.bold()` in place with no way to escape it. A `Text`'s own
    /// weight still wins, being closer.
    public func fontWeight(_ weight: FontWeight?) -> some View {
        style(.text, (weight ?? .regular).styleAttributes)
    }

    /// Applies a case transform to all text in this view's subtree.
    ///
    /// `nil` clears one set further out rather than declining to speak, which
    /// is what SwiftUI's `Text.Case?` environment value means. See
    /// ``StyleAttributes/textCase``.
    public func textCase(_ textCase: TextCase?) -> some View {
        style(.text, StyleAttributes(textCase: .some(textCase)))
    }

    /// Applies a text scale to all text in this view's subtree — mirrors
    /// SwiftUI's `textScale(_:isEnabled:)`.
    ///
    /// `.secondary` draws one intensity tier down: bold becomes plain, plain
    /// becomes faint (see ``Text/Scale``). A descendant's own scale wins.
    ///
    /// - Parameters:
    ///   - scale: The text scale to apply.
    ///   - isEnabled: Whether to apply it; `false` leaves the subtree as it was.
    /// - Returns: A view whose text takes the scale.
    public func textScale(_ scale: Text.Scale, isEnabled: Bool = true) -> some View {
        style(.text, isEnabled ? StyleAttributes(textScale: scale) : StyleAttributes())
    }
}

// MARK: - Seeing Through the Wrapper

/// - Note: An environment value reaches a subtree whether it was set one level
///   up or two, so publishing it around each member is the same thing as
///   publishing it once around the pair. What changes is only that the members
///   stay the enclosing container's own children.
extension StyleCascadeModifier: ContentRewrapping {
    public var wrappedContent: Content { content }

    /// Its content's context: the style it publishes (``SingleContentWrapper/wrappedContentContext(_:)``).
    public func wrappedContentContext(_ context: RenderContext) -> RenderContext? { modifiedContext(context) }

    public func rewrapping<V: View>(_ view: V) -> any View {
        StyleCascadeModifier<V>(content: view, scope: scope, attributes: attributes)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension StyleCascadeModifier: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty: ``GridRowProviding`` has the whole implementation
/// for a ``SingleContentWrapper``.
extension StyleCascadeModifier: GridRowProviding where Content: GridRowProviding {}

// MARK: - Removal Transitions

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays — see `DrawsContentUnchanged`.
extension StyleCascadeModifier: DrawsContentUnchanged {}
