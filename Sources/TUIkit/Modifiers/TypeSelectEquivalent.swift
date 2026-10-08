//  🖥️ TUIkit — Terminal UI Kit for Swift
//  TypeSelectEquivalent.swift
//
//  The text a list or table row answers to when the user types to find it.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

/// A row's stated type-select text, peeked by the list or table that searches
/// its rows (see ``View/typeSelectEquivalent(_:)-(Text?)``).
@MainActor
protocol _TypeSelectEquivalentCarrying {
    /// The stated text: `nil` to use the row's own text, `""` to take the row
    /// out of type select.
    var typeSelectEquivalent: String? { get }
}

/// A view with an explicit type-select text. Draws its content unchanged.
struct _TypeSelectEquivalentModifier<Content: View>: View, Renderable, Layoutable {
    let content: Content
    let equivalent: String?

    var body: Never { fatalError("_TypeSelectEquivalentModifier renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        TUIkit.renderToBuffer(content, context: context)
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(content, proposal: proposal, context: context)
    }
}

extension _TypeSelectEquivalentModifier: _TypeSelectEquivalentCarrying {
    var typeSelectEquivalent: String? { equivalent }
}

/// Names its content, so the peek — and a container asking for a z-index or a
/// tag — can look through it.
extension _TypeSelectEquivalentModifier: SingleContentWrapper {
    var wrappedContent: Content { content }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays.
extension _TypeSelectEquivalentModifier: DrawsContentUnchanged {}

/// The stated type-select text of `row`, looking through the single-content
/// wrappers around it: `.some(nil)` for a row stating none — derive it — and
/// `nil` for one with no modifier at all.
@MainActor
func statedTypeSelectEquivalent(of row: any View) -> String?? {
    guard let carrier = throughWrappers(row, as: (any _TypeSelectEquivalentCarrying).self) else { return nil }
    return .some(carrier.typeSelectEquivalent)
}

/// The type-select text `row` states, as a row's probe, for a row handed to
/// the list already drawn — `nil` where it states none, so its drawn text is
/// used.
@MainActor
func typeSelectProbe(statedBy row: any View) -> (() -> String?)? {
    guard let stated = statedTypeSelectEquivalent(of: row), let stated else { return nil }
    return { stated }
}

extension View {
    /// Sets an explicit type select equivalent text in a collection, such as
    /// a list or table.
    ///
    /// With a list or table focused, typing a few characters moves its cursor
    /// to the first row, after the cursor, whose text starts with them —
    /// ignoring case, within a second of the last key. A row's text is its own
    /// first line of text unless it states one with this modifier; an empty
    /// string takes the row out of type select, and `nil` uses the row's own.
    ///
    /// ```swift
    /// List(people, selection: $selectedPersonID) { person in
    ///     person.avatar
    ///         .typeSelectEquivalent(person.name)
    /// }
    /// ```
    ///
    /// - Parameter text: The text a typed prefix matches, or `nil` for the
    ///   row's own.
    public func typeSelectEquivalent(_ text: Text?) -> some View {
        _TypeSelectEquivalentModifier(content: self, equivalent: text?.content)
    }

    /// Sets an explicit type select equivalent text from a localized key.
    ///
    /// - Parameter stringKey: The key for the text — a literal is looked up,
    ///   see ``LocalizedStringKey``.
    public func typeSelectEquivalent(_ stringKey: LocalizedStringKey) -> some View {
        _TypeSelectEquivalentModifier(content: self, equivalent: stringKey.localized)
    }

    /// Sets an explicit type select equivalent text, used as written.
    ///
    /// - Parameter string: The text a typed prefix matches.
    @_disfavoredOverload
    public func typeSelectEquivalent<S: StringProtocol>(_ string: S) -> some View {
        _TypeSelectEquivalentModifier(content: self, equivalent: String(string))
    }
}
