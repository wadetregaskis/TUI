//  🖥️ TUI — A Terminal UI framework for Swift
//  TextInputSuggestions.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

// MARK: - Suggestion Entries

/// A single entry contributed to a text field's input-suggestions menu.
///
/// `@usableFromInline`, for ``TextSuggestions``' inlinable members.
@usableFromInline
package enum _TextSuggestionEntry {
    /// A pickable suggestion. `completion` is the text inserted into the
    /// field when it is picked; `nil` derives it from the label's rendered
    /// text at render time (the common `Text("…")` case).
    case option(completion: String?, label: AnyView)

    /// A suggestion that adds a search token instead of completing the text:
    /// one of a searchable's suggested tokens, or a view given a token by
    /// `searchCompletion(_:)`. `token` is the token itself, erased; the
    /// searchable that owns the token collection takes it, through the
    /// ``SearchTokenSink`` it offers beside the entries. A field with no sink,
    /// or one whose tokens are of another type, leaves the entry out.
    case token(Any, label: AnyView)

    /// A rule separating suggestion groups (a ``Divider`` in the builder).
    case divider
}

// MARK: - What a Suggestion Carries

/// The completion ``View/textInputCompletion(_:)`` gives a suggestion. A
/// container value, so it is found through every modifier written after it,
/// as a picker option's tag is.
private struct TextInputCompletionKey: ContainerValueKey {
    static var defaultValue: String? { nil }
}

/// The search token `searchCompletion(_:)` gives a suggestion, a container
/// value as the completion is.
private struct SearchTokenCompletionKey: ContainerValueKey {
    static var defaultValue: SearchTokenCompletion? { nil }
}

