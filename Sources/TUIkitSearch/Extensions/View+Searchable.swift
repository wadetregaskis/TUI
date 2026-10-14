//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+Searchable.swift
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation
import TUIkitTextInput

extension View {
    /// Marks this view as searchable, presenting a search field bound to `text`.
    ///
    /// Mirrors SwiftUI's `searchable(text:placement:prompt:)`. As in SwiftUI, the
    /// framework only surfaces the field and writes the binding — **filtering is
    /// the app's job**: observe `text` and filter your own content.
    ///
    /// ```swift
    /// List(results) { Text($0.name) }
    ///     .searchable(text: $query)   // you filter `results` by `query`
    /// ```
    ///
    /// - Note: `placement` is a preference, as SwiftUI documents it, and the
    ///   field renders at the top of the searchable subtree whatever it says —
    ///   unless a `DefaultToolbarItem(kind: .search)` places the field in one of
    ///   the window's bars, or `toolbar(removing: .search)` takes it away.
    ///
    /// - Parameters:
    ///   - text: The text to display and edit in the search field.
    ///   - placement: The preferred placement (inert in a terminal — see the note).
    ///   - prompt: A `Text` to display when the search field is empty.
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text? = nil
    ) -> some View {
        _ = placement
        return SearchableModifier(content: self, text: text, prompt: prompt)
    }

    /// Marks this view as searchable, with a localized prompt.
    ///
    /// A string **literal** binds here, so the prompt is a lookup key — see
    /// ``LocalizedStringKey``.
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey
    ) -> some View {
        searchable(text: text, placement: placement, prompt: Text(prompt))
    }

    /// Marks this view as searchable, with a prompt displayed as written.
    @_disfavoredOverload
    public func searchable(
        text: Binding<String>,
        placement: SearchFieldPlacement = .automatic,
        prompt: some StringProtocol
    ) -> some View {
        searchable(text: text, placement: placement, prompt: Text(String(prompt)))
    }

    /// Marks this view as searchable, with programmatic presentation of the
    /// search field. Mirrors SwiftUI's
    /// `searchable(text:isPresented:placement:prompt:)`.
    ///
    /// `isPresented` is `true` while the search field holds the focus, as
    /// ``EnvironmentValues/isSearching`` is. Setting it to `true` moves the
    /// focus to the field; setting it to `false` ends the search, as
    /// ``DismissSearchAction`` does — the query is emptied and the focus moves
    /// on to the content.
    ///
    /// - Parameters:
    ///   - text: The text to display and edit in the search field.
    ///   - isPresented: Whether search is presented.
    ///   - placement: The preferred placement (the field is drawn at the top
    ///     of the searchable subtree, whatever is preferred).
    ///   - prompt: A `Text` to display when the search field is empty.
    public func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: Text? = nil
    ) -> some View {
        _ = placement
        return SearchableModifier(content: self, text: text, prompt: prompt, isPresented: isPresented)
    }

    /// Marks this view as searchable, with programmatic presentation and a
    /// localized prompt.
    ///
    /// A string **literal** binds here, so the prompt is a lookup key — see
    /// ``LocalizedStringKey``.
    public func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey
    ) -> some View {
        searchable(text: text, isPresented: isPresented, placement: placement, prompt: Text(prompt))
    }

    /// Marks this view as searchable, with programmatic presentation and a
    /// prompt displayed as written.
    @_disfavoredOverload
    public func searchable(
        text: Binding<String>,
        isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic,
        prompt: some StringProtocol
    ) -> some View {
        searchable(
            text: text, isPresented: isPresented, placement: placement, prompt: Text(String(prompt)))
    }
}

// MARK: - Suggestions

