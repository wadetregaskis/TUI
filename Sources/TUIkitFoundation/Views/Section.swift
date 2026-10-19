//  🖥️ TUIkit — Terminal UI Kit for Swift
//  Section.swift
//
//  Created by LAYERED.work
//  License: MIT

// MARK: - Section

/// A container view that groups content with optional header and footer.
///
/// `Section` organizes list content into logical groups with visual headers
/// and footers. When used inside a `List`, sections provide hierarchical
/// structure with appropriate styling.
///
/// ## SwiftUI Conformity
///
/// This implementation matches the SwiftUI `Section` API:
/// - `Section { content } header: { header } footer: { footer }`
/// - `Section("Title") { content }`
///
/// ## Usage
///
/// ```swift
/// List(selection: $selection) {
///     Section {
///         ForEach(recentItems) { item in
///             Text(item.name)
///         }
///     } header: {
///         Text("Recent")
///     }
///
///     Section("All Items") {
///         ForEach(allItems) { item in
///             Text(item.name)
///         }
///     }
/// }
/// ```
///
/// ## In a List, a Form and a Table
///
/// A `List` draws a section as a group of its rows: the header bold and
/// dimmed, the footer dimmed, a blank header or footer dropped, and a
/// collapsible section's header behind a disclosure triangle that toggles it.
/// A `Form` and a `Table` draw sections in their own ways.
///
/// ## Everywhere Else
///
/// In any other container a section is its parts: its header's, content's and
/// footer's views become the container's own children, laid out as the
/// container lays out any child — in a `VStack` its `spacing` falls between
/// the header and the first row as between any two rows, an `HStack` lays the
/// parts along its row, a `Grid` gives each a row of its own and a `Layout`
/// sees each as a subview. The header and footer are drawn as written, with no
/// styling of their own, and a collapsible section shows its header as written
/// and its content only while expanded — as SwiftUI does (measured on macOS
/// 15.8). A modifier written on the section reaches each part, as one on a
/// `Group` reaches each member. Drawn on its own — a view's whole `body` — a
/// section stacks its parts vertically, as a `Group` does.
///
/// A lazy stack that pins its sections' headers or footers (`pinnedViews:`)
/// keeps its own sections whole, to pin them, and lays each one's parts out as
/// it lays out its children.
@MainActor
public struct Section<Parent, Content, Footer> {
    /// The header view displayed above the section content.
    package let header: Parent

    /// The main content of the section.
    package let content: Content

    /// The footer view displayed below the section content.
    package let footer: Footer

    /// Whether the section's content is shown, for a collapsible section
    /// (`Section(isExpanded:…)`), or `nil` for one that always shows it.
    package let isExpanded: Binding<Bool>?

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitTables makes these, for a table's sections.
    package init(header: Parent, content: Content, footer: Footer, isExpanded: Binding<Bool>?) {
        self.header = header
        self.content = content
        self.footer = footer
        self.isExpanded = isExpanded
    }
}

// MARK: - A section of views

/// A section of views is a view. Its parts are unconstrained for the same
/// reason `Group`'s content is: so that a section can hold what is not a
/// view — a table's rows.
extension Section: View where Parent: View, Content: View, Footer: View {
    public var body: some View {
        _SectionCore(header: header, content: content, footer: footer, isExpanded: isExpanded)
    }

    /// A section is its parts to most containers (``View/_handsOverChildren``),
    /// so a view whose body is one is taken apart as the section would be.
    public static var _handsOverChildren: Bool { true }

    /// Its parts' answer: a section is taken apart into its header, content
    /// and footer, so a layout in any of them is a member a row asks.
    public static var _statesSpacingPreference: Bool {
        Parent._statesSpacingPreference || Content._statesSpacingPreference || Footer._statesSpacingPreference
    }
}

// MARK: - Full Initializer (header + content + footer)

extension Section where Parent: View, Content: View, Footer: View {
    /// Creates a section with content, header, and footer.
    ///
    /// This is the most flexible initializer, matching SwiftUI's signature.
    ///
    /// - Parameters:
    ///   - content: A ViewBuilder that defines the section's main content.
    ///   - header: A ViewBuilder that defines the header view.
    ///   - footer: A ViewBuilder that defines the footer view.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Parent,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.header = header()
        self.footer = footer()
        self.isExpanded = nil
    }
}

