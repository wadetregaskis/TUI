//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarPresentationRows.swift
//
//  A `.toolbar` inside a sheet, a full-screen cover or a popover: its items
//  drawn by the view that declared them, in a row above it and a row below.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - The Rows

/// A `.toolbar` in presented content draws its items in two rows round the view
/// it is attached to, inside the presentation, as macOS lays a sheet's out:
///
/// - BELOW the view, the sheet's button row: ``ToolbarItemPlacement/destructiveAction``
///   items at the leading end, then the bottom bar's (``ToolbarItemPlacement/bottomBar``,
///   ``ToolbarItemPlacement/status``), and at the trailing end the
///   ``ToolbarItemPlacement/cancellationAction`` items and, last, the
///   ``ToolbarItemPlacement/confirmationAction`` ones;
/// - ABOVE it, every other placement, laid out as the window's top bar lays
///   them out, with no title.
///
/// A confirmation item's button is the presentation's default button — Return,
/// when the focused control lets the key through — and a cancellation item's
/// its cancel button (`.keyboardShortcut(.defaultAction / .cancelAction)`),
/// which Escape presses, as on macOS: the presentation's own Escape runs it in
/// place of dismissing (`DismissalGate.escape`).
///
/// The rows are drawn after the view, so their controls follow its controls in
/// the presentation's focus section, and the view's first control is the one
/// focused when it opens. They are part of the view's own layout — it is
/// proposed what they leave — so they appear and go with it, in the same frame.
extension _ToolbarModifier {
    /// The rows' items, top and bottom, at their identities under this view.
    private func presentationEntries(
        depth: Int, context: RenderContext
    ) -> (top: [WindowChromeState.ToolbarEntry], bottom: [WindowChromeState.ToolbarEntry]) {
        var top: [WindowChromeState.ToolbarEntry] = []
        var bottom: [WindowChromeState.ToolbarEntry] = []
        for item in toolbarItems(of: items) {
            let view: AnyView =
                switch item.placement.role {
                case .confirmationAction: AnyView(item.view.keyboardShortcut(.defaultAction))
                case .cancellationAction: AnyView(item.view.keyboardShortcut(.cancelAction))
                default: item.view
                }
            let entry = WindowChromeState.ToolbarEntry(
                placement: item.placement, view: view, environment: context.environment,
                identity: itemIdentity(item, depth: depth, context: context),
                isFlexibleSpace: item.isFlexibleSpace)
            if item.placement.isPresentationButtonRow {
                bottom.append(entry)
            } else {
                top.append(entry)
            }
        }
        return (top, bottom)
    }

    /// The context a row is drawn and measured in.
    private func rowContext(_ index: Int, width: Int?, context: RenderContext) -> RenderContext {
        var rowContext = context.withChildIdentity(type: _ToolbarBarRow.self, index: index)
        if let width {
            rowContext.availableWidth = width
            rowContext.hasExplicitWidth = true
        }
        return rowContext
    }

    /// `row`'s natural size — its items side by side, its spacers at their
    /// least — or zero for a row with nothing in it.
    ///
    /// The IDEAL width, not the room offered: the row's spacers fill whatever
    /// they are given, so measured against the presentation's width a row of
    /// one button made a popover as wide as the terminal.
    private func naturalSize(
        of entries: [WindowChromeState.ToolbarEntry], row index: Int, context: RenderContext
    ) -> ViewSize {
        guard !entries.isEmpty else { return ViewSize(width: 0, height: 0) }
        return measureChild(
            _ToolbarBarRow(entries: entries, title: "", subtitle: "", isPresentation: true),
            proposal: .unspecified, context: rowContext(index, width: nil, context: context).askingIdealWidth())
    }

    /// Draws the view with its items in rows above and below it.
    func renderInPresentation(context: RenderContext) -> FrameBuffer {
        let declaration = declaring(in: context)
        var contentContext = declaration.content
        let (top, bottom) = presentationEntries(depth: declaration.depth, context: context)
        guard !top.isEmpty || !bottom.isEmpty else { return TUIkitView.renderToBuffer(content, context: contentContext) }

        let topSize = naturalSize(of: top, row: 0, context: context)
        let bottomSize = naturalSize(of: bottom, row: 1, context: context)
        contentContext.availableHeight = max(0, context.availableHeight - topSize.height - bottomSize.height)
        // The view first, so its controls come first in the focus section.
        let body = TUIkitView.renderToBuffer(content, context: contentContext)
        let width = min(max(0, context.availableWidth), max(body.width, topSize.width, bottomSize.width))

        func row(_ entries: [WindowChromeState.ToolbarEntry], _ index: Int, height: Int) -> FrameBuffer {
            var rowContext = rowContext(index, width: width, context: context)
            rowContext.availableHeight = height
            return TUIkitView.renderToBuffer(
                _ToolbarBarRow(entries: entries, title: "", subtitle: "", isPresentation: true),
                context: rowContext)
        }
        let topRow = top.isEmpty ? nil : row(top, 0, height: topSize.height)
        let bottomRow = bottom.isEmpty ? nil : row(bottom, 1, height: bottomSize.height)
        var buffer = topRow ?? FrameBuffer()
        buffer.appendVertically(body)
        if let bottomRow { buffer.appendVertically(bottomRow) }
        return buffer
    }

    /// The view's size with its rows.
    func sizeInPresentation(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        let (depth, contentContext) = declaring(in: context)
        let (top, bottom) = presentationEntries(depth: depth, context: context)
        guard !top.isEmpty || !bottom.isEmpty else {
            return measureChild(content, proposal: proposal, context: contentContext)
        }
        let topSize = naturalSize(of: top, row: 0, context: context)
        let bottomSize = naturalSize(of: bottom, row: 1, context: context)
        let rows = topSize.height + bottomSize.height
        let body = measureChild(
            content,
            proposal: ProposedSize(width: proposal.width, height: proposal.height.map { max(0, $0 - rows) }),
            context: contentContext)
        var width = max(body.width, topSize.width, bottomSize.width)
        if let limit = proposal.width { width = min(width, limit) }
        return ViewSize(
            width: width, height: body.height + rows,
            isWidthFlexible: body.isWidthFlexible, isHeightFlexible: body.isHeightFlexible)
    }
}

extension ToolbarItemPlacement {
    /// Whether, in presented content, an item of this placement is in the
    /// button row below the view: a modal interface's actions, and the
    /// bottom bar's placements.
    var isPresentationButtonRow: Bool {
        switch role {
        case .confirmationAction, .cancellationAction, .destructiveAction, .bottomBar, .status: true
        default: false
        }
    }
}
