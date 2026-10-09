//  🖥️ TUIkit — Terminal UI Kit for Swift
//  View+SearchTokens.swift
//
//  The `searchable` forms that take tokens: whole terms a search is narrowed
//  by, drawn in the field before the text.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitFoundation
import TUIkitView

// MARK: - tokens:

extension View {
    /// Marks this view as searchable with text and tokens. Mirrors SwiftUI's
    /// `searchable(text:tokens:placement:prompt:token:)`.
    ///
    /// The tokens are drawn in the field before the text, each as `token`
    /// builds it, in brackets in the accent colour: `[Apple] [Pear] app▏`.
    /// Backspace in an empty field removes the last one, as on macOS. Filtering
    /// by them is the app's job, as filtering by the text is.
    ///
    /// - Parameters:
    ///   - text: The text to display and edit in the search field.
    ///   - tokens: The tokens to display and edit in the search field.
    ///   - placement: The preferred placement (the field is drawn at the top
    ///     of the searchable subtree, whatever is preferred).
    ///   - prompt: A `Text` to display when the search field is empty.
    ///   - token: Builds the view for a token.
    public func searchable<C, T>(
        text: Binding<String>, tokens: Binding<C>,
        placement: SearchFieldPlacement = .automatic, prompt: Text? = nil,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, T: View, C.Element: Identifiable {
        _ = placement
        return SearchableModifier(
            content: self, text: text, prompt: prompt,
            tokens: .plain(tokens, suggested: nil, token: token))
    }

    /// Marks this view as searchable with text and tokens, and a localized
    /// prompt — a string literal is a lookup key, see ``LocalizedStringKey``.
    public func searchable<C, T>(
        text: Binding<String>, tokens: Binding<C>,
        placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, T: View, C.Element: Identifiable {
        searchable(text: text, tokens: tokens, placement: placement, prompt: Text(prompt), token: token)
    }

    /// Marks this view as searchable with text and tokens, and a prompt
    /// displayed as written.
    @_disfavoredOverload
    public func searchable<C, T, S: StringProtocol>(
        text: Binding<String>, tokens: Binding<C>,
        placement: SearchFieldPlacement = .automatic, prompt: S,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, T: View, C.Element: Identifiable {
        searchable(
            text: text, tokens: tokens, placement: placement, prompt: Text(String(prompt)), token: token)
    }

    /// Marks this view as searchable with text, tokens and programmatic
    /// presentation. Mirrors SwiftUI's
    /// `searchable(text:tokens:isPresented:placement:prompt:token:)`; see
    /// `searchable(text:isPresented:placement:prompt:)`
    /// for `isPresented`.
    public func searchable<C, T>(
        text: Binding<String>, tokens: Binding<C>, isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic, prompt: Text? = nil,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, T: View, C.Element: Identifiable {
        _ = placement
        return SearchableModifier(
            content: self, text: text, prompt: prompt, isPresented: isPresented,
            tokens: .plain(tokens, suggested: nil, token: token))
    }

    /// The tokens-and-presentation form, with a localized prompt.
    public func searchable<C, T>(
        text: Binding<String>, tokens: Binding<C>, isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, T: View, C.Element: Identifiable {
        searchable(
            text: text, tokens: tokens, isPresented: isPresented, placement: placement,
            prompt: Text(prompt), token: token)
    }

    /// The tokens-and-presentation form, with a prompt displayed as written.
    @_disfavoredOverload
    public func searchable<C, T, S: StringProtocol>(
        text: Binding<String>, tokens: Binding<C>, isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic, prompt: S,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, T: View, C.Element: Identifiable {
        searchable(
            text: text, tokens: tokens, isPresented: isPresented, placement: placement,
            prompt: Text(String(prompt)), token: token)
    }
}

// MARK: - suggestedTokens:

extension View {
    /// Marks this view as searchable with text, tokens, and suggested tokens.
    /// Mirrors SwiftUI's
    /// `searchable(text:tokens:suggestedTokens:placement:prompt:token:)`.
    ///
    /// The suggested tokens are offered in the field's suggestions menu while
    /// nothing is typed, above any ``View/searchSuggestions(_:)``, each in
    /// brackets as the field draws a token. The menu opens as it does for
    /// text suggestions — Down at the caret, or a click on the `▾` — and
    /// choosing one (Return on the highlighted row, or a click) adds it to
    /// `tokens` and submits, as choosing a text suggestion does. A suggestion
    /// already among the tokens is not offered again.
    ///
    /// - Parameters:
    ///   - text: The text to display and edit in the search field.
    ///   - tokens: The tokens to display and edit in the search field.
    ///   - suggestedTokens: The tokens to offer as suggestions.
    ///   - placement: The preferred placement.
    ///   - prompt: A `Text` to display when the search field is empty.
    ///   - token: Builds the view for a token.
    public func searchable<C, T>(
        text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>,
        placement: SearchFieldPlacement = .automatic, prompt: Text? = nil,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where
        C: MutableCollection, C: RandomAccessCollection, C: RangeReplaceableCollection, T: View,
        C.Element: Identifiable
    {
        _ = placement
        return SearchableModifier(
            content: self, text: text, prompt: prompt,
            tokens: .plain(tokens, suggested: suggestedTokens, token: token))
    }

    /// The suggested-tokens form, with a localized prompt.
    public func searchable<C, T>(
        text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>,
        placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where
        C: MutableCollection, C: RandomAccessCollection, C: RangeReplaceableCollection, T: View,
        C.Element: Identifiable
    {
        searchable(
            text: text, tokens: tokens, suggestedTokens: suggestedTokens, placement: placement,
            prompt: Text(prompt), token: token)
    }

    /// The suggested-tokens form, with a prompt displayed as written.
    @_disfavoredOverload
    public func searchable<C, T, S: StringProtocol>(
        text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>,
        placement: SearchFieldPlacement = .automatic, prompt: S,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where
        C: MutableCollection, C: RandomAccessCollection, C: RangeReplaceableCollection, T: View,
        C.Element: Identifiable
    {
        searchable(
            text: text, tokens: tokens, suggestedTokens: suggestedTokens, placement: placement,
            prompt: Text(String(prompt)), token: token)
    }

    /// Marks this view as searchable with text, tokens, suggested tokens and
    /// programmatic presentation. Mirrors SwiftUI's
    /// `searchable(text:tokens:suggestedTokens:isPresented:placement:prompt:token:)`.
    public func searchable<C, T>(
        text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>,
        isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: Text? = nil,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, T: View, C.Element: Identifiable {
        _ = placement
        return SearchableModifier(
            content: self, text: text, prompt: prompt, isPresented: isPresented,
            tokens: .plain(tokens, suggested: suggestedTokens, token: token))
    }

    /// The suggested-tokens-and-presentation form, with a localized prompt.
    public func searchable<C, T>(
        text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>,
        isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic,
        prompt: LocalizedStringKey, @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, T: View, C.Element: Identifiable {
        searchable(
            text: text, tokens: tokens, suggestedTokens: suggestedTokens, isPresented: isPresented,
            placement: placement, prompt: Text(prompt), token: token)
    }

    /// The suggested-tokens-and-presentation form, with a prompt displayed as
    /// written.
    @_disfavoredOverload
    public func searchable<C, T, S: StringProtocol>(
        text: Binding<String>, tokens: Binding<C>, suggestedTokens: Binding<C>,
        isPresented: Binding<Bool>, placement: SearchFieldPlacement = .automatic, prompt: S,
        @ViewBuilder token: @escaping (C.Element) -> T
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, T: View, C.Element: Identifiable {
        searchable(
            text: text, tokens: tokens, suggestedTokens: suggestedTokens, isPresented: isPresented,
            placement: placement, prompt: Text(String(prompt)), token: token)
    }
}

// MARK: - editableTokens:

extension View {
    /// Marks this view as searchable with text and editable tokens. Mirrors
    /// SwiftUI's `searchable(text:editableTokens:placement:prompt:token:)`.
    ///
    /// As `searchable(text:tokens:placement:prompt:token:)`,
    /// with `token` handed a binding to its token, so the view it builds can
    /// change it — a picker of a token's kind, say.
    ///
    /// - Parameters:
    ///   - text: The text to display and edit in the search field.
    ///   - editableTokens: The tokens to display and edit.
    ///   - placement: The preferred placement.
    ///   - prompt: A `Text` to display when the search field is empty.
    ///   - token: Builds the view for a token, given a binding to it.
    public func searchable<C>(
        text: Binding<String>, editableTokens: Binding<C>,
        placement: SearchFieldPlacement = .automatic, prompt: Text? = nil,
        @ViewBuilder token: @escaping (Binding<C.Element>) -> some View
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable {
        _ = placement
        return SearchableModifier(
            content: self, text: text, prompt: prompt, tokens: .editable(editableTokens, token: token))
    }

    /// The editable-tokens form, with a localized prompt.
    public func searchable<C>(
        text: Binding<String>, editableTokens: Binding<C>,
        placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey,
        @ViewBuilder token: @escaping (Binding<C.Element>) -> some View
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable {
        searchable(
            text: text, editableTokens: editableTokens, placement: placement, prompt: Text(prompt),
            token: token)
    }

    /// The editable-tokens form, with a prompt displayed as written.
    @_disfavoredOverload
    public func searchable<C>(
        text: Binding<String>, editableTokens: Binding<C>,
        placement: SearchFieldPlacement = .automatic, prompt: some StringProtocol,
        @ViewBuilder token: @escaping (Binding<C.Element>) -> some View
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable {
        searchable(
            text: text, editableTokens: editableTokens, placement: placement,
            prompt: Text(String(prompt)), token: token)
    }

    /// Marks this view as searchable with text, editable tokens and
    /// programmatic presentation. Mirrors SwiftUI's
    /// `searchable(text:editableTokens:isPresented:placement:prompt:token:)`.
    public func searchable<C>(
        text: Binding<String>, editableTokens: Binding<C>, isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic, prompt: Text? = nil,
        @ViewBuilder token: @escaping (Binding<C.Element>) -> some View
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable {
        _ = placement
        return SearchableModifier(
            content: self, text: text, prompt: prompt, isPresented: isPresented,
            tokens: .editable(editableTokens, token: token))
    }

    /// The editable-tokens-and-presentation form, with a localized prompt.
    public func searchable<C>(
        text: Binding<String>, editableTokens: Binding<C>, isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic, prompt: LocalizedStringKey,
        @ViewBuilder token: @escaping (Binding<C.Element>) -> some View
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable {
        searchable(
            text: text, editableTokens: editableTokens, isPresented: isPresented,
            placement: placement, prompt: Text(prompt), token: token)
    }

    /// The editable-tokens-and-presentation form, with a prompt displayed as
    /// written.
    @_disfavoredOverload
    public func searchable<C>(
        text: Binding<String>, editableTokens: Binding<C>, isPresented: Binding<Bool>,
        placement: SearchFieldPlacement = .automatic, prompt: some StringProtocol,
        @ViewBuilder token: @escaping (Binding<C.Element>) -> some View
    ) -> some View
    where C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable {
        searchable(
            text: text, editableTokens: editableTokens, isPresented: isPresented,
            placement: placement, prompt: Text(String(prompt)), token: token)
    }
}

// MARK: - What the field draws

/// A searchable's tokens, type-erased for ``SearchableModifier``: the chips
/// before the field, Backspace's way of removing one, and what the field's
/// suggestions menu offers and adds.
struct SearchTokenRow {
    /// The tokens, drawn in the field before the text.
    let chips: AnyView

    /// Removes the last token, if there is one; whether it did.
    let removeLast: () -> Bool

    /// The suggested tokens not yet chosen, as entries for the field's
    /// suggestions menu.
    let suggestions: [_TextSuggestionEntry]

    /// Takes a token the suggestions menu offered — a suggested token, or one
    /// a `searchCompletion(_:)` in the ``View/searchSuggestions(_:)`` named.
    let sink: SearchTokenSink

    /// The row for read-only tokens, and their suggestions if any.
    @MainActor
    static func plain<C, T: View>(
        _ tokens: Binding<C>, suggested: Binding<C>?, token: @escaping (C.Element) -> T
    ) -> Self
    where C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable {
        let current = Array(tokens.wrappedValue)
        let chosen = Set(current.map(\.id))
        let offered = (suggested?.wrappedValue).map { Array($0).filter { !chosen.contains($0.id) } } ?? []
        return Self(
            chips: AnyView(
                HStack(spacing: 1) {
                    ForEach(current) { element in SearchTokenChip(label: token(element)) }
                }),
            removeLast: removingLast(tokens),
            suggestions: offered.map { element in .token(element, label: AnyView(token(element))) },
            sink: sink(for: tokens))
    }

    /// The row for tokens whose views edit them.
    @MainActor
    static func editable<C, T: View>(
        _ tokens: Binding<C>, token: @escaping (Binding<C.Element>) -> T
    ) -> Self
    where C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable {
        let current = Array(tokens.wrappedValue)
        return Self(
            chips: AnyView(
                HStack(spacing: 1) {
                    ForEach(current) { element in
                        SearchTokenChip(label: token(binding(to: element, in: tokens)))
                    }
                }),
            removeLast: removingLast(tokens),
            suggestions: [],
            sink: sink(for: tokens))
    }

    /// Takes the suggestions menu's tokens of `C.Element`'s type into
    /// `tokens` — never one whose id is there already, as a token's id is its
    /// identity among the chips.
    @MainActor
    private static func sink<C>(for tokens: Binding<C>) -> SearchTokenSink
    where C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable {
        SearchTokenSink { value in
            guard let element = value as? C.Element else { return nil }
            let id = element.id
            let isChosen = tokens.wrappedValue.contains { $0.id == id }
            return (
                isChosen,
                {
                    guard !tokens.wrappedValue.contains(where: { $0.id == id }) else { return }
                    tokens.wrappedValue.append(element)
                }
            )
        }
    }

    /// Removes the last of `tokens`, and says whether there was one.
    private static func removingLast<C>(_ tokens: Binding<C>) -> () -> Bool
    where C: RandomAccessCollection, C: RangeReplaceableCollection {
        {
            guard !tokens.wrappedValue.isEmpty else { return false }
            tokens.wrappedValue.removeLast()
            return true
        }
    }

    /// A binding to the token with `element`'s id — found by id on every read
    /// and write, so it follows the token if others are added or removed
    /// before it.
    private static func binding<C>(to element: C.Element, in tokens: Binding<C>) -> Binding<C.Element>
    where C: RandomAccessCollection, C: RangeReplaceableCollection, C.Element: Identifiable {
        let id = element.id
        return Binding(
            get: { tokens.wrappedValue.first { $0.id == id } ?? element },
            set: { newValue in
                guard let index = tokens.wrappedValue.firstIndex(where: { $0.id == id }) else { return }
                tokens.wrappedValue.replaceSubrange(
                    index..<tokens.wrappedValue.index(after: index), with: CollectionOfOne(newValue))
            })
    }
}

/// One token as the field draws it: in brackets, in the accent colour.
struct SearchTokenChip<Label: View>: View {
    let label: Label

    /// Styled, and erased, by TUIkitFoundation (`erasedForegroundStyle(_:)`):
    /// `foregroundStyle(_:)`'s result names a type only it can see, which this
    /// module would look up at run time on every evaluation (CONTRIBUTING.md,
    /// "Crossing a module boundary").
    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "[")
            label
            Text(verbatim: "]")
        }
        .erasedForegroundStyle(Color.palette.accent)
    }
}