// MARK: - Header + Content (no footer)

extension Section where Parent: View, Content: View, Footer: View, Footer == EmptyView {
    /// Creates a section with content and header, without a footer.
    ///
    /// - Parameters:
    ///   - content: A ViewBuilder that defines the section's main content.
    ///   - header: A ViewBuilder that defines the header view.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Parent
    ) {
        self.content = content()
        self.header = header()
        self.footer = EmptyView()
        self.isExpanded = nil
    }
}

// MARK: - Content + Footer (no header)

extension Section where Parent: View, Content: View, Footer: View, Parent == EmptyView {
    /// Creates a section with content and footer, without a header.
    ///
    /// - Parameters:
    ///   - content: A ViewBuilder that defines the section's main content.
    ///   - footer: A ViewBuilder that defines the footer view.
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.header = EmptyView()
        self.footer = footer()
        self.isExpanded = nil
    }
}

// MARK: - Content Only (no header, no footer)

extension Section where Parent: View, Content: View, Footer: View, Parent == EmptyView, Footer == EmptyView {
    /// Creates a section with content only, without header or footer.
    ///
    /// - Parameter content: A ViewBuilder that defines the section's main content.
    public init(
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.header = EmptyView()
        self.footer = EmptyView()
        self.isExpanded = nil
    }
}

// MARK: - String Title Convenience

extension Section where Parent: View, Content: View, Footer: View, Parent == Text, Footer == EmptyView {
    /// Creates a section with a string title as the header.
    ///
    /// This convenience initializer matches SwiftUI's `Section(_ title:content:)`.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the header text — a literal is looked up, see
    ///     ``LocalizedStringKey``.
    ///   - content: A ViewBuilder that defines the section's main content.
    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.header = Text(titleKey)
        self.content = content()
        self.footer = EmptyView()
        self.isExpanded = nil
    }

    /// Creates a section with a string title as the header, shown as written.
    ///
    /// Generic over `StringProtocol` rather than taking a concrete `String`,
    /// which is what keeps a *literal* binding to the key overload above — see
    /// ``LocalizedStringKey``.
    ///
    /// - Parameters:
    ///   - title: The string to use as the header text.
    ///   - content: A ViewBuilder that defines the section's main content.
    @_disfavoredOverload
    public init<S: StringProtocol>(
        _ title: S,
        @ViewBuilder content: () -> Content
    ) {
        self.header = Text(String(title))
        self.content = content()
        self.footer = EmptyView()
        self.isExpanded = nil
    }
}

// MARK: - Collapsible (isExpanded:)

extension Section where Parent: View, Content: View, Footer: View, Parent == Text, Footer == EmptyView {
    /// Creates a section with a localized title as its header, and a binding
    /// to whether its content is shown.
    ///
    /// In a `List` the header carries a disclosure triangle — `▼` while the
    /// content is shown, `▶` while it is not — and is a control of its own: a
    /// Tab stop that Return or Space toggles, Right opens and Left closes, and
    /// a click toggles, as a ``DisclosureGroup``'s header is. A collapsed
    /// section's rows leave the list. Anywhere else the header is drawn as
    /// written and the content only while the binding is `true`, as SwiftUI's
    /// is (measured on macOS 15.8).
    ///
    /// - Parameters:
    ///   - titleKey: The key for the header text — a literal is looked up, see
    ///     ``LocalizedStringKey``.
    ///   - isExpanded: A binding to whether the section's content is shown.
    ///   - content: The section's content.
    public init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.header = Text(titleKey)
        self.content = content()
        self.footer = EmptyView()
        self.isExpanded = isExpanded
    }

    /// Creates a section with a title, shown as written, as its header, and a
    /// binding to whether its content is shown.
    ///
    /// - Parameters:
    ///   - title: The header text.
    ///   - isExpanded: A binding to whether the section's content is shown.
    ///   - content: The section's content.
    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.header = Text(String(title))
        self.content = content()
        self.footer = EmptyView()
        self.isExpanded = isExpanded
    }
}

