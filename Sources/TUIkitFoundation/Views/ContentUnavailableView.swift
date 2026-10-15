//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ContentUnavailableView.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Content Unavailable View

/// A view that displays a placeholder when content is unavailable.
///
/// Use `ContentUnavailableView` to communicate that the current view has
/// no content to display. Common use cases include empty search results,
/// empty lists, and error states.
///
/// The view arranges a label, an optional description, and optional actions
/// vertically, centered in the available space.
///
/// ## Examples
///
/// ```swift
/// // Simple text label
/// ContentUnavailableView("No Items")
///
/// // With description
/// ContentUnavailableView("No Items", description: "Add items to get started.")
///
/// // Full ViewBuilder API
/// ContentUnavailableView {
///     Text("No Results")
/// } description: {
///     Text("Try a different search term.")
/// } actions: {
///     Button("Clear Search") { }
/// }
///
/// // Search preset
/// ContentUnavailableView.search
/// ContentUnavailableView.search(text: "query")
/// ```
public struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
    /// The label view (typically a title or icon).
    let label: Label

    /// The description view (typically explanatory text).
    let description: Description

    /// The action views (typically buttons).
    let actions: Actions

    /// Creates a content unavailable view with label, description, and actions.
    ///
    /// - Parameters:
    ///   - label: The primary label view.
    ///   - description: The description view below the label.
    ///   - actions: The action views below the description.
    public init(
        @ViewBuilder label: () -> Label,
        @ViewBuilder description: () -> Description,
        @ViewBuilder actions: () -> Actions
    ) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    public var body: some View {
        _ContentUnavailableViewCore(
            label: label,
            description: description,
            actions: actions
        )
    }
}

// MARK: - Convenience Initializers

extension ContentUnavailableView where Description == EmptyView, Actions == EmptyView {
    /// Creates a content unavailable view with only a label.
    ///
    /// - Parameter label: The primary label view.
    public init(@ViewBuilder label: () -> Label) {
        self.init(label: label, description: { EmptyView() }, actions: { EmptyView() })
    }
}

extension ContentUnavailableView where Description == EmptyView {
    /// Creates a content unavailable view with a label and actions, and no
    /// description — SwiftUI's `init(label:description:actions:)` with the
    /// description left at its default.
    ///
    /// - Parameters:
    ///   - label: The primary label view.
    ///   - actions: The action views below the label.
    public init(@ViewBuilder label: () -> Label, @ViewBuilder actions: () -> Actions) {
        self.init(label: label, description: { EmptyView() }, actions: actions)
    }
}

extension ContentUnavailableView where Actions == EmptyView {
    /// Creates a content unavailable view with a label and description.
    ///
    /// - Parameters:
    ///   - label: The primary label view.
    ///   - description: The description view below the label.
    public init(
        @ViewBuilder label: () -> Label,
        @ViewBuilder description: () -> Description
    ) {
        self.init(label: label, description: description, actions: { EmptyView() })
    }
}

extension ContentUnavailableView where Label == Text, Description == EmptyView, Actions == EmptyView {
    /// Creates a content unavailable view with a localized title.
    ///
    /// A string **literal** binds here, so it is a lookup key — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameter titleKey: The key for the title text.
    public init(_ titleKey: LocalizedStringKey) {
        self.init(
            label: { Text(titleKey) }, description: { EmptyView() },
            actions: { EmptyView() })
    }

    /// Creates a content unavailable view with a title shown as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameter title: The title text.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S) {
        self.init(
            label: { Text(String(title)) }, description: { EmptyView() },
            actions: { EmptyView() })
    }
}

extension ContentUnavailableView where Label == Text, Description == Text, Actions == EmptyView {
    /// Creates a content unavailable view with a localized title and description.
    ///
    /// Both are keys — an empty state is prose the reader is meant to
    /// understand, so the sentence under the title needs translating as much as
    /// the title does.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the title text.
    ///   - description: The key for the description text.
    public init(_ titleKey: LocalizedStringKey, description: LocalizedStringKey) {
        self.init(
            label: { Text(titleKey) }, description: { Text(description) },
            actions: { EmptyView() })
    }

