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
        TUIkitView.renderToBuffer(content, context: context)
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

    /// Its content is laid out in its own context (``SingleContentWrapper/wrappedContentContext(_:)``).
    func wrappedContentContext(_ context: RenderContext) -> RenderContext? { context }
}

/// Draws its content unchanged, at its own identity, so a removal transition
/// written inside it plays.
extension _TypeSelectEquivalentModifier: DrawsContentUnchanged {}

/// The stated type-select text of `row`, looking through the single-content
/// wrappers around it: `.some(nil)` for a row stating none — derive it — and
/// `nil` for one with no modifier at all.
@MainActor
package func statedTypeSelectEquivalent(of row: any View) -> String?? {
    guard let carrier = throughWrappers(row, as: (any _TypeSelectEquivalentCarrying).self) else { return nil }
    return .some(carrier.typeSelectEquivalent)
}

/// What a row a child walk holds states for type select, seeing past
/// `ForEach`'s value memo — `extractRowBadge(from:)`'s shape, for the same
/// wrapper — without building the row.
///
/// A looped row of an `Equatable` element reaches a walk that splices it among
/// hand-written rows (or a `Section`'s walk) wrapped in `_MemoizedRow`, which
/// is `Renderable` and so opaque to the wrapper walk: the equivalent it stated
/// was simply not there, and the row answered to its drawn text instead.
///
/// The memo's TYPE is asked, walked through the same single-content wrappers
/// the instance walk looks through, so `.typeSelectEquivalent(_:).padding()`
/// is found as the hand-written row's is. Its content is NOT built here:
/// ``_ValueMemoWrapping/memoizedContent`` BUILDS the row, the memo exists so
/// that most rows are not, and this is asked of every such row on every frame
/// — so the memo is handed back, for the probe to build when the user types.
private enum TypeSelectStatement {
    /// The row states nothing: it is matched by its own text.
    case none
    /// The row states this text (`""` takes it out of type select), or `nil`
    /// to be matched by its own text.
    case stated(String?)
    /// A looped row whose type states an equivalent, behind the memo.
    case behindMemo(any _ValueMemoWrapping)

    @MainActor
    init(of row: any View) {
        if let stated = statedTypeSelectEquivalent(of: row) {
            self = .stated(stated)
        } else if let memo = row as? any _ValueMemoWrapping,
            viewTypeStatesTypeSelectEquivalent(memo.memoizedContentType)
        {
            self = .behindMemo(memo)
        } else {
            self = .none
        }
    }
}

/// Whether a view of `type` states a type-select equivalent, at its outside or
/// inside any number of single-content wrappers — the static twin of the
/// instance walk in ``statedTypeSelectEquivalent(of:)``, answered from the
/// type alone.
@MainActor
func viewTypeStatesTypeSelectEquivalent(_ type: any View.Type) -> Bool {
    var current = type
    while true {
        if current is any _TypeSelectEquivalentCarrying.Type { return true }
        guard let wrapper = current as? any SingleContentWrapper.Type else { return false }
        current = wrapper.wrappedContentType
    }
}

extension SingleContentWrapper {
    /// The wrapped content's type, as an existential metatype the static walk
    /// above can step through.
    fileprivate static var wrappedContentType: any View.Type { WrappedContent.self }
}

/// The type-select text `row` states, as a row's probe, else what `ownText`
/// finds — for a row a list draws only when it must, so its own text is a
/// measure's. A looped row behind `ForEach`'s value memo is seen through it,
/// and built only when the probe is asked: when the user types, not on every
/// frame (see `TypeSelectStatement`).
@MainActor
package func typeSelectProbe(
    statedBy row: any View, otherwise ownText: @escaping () -> String?
) -> () -> String? {
    switch TypeSelectStatement(of: row) {
    case .none, .stated(nil):
        return ownText
    case .stated(let text?):
        return { text }
    case .behindMemo(let memo):
        return { statedText(of: memo) ?? ownText() }
    }
}

/// The text the row behind `memo` states, built to ask — `nil` where it states
/// none, so its own text is used.
@MainActor
private func statedText(of memo: any _ValueMemoWrapping) -> String? {
    guard let stated = statedTypeSelectEquivalent(of: memo.memoizedContent) else { return nil }
    return stated
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