extension Section where Parent: View, Content: View, Footer: View, Footer == EmptyView {
    /// Creates a section with a header and a binding to whether its content is
    /// shown.
    ///
    /// The header carries a disclosure triangle and toggles the content from
    /// the keyboard and the pointer, as ``init(_:isExpanded:content:)-(LocalizedStringKey,_,()->Content)``'s does.
    ///
    /// - Parameters:
    ///   - isExpanded: A binding to whether the section's content is shown.
    ///   - content: The section's content.
    ///   - header: A view to use as the section's header.
    public init(
        isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent
    ) {
        self.header = header()
        self.content = content()
        self.footer = EmptyView()
        self.isExpanded = isExpanded
    }
}

/// A section's header as a `List` draws it: the header itself, or — for a
/// collapsible section — the header behind a disclosure triangle, the whole of
/// it one control that toggles the section (a ``DisclosureGroup``'s header,
/// with nothing to disclose but the section's own content).
package struct _SectionHeader<Header: View>: View {
    let header: Header
    let isExpanded: Binding<Bool>?

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitTables makes these, for a table's sections, and
    /// TUIkitForms, for a form's collapsible sections.
    package init(header: Header, isExpanded: Binding<Bool>?) {
        self.header = header
        self.isExpanded = isExpanded
    }

    package var body: some View {
        if let isExpanded {
            DisclosureGroup(isExpanded: isExpanded) {
                EmptyView()
            } label: {
                header
            }
        } else {
            header
        }
    }
}

extension Section where Parent: View, Content: View, Footer: View {
    /// The header as it is drawn: ``_SectionHeader``, or nothing for a section
    /// with no header.
    fileprivate var hasHeader: Bool { !(header is EmptyView) }

    /// The header as a `List` draws it (``_SectionHeader``): behind a
    /// disclosure triangle for a collapsible section.
    fileprivate var drawnHeader: _SectionHeader<Parent> {
        _SectionHeader(header: header, isExpanded: isExpanded)
    }
}

/// Returns `context` with `role` set as its chrome role, so a `List` section's
/// header/footer text styles via the cascade (the ``ChromeRole`` defaults plus
/// any `.chrome(...)` overrides) rather than being post-styled with fixed ANSI.
package func sectionChromeContext(_ context: RenderContext, _ role: ChromeRole) -> RenderContext {
    context.withEnvironment(context.environment.setting(\.chromeRole, to: role))
}

/// Whether a rendered header/footer buffer is entirely blank — so a `List`
/// drops it rather than show an empty row (e.g. an empty `Text("")` header).
func sectionBufferIsBlank(_ buffer: FrameBuffer) -> Bool {
    buffer.isBlank
}

// MARK: - A List's Section Styling

/// `@usableFromInline`, so internal rather than `private`, with its default: the
/// `@inlinable` accessor reads it (module split step A3).
@usableFromInline
struct ListSectionChromeKey: EnvironmentKey {
    @usableFromInline static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether a section drawn as one view here is drawn as a `List` draws its
    /// sections — header bold and dimmed, footer dimmed, a blank one dropped, a
    /// collapsible section's header behind a disclosure triangle.
    ///
    /// Set by a `List` for everything it draws. A list reads most sections as
    /// rows of its own and styles their headers itself; a section it cannot
    /// read that way — one wrapped in a modifier, or nested in another's
    /// content — it draws as one row, and that row's section keeps the list's
    /// styling through this, as SwiftUI styles every section of a list.
    /// Anywhere else a section is drawn as written (decisions B16).
    @inlinable
    package var drawsListSectionChrome: Bool {
        get { self[ListSectionChromeKey.self] }
        set { self[ListSectionChromeKey.self] = newValue }
    }
}

// MARK: - Section Row Extractor

