//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarBar.swift
//
//  A window toolbar as the chrome host draws it: the items placed in it, laid
//  out, each in the environment and at the identity of the view that declared
//  it.
//
//  Created by Wade Tregaskis
//  License: MIT

// MARK: - A Bar's Items

/// The items of one of the window's toolbars, laid out in a row: the leading
/// items, the title (or the principal items in its place), and the trailing
/// items, secondary before primary.
///
/// Pure composition — every item is drawn by ``_ToolbarEntryView``, which puts
/// it back where it was declared. The chrome host frames the row and gives it
/// a focus section of its own.
struct _ToolbarBarRow: View {
    /// The bar's items, in declaration order.
    let entries: [WindowChromeState.ToolbarEntry]

    /// The window's title, shown at the leading end when nothing is principal.
    let title: String

    /// The window's subtitle, shown under the title.
    let subtitle: String

    var body: some View {
        let leading = entries.filter { $0.placement.region == .leading }
        let principal = entries.filter { $0.placement.region == .principal }
        let trailing =
            entries.filter { $0.placement.region == .secondary }
            + entries.filter { $0.placement.region == .trailing }
        HStack(spacing: 1) {
            ForEach(leading.indices, id: \.self) { index in
                _ToolbarEntryView(entry: leading[index])
            }
            if principal.isEmpty, !title.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: title).bold()
                    if !subtitle.isEmpty {
                        Text(verbatim: subtitle).foregroundStyle(.palette.foregroundSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if !principal.isEmpty {
                ForEach(principal.indices, id: \.self) { index in
                    _ToolbarEntryView(entry: principal[index])
                }
                Spacer(minLength: 0)
            }
            ForEach(trailing.indices, id: \.self) { index in
                _ToolbarEntryView(entry: trailing[index])
            }
        }
    }
}

// MARK: - One Item

/// One toolbar item, drawn in the environment of the view that declared it and
/// at the identity it was given there — so a `.disabled(_:)` written above
/// `.toolbar` disables it, its `@State` survives from frame to frame, and its
/// focus ID is derived from where it was declared, not from where the bar is.
///
/// What it keeps from the bar is what the bar is to it: the focus section its
/// controls join, the bar's key channels (a throwaway set while a modal holds
/// the input), and the bar's width and height.
struct _ToolbarEntryView: View, Renderable, Layoutable {
    let entry: WindowChromeState.ToolbarEntry

    var body: Never { fatalError("_ToolbarEntryView renders via Renderable") }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Never stored by a memo around the bar: the item renders at the
        // identity it was declared at, which is not under the bar's, so a
        // change to its `@State` would invalidate nothing the bar's memo is
        // keyed under, and the memo would go on serving the old picture.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        return TUIkit.renderToBuffer(entry.view, context: entryContext(context))
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        measureChild(entry.view, proposal: proposal, context: entryContext(context))
    }

    /// `context`, under the declaring view's environment and identity, with the
    /// bar's own channels put back.
    private func entryContext(_ context: RenderContext) -> RenderContext {
        var environment = entry.environment
        let bar = context.environment
        environment.activeFocusSectionID = bar.activeFocusSectionID
        environment.focusManager = bar.focusManager
        environment.keyEventDispatcher = bar.keyEventDispatcher
        environment.keyboardShortcutRegistry = bar.keyboardShortcutRegistry
        environment.drawsBackdrop = bar.drawsBackdrop
        environment.volatileReadTracker = bar.volatileReadTracker
        var entryContext = context.withEnvironment(environment)
        entryContext.identity = entry.identity
        return entryContext
    }
}