extension View {
    /// Offers a menu of suggestions under the search field of an enclosing
    /// ``View/searchable(text:placement:prompt:)-(_,_,LocalizedStringKey)``.
    ///
    /// Mirrors SwiftUI's `searchSuggestions(_:)`, and is written where SwiftUI
    /// writes it — outside the `searchable`, which is what scopes it to the
    /// search field rather than to every text field in the content:
    ///
    /// ```swift
    /// List(matches) { Text($0.name) }
    ///     .searchable(text: $query)
    ///     .searchSuggestions {
    ///         ForEach(recentQueries, id: \.self) { Text($0) }
    ///         Divider()
    ///         Text("everything").searchCompletion("*")
    ///     }
    /// ```
    ///
    /// Each view the builder makes is a suggestion, wherever it is written —
    /// in a view of your own, a `Group`, an `if`, a `ForEach` — and fills the
    /// field with its text, or with what ``View/searchCompletion(_:)-(String)``
    /// gives it; a ``Divider`` is a rule between groups, and so is the edge of
    /// a `Section` — the same reading ``View/textInputSuggestions(_:)`` gives
    /// its builder, because it is the same menu underneath. The builder is re-evaluated every render, so filtering the
    /// suggestions against the current query is a matter of filtering the data
    /// you build them from.
    ///
    /// The menu opens on demand rather than on focus — Down at the caret, or a
    /// click on the `▾` at the field's trailing edge — and Return on a
    /// highlighted row fills the field and submits, so
    /// `.onSubmit(of: .search)` fires. See ``View/textInputSuggestions(_:)``
    /// for the interaction in full.
    ///
    /// - Parameter suggestions: A view builder of suggestion entries.
    /// - Returns: A view whose enclosed search field offers the suggestions.
    public func searchSuggestions<S: View>(
        @ViewBuilder _ suggestions: () -> S
    ) -> some View {
        _TextSuggestionsReader(content: self, suggestions: suggestions(), keyPath: \.searchSuggestions)
    }

    /// Associates a completed query with this view when it is used as a search
    /// suggestion — SwiftUI's `searchCompletion(_:)`.
    ///
    /// Without it, choosing a suggestion puts its label's plain text in the
    /// field; use this where the label decorates or abbreviates what should
    /// actually be searched for.
    ///
    /// ```swift
    /// Label("Everything", systemImage: "asterisk").searchCompletion("*")
    /// ```
    ///
    /// It is ``View/textInputCompletion(_:)`` under a second name, which is
    /// SwiftUI's own arrangement: two menus, one for a search field and one for
    /// any text field, each with a spelling that reads right at its call site,
    /// and one mechanism beneath both.
    ///
    /// - Parameter completion: The text the field is filled with when this
    ///   suggestion is chosen.
    /// - Returns: A view carrying the completion for the suggestions menu.
    public func searchCompletion(_ completion: String) -> some View {
        textInputCompletion(completion)
    }

    /// Associates a search token with this view when it is used as a search
    /// suggestion — SwiftUI's `searchCompletion(_:)` for a token.
    ///
    /// Choosing the suggestion empties the field and adds the token to the
    /// enclosing searchable's tokens, as SwiftUI replaces the partial text
    /// with it. It is drawn in brackets, as the field draws a token, with a ✓
    /// once the token is among the tokens; choosing it then adds nothing.
    ///
    /// ```swift
    /// List(matches) { Text($0.name) }
    ///     .searchable(text: $query, tokens: $tokens) { Text($0.name) }
    ///     .searchSuggestions {
    ///         Text("Apple").searchCompletion(FruitToken.apple)
    ///     }
    /// ```
    ///
    /// The suggestion is left out where the searchable takes no tokens, or
    /// tokens of another type.
    ///
    /// - Parameter token: The token added when this suggestion is chosen.
    /// - Returns: A view carrying the token for the suggestions menu.
    public func searchCompletion<T: Identifiable>(_ token: T) -> some View {
        containerValue(\.searchTokenCompletion, SearchTokenCompletion(token: token))
    }
}

/// Environment key carrying suggestions down to the enclosed search field.
///
/// Separate from ``EnvironmentValues/textInputSuggestions`` because the two
/// differ in WHO they are for: that one reaches every ``TextField`` in the
/// subtree, this one only the field ``SearchableModifier`` draws. Sharing the
/// key would make `.searchSuggestions` silently arm any text field the caller
/// happens to have in their content.
private struct SearchSuggestionsKey: EnvironmentKey {
    static var defaultValue: TextSuggestions { .none }
}

extension EnvironmentValues {
    /// Suggestions for the enclosing search field. Set via
    /// ``View/searchSuggestions(_:)``.
    var searchSuggestions: TextSuggestions {
        get { self[SearchSuggestionsKey.self] }
        set { self[SearchSuggestionsKey.self] = newValue }
    }
}