/// Protocol for views that can provide section information for List rendering.
///
/// When a `List` contains `Section` views, it uses this protocol to extract
/// section structure for proper rendering with headers, footers, and grouping.
@MainActor
package protocol SectionRowExtractor {
    /// Extracts section information for list rendering.
    ///
    /// - Parameter context: The rendering context.
    /// - Returns: Section metadata including header, content rows, and footer.
    func extractSectionInfo(context: RenderContext) -> SectionInfo

    /// The rows this section's content contributes to the enclosing `List`,
    /// with the row-mutation actions of the `ForEach` that produced them.
    ///
    /// One walk for both because a `Section`'s rows are rows of the enclosing
    /// `List` while its `.onDelete` / `.onMove` offsets are indices into the
    /// `ForEach`'s own collection; the list needs both, and the only thing
    /// that can pair them is the section that holds them. Asked as two
    /// questions, they were two walks through the same wrappers
    /// (``ListRowsPassThrough``) that had to agree about which loop they had
    /// reached; asked as one, the loop the actions belong to is the loop that
    /// produced the rows by construction.
    ///
    /// See ``SectionContentRows/actions`` for when there are actions.
    func extractSectionContentRows<RowID: Hashable>(context: RenderContext) -> SectionContentRows<RowID>
}

/// What a `Section`'s content contributes to the enclosing `List`: its rows,
/// and the actions of the `ForEach` that produced every one of them.
package struct SectionContentRows<RowID: Hashable> {
    /// The content's rows, in order — the section's own header and footer are
    /// not among them.
    package var rows: [ListRow<RowID>]

    /// The row-mutation actions the content carries, when the content IS an
    /// editable `ForEach`, or a `Group`, an `if`/`else` or a view of the app's
    /// own whose `body` is one (any number deep) — `nil` otherwise.
    ///
    /// None of those wrappers is one of the exceptions below: each contributes
    /// exactly its content's rows, so a `ForEach` alone inside one is still the
    /// whole of what the section draws, and every row is still that loop's.
    ///
    /// `nil` for a section of statically-written rows, and also whenever the
    /// `ForEach` is not the section's WHOLE content — beside a hand-written
    /// row, or beside a second `ForEach`: there the children arrive already
    /// flattened, so a row cannot say which of them produced it, and a guess
    /// would put an offset into the wrong collection — one measured from the
    /// HEADER, so a press on the second looped row deletes the third element.
    /// With two loops it is worse: there are two sets of actions and nothing
    /// to choose between them, so a press on a row of the second edits the
    /// FIRST one's collection. The refusal is pinned by
    /// `ListUnownedEditActionTests`, against that exact guess.
    ///
    /// The looped rows there do know their selection ids now
    /// (``FlattenedRowIDs``), and an id changes none of this: it says what a
    /// row IS, not which collection it is in or where — a tag can replace it
    /// and a second loop can share it. The POSITIONAL match that found those
    /// ids does know which loop made each row and at what offset; wiring the
    /// editing gestures through it (an owner per loop, with its row span) is
    /// a change of its own, and until it is made the refusal stands.
    package var actions: (any DynamicViewContentActions)?

    /// Which element of the loop each row draws, for ``actions`` — one row per
    /// element, or a row's several views (decisions B15).
    package var elements: ListRowElements = .onePerRow
}

/// Metadata about a section for List rendering.
package struct SectionInfo {
    /// The rendered header buffer (nil if no header).
    package let headerBuffer: FrameBuffer?

    /// The rendered footer buffer (nil if no footer).
    package let footerBuffer: FrameBuffer?

    /// The section's separator preference (``View/listSectionSeparator(_:edges:)``
    /// and its tint): the line under its header is its `.top` edge, the line under
    /// its last row its `.bottom` edge (decisions A47).
    package var separator = ListSeparatorPreference()

    /// The memberwise initializer, spelled out because the synthesized one is
    /// internal and TUIkitLists makes these, for its lists.
    package init(
        headerBuffer: FrameBuffer?,
        footerBuffer: FrameBuffer?,
        separator: ListSeparatorPreference = ListSeparatorPreference()
    ) {
        self.headerBuffer = headerBuffer
        self.footerBuffer = footerBuffer
        self.separator = separator
    }
}

/// A section under an environment write is still a section to a `List` — its
/// header, its rows and its footer, each a row of the list — with the write
/// applied to all of them. Without it the list drew such a section as ONE
/// row: `Section { … }.headerProminence(.increased)` lost its rows'
/// selection, their tags and their badges, and the section its separators.
/// The environment writes `SectionPartsProviding` already sees through.
extension EnvironmentModifier: SectionRowExtractor where Content: SectionRowExtractor {
    package func extractSectionInfo(context: RenderContext) -> SectionInfo {
        content.extractSectionInfo(context: contentContext(context))
    }