/// A search token, erased: boxed, so that reading it back is one cast to this
/// type rather than a cast to an optional of `Any`.
package struct SearchTokenCompletion {
    /// The token itself.
    package let token: Any

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUISearch makes these (`searchCompletion(_:)` given a
    /// token).
    package init(token: Any) {
        self.token = token
    }
}

extension ContainerValues {
    /// The text a suggestion fills its field with, where
    /// ``View/textInputCompletion(_:)`` gave one.
    package var textInputCompletion: String? {
        get { self[TextInputCompletionKey.self] }
        set { self[TextInputCompletionKey.self] = newValue }
    }

    /// The search token a suggestion adds, where `searchCompletion(_:)` gave
    /// one.
    package var searchTokenCompletion: SearchTokenCompletion? {
        get { self[SearchTokenCompletionKey.self] }
        set { self[SearchTokenCompletionKey.self] = newValue }
    }
}

extension View {
    /// Associates a fully formed completion string with this view when it is
    /// used as a text input suggestion.
    ///
    /// Without this modifier a suggestion's completion is the plain text of
    /// its label; use it when the label decorates or abbreviates the value:
    ///
    /// ```swift
    /// TextField("Ramp", text: $ramp)
    ///     .textInputSuggestions {
    ///         Label("Blocks", systemImage: "square.fill")
    ///             .textInputCompletion("▏▎▍▌▋▊▉")
    ///     }
    /// ```
    ///
    /// - Parameter completion: The text inserted into the field when this
    ///   suggestion is picked.
    /// - Returns: A view carrying the completion for the suggestions menu.
    nonisolated public func textInputCompletion(_ completion: String) -> some View {
        containerValue(\.textInputCompletion, completion)
    }
}

// MARK: - Environment

/// What a `.textInputSuggestions` or `.searchSuggestions` above offers: the
/// entries, and whether such a modifier is in force at all — one can be,
/// offering nothing this frame, because its builder filtered everything out.
///
/// Compared by presence and emptiness alone — see `==`.
///
/// `@usableFromInline`, with its stored properties and the types they hold,
/// and `none`, `offering(_:tokenSink:)` and the initializer they call
/// `@inlinable`: TUISearch makes these on every evaluation of a
/// searchable since module split step C5, and called each out of line until
/// they were (the plan's tier 2 for that step). `tokenSink` is a `let` with
/// no default for the same reason: an inlined initializer would call a
/// stored property's default out of line (CONTRIBUTING.md, "Crossing a
/// module boundary").
@usableFromInline
package struct TextSuggestions: Equatable {
    /// The normalized entries, in menu order.
    @usableFromInline package let entries: [_TextSuggestionEntry]

    /// Whether a suggestions modifier put these here, as opposed to the key's
    /// default.
    @usableFromInline let isPresent: Bool

    /// Where a token entry's token goes when it is chosen — the token
    /// collection of the searchable whose field this is — or `nil` outside a
    /// searchable with tokens, where such an entry is left out of the menu.
    @usableFromInline let tokenSink: SearchTokenSink?

    /// The memberwise initializer, spelled out to be `@inlinable`.
    @inlinable
    package init(entries: [_TextSuggestionEntry], isPresent: Bool, tokenSink: SearchTokenSink?) {
        self.entries = entries
        self.isPresent = isPresent
        self.tokenSink = tokenSink
    }

    /// No suggestions modifier in force.
    ///
    /// Computed rather than stored, as are the keys' defaults built from it: a
    /// token entry holds its token as `Any`, so this type is not `Sendable`
    /// and cannot be a stored static.
    @inlinable
    package static var none: Self { Self(entries: [], isPresent: false, tokenSink: nil) }

    /// What a suggestions modifier offers.
    @inlinable
    package static func offering(_ entries: [_TextSuggestionEntry], tokenSink: SearchTokenSink? = nil) -> Self {
        Self(entries: entries, isPresent: true, tokenSink: tokenSink)
    }

    /// Whether a field has anything here to choose: an option, or a token its
    /// sink takes. Exactly when `TextFieldSuggestions.prepare` builds a menu
    /// for an enabled field, so it is what decides the `▾` — in a vertical
    /// field's measure, which does not prepare the menu, as in its render.
    ///
    /// Not `!entries.isEmpty`: a token entry the field cannot take (it has no
    /// sink, or the sink's tokens are of another type) is no suggestion, so a
    /// list of them alone offers nothing, and a measure that counted them
    /// narrowed the text for a `▾` the render never drew.
    @MainActor
    var offersChoice: Bool {
        entries.contains { entry in
            switch entry {
            case .option: true
            case .token(let token, _): tokenSink?.choice(token) != nil
            case .divider: false
            }
        }
    }

    /// Equal when both are present or both are not, and both are empty or
    /// both are not — never by what the entries say.
    ///
    /// An environment value that cannot be compared turns off every memo
    /// beneath it, and the entries cannot be: a label is an `AnyView`, and a
    /// completion is read off the label's RENDERED text. So a List under
    /// `.searchSuggestions` drew every row afresh on every frame. Comparing by
    /// content would be worse — suggestions are rebuilt as the query is typed,
    /// so every keystroke would clear everything below.
    ///
    /// This is enough because the one reader of the entries, a text field
    /// (`TextFieldSuggestions.prepare`), declares a render side effect whenever
    /// suggestions are present, so no memo that holds such a field ever stores
    /// — it re-renders, and re-syncs its handler, as it always did. Any other
    /// memo below holds no reader, so it cannot draw differently for different
    /// entries. The emptiness term is a margin on top: the `▾` a field draws
    /// depends on it, and should a reader ever skip the declaration, a change
    /// of emptiness still clears.
    ///
    /// The token sink is left out for the same reason: closures over the
    /// searchable's binding, read only by that same field.
    @usableFromInline
    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isPresent == rhs.isPresent && lhs.entries.isEmpty == rhs.entries.isEmpty
    }
}

/// What choosing one of a text field's suggestions does — see
/// ``TextFieldHandler/acceptSuggestion(at:)``.
enum TextSuggestionChoice {
    /// Fills the field with this text.
    case completion(String)

    /// Empties the field and adds a search token, by calling `choose`.
    case token(choose: () -> Void)

    /// The text a completion fills the field with; `nil` for a token.
    var completion: String? {
        if case .completion(let text) = self { return text }
        return nil
    }
}

/// A searchable's token collection, type-erased for the suggestions menu: what
/// choosing a token entry does.
///
/// `@usableFromInline`, for ``TextSuggestions``' inlinable members.
@usableFromInline
package struct SearchTokenSink {
    /// For a token of the collection's element type, whether it is already
    /// among the tokens, and how to add it; `nil` for a token of any other
    /// type, which this searchable cannot take.
    let choice: (Any) -> (isChosen: Bool, choose: () -> Void)?

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUISearch makes these, for a searchable with tokens.
    package init(choice: @escaping (Any) -> (isChosen: Bool, choose: () -> Void)?) {
        self.choice = choice
    }
}

