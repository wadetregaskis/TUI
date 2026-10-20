//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SearchableModifier.swift
//
//  The view `.searchable` builds: a search field above the searchable content.
//  The modifiers that configure it live in View+Searchable.swift and beside it.
//
//  Created by LAYERED.work
//  License: MIT

import TUIkitFoundation
import TUIkitTextInput

/// Composes a search field above the searchable content. Pure composition — no
/// `_*Core`, no overlay, no focus machinery (Box.swift is the reference model).
struct SearchableModifier<Content: View>: View {
    let content: Content
    let text: Binding<String>
    let prompt: Text?

    /// Whether search is presented, for the `isPresented:` forms: kept equal to
    /// ``isSearching`` from the field's side, and acted on from the app's.
    var isPresented: Binding<Bool>?

    /// The tokens, for the `tokens:` forms — see `View+SearchTokens.swift`.
    var tokens: SearchTokenRow?

    /// Whether the field holds focus — the value ``EnvironmentValues/isSearching``
    /// publishes to `content`.
    ///
    /// State rather than a focus query, because the field's focus ID is
    /// generated from its own render identity and nothing out here knows it.
    /// `onEditingChanged` is precisely the focus transition (``TextFieldHandler``
    /// fires it from `onFocusReceived`/`onFocusLost`), so the state tracks
    /// focus rather than approximating it.
    @State private var isSearching = false

    /// What ending this search does, handed to the content — see
    /// ``SearchDismissal``.
    @State private var dismissal = SearchDismissal()

    /// Taken out of the environment here, in the body, because the closure
    /// below runs during event dispatch — outside any render, where an
    /// `@Environment` read is nil.
    @Environment(\.focusManager) private var focusManager

    /// The bare `⌕` (U+2315 telephone recorder) is drawn tiny and thin-lined by
    /// Terminal.app, so it reads as noise beside the field rather than a search
    /// affordance. On terminals that render emoji chrome legibly we use a bold
    /// magnifier instead; elsewhere we draw no icon at all and let the "Search"
    /// prompt carry the meaning (a mis-drawn glyph is worse than none).
    @Environment(\.supportsEmojiChrome) private var supportsEmojiChrome

    /// Which side the icon sits on — and therefore which magnifier it is.
    @Environment(\.searchFieldIconPlacement) private var iconPlacement

    /// What ``View/searchSuggestions(_:)`` above us offered, on its way to the
    /// query field alone.
    @Environment(\.searchSuggestions) private var suggestions

    /// What ``View/searchScopes(_:scopes:)`` above us offered, if anything.
    @Environment(\.searchScopeBar) private var scopeBar

    /// What ``View/searchSelection(_:)`` around us bound the field's
    /// selection to, if anything.
    @Environment(\.searchSelection) private var selection

    /// Where the default prompt's word comes from: the environment's service,
    /// which a running app republishes as the shared one each frame, so a
    /// subtree (or a test) can show it in another language without switching
    /// the whole process, as `LocalizedString` reads its service.
    @Environment(\.localizationService) private var localizationService

    /// The magnifier that faces the field from `iconPlacement`'s side: 🔎 is
    /// RIGHT-pointing so it looks rightward into a trailing field, 🔍 is
    /// LEFT-pointing so it looks leftward into a leading one. (The Unicode
    /// names read backwards from the rendered shape at a glance — U+1F50E
    /// RIGHT-POINTING is the one whose lens sits on the right.)
    private var icon: Text {
        Text(iconPlacement == .leading ? "\u{1F50E}" : "\u{1F50D}")
    }

    var body: some View {
        // Refreshed on every evaluation, so the action the content was handed
        // — perhaps frames ago, and served from a memo since — ends the search
        // as it stands now.
        dismissal.text = text
        dismissal.focusManager = focusManager
        dismissal.isSearching = isSearching
        return presentationSync(searchStack)
    }

