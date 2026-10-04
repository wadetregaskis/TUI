//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SectionActions.swift
//
//  `.sectionActions(content:)`: controls a list draws in a section's header.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitCore
import TUIkitView

extension View {
    /// Adds custom actions to a section.
    ///
    /// On macOS the actions appear when the pointer hovers over the section.
    /// A terminal list shows them all the time instead, one cell after the
    /// section's header title, where the keyboard reaches them as it reaches
    /// any control — Tab moves onto each — and a click presses them: an action
    /// shown only under the pointer would be one the keyboard could not use.
    /// Not at the header's trailing edge, as macOS puts them: the header row
    /// is drawn before the list knows the width it hugs to, and a flush-right
    /// action would be clipped in a list that hugs its rows.
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
    public func sectionActions<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        _SectionActionsView(content: self, actions: content())
    }
}

/// A section with the actions `.sectionActions(content:)` gave it — drawn as
/// its section outside a list, and read by a list as that section with the
/// actions on its header's line.
struct _SectionActionsView<Content: View, Actions: View>: View {
    let content: Content
    let actions: Actions

    var body: Content { content }
}

/// The section's parts, with these actions — what ``SectionConfiguration``
/// hands a custom container.
extension _SectionActionsView: SectionPartsProviding where Content: SectionPartsProviding {
    var sectionParts: SectionParts {
        var parts = content.sectionParts
        parts.actions = actions
        return parts
    }
}

extension _SectionActionsView: SectionRowExtractor where Content: SectionRowExtractor {
    /// The section's rows, a step inside this view's identity — where drawing
    /// the view through its `body` puts the section.
    func extractSectionContentRows<RowID: Hashable>(context: RenderContext) -> SectionContentRows<RowID> {
        content.extractSectionContentRows(context: context.withChildIdentity(type: Content.self))
    }

    /// The section's header, footer and content, with the actions drawn on
    /// the header's first line one cell after its title — or as the header,
    /// for a section without one. Actions that draw nothing leave the header
    /// as it was.
    func extractSectionInfo(context: RenderContext) -> SectionInfo {
        let info = content.extractSectionInfo(context: context.withChildIdentity(type: Content.self))
        let drawnActions = TUIkit.renderToBuffer(
            actions, context: context.withChildIdentity(erasedType: Actions.self, key: "sectionActions"))
        guard !drawnActions.isBlank else { return info }
        var header = info.headerBuffer ?? FrameBuffer()
        header.appendHorizontally(drawnActions, spacing: 1)
        return SectionInfo(headerBuffer: header, footerBuffer: info.footerBuffer, contentBuffer: info.contentBuffer)
    }
}