    package func extractSectionContentRows<RowID: Hashable>(context: RenderContext) -> SectionContentRows<RowID> {
        content.extractSectionContentRows(context: contentContext(context))
    }
}

/// As ``EnvironmentModifier``'s.
extension TransformEnvironmentModifier: SectionRowExtractor where Content: SectionRowExtractor {
    package func extractSectionInfo(context: RenderContext) -> SectionInfo {
        content.extractSectionInfo(context: transformed(context))
    }

    package func extractSectionContentRows<RowID: Hashable>(context: RenderContext) -> SectionContentRows<RowID> {
        content.extractSectionContentRows(context: transformed(context))
    }
}

/// As ``EnvironmentModifier``'s: an observable written around a section
/// reaches each of its parts.
extension ObjectEnvironmentModifier: SectionRowExtractor where Content: SectionRowExtractor {
    package func extractSectionInfo(context: RenderContext) -> SectionInfo {
        content.extractSectionInfo(context: objectContext(context))
    }

    package func extractSectionContentRows<RowID: Hashable>(context: RenderContext) -> SectionContentRows<RowID> {
        content.extractSectionContentRows(context: objectContext(context))
    }

    /// `context` with the object written, as the modifier's own render
    /// writes it.
    private func objectContext(_ context: RenderContext) -> RenderContext {
        var environment = context.environment
        environment[observable: T.self] = object
        return context.withEnvironment(environment)
    }
}

/// A container value written on a section is its own, and changes nothing
/// the list draws: the section's parts, a step inside this view's identity —
/// where drawing it through its `body` puts the section.
extension _ContainerValueView: SectionRowExtractor where Content: SectionRowExtractor {
    package func extractSectionInfo(context: RenderContext) -> SectionInfo {
        content.extractSectionInfo(context: context.withChildIdentity(type: Content.self))
    }

    package func extractSectionContentRows<RowID: Hashable>(context: RenderContext) -> SectionContentRows<RowID> {
        content.extractSectionContentRows(context: context.withChildIdentity(type: Content.self))
    }
}

/// A section with a buffer modifier on it — `.padding()`, `.background(_:)`,
/// `.frame(height:)` — is still a section to its `List`: its header, each of
/// its rows and its footer a row of the list, the modifier applied to each,
/// as ``SectionPartsProviding`` applies it to each part in every other
/// container. Drawn as ONE row before, the section lost its rows' badges,
/// their tags and with them the selection, and its separators.
///
/// Each row's content is laid out in the context the modifier gives its
/// content (`adjustContext`) and its buffer modified as the row renders, so a
/// looped row is still built only when it is drawn.
extension ModifiedView: SectionRowExtractor where Content: SectionRowExtractor {
    package func extractSectionInfo(context: RenderContext) -> SectionInfo {
        let info = content.extractSectionInfo(context: modifier.adjustContext(context))
        return SectionInfo(
            headerBuffer: info.headerBuffer.map { modified($0, context: context) },
            footerBuffer: info.footerBuffer.map { modified($0, context: context) },
            separator: info.separator)
    }

    package func extractSectionContentRows<RowID: Hashable>(context: RenderContext) -> SectionContentRows<RowID> {
        var extracted: SectionContentRows<RowID> = content.extractSectionContentRows(
            context: modifier.adjustContext(context))
        extracted.rows = extracted.rows.map { row in
            row.mappingBuffer { modified($0, context: context) }
        }
        return extracted
    }

    /// `buffer`, a part of the section drawn in the modifier's content
    /// context, modified as ``ModifiedView`` modifies what it draws.
    private func modified(_ buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        var result = modifier._modify(buffer: buffer, context: context, owner: Self.self)
        if result.overlays.isEmpty && !buffer.overlays.isEmpty { result.overlays = buffer.overlays }
        return result
    }
}

extension Section: SectionRowExtractor where Parent: View, Content: View, Footer: View {
    package func extractSectionContentRows<RowID: Hashable>(
        context: RenderContext
    ) -> SectionContentRows<RowID> {
        // A collapsed section's rows leave the list.
        guard showsContent else { return SectionContentRows(rows: [], actions: nil) }
        return Self.listRows(of: content, context: context)
    }