    /// The field, with the icon at its side, any tokens before it, and the
    /// clear button after it while it holds text.
    ///
    /// Backspace in an empty field removes the last token — asked of the row
    /// rather than the field, through `onKeyPress`, which hears the key before
    /// the field does and only while the focus is in the row.
    @ViewBuilder
    private var fieldRow: some View {
        let row = HStack(spacing: 1) {
            if supportsEmojiChrome, iconPlacement == .leading {
                icon
            }
            if let tokens {
                tokens.chips
            }
            // Scope ONLY the query field to the `.search` submit role, so a
            // Return here fires `.onSubmit(of: .search)` — not `.onSubmit(of:
            // .text)`, and a plain text field in `content` (a sibling) still
            // consumes `.text`.
            queryField
                .environment(\.submitTriggerRole, .search)
            // A slot of its own after the field's, so the field stays the same
            // view as the button comes and goes.
            if !text.wrappedValue.isEmpty {
                clearButton
            }
            if supportsEmojiChrome, iconPlacement == .trailing {
                icon
            }
        }
        if let tokens {
            let text = text
            row.onKeyPress(.delete) {
                text.wrappedValue.isEmpty && tokens.removeLast() ? .handled : .ignored
            }
        } else {
            row
        }
    }

    /// macOS's cancel button: a ✕ at the field's trailing end while it holds
    /// text, which empties it (measured on macOS 15.8.1, `Tools/SwiftUIProbes/
    /// Search field clear button`). Not a Tab stop, as macOS's is not in the
    /// key view loop: its keyboard route is Ctrl-U, which empties any field.
    /// Drawn as `Shortcut.cross` (✗, U+2717), the framework's cancel symbol, in
    /// the secondary ink: a Dingbat of neutral East Asian width, so one cell
    /// everywhere, where macOS's ⓧ (U+24E7) is ambiguous-width and two cells in
    /// a CJK terminal (Terminal compatibility survey, "The search field's ✕").
    private var clearButton: some View {
        let text = text
        return Button {
            text.wrappedValue = ""
        } label: {
            Text(verbatim: Shortcut.cross)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .focusable(false)
    }

    /// The row under the field — the scopes — when it shows now, or `nil`.
    ///
    /// It stays while the focus is in it, or Tab from the field would hide
    /// what it was heading for.
    private var accessories: AnyView? {
        let hasQuery = !text.wrappedValue.isEmpty
        let focusInRows = dismissal.focusIsInAccessories
        return scopeBar.flatMap { bar in
            bar.activation.showsScopes(
                isSearching: isSearching, hasQuery: hasQuery, focusInScopes: focusInRows) ? bar.picker : nil
        }
    }

    /// The field above the content — or in a bar, or nowhere
    /// (``_SearchFieldPlace``).
    private var searchStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The field, and the rows under it: one child, so the content stays
            // the stack's second whether or not the rows show, and wherever the
            // field is drawn.
            _SearchFieldPlace(
                field: VStack(alignment: .leading, spacing: 0) {
                    fieldRow
                    if let accessories {
                        _SearchAccessoryFrame(content: accessories, search: dismissal)
                    }
                })
            // Both values reach the CONTENT only, which is where SwiftUI puts
            // them: they answer questions about the field, and the field is the
            // framework's, not the caller's.
            content
                .environment(\.isSearching, isSearching)
                .environment(\.searchDismissal, dismissal)
                // What `ContentUnavailableView.search` names.
                .environment(\.searchQuery, text.wrappedValue)
                // A `searchFocused` or `searchScopes` written outside belongs to
                // THIS searchable's field, and not a searchable's in the content
                // as well.
                .environment(\.searchFocusOffer, nil)
                .environment(\.searchScopeBar, nil)
                .environment(\.searchSelection, nil)
        }
    }

    /// For the `isPresented:` forms, acts on the app's writes: presenting
    /// moves the focus to the field, and ending the search dismisses it.
    ///
    /// After the frame, not during it: the focus move needs the ring this
    /// render is still building, and dismissing writes the query, which is
    /// state this render has already read.
    @ViewBuilder
    private func presentationSync(_ stack: some View) -> some View {
        if let isPresented {
            let dismissal = dismissal
            let isSearching = isSearching
            stack.onChange(of: isPresented.wrappedValue, initial: true) { _, presented in
                if presented, !isSearching {
                    Task { @MainActor in dismissal.focusField() }
                } else if !presented, isSearching {
                    Task { @MainActor in dismissal.dismiss() }
                }
            }
        } else {
            stack
        }
    }

    /// The query field, carrying whatever `.searchSuggestions` offered, after
    /// the suggested tokens.
    ///
    /// The suggested tokens come first, as their own group, and only while
    /// nothing is typed: SwiftUI offers them for an empty field. Both kinds
    /// share the one menu, so its keys, its pointer handling and its
    /// Return-to-submit rule are the text suggestions' own.
    ///
    /// The hand-off is what scopes the suggestions: they arrive on an
    /// environment key of their own and are turned into the general
    /// text-field key HERE, on this one field, so a `TextField` the caller has
    /// in `content` is not armed by a modifier that never mentioned it.
    ///
    /// Left alone when there are none, rather than written as an empty list:
    /// a `.textInputSuggestions` set above the whole searchable is a
    /// deliberate statement about every field in it, and clearing it here
    /// would make the search field the one exception.
    ///
    /// Decided INSIDE one modifier, not by choosing between two views: a
    /// branch would make the field a different view whenever a keystroke
    /// filtered the suggestions down to nothing, and its caret and focus with
    /// it.
    private var queryField: some View {
        // The fallback prompt is the framework's word, not the caller's, so it
        // comes from the table. `Text(verbatim:)` because the lookup has
        // already happened — see `ContentUnavailableView.search`.
        let defaultPrompt = Text(verbatim: localizationService.string(for: LocalizationKey.Label.search))
        let tokenSink = tokens?.sink
        var offered = text.wrappedValue.isEmpty ? tokens?.suggestions ?? [] : []
        if !offered.isEmpty, !suggestions.entries.isEmpty {
            offered.append(.divider)
        }
        offered += suggestions.entries
        let isPresented = isPresented
        let field = baseField(prompt: prompt ?? defaultPrompt)
            .onEditingChanged { began in
                isSearching = began
                // The field's side of `isPresented`: presented while it holds
                // the focus, as `isSearching` is.
                if let isPresented, isPresented.wrappedValue != began {
                    isPresented.wrappedValue = began
                }
            }
            .transformEnvironment(\.textInputSuggestions) { inherited in
                if !offered.isEmpty { inherited = .offering(offered, tokenSink: tokenSink) }
            }
        // Records where the field rendered, so presenting can focus it, and
        // binds a `searchFocused` focus state to it.
        return _SearchFieldFocus(content: field, search: dismissal)
    }

    /// The query field, its selection bound where a `searchSelection` around
    /// the searchable asked — the same field either way, so binding one does
    /// not make the field a different view.
    private func baseField(prompt: Text) -> TextField<Text> {
        if #available(macOS 15, *), let binding = selection?.binding as? Binding<TextSelection?> {
            return TextField("", text: text, selection: binding, prompt: prompt)
        }
        return TextField("", text: text, prompt: prompt)
    }
}

// MARK: - Environment without reflection

extension SearchableModifier: ResolvesOwnEnvironment {
    package func resolveOwnEnvironment(_ environment: EnvironmentValues) {
        _focusManager.resolveEnvironment(environment)
        _supportsEmojiChrome.resolveEnvironment(environment)
        _iconPlacement.resolveEnvironment(environment)
        _suggestions.resolveEnvironment(environment)
        _scopeBar.resolveEnvironment(environment)
        _selection.resolveEnvironment(environment)
        _localizationService.resolveEnvironment(environment)
    }
}