/// Environment key carrying the extracted suggestion entries down to the
/// text fields in the modified subtree.
///
/// `@usableFromInline package` rather than `private`, with its default
/// `@inlinable`: the `@inlinable` accessor names it.
@usableFromInline
package struct TextInputSuggestionsKey: EnvironmentKey {
    @inlinable package static var defaultValue: TextSuggestions { .none }
}

extension EnvironmentValues {
    /// The input suggestions available to text fields in this subtree.
    /// Set via ``View/textInputSuggestions(_:)``.
    ///
    /// `@inlinable`: a searchable's field (TUISearch) writes it on every
    /// evaluation that offers suggestions, through the key path its
    /// `transformEnvironment(_:transform:)` takes.
    @inlinable
    package var textInputSuggestions: TextSuggestions {
        get { self[TextInputSuggestionsKey.self] }
        set { self[TextInputSuggestionsKey.self] = newValue }
    }
}

// MARK: - The Modifier

extension View {
    /// Presents a drop-down menu of input suggestions beneath any
    /// ``TextField`` in this view's subtree while it is focused — the
    /// combo-box pattern: a field that accepts free text *and* offers a menu
    /// of pre-defined or recent values.
    ///
    /// Each view the builder makes is a suggestion, wherever it is written —
    /// in a view of your own, a `Group`, an `if`, a `ForEach` — and fills the
    /// field with its text, or with the completion
    /// ``View/textInputCompletion(_:)`` gives it. A ``Divider`` is a rule
    /// between groups, and so is the edge of a `Section`:
    ///
    /// ```swift
    /// TextField("City", text: $city)
    ///     .textInputSuggestions {
    ///         ForEach(favouriteCities, id: \.self) { Text($0) }
    ///         if !recentCities.isEmpty {
    ///             Divider()
    ///             ForEach(recentCities, id: \.self) { Text($0) }
    ///         }
    ///     }
    /// ```
    ///
    /// The builder is re-evaluated on every render, so filtering the
    /// suggestions against the field's current text is just a matter of
    /// filtering the data you build them from.
    ///
    /// ## Interaction
    ///
    /// The menu opens ON DEMAND, never just because the field gained focus:
    /// press Down at the caret, or click the `▾` disclosure at the field's
    /// trailing edge (clicking it again — or Escape — closes). Typing keeps
    /// editing the field and leaves the menu's open state alone; Down then
    /// walks the menu (Up from the first row returns to the caret); Enter
    /// picks the highlighted suggestion — filling the field and firing
    /// ``TextField/onSubmit(_:)``, the combo-box convention — while Enter
    /// with no highlight submits as usual and closes the menu. Clicking a
    /// row picks it; the wheel scrolls a long menu. The menu never outlives
    /// the field's focus.
    ///
    /// - Parameter suggestions: A view builder of suggestion entries.
    /// - Returns: A view whose text fields offer the suggestions.
    nonisolated public func textInputSuggestions<S: View>(
        @ViewBuilder _ suggestions: () -> S
    ) -> some View {
        _TextSuggestionsReader(content: self, suggestions: suggestions(), keyPath: \.textInputSuggestions)
    }