    package func extractSectionInfo(context: RenderContext) -> SectionInfo {
        // Header/footer render under a chrome role so their text styles through
        // the cascade (see ``ChromeRole`` / ``Text``). The styling is per-line
        // and unshifted, so overlays and hit-test regions carry through.
        func renderedChrome(_ view: some View, _ role: ChromeRole, isEmptyView: Bool) -> FrameBuffer? {
            guard !isEmptyView else { return nil }
            let buffer = TUIkitView.renderToBuffer(view, context: sectionChromeContext(context, role))
            // A blank header/footer is dropped (nil), not shown as an empty row.
            return sectionBufferIsBlank(buffer) ? nil : buffer
        }
        let headerBuffer = renderedChrome(drawnHeader, .sectionHeader, isEmptyView: !hasHeader)
        let footerBuffer = renderedChrome(footer, .sectionFooter, isEmptyView: footer is EmptyView)
        // The content is not drawn here: its rows are the list's, drawn when
        // the list reads them (``extractSectionContentRows(context:)``). It
        // used to be drawn whole as well, into a buffer nothing read, every
        // frame: every row of the section, on screen or not, appeared, put up
        // its presentations and took a place in the focus ring, and each
        // drawn row was drawn twice (decisions B-LISTS-2, site 1).
        return SectionInfo(headerBuffer: headerBuffer, footerBuffer: footerBuffer)
    }
}

// MARK: - Section as ChildInfoProvider

extension Section: ChildInfoProvider where Parent: View, Content: View, Footer: View {
    public func childInfos(context: RenderContext) -> [ChildInfo] {
        // For stack layouts, render Section as a single unit
        let buffer = TUIkitView.renderToBuffer(self, context: context)
        return [ChildInfo(buffer: buffer, isSpacer: false, spacerMinLength: nil, size: nil)]
    }
}

// MARK: - Section as ListRowExtractor

extension Section: ListRowExtractor where Parent: View, Content: View, Footer: View {
    /// Extracts list rows from the section's content.
    ///
    /// Delegates to the content's `ListRowExtractor` implementation if available
    /// (e.g., `ForEach`). This allows List to extract individual content rows
    /// while separately handling section headers and footers.
    ///
    /// - Parameter context: The rendering context.
    /// - Returns: Array of list rows from the section's content.
    package func extractListRows<RowID: Hashable>(context: RenderContext) -> [ListRow<RowID>] {
        guard showsContent else { return [] }
        return Self.listRows(of: content, context: context).rows
    }

    /// The rows `content` contributes to the enclosing `List`, and the actions
    /// of the loop that produced them, asked of what it IS — generic over the
    /// view, rather than reading `self.content`, so it can be asked again of
    /// the view inside a `Group` or an `if`/`else`.
    private static func listRows<V: View, RowID: Hashable>(
        of content: V, context: RenderContext
    ) -> SectionContentRows<RowID> {
        // A `Group` or an `if`/`else` is taken off first, under the step the
        // child walk would have taken through it — `_ListCore.extractRows`'s
        // rule, for its reason (see ``ListRowsPassThrough``). Asked of the
        // wrapper, the `ListRowExtractor` question below failed and the rows
        // came from the child walk: keyed by position rather than by element,
        // and owned by no loop's `.onDelete` / `.onMove`.
        if let passThrough = content as? any ListRowsPassThrough {
            passThrough.noteLookedThrough(in: context)
            return listRows(
                of: passThrough.listRowsContent, context: passThrough.listRowsContext(context))
        }
        // And a view of the app's own whose `body` is rows, by the same rule
        // and for the same reason (see `listRowsBody(of:context:)`).
        if let body = listRowsBody(of: content, context: context) {
            return listRows(of: body.content, context: body.context)
        }
        // Only when the content IS the `ForEach`, seen through those wrappers:
        // `resolveChildViews` flattens a `ForEach` sitting among static rows,
        // so in that arrangement no row can be attributed to it and this is
        // `nil` (see ``SectionContentRows/actions``). A loop whose rows are
        // several views each says which element each row draws: the same
        // number from each, or — rows that vary — the run its key names.
        let unwrapped: (rows: [ListRow<RowID>], rowKeys: [String?]?) = unwrappedListRows(
            of: content, context: context)
        let actions = content as? any DynamicViewContentActions
        let elements: ListRowElements?
        switch (content as? any WindowedListRowExtractor)?.listRowsPerElement {
        case .some(let perElement) where perElement > 1: elements = .perElement(perElement)
        case .some: elements = .onePerRow
        case .none where content is any WindowedListRowExtractor:
            elements = (content as? any KeyedLoop).flatMap { loop in
                unwrapped.rowKeys.flatMap { ListRowElements.listed(rowKeys: $0, of: loop) }
            }
        case .none: elements = .onePerRow
        }
        return SectionContentRows(
            rows: unwrapped.rows, actions: elements == nil ? nil : actions, elements: elements ?? .onePerRow)
    }

