//  🖥️ TUIkit — Terminal UI Kit for Swift
//  PanelToggleButton.swift
//
//  The button a toolbar draws for a panel's toggle: a split view's sidebar,
//  placed by `DefaultToolbarItem(kind: .sidebarToggle)` or put in the window's
//  top bar by default.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIkitFoundation

// MARK: - The Button

/// The button a toolbar draws for a panel's toggle: the arrow, which says
/// which way the panel goes, as a ``Button`` the bar frames as it frames any.
///
/// It toggles the panel of the view it was declared in — the split view whose
/// column it is in, for a sidebar — else the window's
/// (``WindowChromeState/panelToggle(_:)``), and draws nothing where there is
/// neither. Drawn, it tells the window so
/// (``WindowChromeState/noteBarToggleDrawn(for:)``): the split view then leaves
/// out its ▶ edge column, which the button stands in for.
struct _PanelToggleButton: View, Renderable, Layoutable {
    /// The panel the button toggles.
    let panel: PanelToggle.Panel

    var body: Never { fatalError("_PanelToggleButton renders via Renderable") }

    /// The toggle this button works: the split view's it was declared in, else
    /// the window's.
    private func toggle(_ context: RenderContext) -> PanelToggle? {
        switch context.environment.panelToggleScope(panel) {
        case .window: context.environment.windowChrome?.panelToggle(panel)
        case .split(let toggle): toggle
        }
    }

    /// The button's focus ID, from this view's identity.
    private func focusID(_ context: RenderContext) -> String {
        "panel-toggle-\(context.identity.path)"
    }

    private func button(_ toggle: PanelToggle, context: RenderContext) -> some View {
        let action = toggle.action
        return Button { action.perform() } label: { Text(verbatim: toggle.arrow) }
            .focusID(focusID(context))
            .help(toggle.helpText)
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let toggle = toggle(context) else { return FrameBuffer() }
        let buffer = TUIkitView.renderToBuffer(button(toggle, context: context), context: context)
        guard !context.isMeasuring else { return buffer }
        // Noted afresh by every frame that draws it, which a memoised ancestor
        // serving its buffer would skip: the split view would bring its ▶
        // back under the button.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        if context.environment.windowChrome?.noteBarToggleDrawn(for: toggle.owner) == true {
            // The split drew its ▶ before this frame's bars: drawn again, it
            // leaves it out.
            context.renderCache?.invalidateRender(for: toggle.owner)
        }
        // What Return does here, in place of the button's own "activate".
        FocusRegistration.publishActivationLabel(
            toggle.activationLabel, context: context,
            isFocused: FocusRegistration.isFocused(context: context, focusID: focusID(context)))
        return buffer
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let toggle = toggle(context) else { return ViewSize.fixed(0, 0) }
        return measureChild(button(toggle, context: context), proposal: proposal, context: context)
    }
}