    /// Presents input suggestions built from a collection of identifiable
    /// data. See ``View/textInputSuggestions(_:)``.
    ///
    /// - Parameters:
    ///   - suggestions: The data to build suggestions from.
    ///   - content: A view builder producing each element's suggestion.
    /// - Returns: A view whose text fields offer the suggestions.
    nonisolated public func textInputSuggestions<Data: RandomAccessCollection, Content: View>(
        _ suggestions: Data,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View where Data.Element: Identifiable {
        _TextSuggestionsReader(
            content: self, suggestions: ForEach(suggestions, content: content), keyPath: \.textInputSuggestions)
    }

    /// Presents input suggestions built from a collection of data, identified
    /// by a key path. See ``View/textInputSuggestions(_:)``.
    ///
    /// - Parameters:
    ///   - suggestions: The data to build suggestions from.
    ///   - id: The key path to each element's identity.
    ///   - content: A view builder producing each element's suggestion.
    /// - Returns: A view whose text fields offer the suggestions.
    nonisolated public func textInputSuggestions<
        Data: RandomAccessCollection, ID: Hashable, Content: View
    >(
        _ suggestions: Data,
        id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) -> some View {
        _TextSuggestionsReader(
            content: self, suggestions: ForEach(suggestions, id: id, content: content),
            keyPath: \.textInputSuggestions)
    }
}

// MARK: - Reading the Suggestions

/// The entries of `suggestions`, in menu order, resolved in `scope` as
/// ``Group/init(subviews:transform:)`` resolves members
/// (`subviewGroups(of:in:)`): so a suggestion is found inside a view of the
/// app's own, a `Group`, an `AnyView`, a `Section` or an `if`, and its
/// completion or token behind any modifier written after it — where the walk
/// of seven view types this replaced found none of those (deviation V7, fixed
/// by the owner's ruling of 2026-10-13).
///
/// A ``Divider`` is a rule, and so is the edge of each top-level `Section`
/// with a header, as in a ``Picker``'s menu; edge and doubled rules are
/// collapsed, so a group a condition empties leaves none behind. Every other
/// member is a suggestion: one that adds the token `searchCompletion(_:)`
/// gave it, or one that fills the field with the completion
/// ``View/textInputCompletion(_:)`` gave it — or, with neither, its label's
/// text, read when the field draws the menu.
@MainActor
package func textSuggestionEntries(of suggestions: some View, in scope: RenderContext) -> [_TextSuggestionEntry] {
    var entries: [_TextSuggestionEntry] = []
    for group in subviewGroups(of: suggestions, in: scope) {
        if !group.header.isEmpty { entries.append(.divider) }
        for member in group.members {
            if member.isDivider {
                entries.append(.divider)
                continue
            }
            let values = member.containerValues
            if let token = values.searchTokenCompletion {
                entries.append(.token(token.token, label: AnyView(member)))
            } else {
                entries.append(.option(completion: values.textInputCompletion, label: AnyView(member)))
            }
        }
        if !group.header.isEmpty { entries.append(.divider) }
    }
    return DropdownMenu.normalizedEntries(entries) { entry in
        if case .divider = entry { return true }
        return false
    }
}

/// Resolves a suggestions builder's entries in the context it is drawn in, and
/// publishes them at `keyPath` to the text fields below: what
/// ``View/textInputSuggestions(_:)`` and `searchSuggestions(_:)` put round
/// their content.
///
/// Resolved where the modifier is, as SwiftUI evaluates the builder there, one
/// identity step in (this type, 0), so a view of the app's own among the
/// suggestions keeps its `@State` apart from the content's. The content draws
/// at the reader's own identity, under the ``EnvironmentModifier`` the reader
/// makes for each pass — so to the content, and to a container looking
/// through it, the reader is the `.environment` modifier it was before the
/// suggestions needed a context to be read in.
nonisolated package struct _TextSuggestionsReader<Content: View, Suggestions: View>: View, Renderable, Layoutable {
    let content: Content
    let suggestions: Suggestions
    let keyPath: WritableKeyPath<EnvironmentValues, TextSuggestions>

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUISearch makes these (`searchSuggestions(_:)`).
    package init(
        content: Content, suggestions: Suggestions, keyPath: WritableKeyPath<EnvironmentValues, TextSuggestions>
    ) {
        self.content = content
        self.suggestions = suggestions
        self.keyPath = keyPath
    }

    /// Not used to draw — the ``Renderable`` conformance takes priority — but
    /// the content, as ``EnvironmentModifier``'s is, so a container asking
    /// what this view hands over is asked of the content.
    @MainActor package var body: some View {
        content
    }

    @MainActor package func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        publishing(in: context).sizeThatFits(proposal: proposal, context: context)
    }

    @MainActor package func renderToBuffer(context: RenderContext) -> FrameBuffer {
        publishing(in: context).renderToBuffer(context: context)
    }

    /// The content under the suggestions resolved in `context`.
    @MainActor private func publishing(in context: RenderContext) -> EnvironmentModifier<Content, TextSuggestions> {
        let entries = textSuggestionEntries(of: suggestions, in: context.withChildIdentity(type: Self.self, index: 0))
        return EnvironmentModifier(content: content, keyPath: keyPath, value: .offering(entries))
    }
}