    /// ``listRows(of:context:)``'s rows once the wrappers are off, with each
    /// row's identity key where they came from the child walk.
    private static func unwrappedListRows<V: View, RowID: Hashable>(
        of content: V, context: RenderContext
    ) -> (rows: [ListRow<RowID>], rowKeys: [String?]?) {
        // Delegate to content if it's a ListRowExtractor (e.g., ForEach)
        // — unless its rows make a number of list rows only each row knows,
        // which the child walk below reads (decisions B15).
        let rowsVary = (content as? any WindowedListRowExtractor).map { $0.listRowsPerElement == nil } ?? false
        if let extractor = content as? ListRowExtractor, !rowsVary {
            return (extractor.extractListRows(context: context), nil)
        }

        // Static children (a TupleView of rows, perhaps with a `ForEach`
        // among them): one row per child, each carrying the badge of its
        // `.badge(_:)` wrapper, if any — matching the flat List's child
        // extraction.
        if content is ChildViewProvider || isCompositeHandingOverChildren(V.self) {
            // A view of the app's own whose body is several views is taken
            // apart into them by the walk below (decisions D1S, B-D1S-6).
            //
            // Through `resolveChildViews`, not the provider's `childViews`
            // directly: an `if`/`else` among the children gets its branch step
            // there, in the tuple splice, and without it both branches' rows
            // rendered at the list's identity and shared their `@State`. (A
            // lone one never reaches here: it is taken off above, under the
            // same step.)
            //
            // A `Section` nested in the content whole, as the list's own walk
            // keeps its sections (`RenderContext.keepsSectionsWhole`): one row.
            var rows: [ListRow<RowID>] = []
            var rowKeys: [String?] = []
            let children = resolveChildViews(from: content, context: context.keepingSectionsWhole())
            let rowIDs = FlattenedRowIDs<RowID>(content: content, children: children, sectionsWhole: true)
            for (index, child) in children.enumerated() where !child.isSpacer {
                // A looped row by its own `ForEach`'s rule, any other row by
                // its own `.tag(_:)`, else its index — through the same
                // `FlattenedRowIDs` the flat `List` keys its children by,
                // because a row inside a Section is a row of the enclosing
                // List and must not answer to a different rule. Asked by the
                // child's place among ALL the children, spacers included: the
                // place is what matches a looped row to its loop. `nil` when
                // nothing can be cast into the selection type: the row draws
                // and is simply not selectable. See `ListRow.id` — which asks
                // for it when the list wants it, not here: a looped row's
                // answer can cost a build of the row.
                let rowID = rowIDs.askedID(ofChildAt: index, ordinal: rows.count)
                // Drawn when the list reads it, as a looped row of a lone
                // `ForEach` is (decisions B73, B-LISTS-2): out of the window,
                // not at all, and under the cursor after the list knows it is
                // there. Its badge through `extractRowBadge(from:)`, which sees
                // past `ForEach`'s value memo; what it reports — a separator,
                // a refusal — stamped as THIS list row's.
                let listRow = (context.environment.listRowEditRestrictions?.rowIndexBase ?? 0) + rows.count
                rows.append(ListRow(askedID: rowID, content: deferredListRow(of: child, listRow: listRow, context: context)))
                rowKeys.append(child.identityChildKey)
            }
            return (rows, rowKeys)
        }

        // Fallback: the content as a single row, carrying its badge, drawn
        // when the list reads it.
        guard let lone = loneListRow(of: content, context: context) else { return ([], nil) }
        return ([ListRow(id: staticListRowID(of: content, ordinal: 0, as: RowID.self), content: lone)], nil)
    }
}