    /// Creates a content unavailable view with strings shown as written.
    ///
    /// Both are generic over `StringProtocol` rather than concrete `String`s,
    /// which is what keeps *literals* binding to the key overload above — see
    /// ``LocalizedStringKey``. A type parameter each, not one shared between
    /// them: they are two independent strings, and one `S` would force a caller
    /// who has a `String` for the title and a `Substring` for the description to
    /// convert one of them for no reason. ``LabeledContent`` is the in-tree
    /// precedent for the two-parameter shape.
    ///
    /// - Parameters:
    ///   - title: The title text.
    ///   - description: The description text.
    @_disfavoredOverload
    public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, description: S2) {
        self.init(
            label: { Text(String(title)) }, description: { Text(String(description)) },
            actions: { EmptyView() })
    }
}

// MARK: - Search Preset

extension ContentUnavailableView
where
    Label == SearchUnavailableContent.Label, Description == SearchUnavailableContent.Description,
    Actions == SearchUnavailableContent.Actions
{
    /// A content unavailable view for empty search results.
    ///
    /// Inside a `searchable` modifier, it names the query
    /// — "No Results for "zzz"" — as SwiftUI's does: "A `ContentUnavailableView`
    /// initialized with this static member is expected to be contained within a
    /// searchable view hierarchy. Such a configuration enables the search query
    /// to be parsed into the view's description." Elsewhere, or with the query
    /// empty, it says "No Results".
    public static var search: Self {
        Self(
            label: { SearchUnavailableContent.Label(text: nil) },
            description: { SearchUnavailableContent.Description() },
            actions: { SearchUnavailableContent.Actions() })
    }

    /// A content unavailable view for empty search results with a query: "No
    /// Results for "\(text)"", whatever search it is in — for a search field of
    /// the app's own.
    ///
    /// - Parameter text: The search query that produced no results.
    /// - Returns: A configured content unavailable view.
    public static func search(text: String) -> Self {
        Self(
            label: { SearchUnavailableContent.Label(text: text) },
            description: { SearchUnavailableContent.Description() },
            actions: { SearchUnavailableContent.Actions() })
    }
}

/// The views of ``ContentUnavailableView/search`` — SwiftUI's type of the same
/// name.
public struct SearchUnavailableContent: Sendable {
    /// The title: "No Results", or "No Results for "…"" naming the query.
    public struct Label: View {
        /// The query `search(text:)` was given, or `nil` for the enclosing
        /// searchable's.
        let text: String?

        /// The query of the searchable this is in (``EnvironmentValues/searchQuery``).
        @Environment(\.searchQuery) private var searchQuery

        public var body: some View {
            // The query goes in through `%@` rather than Swift interpolation,
            // so a translation chooses both the wording AND its own quotation
            // marks — „…" in German, « … » in French. `Text(verbatim:)` around
            // the resolved string: the lookup has happened, and letting the
            // RESULT bind to `Text`'s key overload would search for the
            // translated prose as a key.
            let query = text ?? searchQuery ?? ""
            Text(
                verbatim: query.isEmpty
                    ? LocalizationService.shared.string(for: LocalizationKey.Label.noResults)
                    : LocalizedStringKey.substituting(
                        [query], into: LocalizationService.shared.string(for: LocalizationKey.Label.noResultsFor)))
        }
    }

    /// The description: "Check the spelling or try a new search."
    public struct Description: View {
        public var body: some View {
            Text(verbatim: LocalizationService.shared.string(for: LocalizationKey.Label.noResultsHint))
        }
    }

    /// The actions: none.
    public struct Actions: View {
        public var body: some View { EmptyView() }
    }
}

// MARK: - The search query

private struct SearchQueryKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The query of the ``View/searchable(text:placement:prompt:)`` this is in,
    /// which ``ContentUnavailableView/search`` names, or `nil` outside one.
    package var searchQuery: String? {
        get { self[SearchQueryKey.self] }
        set { self[SearchQueryKey.self] = newValue }
    }
}