/// An environment value reaches a subtree whether it was set one level up or
/// two, so publishing the suggestions round each member of multi-view content
/// is the same as publishing them once round the lot — as for
/// ``EnvironmentModifier``. Each copy resolves them at its member's identity.
@MainActor extension _TextSuggestionsReader: ContentRewrapping {
    package var wrappedContent: Content { content }

    /// Its content's context: the suggestions it publishes (``SingleContentWrapper/wrappedContentContext(_:)``).
    package func wrappedContentContext(_ context: RenderContext) -> RenderContext? { publishing(in: context).contentContext(context) }

    package func rewrapping<V: View>(_ view: V) -> any View {
        _TextSuggestionsReader<V, Suggestions>(content: view, suggestions: suggestions, keyPath: keyPath)
    }
}

/// Body deliberately empty: ``ChildViewProvider`` has the whole implementation
/// for a ``SingleContentWrapper``.
@MainActor extension _TextSuggestionsReader: ChildViewProvider where Content: ChildViewProvider {}

/// Body deliberately empty, as above: a section with suggestions on it is
/// still a section.
@MainActor extension _TextSuggestionsReader: SectionPartsProviding where Content: SectionPartsProviding {}

/// A section with suggestions on it is still a section to its `List`: its
/// parts drawn under the suggestions resolved here, as the reader draws its
/// content.
@MainActor extension _TextSuggestionsReader: SectionRowExtractor where Content: SectionRowExtractor {
    package func extractSectionInfo(context: RenderContext) -> SectionInfo {
        publishing(in: context).extractSectionInfo(context: context)
    }

    package func extractSectionContentRows<RowID: Hashable>(context: RenderContext) -> SectionContentRows<RowID> {
        publishing(in: context).extractSectionContentRows(context: context)
    }
}

/// Body deliberately empty, as above: a grid row with suggestions on it is
/// still a row.
@MainActor extension _TextSuggestionsReader: GridRowProviding where Content: GridRowProviding {}

/// It draws its content unchanged, at its own identity, so a removal
/// transition written inside it plays — see `DrawsContentUnchanged`.
@MainActor extension _TextSuggestionsReader: DrawsContentUnchanged {}

// MARK: - The Field's Menu

/// The render-pass half of a text field's suggestions menu: builds the
/// ``DropdownMenu`` rows from the environment's entries, syncs the field
/// handler's completion list, and attaches the open popup as an overlay.
/// ``TextField``'s core calls this; the keyboard half lives on
/// ``TextFieldHandler``.
@MainActor
enum TextFieldSuggestions {
    /// The prepared menu model for one render pass.
    struct Menu {
        /// The drop-down's entries, in display order.
        let entries: [DropdownMenu.Entry]

        /// Whether the popup is showing this frame (focused, not dismissed,
        /// at least one option).
        let isOpen: Bool
    }

