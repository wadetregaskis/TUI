//  🖥️ TUI — A Terminal UI framework for Swift
//  PanelToggleButton.swift
//
//  The button a toolbar draws for a panel's toggle: a split view's sidebar,
//  placed by `DefaultToolbarItem(kind: .sidebarToggle)` or put in the window's
//  top bar by default.
//
//  Created by Wade Tregaskis
//  License: MIT

import TUIFoundation

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
///
/// With a label (`DefaultToolbarItem(kind:placement:label:)`), the button draws
/// it after the arrow, and its text names the panel: in the button's help and
/// key hint, and — handed to the panel's owner through the toggle's action —
/// in the hints of the owner's own handles.
struct _PanelToggleButton: View, Renderable, Layoutable {
    /// The panel the button toggles.
    let panel: PanelToggle.Panel

    /// What the button shows after its arrow, or `nil`.
    let label: AnyView?

    var body: Never { fatalError("_PanelToggleButton renders via Renderable") }

    /// The toggle this button works: the split view's it was declared in, else
    /// the window's.
    ///
    /// The window's is an unkeyed read (``VolatileReadTracker/recordUnkeyedRead()``):
    /// a panel registers its toggle with the window's chrome as the walk
    /// draws it, so the bar can measure this button before its panel has
    /// registered — finding no toggle and drawing nothing — and again after,
    /// in the same pass, with the same identity and the same view value. Read
    /// unannounced, the per-pass measure memo served the first answer, 0 × 0,
    /// to the second (found by `TUI_VERIFY_MEASURE_MEMO`).
    private func toggle(_ context: RenderContext) -> PanelToggle? {
        switch context.environment.panelToggleScope(panel) {
        case .window:
            guard let chrome = context.environment.windowChrome else { return nil }
            context.environment.volatileReadTracker?.recordUnkeyedRead()
            return chrome.panelToggle(panel)
        case .split(let toggle): return toggle
        }
    }

    /// The button's focus ID, from this view's identity.
    private func focusID(_ context: RenderContext) -> String {
        "panel-toggle-\(context.identity.path)"
    }

    /// The label's text, which names the panel: rendered as a measure, which
    /// registers nothing, and its first line taken without its colours, as a
    /// tab's label view is read for the strip. `nil` without a label, or for one
    /// that draws no text.
    private func name(_ context: RenderContext) -> String? {
        guard let label else { return nil }
        var labelContext = context
        labelContext.isMeasuring = true
        let line = TUIView.renderToBuffer(label, context: labelContext).lines.first?.stripped ?? ""
        // Trimmed of spaces by index rather than as `drop`/`reversed` twice
        // over, a chain Swift 6.4.0 took 11 ms to type-check.
        guard let first = line.firstIndex(where: { $0 != " " }),
            let last = line.lastIndex(where: { $0 != " " })
        else { return nil }
        return String(line[first...last])
    }

    private func button(_ toggle: PanelToggle, name: String?, context: RenderContext) -> some View {
        let action = toggle.action
        return Button { action.perform() } label: {
            HStack(spacing: 1) {
                Text(verbatim: toggle.arrow)
                label
            }
        }
        .focusID(focusID(context))
        .help(toggle.helpText(named: name))
    }

    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        guard let toggle = toggle(context) else { return FrameBuffer() }
        let name = name(context)
        let buffer = TUIView.renderToBuffer(button(toggle, name: name, context: context), context: context)
        guard !context.isMeasuring else { return buffer }
        // Noted afresh by every frame that draws it, which a memoised ancestor
        // serving its buffer would skip: the split view would bring its ▶
        // back under the button.
        context.environment.volatileReadTracker?.recordRenderSideEffect()
        let isNew = context.environment.windowChrome?.noteBarToggleDrawn(for: toggle.owner) == true
        let renamed = toggle.action.labelText != name
        toggle.action.labelText = name
        if isNew || renamed {
            // The owner drew its handles before this frame's bars — a split
            // view its ▶, the hints their old names: drawn again, it leaves
            // the ▶ out and names the panel as this button does.
            context.renderCache?.invalidateRender(for: toggle.owner)
        }
        // What Return does here, in place of the button's own "activate".
        FocusRegistration.publishActivationLabel(
            toggle.activationLabel(named: name), context: context,
            isFocused: FocusRegistration.isFocused(context: context, focusID: focusID(context)))
        return buffer
    }

    func sizeThatFits(proposal: ProposedSize, context: RenderContext) -> ViewSize {
        guard let toggle = toggle(context) else { return ViewSize.fixed(0, 0) }
        return measureChild(button(toggle, name: nil, context: context), proposal: proposal, context: context)
    }
}