// MARK: - Internal Core View

/// Internal view that handles the actual rendering of ContentUnavailableView.
///
/// Renders label, description, and actions as a vertically stacked layout,
/// centered horizontally in the available width.
private struct _ContentUnavailableViewCore<Label: View, Description: View, Actions: View>: View, Renderable, Layoutable {
    let label: Label
    let description: Description
    let actions: Actions

    var body: Never {
        fatalError("_ContentUnavailableViewCore renders via Renderable")
    }

    /// Available-width-dependent (like ``ViewThatFits``): the assembled block is
    /// left-padded to sit centred in `context.availableWidth`, so its rendered
    /// width is a function of the offered width, not a single intrinsic value. A
    /// single render under the layout's own context reports that width exactly —
    /// measure and render must occur at the same width (they do in two-pass
    /// layout). It is *not* flexible in the contract sense (it does not fill to
    /// the edge — only the left pad grows), so it reports `.fixed`.
    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureFixedByRendering(self, proposal: proposal, context: context)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        let palette = context.environment.palette

        // Each slot renders under its OWN child identity, not the core's.
        // They are three caller-supplied @ViewBuilders, and at one identity a
        // composite slot's first @State binds StateKey(coreIdentity, 0) — the
        // same key for all three, so a matching type silently shares one box
        // and a mismatched one makes `storage(for:)` replace the box every
        // render, resetting each slot to its default. The collision class
        // 778699f5 closed and 6ab904e7 carried to ProgressView's two labels;
        // these three sites were missed instances. The index (not the type)
        // is what separates them: two slots can hold the same view type.
        let labelBuffer = TUIkitView.renderToBuffer(
            label, context: context.withChildIdentity(erasedType: type(of: label), index: 0))

        // Render description with secondary foreground color
        var descContext = context.withChildIdentity(
            erasedType: type(of: description), index: 1)
        if descContext.environment.foregroundStyle == nil {
            descContext.environment.foregroundStyle = .color(palette.foregroundSecondary)
        }
        let descBuffer = TUIkitView.renderToBuffer(description, context: descContext)

        // Render actions
        let actionsBuffer = TUIkitView.renderToBuffer(
            actions, context: context.withChildIdentity(erasedType: type(of: actions), index: 2))

        // Combine vertically with spacing
        var result = FrameBuffer()

        // A *visually blank* part (e.g. ContentUnavailableView("") whose label
        // is a Text("") that padded itself to spaces) is dropped, not just a
        // zero-length one — otherwise it would reserve an empty row.
        if !labelBuffer.isBlank {
            result.appendVertically(labelBuffer)
        }

        if !descBuffer.isBlank {
            result.appendVertically(descBuffer, spacing: 1)
        }

        if !actionsBuffer.isBlank {
            result.appendVertically(actionsBuffer, spacing: 1)
        }

        // Centre the assembled buffer as one block, applying a
        // single uniform horizontal shift to every line.
        //
        // The previous implementation centred each line
        // independently using its own visible width. That looked
        // marginally nicer when label / description / actions had
        // very different widths, but it made the inner content's
        // hit-test regions (typically on the action Buttons)
        // impossible to shift correctly — `replacingLines` can
        // only carry a single uniform shift, and per-line shifts
        // would leave the action buttons' regions pointing at
        // their pre-centre column positions, so clicks would land
        // a few cells off the actual buttons.
        //
        // Block centring relative to result.width keeps every
        // line's offset consistent, so the buttons' regions stay
        // accurate after shifting. Visually it means shorter
        // lines (e.g. the title) are left-aligned within the
        // bounding box of the widest line rather than individually
        // centred.
        guard !result.isEmpty else { return result }

        let targetWidth = context.availableWidth
        let leftPad = max(0, (targetWidth - result.width) / 2)
        let padding = String(repeating: " ", count: leftPad)
        let centeredLines = result.lines.map { padding + $0 }

        return result.replacingLines(centeredLines, overlayShiftX: leftPad)
    }
}