    /// Builds the menu model and syncs the handler's completions/highlight.
    /// Returns `nil` when there are no suggestions, or the field is disabled.
    ///
    /// Reads the entries itself, because reading them obliges it to declare: a
    /// field under a suggestions modifier syncs handler state from labels it
    /// renders on every pass, and nothing in any memo's key sees them — the
    /// environment value compares by presence and emptiness alone
    /// (``TextSuggestions``). So the field makes every memo that holds it
    /// decline, whenever a modifier is present, empty or not and disabled or
    /// not, and a served buffer can never stand in for a render that would
    /// have changed its completions.
    static func prepare(
        isDisabled: Bool,
        handler: TextFieldHandler,
        currentText: String,
        isFocused: Bool,
        context: RenderContext
    ) -> Menu? {
        let suggestions = context.environment.textInputSuggestions
        if suggestions.isPresent {
            context.environment.volatileReadTracker?.recordRenderSideEffect()
        }
        // A disabled field leaves its handler alone, as it always has.
        guard !isDisabled else { return nil }
        let entries = suggestions.entries
        // No suggestions this frame — make sure stale completions don't leave
        // the handler intercepting Down/Enter.
        func offerNothing() -> Menu? {
            handler.suggestionChoices = []
            handler.suggestionHighlight = nil
            return nil
        }
        guard suggestions.offersChoice else { return offerNothing() }
        // Labels render at the SCREEN width, not the field's: the pop-up is
        // an overlay that may grow wider than its control, so a narrow field
        // must not wrap/truncate its option labels.
        var labelContext = context.withAvailableWidth(
            max(context.availableWidth, context.environment.terminalWidth))
        // Every label renders at the field's own identity, so two labels'
        // memos would share one entry and one environment slot. The entries
        // being uncomparable used to keep them all from storing; this keeps
        // them so now that the value compares.
        labelContext.environment.hasUncomparableEnvironmentValue = true
        labelContext.leaveScrollCanvas()

        // The drop-down's own model — the same one the `Picker` builds, so the
        // marker column, the width and the pointer handling are one
        // implementation rather than two that drift.
        var menuEntries: [DropdownMenu.Entry] = []
        var choices: [TextSuggestionChoice] = []
        for entry in entries {
            switch entry {
            case .divider:
                menuEntries.append(.divider)
            case .option(let explicit, let label):
                let rendered = label.renderToBuffer(context: labelContext).lines.first ?? ""
                let completion = explicit ?? rendered.stripped
                // The option whose completion is the field's current text is
                // the "selected" one: the field's value IS the selection.
                menuEntries.append(
                    .option(label: rendered, isSelected: completion == currentText))
                choices.append(.completion(completion))
            case .token(let token, let label):
                // A token this field's searchable cannot take — it has none, or
                // they are of another type — is no suggestion here at all.
                guard let choice = suggestions.tokenSink?.choice(token) else { continue }
                // In brackets, as the field draws a chosen token, so a row that
                // adds a token reads differently from one that completes the
                // text. Not in the accent, as the field's tokens are: the
                // highlight fills with the accent, and the label would sink
                // into its own row. A token already chosen earns the ✓.
                let rendered = label.renderToBuffer(context: labelContext).lines.first ?? ""
                menuEntries.append(.option(label: "[" + rendered + "]", isSelected: choice.isChosen))
                choices.append(.token(choose: choice.choose))
            }
        }
        // Token entries the field could not take may leave a divider stranded.
        // (Never nothing to choose: `offersChoice` above is this loop's filter.)
        menuEntries = DropdownMenu.normalizedEntries(menuEntries) { entry in
            if case .divider = entry { return true }
            return false
        }

        handler.suggestionChoices = choices
        // The suggestions are rebuilt every frame (that is how filtering them
        // against the field's text works), so the highlight has to be told what
        // survived.
        handler.suggestionHighlighting.adopt(count: choices.count)
        // Captured at render so a Shift-accelerated Up/Down in the open pop-up
        // can jump at event time, when the environment is out of reach.
        handler.shiftStepMultiplier = context.environment.shiftStepMultiplier

        // What the field's `▾` press tells the dispatcher too, so the two agree
        // on whether the menu is on screen (`TextFieldMouseHandler.register`).
        let isOpen = isFocused && handler.suggestionsActive
        if isOpen, !context.isMeasuring {
            // The menu's Escape (close) takes precedence over any page-level
            // ESC handler while open — surface that in the status bar, as the
            // picker's drop-down does.
            context.environment.statusBar?.escapeLabelOverride =
                LocalizationService.shared.string(
                    for: LocalizationKey.StatusBar.closeSuggestions)
        }
        return Menu(entries: menuEntries, isOpen: isOpen)
    }

    /// Renders the open popup and attaches it to the field's buffer as an
    /// overlay anchored one row beneath the field — through the same
    /// ``DropdownMenu`` assembly the `Picker` uses, so the two menus sit on one
    /// grid, size themselves by one rule and answer the pointer identically.
    static func attach(
        menu: Menu,
        to buffer: inout FrameBuffer,
        handler: TextFieldHandler,
        context: RenderContext
    ) {
        DropdownMenu.attach(
            DropdownMenu.OptionMenu(
                entries: menu.entries,
                highlightedOption: handler.suggestionHighlight,
                scroll: handler.suggestionScroll,
                followHighlight: handler.suggestionHighlighting.consumeFollowPending(),
                autoRepeatToken: "textfield-suggestions-\(context.identity.path)"),
            to: &buffer,
            context: context,
            // The pointer is already looking at the row it is over, so a hover
            // moves the highlight without asking the window to scroll.
            onHover: { ordinal in handler.suggestionHighlighting.point(at: ordinal) },
            onActivate: { ordinal in handler.acceptSuggestion(at: ordinal) },
            onDismiss: { handler.suggestionsOpen = false })
    }
}
