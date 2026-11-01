//  🖥️ TUI — A Terminal UI framework for Swift
//  SectionActions.swift
//
//  `.sectionActions(content:)`: controls a list draws in a section's header.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUICore
import TUIFoundation
import TUIView

extension View {
    /// Adds custom actions to a section.
    ///
    /// On macOS the actions appear at the trailing end of the section's
    /// header when the pointer hovers over the section. A terminal list shows
    /// them then, and also while the section has the keyboard — the focused
    /// list's cursor on one of its rows, or the focus on one of the actions —
    /// where Tab from the list moves onto each and a click presses them: an
    /// action shown only under the pointer would be one the keyboard could not
    /// use. Otherwise their cells are left blank, so nothing moves as they
    /// come and go. They are at the header's trailing edge, as macOS puts them, in
    /// a list that fills the width it is offered; in one that hugs its rows —
    /// a tab view's sidebar — they go one cell after the header's title, as
    /// the header is drawn before the list knows the width it hugs to.
    ///
    /// A section with no header shows its actions alone on the header's line.
    /// The actions belong to a section in a `List`; anywhere else — a
    /// `Section` in a stack — the view draws as it would without them. A
    /// custom container reads them as the section's
    /// ``SectionConfiguration/actions``.
    ///
    /// ```swift
    /// List {
    ///     Section("Categories") {
    ///         Label("Climate", systemImage: "fan")
    ///         Label("Lights", systemImage: "lightbulb")
    ///     }
    ///     .sectionActions {
    ///         Button("Add Category", systemImage: "plus") { }
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter content: The actions to show in the section's header.
    nonisolated public func sectionActions<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        _SectionActionsView(content: self, actions: content())
    }
}

/// A section with the actions `.sectionActions(content:)` gave it — drawn as
/// its section outside a list, and read by a list as that section with the
/// actions on its header's line.
nonisolated struct _SectionActionsView<Content: View, Actions: View>: View {
    let content: Content
    let actions: Actions

    @MainActor var body: Content { content }
}

/// The section's parts, with these actions — what ``SectionConfiguration``
/// hands a custom container.
@MainActor extension _SectionActionsView: SectionPartsProviding where Content: SectionPartsProviding {
    var sectionParts: SectionParts {
        var parts = content.sectionParts
        parts.actions = actions
        return parts
    }
}

@MainActor extension _SectionActionsView: SectionRowExtractor where Content: SectionRowExtractor {
    /// The section's rows, a step inside this view's identity — where drawing
    /// the view through its `body` puts the section.
    func extractSectionContentRows<RowID: Hashable>(context: RenderContext) -> SectionContentRows<RowID> {
        content.extractSectionContentRows(context: context.withChildIdentity(type: Content.self))
    }

    /// The section's header and footer, with the actions for the header's
    /// line: flush against the row's trailing edge in a list that fills its
    /// width — the width the row is drawn at, where the list puts a row's
    /// badge — and one cell after the title in a list that hugs its rows
    /// (``EnvironmentValues/listRowsHug``), whose width is settled from the
    /// rows only after they are drawn. A section without a header shows them
    /// alone on the header's line. Actions that draw nothing leave the header
    /// as it was.
    ///
    /// The list draws them only while the section is in use (owner ruling
    /// B78-VISIBILITY), through ``SectionInfo/headerActions``; until then the
    /// header holds their cells blank, as MEASURED rather than drawn — a
    /// drawing registers them as focus stops — so the rows under a headerless
    /// section and a hugging list's width stay put as they come and go.
    func extractSectionInfo(context: RenderContext) -> SectionInfo {
        let info = content.extractSectionInfo(context: context.withChildIdentity(type: Content.self))
        let actionsContext = context.withChildIdentity(erasedType: Actions.self, key: "sectionActions")
        let size = measureChild(
            actions, proposal: ProposedSize(width: context.availableWidth, height: context.availableHeight),
            context: actionsContext)
        guard size.width > 0, size.height > 0 else { return info }
        let header = info.headerBuffer ?? FrameBuffer()
        let hugs = context.environment.listRowsHug
        let width = context.availableWidth
        func spacing(before actionsWidth: Int) -> Int {
            hugs ? 1 : max(1, width - header.width - actionsWidth)
        }
        var reserved = header
        reserved.appendHorizontally(
            FrameBuffer(lines: Array(repeating: String.spaces(size.width), count: size.height)),
            spacing: spacing(before: size.width))
        let actions = actions
        let headerActions = SectionHeaderActions(identity: actionsContext.identity) {
            let drawn = TUIView.renderToBuffer(actions, context: actionsContext)
            guard !drawn.isBlank else { return reserved }
            var shown = header
            shown.appendHorizontally(drawn, spacing: spacing(before: drawn.width))
            return shown
        }
        return SectionInfo(
            headerBuffer: reserved, footerBuffer: info.footerBuffer, separator: info.separator,
            headerActions: headerActions)
    }
}
